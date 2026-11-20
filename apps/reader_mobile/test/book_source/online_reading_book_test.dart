import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reader_mobile/book_source/book_source_cookie_store.dart';
import 'package:reader_mobile/book_source/book_source_http_client.dart';
import 'package:reader_mobile/book_source/book_source_models.dart';
import 'package:reader_mobile/book_source/book_source_service.dart';
import 'package:reader_mobile/book_source/online_book_controller.dart';
import 'package:reader_mobile/book_source/online_book_detail_page.dart';
import 'package:reader_mobile/book_source/online_chapter_content_store.dart';
import 'package:reader_mobile/book_source/online_reading_book.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/reader/book_opener.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/reader_pump.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('详情页目录可直达在线阅读，关闭后保留位置和离线下载入口', (tester) async {
    final directory = Directory.systemTemp.createTempSync('online-detail-');
    addTearDown(() => directory.delete(recursive: true));
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final library = LibraryStore(
      database: db,
      directoryProvider: () async => directory,
    );
    final cookies = BookSourceCookieStore(
      directoryProvider: () async => directory,
    );
    final requested = <String>[];
    final service = BookSourceService(
      cookieStore: cookies,
      chapterContentStore: OnlineChapterContentStore(
        directoryProvider: () async => directory,
      ),
      httpClient: BookSourceHttpClient(
        cookieStore: cookies,
        client: MockClient((request) async {
          final path = request.url.path;
          requested.add(path);
          return http.Response(
            jsonEncode(switch (path) {
              '/book' => {'toc': '/toc'},
              '/toc' => {
                'chapters': [
                  {'title': '第1章', 'url': '/1'},
                  {'title': '第2章', 'url': '/2'},
                ],
              },
              _ => {'content': '<p>这是可用于阅读和续读定位的第 $path 章正文。</p>'},
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );
    final controller = OnlineBookController(
      library: library,
      service: service,
      cookieStore: cookies,
    );
    addTearDown(controller.dispose);
    final book = _book(service, [1, 2]);
    final opener = BookOpener(
      library: library,
      progressStore: MemoryReaderProgressStore(),
    );
    Future<void>? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: OnlineBookDetailPage(
          controller: controller,
          source: book.source,
          book: book.book,
          onRead: (context, book, {startChapter}) => opened = opener.openOnline(
            context,
            book,
            startChapter: startChapter,
          ),
        ),
      ),
    );
    final online = find.byKey(const ValueKey('online-book-read'));
    final download = find.byKey(const ValueKey('online-book-download'));
    await pumpReaderUntil(tester, online);
    expect(download, findsOneWidget);
    expect(requested, ['/book', '/toc']);
    await tester.tap(find.text('2. 第2章'));
    await pumpReaderUntil(tester, find.byKey(const ValueKey('reader-content')));
    expect(tester.widget<ReaderPage>(find.byType(ReaderPage)).onSearch, isNull);
    expect(requested.take(3), ['/book', '/toc', '/2']);
    Navigator.of(tester.element(find.byType(ReaderPage))).pop();
    await pumpReaderTask(tester, opened!);
    expect(
      (await pumpReaderTask(
        tester,
        OnlineReadingProgress(library, book).load(book.id),
      ))?.spineIndex,
      1,
    );
    expect(download, findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test('首屏只读目标章，随后预取下一章，失败可重试并从缓存续读', () async {
    final directory = await Directory.systemTemp.createTemp('online-reading-');
    addTearDown(() => directory.delete(recursive: true));
    final cookies = BookSourceCookieStore(
      directoryProvider: () async => directory,
    );
    final requested = <String>[];
    final started = Completer<void>();
    final release = Completer<void>();
    var fail = true;
    final service = BookSourceService(
      cookieStore: cookies,
      chapterContentStore: OnlineChapterContentStore(
        directoryProvider: () async => directory,
      ),
      httpClient: BookSourceHttpClient(
        cookieStore: cookies,
        client: MockClient((request) async {
          final path = request.url.path;
          requested.add(path);
          if (path == '/2') {
            started.complete();
            await release.future;
          }
          if (path == '/4' && fail) return http.Response('', 503);
          return http.Response(
            jsonEncode({'content': '<p>第 $path 章的正文内容，供阅读与恢复定位。</p>'}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );
    addTearDown(service.dispose);
    final book = _book(service, [1, 2, 3, 4, 5]);
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final library = LibraryStore(
      database: db,
      directoryProvider: () async => directory,
    );
    final source = book.open();
    final reader = ReaderSession(
      source: source,
      store: OnlineReadingProgress(library, book, startChapter: 1),
      bookId: book.id,
      contentRevision: book.revision,
      persistInitialPosition: true,
    );
    addTearDown(() async {
      reader.dispose();
      source.close();
      await source.preparationsStopped;
    });

    expect(source.toc.map((chapter) => chapter.title), [
      '第1章',
      '第2章',
      '第3章',
      '第4章',
      '第5章',
    ]);
    expect(requested, isEmpty);
    final opening = reader.open(contentWidth: 325, contentHeight: 580);
    await started.future.timeout(const Duration(seconds: 5));
    final sameChapter = service.fetchChapterContent(
      book.source,
      book.chapters[1],
      book.book.bookUrl,
      nextChapter: book.chapters[2],
    );
    await reader.preparseNextChapter();
    expect(requested, ['/2']);
    release.complete();
    await sameChapter;
    await opening;
    expect(reader.error, isNull);
    expect(reader.page?.spineIndex, 1);
    await reader.flushProgress();
    expect(
      (await OnlineReadingProgress(library, book).load(book.id))?.spineIndex,
      1,
    );
    expect((await source.loadAnchorChapter(1)).text, contains('第 /2 章的正文内容'));

    await reader.preparseNextChapter();
    expect(requested, ['/2', '/3']);
    await expectLater(
      reader.jumpToTocEntry(source.toc[3]),
      throwsA(isA<BookSourceException>()),
    );
    expect(reader.page?.spineIndex, 1);
    fail = false;
    expect(await reader.jumpToTocEntry(source.toc[3]), isTrue);
    expect(reader.page?.spineIndex, 3);
    await reader.flushProgress();
    expect(requested, ['/2', '/3', '/4', '/4']);

    final reopened = book.open();
    final resumed = ReaderSession(
      source: reopened,
      store: OnlineReadingProgress(library, book),
      bookId: book.id,
      contentRevision: book.revision,
    );
    try {
      await resumed.open(contentWidth: 285, contentHeight: 500);
      expect(resumed.error, isNull);
      expect(resumed.page?.spineIndex, 3);
      expect(resumed.progress?.cfi, reader.progress?.cfi);
      expect(requested, ['/2', '/3', '/4', '/4']);
      expect(await library.list(), isEmpty);
    } finally {
      resumed.dispose();
      reopened.close();
      await reopened.preparationsStopped;
    }

    final appended = _book(service, [1, 2, 3, 4, 5, 6]);
    final appendedProgress = await OnlineReadingProgress(
      library,
      appended,
    ).load(appended.id);
    expect(appendedProgress?.cfi, reader.progress?.cfi);
    final reordered = _book(service, [4, 1, 2, 3, 5]);
    final reorderedProgress = await OnlineReadingProgress(
      library,
      reordered,
    ).load(reordered.id);
    expect(reorderedProgress?.spineIndex, 0);
    expect(reorderedProgress?.cfi, isNull);
    expect(reorderedProgress?.approximate, isTrue);
  });

  test('同一POST地址的不同章节按请求身份续读，重排不误用旧CFI', () async {
    final service = BookSourceService();
    addTearDown(service.dispose);
    final library = LibraryStore.memory();
    final base = _book(service, [1, 2]);
    OnlineReadingBook withChapters(List<int> bodies) => OnlineReadingBook(
      source: base.source,
      book: base.book,
      service: service,
      chapters: [
        for (final (index, body) in bodies.indexed)
          OnlineChapter(
            index: index,
            title: '第$body章',
            url: 'https://example.test/content',
            requestOptions: {
              'method': 'POST',
              'body': {'chapter': body},
            },
          ),
      ],
    );
    final book = withChapters([1, 2]);
    await OnlineReadingProgress(library, book).save(
      book.id,
      ReaderProgress(
        spineIndex: 1,
        pageIndex: 3,
        cfi: 'epubcfi(/6/4!/4/2:8)',
        contentRevision: book.revision,
      ),
    );
    final saved = await OnlineReadingProgress(library, book).load(book.id);
    expect(saved?.spineIndex, 1);
    expect(saved?.cfi, 'epubcfi(/6/4!/4/2:8)');
    final reordered = withChapters([2, 1]);
    final restored = await OnlineReadingProgress(
      library,
      reordered,
    ).load(reordered.id);
    expect(restored?.spineIndex, 0);
    expect(restored?.cfi, isNull);
    expect(restored?.approximate, isTrue);
    expect(
      (await OnlineReadingProgress(
        library,
        book,
        startChapter: 99,
      ).load(book.id))?.spineIndex,
      1,
    );
  });
}

OnlineReadingBook _book(BookSourceService service, List<int> chapters) {
  final source = BookSource.fromJson({
    'bookSourceName': '测试源',
    'bookSourceUrl': 'https://example.test',
    'ruleBookInfo': {'tocUrl': r'$.toc'},
    'ruleToc': {
      'chapterList': r'$.chapters[*]',
      'chapterName': r'$.title',
      'chapterUrl': r'$.url',
    },
    'ruleContent': {'content': r'$.content'},
  });
  return OnlineReadingBook(
    source: source,
    book: OnlineBook(
      sourceId: source.id,
      sourceName: source.name,
      name: '测试书',
      author: '测试作者',
      bookUrl: 'https://example.test/book',
    ),
    chapters: [
      for (final (index, chapter) in chapters.indexed)
        OnlineChapter(
          index: index,
          title: '第$chapter章',
          url: 'https://example.test/$chapter',
        ),
    ],
    service: service,
  );
}
