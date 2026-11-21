import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_mobile/book_source/book_source_cookie_store.dart';
import 'package:reader_mobile/book_source/book_source_http_client.dart';
import 'package:reader_mobile/book_source/book_source_models.dart';
import 'package:reader_mobile/book_source/book_source_service.dart';
import 'package:reader_mobile/book_source/book_source_store.dart';
import 'package:reader_mobile/book_source/online_book_controller.dart';
import 'package:reader_mobile/book_source/online_book_detail_page.dart';
import 'package:reader_mobile/book_source/online_chapter_content_store.dart';
import 'package:reader_mobile/book_source/online_chapter_request.dart';
import 'package:reader_mobile/book_source/online_reading_book.dart';
import 'package:reader_mobile/book_source/online_search_page.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/reader/book_opener.dart';
import 'package:reader_mobile/reader/reader_settings.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/reader_pump.dart';
import '../support/test_epub.dart';

void main() {
  testWidgets('目录请求未返回时缓存仍可打开，并从完整目录直达第75章', (tester) async {
    final fixture = await tester.runAsync(() => _ReadingFixture.create(80));
    final f = fixture!;
    addTearDown(f.dispose);
    final book = f.readingBook;
    await pumpReaderTask(tester, f.cacheChapter(74));
    await pumpReaderTask(
      tester,
      f.controller.catalogs.save(f.source, book.book, book.chapters),
    );
    f.offline = true;
    f.catalogGate = Completer<void>();
    f.requested.clear();
    final opener = BookOpener(
      library: f.library,
      progressStore: MemoryReaderProgressStore(),
    );
    Future<void>? opened;
    int? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: OnlineBookDetailPage(
          controller: f.controller,
          source: f.source,
          book: book.book,
          onRead: (context, reading, {startChapter}) {
            selected = startChapter;
            return opened = opener.openOnline(
              context,
              reading,
              startChapter: startChapter,
            );
          },
        ),
      ),
    );
    await pumpReaderUntil(
      tester,
      find.byKey(const ValueKey('online-book-read')),
    );
    expect(f.requested, ['/book']);
    final fullToc = find.byKey(const ValueKey('online-book-full-toc'));
    await tester.scrollUntilVisible(
      fullToc,
      600,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(fullToc);
    await pumpReaderUntil(
      tester,
      find.byKey(const ValueKey('online-toc-query')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('online-toc-query')),
      '第75章',
    );
    await tester.pump();
    await tester.tap(find.text('75. 第75章'));
    await pumpReaderUntil(tester, find.byKey(const ValueKey('reader-content')));
    expect(selected, 74);
    final source =
        tester.widget<ReaderPage>(find.byType(ReaderPage)).source
            as EpubChapterSource;
    expect(
      (await pumpReaderTask(tester, source.loadAnchorChapter(74))).text,
      contains('第75章的缓存正文'),
    );
    expect(f.requested.where((path) => path == '/75'), isEmpty);
    f.catalogGate!.complete();
    Navigator.of(tester.element(find.byType(ReaderPage))).pop();
    await pumpReaderTask(tester, opened!);
    final saved = await pumpReaderTask(
      tester,
      OnlineReadingProgress(f.library, book).load(book.id),
    );
    expect(saved?.spineIndex, 74);
    expect(f.requested.where((path) => path == '/toc'), isEmpty);
    expect(
      (await pumpReaderTask(
        tester,
        f.controller.catalogs.read(f.source, book.book),
      ))?.chapters.length,
      80,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('最近阅读刷新失败仍可离线续读，原EPUB书架和进度保持', (tester) async {
    final fixture = await tester.runAsync(() => _ReadingFixture.create(3));
    final f = fixture!;
    addTearDown(f.dispose);
    final local = await pumpReaderTask(
      tester,
      f.library.importBytes(
        buildTestEpub(title: '原有 EPUB', paragraphs: ['原有 EPUB 的正常正文。']),
      ),
    );
    final localStore = MemoryReaderProgressStore();
    final localProgress = ReaderProgress(
      spineIndex: 0,
      pageIndex: 0,
      contentRevision: local.contentRevision,
    );
    await localStore.save(local.id, localProgress);
    await pumpReaderTask(
      tester,
      f.library.setSetting(ReaderSettingsStore.keyFontSize, '21.0'),
    );
    final book = f.readingBook;
    await pumpReaderTask(tester, f.cacheChapter(1));
    await pumpReaderTask(
      tester,
      f.controller.catalogs.remember(f.source, book.book, book.chapters),
    );
    await pumpReaderTask(
      tester,
      OnlineReadingProgress(f.library, book).save(
        book.id,
        ReaderProgress(
          spineIndex: 1,
          pageIndex: 0,
          contentRevision: book.revision,
        ),
      ),
    );
    f.offline = true;
    f.requested.clear();
    final opener = BookOpener(library: f.library, progressStore: localStore);
    Future<void>? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: OnlineSearchPage(
          controller: f.controller,
          onRead: (context, reading, {startChapter}) => opened = opener
              .openOnline(context, reading, startChapter: startChapter),
        ),
      ),
    );
    final recent = find.byKey(ValueKey('online-recent-${book.book.bookUrl}'));
    await pumpReaderUntil(tester, recent);
    await tester.tap(recent);
    await pumpReaderUntil(tester, find.byKey(const ValueKey('reader-content')));
    final source =
        tester.widget<ReaderPage>(find.byType(ReaderPage)).source
            as EpubChapterSource;
    expect(
      (await pumpReaderTask(tester, source.loadAnchorChapter(1))).text,
      contains('第2章的缓存正文'),
    );
    expect(f.requested.where((path) => path == '/book'), hasLength(1));
    expect(f.requested.where((path) => path == '/toc'), isEmpty);
    Navigator.of(tester.element(find.byType(ReaderPage))).pop();
    await pumpReaderTask(tester, opened!);
    expect(
      (await pumpReaderTask(tester, f.library.list())).map((entry) => entry.id),
      [local.id],
    );
    expect(await localStore.load(local.id), same(localProgress));
    expect(
      await pumpReaderTask(
        tester,
        f.library.getSetting(ReaderSettingsStore.keyFontSize),
      ),
      '21.0',
    );
    expect(
      (await pumpReaderTask(
        tester,
        OnlineReadingProgress(f.library, book).load(book.id),
      ))?.spineIndex,
      1,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('来源模式变化后旧入口停用，目录规则变化后有网自动重取', (tester) async {
    final fixture = await tester.runAsync(() => _ReadingFixture.create(3));
    final f = fixture!;
    addTearDown(f.dispose);
    final book = f.readingBook;
    await pumpReaderTask(
      tester,
      f.controller.catalogs.remember(f.source, book.book, book.chapters),
    );
    var opens = 0;
    OnlineReadingBook? openedBook;
    await tester.pumpWidget(
      MaterialApp(
        home: OnlineSearchPage(
          controller: f.controller,
          onRead: (_, reading, {startChapter}) async {
            opens++;
            openedBook = reading;
          },
        ),
      ),
    );
    final recent = find.byKey(ValueKey('online-recent-${book.book.bookUrl}'));
    await pumpReaderUntil(tester, recent);
    final oldTap = tester.widget<ListTile>(recent).onTap!;
    await pumpReaderTask(
      tester,
      f.controller.setSourceLoadMode(f.source.id, BookSourceLoadMode.book),
    );
    oldTap();
    await tester.pump();
    expect(opens, 0);
    await pumpReaderTask(
      tester,
      f.controller.setSourceLoadMode(f.source.id, BookSourceLoadMode.chapter),
    );
    await pumpReaderUntil(tester, recent);
    final oldRulesTap = tester.widget<ListTile>(recent).onTap!;
    await pumpReaderTask(
      tester,
      f.controller.importText(
        jsonEncode({
          ...f.source.toJson(),
          'ruleToc': {
            'chapterList': r'$.catalog[*]',
            'chapterName': r'$.title',
            'chapterUrl': r'$.url',
          },
        }),
      ),
    );
    f.catalogRoot = 'catalog';
    f.remoteOrder = [1, 2, 3, 4];
    oldRulesTap();
    await pumpReaderUntilComplete(tester, () => opens == 1);
    expect(openedBook?.source.toc.chapterList, r'$.catalog[*]');
    expect(openedBook?.chapters, hasLength(4));
    expect(f.requested, ['/book', '/toc']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('目录规则失效仍保留最近入口，断网时不误用旧目录', (tester) async {
    final fixture = await tester.runAsync(() => _ReadingFixture.create(3));
    final f = fixture!;
    addTearDown(f.dispose);
    final book = f.readingBook;
    await pumpReaderTask(
      tester,
      f.controller.catalogs.remember(f.source, book.book, book.chapters),
    );
    await pumpReaderTask(
      tester,
      f.controller.importText(
        jsonEncode({
          ...f.source.toJson(),
          'ruleToc': {
            'chapterList': r'$.catalog[*]',
            'chapterName': r'$.title',
            'chapterUrl': r'$.url',
          },
        }),
      ),
    );
    f.offline = true;
    var opens = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: OnlineSearchPage(
          controller: f.controller,
          onRead: (_, _, {startChapter}) async => opens++,
        ),
      ),
    );
    final recent = find.byKey(ValueKey('online-recent-${book.book.bookUrl}'));
    await pumpReaderUntil(tester, recent);
    expect(find.textContaining('目录待更新'), findsOneWidget);
    await tester.tap(recent);
    await pumpReaderUntil(tester, find.textContaining('无法继续阅读'));
    expect(opens, 0);
    expect(f.requested, ['/book']);
    expect(
      await pumpReaderTask(
        tester,
        f.controller.catalogs.read(f.controller.sources.single, book.book),
      ),
      isNull,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('最近阅读快速更新目录后新增章立即可读，原章节CFI保留', (tester) async {
    final fixture = await tester.runAsync(() => _ReadingFixture.create(3));
    final f = fixture!;
    addTearDown(f.dispose);
    final book = f.readingBook;
    await pumpReaderTask(
      tester,
      f.controller.catalogs.remember(f.source, book.book, book.chapters),
    );
    final before = await pumpReaderTask(tester, f.saveProgress(1));
    expect(before?.cfi, isNotNull);
    f.remoteOrder = [1, 2, 3, 4];
    f.requested.clear();
    final opener = BookOpener(
      library: f.library,
      progressStore: MemoryReaderProgressStore(),
    );
    Future<void>? opened;
    ReaderProgress? restored;
    OnlineReadingBook? openedBook;
    await tester.pumpWidget(
      MaterialApp(
        home: OnlineSearchPage(
          controller: f.controller,
          onRead: (context, reading, {startChapter}) async {
            openedBook = reading;
            restored = await OnlineReadingProgress(
              f.library,
              reading,
            ).load(reading.id);
            await (opened = opener.openOnline(
              context,
              reading,
              startChapter: startChapter,
            ));
          },
        ),
      ),
    );
    await pumpReaderUntil(
      tester,
      find.byKey(ValueKey('online-recent-${book.book.bookUrl}')),
    );
    await tester.tap(
      find.byKey(ValueKey('online-recent-${book.book.bookUrl}')),
    );
    await pumpReaderUntil(tester, find.byKey(const ValueKey('reader-content')));
    expect(openedBook?.chapters, hasLength(4));
    expect(restored?.spineIndex, 1);
    expect(restored?.cfi, before?.cfi);
    final source =
        tester.widget<ReaderPage>(find.byType(ReaderPage)).source
            as EpubChapterSource;
    expect(source.toc, hasLength(4));
    expect(
      (await pumpReaderTask(tester, source.loadAnchorChapter(3))).text,
      contains('第4章的缓存正文'),
    );
    expect(f.requested.where((path) => path == '/book'), hasLength(1));
    expect(f.requested.where((path) => path == '/toc'), hasLength(1));
    Navigator.of(tester.element(find.byType(ReaderPage))).pop();
    await pumpReaderTask(tester, opened!);
    expect(
      (await pumpReaderTask(
        tester,
        f.controller.catalogs.read(f.source, book.book),
      ))?.chapters,
      hasLength(4),
    );
    expect(await pumpReaderTask(tester, f.library.list()), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await pumpReaderTask(tester, f.service.chapterRequestsStopped);
  });

  testWidgets('最近阅读目录请求缓慢时先读缓存，后台更新保持会话目录不变', (tester) async {
    final fixture = await tester.runAsync(() => _ReadingFixture.create(3));
    final f = fixture!;
    addTearDown(f.dispose);
    final book = f.readingBook;
    await pumpReaderTask(
      tester,
      f.controller.catalogs.remember(f.source, book.book, book.chapters),
    );
    await pumpReaderTask(tester, f.saveProgress(1));
    f.requested.clear();
    f.catalogGate = Completer<void>();
    f.remoteOrder = [1, 2, 3, 4];
    final opener = BookOpener(
      library: f.library,
      progressStore: MemoryReaderProgressStore(),
    );
    Future<void>? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: OnlineSearchPage(
          controller: f.controller,
          onRead: (context, reading, {startChapter}) => opened = opener
              .openOnline(context, reading, startChapter: startChapter),
        ),
      ),
    );
    final recent = find.byKey(ValueKey('online-recent-${book.book.bookUrl}'));
    await pumpReaderUntil(tester, recent);
    await tester.tap(recent);
    await pumpReaderUntil(tester, find.byKey(const ValueKey('reader-content')));
    expect(f.catalogGate!.isCompleted, isFalse);
    final source =
        tester.widget<ReaderPage>(find.byType(ReaderPage)).source
            as EpubChapterSource;
    expect(source.toc, hasLength(3));
    expect(
      (await pumpReaderTask(tester, source.loadAnchorChapter(1))).text,
      contains('第2章的缓存正文'),
    );
    final sharedRefresh = f.controller.refreshCatalog(f.source, book.book);
    f.catalogGate!.complete();
    await pumpReaderTask(tester, sharedRefresh);
    expect(source.toc, hasLength(3));
    final updated = await pumpReaderTask(
      tester,
      f.controller.catalogs.read(f.source, book.book),
    );
    expect(updated?.chapters, hasLength(4));
    expect(f.requested.where((path) => path == '/book'), hasLength(1));
    expect(f.requested.where((path) => path == '/2'), isEmpty);
    Navigator.of(tester.element(find.byType(ReaderPage))).pop();
    await pumpReaderTask(tester, opened!);
    expect(
      (await pumpReaderTask(
        tester,
        OnlineReadingProgress(
          f.library,
          OnlineReadingBook(
            source: f.source,
            book: updated!.book,
            chapters: updated.chapters,
            service: f.service,
          ),
        ).load(book.id),
      ))?.spineIndex,
      1,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('完整目录打开后后台重排，同一POST地址按章节参数跳转', (tester) async {
    final fixture = await tester.runAsync(
      () => _ReadingFixture.create(80, postChapters: true),
    );
    final f = fixture!;
    addTearDown(f.dispose);
    final book = f.readingBook;
    await pumpReaderTask(
      tester,
      f.controller.catalogs.save(f.source, book.book, book.chapters),
    );
    f.catalogGate = Completer<void>();
    f.remoteOrder = [
      75,
      for (var index = 1; index <= 80; index++)
        if (index != 75) index,
      81,
    ];
    final opener = BookOpener(
      library: f.library,
      progressStore: MemoryReaderProgressStore(),
    );
    Future<void>? opened;
    int? selected;
    OnlineReadingBook? openedBook;
    await tester.pumpWidget(
      MaterialApp(
        home: OnlineBookDetailPage(
          controller: f.controller,
          source: f.source,
          book: book.book,
          onRead: (context, reading, {startChapter}) {
            openedBook = reading;
            selected = startChapter;
            return opened = opener.openOnline(
              context,
              reading,
              startChapter: startChapter,
            );
          },
        ),
      ),
    );
    await pumpReaderUntil(
      tester,
      find.byKey(const ValueKey('online-book-read')),
    );
    final sharedRefresh = f.controller.refreshCatalog(f.source, book.book);
    final fullToc = find.byKey(const ValueKey('online-book-full-toc'));
    await tester.scrollUntilVisible(
      fullToc,
      600,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(fullToc);
    await pumpReaderUntil(
      tester,
      find.byKey(const ValueKey('online-toc-query')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('online-toc-query')),
      '第75章',
    );
    await tester.pump();
    expect(find.text('75. 第75章'), findsOneWidget);
    f.catalogGate!.complete();
    await pumpReaderTask(tester, sharedRefresh);
    await tester.tap(find.text('75. 第75章'));
    await pumpReaderUntil(tester, find.byKey(const ValueKey('reader-content')));
    expect(selected, 0);
    expect(openedBook?.chapters, hasLength(81));
    expect(openedBook?.chapters.first.requestOptions['body'], 'chapter=75');
    final source =
        tester.widget<ReaderPage>(find.byType(ReaderPage)).source
            as EpubChapterSource;
    expect(
      (await pumpReaderTask(tester, source.loadAnchorChapter(0))).text,
      contains('第75章的缓存正文'),
    );
    expect(f.requested.where((path) => path == '/book'), hasLength(1));
    expect(f.requested.where((path) => path == '/toc'), hasLength(1));
    Navigator.of(tester.element(find.byType(ReaderPage))).pop();
    await pumpReaderTask(tester, opened!);
    expect(
      (await pumpReaderTask(
        tester,
        f.controller.catalogs.read(f.source, book.book),
      ))?.chapters.first.requestOptions['body'],
      'chapter=75',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  test('目录刷新合并等价请求，隔离同一详情接口不同POST参数', () async {
    final f = await _ReadingFixture.create(3);
    addTearDown(f.dispose);
    final book = f.readingBook.book;
    final first = book.copyWith(
      bookOptions: {
        'method': 'POST',
        'body': 'book=one',
        'headers': {'A': '1', 'B': '2'},
      },
    );
    final equivalent = first.copyWith(
      bookOptions: {
        'headers': {'B': '2', 'A': '1'},
        'body': 'book=one',
        'method': 'POST',
      },
    );
    final second = book.copyWith(
      bookOptions: {'method': 'POST', 'body': 'book=two'},
    );
    f.catalogGate = Completer<void>();
    final one = f.controller.refreshCatalog(f.source, first);
    final equivalentTask = f.controller.refreshCatalog(f.source, equivalent);
    final two = f.controller.refreshCatalog(f.source, second);
    expect(identical(one, equivalentTask), isTrue);
    expect(identical(one, two), isFalse);
    f.catalogGate!.complete();
    await Future.wait([one, two]);
    expect(f.requested.where((path) => path == '/book'), hasLength(2));
    expect(f.detailBodies, unorderedEquals(['book=one', 'book=two']));
  });

  test('来源规则更新后的旧响应不能覆盖已保存的新目录', () async {
    final f = await _ReadingFixture.create(3);
    addTearDown(f.dispose);
    final book = f.readingBook.book;
    final gate = f.catalogGate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    final started = f.detailStarted = Completer<void>();
    final old = f.controller.refreshCatalog(f.source, book);
    await started.future.timeout(const Duration(seconds: 5));
    await f.controller.importText(
      jsonEncode({...f.source.toJson(), 'header': '{"X-Catalog-Version":"2"}'}),
    );
    final changed = f.controller.sources.single;
    f.catalogGate = null;
    f.remoteOrder = [1, 2, 3, 4];
    await f.controller.refreshCatalog(changed, book.copyWith(name: '更新书名'));
    gate.complete();
    await expectLater(old, throwsA(isA<BookSourceException>()));
    final current = await f.controller.catalogs.read(changed, book);
    expect(current?.book.name, '更新书名');
    expect(current?.chapters, hasLength(4));
    expect(await f.controller.catalogs.read(f.source, book), isNull);
  });

  test('正文v3升级v4后同地址POST续读保留原章，旧章内坐标重置', () async {
    final f = await _ReadingFixture.create(3, postChapters: true);
    addTearDown(f.dispose);
    final book = f.readingBook;
    String digest(Object value) =>
        sha256.convert(utf8.encode(jsonEncode(value))).toString();
    final legacyRules = digest({
      'version': 3,
      'base': f.source.baseUrl,
      'headers': f.source.header,
      'jsLib': f.source.jsLib,
      'content': f.source.content.content,
      'next': f.source.content.nextContentUrl,
      'replace': f.source.content.replaceRegex,
      'source': f.source.content.sourceRegex,
    });
    final legacyChapters = [
      for (final (index, chapter) in book.chapters.indexed)
        digest([
          legacyRules,
          chapter.title,
          chapter.updateTime,
          onlineChapterIdentity(chapter),
          if (index + 1 < book.chapters.length)
            onlineChapterIdentity(book.chapters[index + 1]),
        ]),
    ];
    final legacyRevision = digest([
      '在线正文1',
      book.id,
      for (final (index, chapter) in book.chapters.indexed)
        [chapter.url, legacyChapters[index]],
    ]);
    await f.library.setSetting(
      'online_reading_progress:${book.id}',
      jsonEncode({
        'url': book.chapters[1].url,
        'chapterIdentity': onlineChapterIdentity(book.chapters[1]),
        'revision': legacyRevision,
        'chapterRevision': legacyChapters[1],
        'spine': 1,
        'page': 8,
        'cfi': 'epubcfi(/6/4!/4/2/1:12)',
        'scroll': 135.0,
        'layout': '旧版布局',
        'approximate': false,
        'finished': true,
      }),
    );

    expect(f.service.contentRulesFingerprint(f.source), isNot(legacyRules));
    final restored = await OnlineReadingProgress(f.library, book).load(book.id);
    expect(restored?.spineIndex, 1);
    expect(restored?.pageIndex, 0);
    expect(restored?.cfi, isNull);
    expect(restored?.scrollOffset, isNull);
    expect(restored?.layoutFingerprint, isNull);
    expect(restored?.approximate, isTrue);
    expect(restored?.finished, isFalse);
    expect(restored?.contentRevision, book.revision);
    expect(f.requested, isEmpty);
  });
}

class _ReadingFixture {
  _ReadingFixture(
    this.directory,
    this.db,
    this.library,
    this.source,
    this.service,
    this.controller,
    int count, {
    bool postChapters = false,
  }) {
    readingBook = OnlineReadingBook(
      source: source,
      book: OnlineBook(
        sourceId: source.id,
        sourceName: source.name,
        name: '缓存测试书',
        author: '测试作者',
        bookUrl: 'https://example.test/book',
        tocUrl: 'https://example.test/toc',
      ),
      chapters: [
        for (var index = 0; index < count; index++)
          OnlineChapter(
            index: index,
            title: '第${index + 1}章',
            url: postChapters
                ? 'https://example.test/content'
                : 'https://example.test/${index + 1}',
            requestOptions: postChapters
                ? {'method': 'POST', 'body': 'chapter=${index + 1}'}
                : const {},
          ),
      ],
      service: service,
    );
    remoteOrder = [for (var index = 1; index <= count; index++) index];
    this.postChapters = postChapters;
  }

  final Directory directory;
  final AppDatabase db;
  final LibraryStore library;
  final BookSource source;
  final BookSourceService service;
  final OnlineBookController controller;
  late final OnlineReadingBook readingBook;
  final requested = <String>[];
  final detailBodies = <String>[];
  late List<int> remoteOrder;
  late final bool postChapters;
  String catalogRoot = 'chapters';
  bool offline = false;
  Completer<void>? catalogGate;
  Completer<void>? detailStarted;

  static Future<_ReadingFixture> create(
    int count, {
    bool postChapters = false,
  }) async {
    final directory = await Directory.systemTemp.createTemp('online-nav-');
    final db = AppDatabase(NativeDatabase.memory());
    final library = LibraryStore(
      database: db,
      directoryProvider: () async => directory,
    );
    final store = BookSourceStore(directoryProvider: () async => directory);
    final source = await store.importText(
      jsonEncode({
        'bookSourceName': '缓存测试源',
        'bookSourceUrl': 'https://example.test',
        'searchUrl': '/search?key={{key}}',
        'ruleSearch': {'bookList': r'$.books[*]'},
        'ruleBookInfo': {'tocUrl': r'$.toc'},
        'ruleToc': {
          'chapterList': r'$.chapters[*]',
          'chapterName': r'$.title',
          'chapterUrl': r'$.url',
        },
        'ruleContent': {'content': r'$.content'},
      }),
    );
    final cookies = BookSourceCookieStore(
      directoryProvider: () async => directory,
    );
    late final _ReadingFixture fixture;
    final service = BookSourceService(
      cookieStore: cookies,
      chapterContentStore: OnlineChapterContentStore(
        directoryProvider: () async => directory,
      ),
      httpClient: BookSourceHttpClient(
        cookieStore: cookies,
        client: MockClient((request) async {
          final path = request.url.path;
          fixture.requested.add(path);
          if (path == '/book') {
            fixture.detailBodies.add(request.body);
            if (fixture.detailStarted?.isCompleted == false) {
              fixture.detailStarted!.complete();
            }
            await fixture.catalogGate?.future;
          }
          if (fixture.offline) return http.Response('离线测试', 503);
          return http.Response(
            jsonEncode(switch (path) {
              '/book' => {'toc': '/toc'},
              '/toc' => {
                fixture.catalogRoot: [
                  for (final number in fixture.remoteOrder)
                    {
                      'title': '第$number章',
                      'url': fixture.postChapters
                          ? '/content,${jsonEncode({'method': 'POST', 'body': 'chapter=$number'})}'
                          : '/$number',
                    },
                ],
              },
              _ => {
                'content':
                    '<p>第${path == '/content' ? request.body.split('=').last : path.substring(1)}章的缓存正文，供离线续读。</p>',
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );
    fixture = _ReadingFixture(
      directory,
      db,
      library,
      source,
      service,
      OnlineBookController(
        library: library,
        store: store,
        service: service,
        cookieStore: cookies,
      ),
      count,
      postChapters: postChapters,
    );
    await fixture.controller.initialize();
    return fixture;
  }

  Future<String> cacheChapter(int index) => service.fetchChapterContent(
    source,
    readingBook.chapters[index],
    readingBook.book.bookUrl,
    nextChapter: index + 1 < readingBook.chapters.length
        ? readingBook.chapters[index + 1]
        : null,
  );

  Future<ReaderProgress?> saveProgress(int index) async {
    final source = readingBook.open();
    final store = OnlineReadingProgress(
      library,
      readingBook,
      startChapter: index,
    );
    final session = ReaderSession(
      source: source,
      store: store,
      bookId: readingBook.id,
      contentRevision: readingBook.revision,
      persistInitialPosition: true,
    );
    try {
      await session.open(contentWidth: 325, contentHeight: 580);
      await session.flushProgress();
      return await store.load(readingBook.id);
    } finally {
      session.dispose();
      source.close();
      await source.preparationsStopped;
    }
  }

  Future<void> dispose() async {
    if (catalogGate != null && !catalogGate!.isCompleted) {
      catalogGate!.complete();
    }
    controller.dispose();
    await service.chapterRequestsStopped;
    await db.close();
    await directory.delete(recursive: true);
  }
}
