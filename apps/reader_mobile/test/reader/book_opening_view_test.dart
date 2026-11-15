import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/editing.dart';
import 'package:reader_mobile/editing/book_editor_page.dart';
import 'package:reader_mobile/editing/book_edit_repository.dart';
import 'package:reader_mobile/diagnostics/reader_log.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/library/revision_anchor_index.dart';
import 'package:reader_mobile/reader/book_opener.dart';
import 'package:reader_mobile/reader/book_opening_view.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_mobile/reader/epub_reader_page.dart';
import 'package:reader_mobile/reader/reader_settings.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/storage/drift_progress_store.dart';
import 'package:reader_ui/a11y/semantics_layer.dart';
import 'package:reader_ui/page_furniture/page_furniture.dart';
import 'package:reader_ui/reader_page.dart';

import '../support/test_epub.dart';
import '../support/reader_pump.dart';
import '../library/fixtures/revision_epub.dart';

import 'package:reader_ui/reader_session.dart';

class _DelayedLibraryStore extends LibraryStore {
  _DelayedLibraryStore() : super.memory();

  final Completer<Uint8List> _bytes = Completer<Uint8List>();

  @override
  Future<Uint8List> readBytes(BookEntry entry) => _bytes.future;

  void finish(Uint8List bytes) => _bytes.complete(bytes);
}

class _ReopenProgressStore extends DriftProgressStore {
  _ReopenProgressStore(super.db);
  final sources = <EpubChapterSource>[];

  @override
  Future<void Function()> bindSource(
    String bookId,
    EpubChapterSource source,
    String revision,
  ) {
    if (sources.isNotEmpty) {
      expect(sources.last.isClosed, isTrue, reason: '新版本绑定前必须释放旧章节源');
    }
    sources.add(source);
    return super.bindSource(bookId, source, revision);
  }
}

Future<void> _pumpFrames(WidgetTester tester, {int frames = 12}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets(
    '手机阅读菜单与选区不提供 EPUB 编辑入口',
    (tester) async {
      late Directory temporary;
      late File epub;
      await tester.runAsync(() async {
        temporary = await Directory.systemTemp.createTemp('reader-no-editor-');
        epub = await File('${temporary.path}/book.epub')
            .writeAsBytes(buildTestEpub());
      });
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() => temporary.delete(recursive: true));
      });
      await tester.pumpWidget(
        MaterialApp(
          home: EpubReaderPage(
            sourcePath: epub.path,
            bookId: 'mobile-no-editor',
            store: MemoryReaderProgressStore(),
            bookEditorRepository: BookEditRepository(LibraryStore.memory()),
          ),
        ),
      );
      await pumpReaderUntil(tester, find.byType(ReaderPageFooter));
      final reader = tester.widget<ReaderPage>(find.byType(ReaderPage));
      expect(reader.onOpenEditor, isNull);
      expect(reader.onEditTarget, isNull);
      await tester.tapAt(const Offset(400, 300));
      await _pumpFrames(tester);
      expect(find.byTooltip('编辑书籍'), findsNothing);
      expect(find.text('编辑原文'), findsNothing);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets('保存编辑后自动重开新版本并保留设置书签和已迁移进度', (tester) async {
    late Directory temporary;
    late AppDatabase db;
    late LibraryStore library;
    late BookEntry entry;
    late _ReopenProgressStore progress;
    await tester.runAsync(() async {
      temporary = await Directory.systemTemp.createTemp('reader-reopen-');
      db = AppDatabase(NativeDatabase.memory());
      library = LibraryStore(
        database: db,
        directoryProvider: () async => temporary,
      );
      entry = await library.importBytes(buildRevisionTestEpub());
      progress = _ReopenProgressStore(db);
      final index = await buildRevisionAnchorBookFile(
        File(entry.filePath),
        revision: entry.contentRevision!,
      );
      final chapter = index.chapter(1)!;
      final cfi = chapter.cfiAt(chapter.text.indexOf(revisionBookmarkQuote))!;
      await progress.save(
        entry.id,
        ReaderProgress(
          spineIndex: 1,
          pageIndex: 0,
          cfi: cfi,
          contentRevision: entry.contentRevision,
        ),
      );
      await library
          .bookmarkStore(entry.id)!
          .add(cfi: cfi, spineIndex: 1, label: '保存后仍在原章');
      await ReaderSettingsStore(library)
          .save(const ReaderSettings(fontSize: 23));
    });
    const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      pathChannel,
      (_) async => temporary.path,
    );
    addTearDown(() async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        pathChannel,
        null,
      );
      await tester.pumpWidget(const SizedBox());
      await pumpReaderUntilComplete(
        tester,
        () => progress.sources.every((source) => source.isClosed),
      );
      await tester.runAsync(() async {
        await db.close();
        await temporary.delete(recursive: true);
      });
    });
    final opener = BookOpener(library: library, progressStore: progress);
    final contextKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(key: contextKey, builder: (_) => const Text('书架')),
        ),
      ),
    );
    final opened = opener.open(contextKey.currentContext!, entry);
    await pumpReaderUntil(tester, find.byType(ReaderPageFooter));
    await _pumpFrames(tester);
    final oldReader = tester.widget<ReaderPage>(find.byType(ReaderPage));
    final oldSource = oldReader.source as EpubChapterSource;
    oldReader.onOpenEditor!();
    await pumpReaderUntil(tester, find.byType(BookEditorPage));
    final editor = tester
        .widget<BookEditorPage>(find.byType(BookEditorPage))
        .controller;
    final paragraph = editor.session
        .editableDocument('OEBPS/first.xhtml')
        .elements
        .firstWhere((node) => node.tag == 'p');
    expect(
      editor.runCommand(
        () => editor.session.replaceText(paragraph, '保存后的新正文。'),
      ),
      isTrue,
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('保存书籍'));
    await pumpReaderUntilComplete(
      tester,
      () => find.byType(BookEditorPage).evaluate().isEmpty,
      description: '编辑保存完成',
      maxFrames: 240,
    );
    await pumpReaderUntilComplete(
      tester,
      () {
        final readers = tester.widgetList<ReaderPage>(find.byType(ReaderPage));
        return find.byType(BookEditorPage).evaluate().isEmpty &&
            readers.length == 1 &&
            readers.single.source != oldSource;
      },
      description: '保存后自动重开',
      maxFrames: 240,
    );
    await pumpReaderUntil(tester, find.byType(ReaderPageFooter));
    final newReader = tester.widget<ReaderPage>(find.byType(ReaderPage));
    expect(oldSource.isClosed, isTrue);
    expect(newReader.contentRevision, isNot(entry.contentRevision));
    expect(newReader.overrides!.fontSize, 23);
    final page = tester
        .widget<ReaderSemanticsLayer>(find.byType(ReaderSemanticsLayer))
        .page;
    expect(page.spineIndex, 1);
    await tester.runAsync(() async {
      final saved = await library.bookById(entry.id);
      expect(newReader.contentRevision, saved!.contentRevision);
      final before = (await db.select(db.readingProgress).getSingle()).toJson();
      await progress.save(
        entry.id,
        ReaderProgress(
          spineIndex: 0,
          pageIndex: 0,
          cfi: 'epubcfi(/6/2!/4/2/1:0)',
          contentRevision: entry.contentRevision,
        ),
      );
      expect(
        (await db.select(db.readingProgress).getSingle()).toJson(),
        before,
        reason: '旧会话晚到的保存不能覆盖新版迁移位置',
      );
      expect(
        (await progress.load(entry.id))!.contentRevision,
        saved.contentRevision,
      );
      expect(
        (await library.bookmarkStore(entry.id)!.list()).single.label,
        '保存后仍在原章',
      );
    });
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await _pumpFrames(tester);
    await pumpReaderTask(tester, opened);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

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
    final log = ReaderLog.instance;
    log.resetForTest();
    addTearDown(log.resetForTest);
    await pumpReaderTask(tester, log.clear());
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
    final text = await pumpReaderTask(tester, log.exportText());
    expect(text, contains('user_open_book'));
    expect(text, contains('book_id=${entry.id.substring(0, 8)}'));
    expect(text, isNot(contains(entry.title)), reason: '开书诊断不能记录明文书名');
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
