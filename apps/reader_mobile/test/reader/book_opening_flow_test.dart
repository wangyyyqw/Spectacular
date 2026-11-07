import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/reader/book_opening_reader.dart';
import 'package:reader_mobile/reader/book_opening_view.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';
import 'package:reader_mobile/reader/epub_reader_page.dart';
import 'package:reader_mobile/reader/reader_font_store.dart';
import 'package:reader_mobile/reader/reader_settings.dart';
import 'package:reader_ui/decorations/decoration.dart';
import 'package:reader_ui/page_furniture/page_furniture.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/test_epub.dart';
import '../support/reader_pump.dart';

final _book = BookEntry(
  id: 'opening-readiness',
  title: '首屏准备',
  author: '测试作者',
  filePath: '',
  addedAt: DateTime(2026),
);

class _DeferredFonts extends ReaderFontStore {
  _DeferredFonts() : super(LibraryStore.memory());

  final font = ReaderFontEntry(
    family: 'user_${'a' * 64}',
    displayName: '测试字体',
    filePath: '',
  );
  final ready = Completer<ReaderFontEntry>();
  bool loadStarted = false;

  @override
  Future<List<ReaderFontEntry>> list() async => [font];

  @override
  Future<ReaderFontEntry> load(String family) {
    loadStarted = true;
    return ready.future;
  }
}

class _DeferredDecorations extends Fake implements ReaderDecorationStore {
  final ready = Completer<List<ReaderDecoration>>();
  int reads = 0;

  @override
  Future<List<ReaderDecoration>> list() {
    reads += 1;
    return ready.future;
  }
}

/// 取消路径仅关闭并等待释放，不应再读取晚到源的章节内容。
class _ClosingSource extends Fake implements EpubChapterSource {
  _ClosingSource(this.source);

  final EpubChapterSource source;
  final released = Completer<void>();
  int closeCalls = 0;

  @override
  bool get isClosed => source.isClosed;

  @override
  Future<void> get preparationsStopped async {
    await released.future;
    await source.preparationsStopped;
  }

  @override
  void close() {
    closeCalls += 1;
    source.close();
  }
}

void main() {
  testWidgets('源和字体并行准备，目标装饰及正文数字完成后才揭开封面', (tester) async {
    final bytes = buildTestEpub(title: _book.title);
    final source = await EpubChapterSource.open(bytes, verifyCrc: false);
    addTearDown(source.close);
    final openingSource = Completer<EpubChapterSource>();
    final fonts = _DeferredFonts();
    final decorations = _DeferredDecorations();
    final store = MemoryReaderProgressStore();
    final closed = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: BookOpeningReader(
          book: _book,
          readerBuilder: (onReady, readingActive) => EpubReaderPage(
            bytes: bytes,
            sourceFuture: openingSource.future,
            contentRevision: 'opening-fonts',
            bookId: _book.id,
            store: store,
            settings: ReaderSettings(fontFamily: fonts.font.family),
            fontStore: fonts,
            decorations: decorations,
            readingActive: readingActive,
            onReady: onReady,
            onClosed: closed.complete,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(fonts.loadStarted, isTrue);
    openingSource.complete(source);
    await tester.pump(const Duration(milliseconds: 800));
    expect(source.isClosed, isFalse);
    expect(find.byType(BookOpeningView), findsOneWidget);
    expect(find.byType(ReaderPage), findsNothing, reason: '首次排版等待用户字体');
    expect(source.anchorPreparationCount, 0);

    fonts.ready.complete(fonts.font);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.byType(ReaderPage), findsOneWidget);
    expect(decorations.reads, 1);
    expect(find.byType(BookOpeningView), findsOneWidget);
    expect(find.byType(ReaderPageFooter), findsNothing, reason: '目标装饰未准备好');

    decorations.ready.complete([]);
    await pumpReaderUntil(tester, find.byType(ReaderPageFooter));
    await tester.pumpAndSettle();
    expect(find.byType(BookOpeningView), findsNothing);
    expect(find.byType(ReaderPageHeader), findsWidgets);
    final footer = tester
        .widgetList<ReaderPageFooter>(find.byType(ReaderPageFooter))
        .first;
    expect(footer.progress, inInclusiveRange(0, 1));
    expect(
      tester.widget<ReaderPage>(find.byType(ReaderPage)).overrides?.fontFamily,
      fonts.font.family,
    );
    expect(decorations.reads, 1, reason: '揭开封面不重新读取装饰');
    expect(source.anchorPreparationCount, 1);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await closed.future;
    expect(source.isClosed, isTrue);
  });

  testWidgets('源已打开时仍等待实际内容版本，版本绑定后才创建阅读会话', (tester) async {
    final bytes = buildTestEpub(title: _book.title);
    final source = await EpubChapterSource.open(bytes, verifyCrc: false);
    addTearDown(source.close);
    final revision = Completer<String>();
    final closed = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: BookOpeningReader(
          book: _book,
          readerBuilder: (onReady, readingActive) => EpubReaderPage(
            bytes: bytes,
            sourceFuture: Future.value(source),
            contentRevisionFuture: revision.future,
            bookId: _book.id,
            store: MemoryReaderProgressStore(),
            readingActive: readingActive,
            onReady: onReady,
            onClosed: closed.complete,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 800));
    expect(source.isClosed, isFalse);
    expect(find.byType(BookOpeningView), findsOneWidget);
    expect(find.byType(ReaderPage), findsNothing);
    expect(source.anchorPreparationCount, 0);

    revision.complete('verified-content-version');
    await pumpReaderUntil(tester, find.byType(ReaderPageFooter));
    await tester.pumpAndSettle();
    final reader = tester.widget<ReaderPage>(find.byType(ReaderPage));
    expect(reader.contentRevision, 'verified-content-version');
    expect(find.byType(BookOpeningView), findsNothing);
    expect(find.byType(ReaderPageFooter), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await closed.future;
  });

  testWidgets('取消后晚到的源只释放一次，准备失败和退出共用关闭任务', (tester) async {
    final source = await EpubChapterSource.open(
      buildTestEpub(),
      verifyCrc: false,
    );
    addTearDown(source.close);
    final observed = _ClosingSource(source);
    final pending = Completer<EpubChapterSource>();
    final settings = Completer<ReaderSettings>();
    var closed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: EpubReaderPage(
          sourceFuture: pending.future,
          settingsFuture: settings.future,
          contentRevision: 'cancelled-opening',
          bookId: _book.id,
          store: MemoryReaderProgressStore(),
          onClosed: () => closed += 1,
        ),
      ),
    );
    settings.completeError(StateError('测试设置读取失败'));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('epub-open-error')),
      findsOneWidget,
      reason: '准备失败无需等其他异步任务结束才展示',
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(closed, 0);
    expect(observed.closeCalls, 0);
    pending.complete(observed);
    await tester.pump();
    await tester.pump();
    expect(observed.isClosed, isTrue);
    expect(observed.closeCalls, 1);
    expect(closed, 0, reason: '退出回调等待准备任务实际释放');
    observed.released.complete();
    await tester.pump();
    expect(closed, 1);
    expect(find.byType(ReaderPage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('打开失败会解除封面，关闭系统动画时无需等待开场时长', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: BookOpeningReader(
          book: _book,
          readerBuilder: (onReady, readingActive) => EpubReaderPage(
            bytes: Uint8List.fromList([1, 2, 3]),
            bookId: _book.id,
            store: MemoryReaderProgressStore(),
            readingActive: readingActive,
            onReady: onReady,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byType(BookOpeningView), findsNothing);
    expect(find.byKey(const ValueKey('epub-open-error')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
