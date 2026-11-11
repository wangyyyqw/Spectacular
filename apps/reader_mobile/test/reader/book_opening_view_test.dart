import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/reader/book_opener.dart';
import 'package:reader_mobile/reader/book_opening_view.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_mobile/reader/epub_reader_page.dart';
import 'package:reader_ui/a11y/semantics_layer.dart';
import 'package:reader_ui/page_furniture/page_furniture.dart';
import 'package:reader_ui/reader_page.dart';

import '../support/test_epub.dart';
import '../support/reader_pump.dart';

import 'package:reader_ui/reader_session.dart';

class _DelayedLibraryStore extends LibraryStore {
  _DelayedLibraryStore() : super.memory();

  final Completer<Uint8List> _bytes = Completer<Uint8List>();

  @override
  Future<Uint8List> readBytes(BookEntry entry) => _bytes.future;

  void finish(Uint8List bytes) => _bytes.complete(bytes);
}

Future<void> _pumpFrames(WidgetTester tester, {int frames = 12}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('读盘期间显示封面展开动画，完成后进入阅读页', (tester) async {
    final library = _DelayedLibraryStore();
    final bytes = buildTestEpub(title: '山海小记', author: '测试作者');
    final entry = await library.importBytes(
      bytes,
      fallbackTitle: 'sample.epub',
    );
    final opener = BookOpener(
      library: library,
      progressStore: MemoryReaderProgressStore(),
    );
    final contextKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            key: contextKey,
            builder: (context) => const SizedBox.expand(),
          ),
        ),
      ),
    );
    final openFuture = opener.open(contextKey.currentContext!, entry);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(
      find.byKey(const ValueKey<String>('book-opening-view')),
      findsOneWidget,
    );
    expect(find.byType(EpubReaderPage), findsOneWidget);
    expect(find.text('山海小记'), findsWidgets);
    expect(find.text('正在打开'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Hero && widget.tag == bookCoverHeroTag(entry.id),
      ),
      findsOneWidget,
    );

    library.finish(bytes);
    await pumpReaderUntil(tester, find.byType(ReaderPageFooter));
    await _pumpFrames(tester);

    expect(
      find.byKey(const ValueKey<String>('book-opening-view')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey<String>('reader-page')), findsOneWidget);

    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await _pumpFrames(tester);
    await pumpReaderTask(tester, openFuture);
  });

  testWidgets('快速读盘在封面展开期间准备正文和数字，揭开不重复打开', (tester) async {
    final library = LibraryStore.memory();
    final bytes = buildTestEpub(title: '山海小记', author: '测试作者');
    final entry = await library.importBytes(
      bytes,
      fallbackTitle: 'sample.epub',
    );
    final opener = BookOpener(
      library: library,
      progressStore: MemoryReaderProgressStore(),
    );
    final contextKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            key: contextKey,
            builder: (context) => const SizedBox.expand(),
          ),
        ),
      ),
    );
    final startedAt = tester.binding.clock.now();
    final openFuture = opener.open(contextKey.currentContext!, entry);
    await tester.pump();
    await pumpReaderUntil(tester, find.byType(ReaderPageFooter), maxFrames: 24);
    final elapsed = tester.binding.clock.now().difference(startedAt);
    expect(elapsed, lessThan(const Duration(milliseconds: 400)));
    await tester.pump(const Duration(milliseconds: 400) - elapsed);

    expect(
      find.byKey(const ValueKey<String>('book-opening-view')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('reader-page')), findsOneWidget);
    final reader = tester.widget<ReaderPage>(find.byType(ReaderPage));
    final source = reader.source as EpubChapterSource;
    final preparedAnchors = source.anchorPreparationCount;
    final layoutCount = source.chapterLayoutCount;
    expect(preparedAnchors, 1);
    final page = tester
        .widget<ReaderSemanticsLayer>(find.byType(ReaderSemanticsLayer))
        .page;
    expect((page.spineIndex, page.pageIndex), (0, 0));
    expect(
      page.slices.map((slice) => slice.block.layout.text).join(),
      contains('这是用于应用壳测试的段落'),
    );
    expect(
      find.byType(ReaderPageHeader),
      findsNothing,
      reason: '章首页按页家具规则隐藏页眉，封面展开不改变该规则',
    );
    final footer = tester
        .widgetList<ReaderPageFooter>(find.byType(ReaderPageFooter))
        .first;
    expect(footer.progress, inInclusiveRange(0, 1));

    await _pumpFrames(tester, frames: 8);

    expect(
      find.byKey(const ValueKey<String>('book-opening-view')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey<String>('reader-page')), findsOneWidget);
    expect(
      tester.widget<ReaderPage>(find.byType(ReaderPage)).source,
      same(source),
    );
    expect(source.anchorPreparationCount, preparedAnchors);
    expect(source.chapterLayoutCount, layoutCount);
    expect(
      tester
          .widget<ReaderSemanticsLayer>(find.byType(ReaderSemanticsLayer))
          .page,
      same(page),
      reason: '揭开封面复用已准备的正文页',
    );

    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await _pumpFrames(tester);
    await pumpReaderTask(tester, openFuture);
  });

  testWidgets('开场动画期间返回会取消后续阅读页打开', (tester) async {
    final library = _DelayedLibraryStore();
    final bytes = buildTestEpub(title: '山海小记', author: '测试作者');
    final entry = await library.importBytes(
      bytes,
      fallbackTitle: 'sample.epub',
    );
    final opener = BookOpener(
      library: library,
      progressStore: MemoryReaderProgressStore(),
    );
    final contextKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            key: contextKey,
            builder: (context) => const Text('书架'),
          ),
        ),
      ),
    );
    final openFuture = opener.open(contextKey.currentContext!, entry);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(
      find.byKey(const ValueKey<String>('book-opening-view')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey<String>('book-opening-close')));
    await _pumpFrames(tester);
    library.finish(bytes);
    await _pumpFrames(tester);
    await pumpReaderTask(tester, openFuture);

    expect(find.text('书架'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('reader-page')), findsNothing);
    expect((await library.bookById(entry.id))?.lastReadAt, isNull);
  });

  testWidgets('开书使用导入时的内容摘要并绑定阅读位置', (tester) async {
    final library = LibraryStore.memory();
    final entry = await library.importBytes(buildTestEpub(title: '已存版本'));
    expect(entry.contentRevision, isNotNull);
    final opener = BookOpener(
      library: library,
      progressStore: MemoryReaderProgressStore(),
    );
    final contextKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            key: contextKey,
            builder: (context) => const SizedBox.expand(),
          ),
        ),
      ),
    );
    final openFuture = opener.open(contextKey.currentContext!, entry);
    await _pumpFrames(tester);
    final reader = tester.widget<ReaderPage>(find.byType(ReaderPage));
    expect(reader.contentRevision, entry.contentRevision);
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await _pumpFrames(tester);
    await pumpReaderTask(tester, openFuture);
  });

  testWidgets('窄横屏和大字号下开场页不溢出', (tester) async {
    tester.view.physicalSize = const Size(800, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final library = LibraryStore.memory();
    final entry = await library.importBytes(
      buildTestEpub(title: '一个足够长的开场动画测试书名'),
      fallbackTitle: 'sample.epub',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.4)),
            child: BookOpeningView(book: entry),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 800));

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey<String>('book-opening-view')),
      findsOneWidget,
    );
  });
}
