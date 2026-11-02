import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/reader/book_opener.dart';
import 'package:reader_mobile/reader/book_opening_view.dart';
import 'package:reader_mobile/storage/file_progress_store.dart';

import '../support/test_epub.dart';

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
      progressStore: FileReaderProgressStore.memory(),
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
    expect(find.text('山海小记'), findsWidgets);
    expect(find.text('正在展开'), findsOneWidget);

    library.finish(bytes);
    await _pumpFrames(tester, frames: 40);

    expect(
      find.byKey(const ValueKey<String>('book-opening-view')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey<String>('reader-page')), findsOneWidget);

    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await _pumpFrames(tester);
    await openFuture;
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
      progressStore: FileReaderProgressStore.memory(),
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
    await openFuture;

    expect(find.text('书架'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('reader-page')), findsNothing);
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
