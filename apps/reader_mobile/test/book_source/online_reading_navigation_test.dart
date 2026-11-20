import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

  testWidgets('最近阅读断网续读不请求详情目录，原EPUB书架和进度保持', (tester) async {
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
    expect(
      f.requested.where((path) => path == '/book' || path == '/toc'),
      isEmpty,
    );
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

  testWidgets('来源模式或目录规则更新后，旧最近阅读卡片不能继续打开', (tester) async {
    final fixture = await tester.runAsync(() => _ReadingFixture.create(3));
    final f = fixture!;
    addTearDown(f.dispose);
    final book = f.readingBook;
    await pumpReaderTask(
      tester,
      f.controller.catalogs.remember(f.source, book.book, book.chapters),
    );
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
    oldRulesTap();
    await pumpReaderUntil(tester, find.text('目录或来源已更新，请重新打开详情获取目录'));
    expect(opens, 0);
    expect(f.requested, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
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
    int count,
  ) {
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
            url: 'https://example.test/${index + 1}',
          ),
      ],
      service: service,
    );
  }

  final Directory directory;
  final AppDatabase db;
  final LibraryStore library;
  final BookSource source;
  final BookSourceService service;
  final OnlineBookController controller;
  late final OnlineReadingBook readingBook;
  final requested = <String>[];
  bool offline = false;
  Completer<void>? catalogGate;

  static Future<_ReadingFixture> create(int count) async {
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
          if (path == '/book') await fixture.catalogGate?.future;
          if (fixture.offline) return http.Response('离线测试', 503);
          return http.Response(
            jsonEncode(switch (path) {
              '/book' => {'toc': '/toc'},
              '/toc' => {
                'chapters': [
                  for (var index = 0; index < count; index++)
                    {'title': '第${index + 1}章', 'url': '/${index + 1}'},
                ],
              },
              _ => {'content': '<p>第${path.substring(1)}章的缓存正文，供离线续读。</p>'},
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

  Future<void> dispose() async {
    if (catalogGate != null && !catalogGate!.isCompleted) {
      catalogGate!.complete();
    }
    controller.dispose();
    await db.close();
    await directory.delete(recursive: true);
  }
}
