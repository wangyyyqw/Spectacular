import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_ui/annotations/annotation.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_mobile/book_source/book_source_cookie_store.dart';
import 'package:reader_mobile/book_source/book_source_http_client.dart';
import 'package:reader_mobile/book_source/book_source_models.dart';
import 'package:reader_mobile/book_source/book_source_service.dart';
import 'package:reader_mobile/book_source/book_source_store.dart';
import 'package:reader_mobile/book_source/online_book_controller.dart';
import 'package:reader_mobile/book_source/online_epub_builder.dart';
import 'package:reader_mobile/book_source/online_epub_metadata.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/storage/drift_progress_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('番外末卷不阻断正文插章，书架检查、实际下载与续读保持一致', () async {
    final dir = await Directory.systemTemp.createTemp('online-controller-');
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });
    final library = LibraryStore(
      database: db,
      directoryProvider: () async => dir,
    );
    final store = BookSourceStore(directoryProvider: () async => dir);
    final cookies = BookSourceCookieStore(directoryProvider: () async => dir);
    final source = await store.importText(
      jsonEncode({
        'bookSourceName': '测试源',
        'bookSourceUrl': 'https://example.test',
        'searchUrl': 'https://example.test/search',
        'ruleSearch': {
          'bookList': r'$.books',
          'name': r'$.name',
          'bookUrl': r'$.url',
        },
        'ruleBookInfo': {
          'name': r'$.name',
          'author': r'$.author',
          'tocUrl': r'$.toc',
          'lastChapter': r'$.lastChapter',
        },
        'ruleToc': {
          'chapterList': r'$.chapters[*]',
          'chapterName': r'$.title',
          'chapterUrl': r'$.url',
          'updateTime': r'$.time',
        },
        'ruleContent': {'content': r'$.content'},
      }),
    );
    final entry = await library.importBytes(
      const OnlineEpubBuilder().build(
        OnlineEpubInput(
          title: '在线书',
          author: '作者',
          sourceName: '测试源',
          sourceId: source.id,
          bookUrl: 'https://example.test/book',
          chapters: const [
            OnlineEpubChapter(
              title: '第一章',
              html: '<p>原正文</p>',
              sourceUrl: 'https://example.test/1',
              volume: '正文',
            ),
            OnlineEpubChapter(
              title: '旧番外',
              html: '<p>原番外正文</p>',
              sourceUrl: 'https://example.test/extra',
              volume: '番外',
            ),
          ],
        ),
      ),
    );
    final document = await EpubChapterSource.openFile(File(entry.filePath));
    final chapter = await document.loadAnchorChapter(0);
    final start = chapter.cfiAt(chapter.text.indexOf('原正文'))!;
    final end = chapter.cfiAt(chapter.text.indexOf('原正文') + 3)!;
    final extra = await document.loadAnchorChapter(1);
    final extraCfi = extra.cfiAt(extra.text.indexOf('原番外正文'))!;
    final progress = DriftProgressStore(db);
    await progress.save(
      entry.id,
      ReaderProgress(
        spineIndex: 1,
        pageIndex: 0,
        cfi: extraCfi,
        contentRevision: entry.contentRevision,
      ),
    );
    final annotation = (await library
        .annotationStore(entry.id)!
        .add(
          type: ReaderAnnotationType.thought,
          startCfi: start,
          endCfi: end,
          quote: '原正文',
          note: '原有想法',
        ))!;
    document.close();
    await store.saveLink(
      entry.id,
      OnlineBookLink(
        sourceId: source.id,
        bookUrl: 'https://example.test/book',
        name: '在线书',
        author: '作者',
      ),
    );
    var count = 2;
    var datedCatalog = false;
    var fail = false;
    var bookInfoRequests = 0;
    final contentRequests = <String>[];
    final service = BookSourceService(
      cookieStore: cookies,
      httpClient: BookSourceHttpClient(
        cookieStore: cookies,
        client: MockClient((request) async {
          final path = request.url.path;
          if (path == '/book') {
            bookInfoRequests++;
            return http.Response(
              jsonEncode({
                'name': '在线书',
                'author': '作者',
                'toc': 'https://example.test/toc',
                if (datedCatalog) 'lastChapter': '第一章',
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          if (path == '/toc') {
            return http.Response(
              jsonEncode({
                'chapters': [
                  for (var index = 1; index <= count; index++)
                    {
                      'title': index == 1 ? '第一章' : '第$index章',
                      'url': 'https://example.test/$index',
                      'volume_name': '正文',
                      if (datedCatalog)
                        'time': index == 1
                            ? '2026-10-08T04:42:08.293Z'
                            : '2026-11-25T01:41:07.215Z',
                    },
                  {
                    'title': '旧番外',
                    'url': 'https://example.test/extra',
                    'volume_name': '番外',
                    'time': '2020-01-01',
                  },
                ],
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          contentRequests.add(path);
          return http.Response(
            jsonEncode({'content': fail ? '' : '新增章有足够长度的正常正文。'}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );
    final controller = OnlineBookController(
      library: library,
      store: store,
      cookieStore: cookies,
      service: service,
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    var updateNotifications = 0;
    controller.addListener(() => updateNotifications++);
    await controller.refreshShelfOnlineUpdates();
    Future<Map<String, dynamic>> record() async =>
        (jsonDecode((await library.getSetting('bookshelf.onlineUpdates.v1'))!)
                as Map<String, dynamic>)[entry.id]
            as Map<String, dynamic>;
    final checked = await record();
    expect(checked['chapterCount'], 3);
    expect(checked['latestChapter'], '第2章');
    expect(checked['updatedAt'], checked['checkedAt']);
    expect(checked['updated'], isTrue);
    expect(updateNotifications, greaterThan(0));
    await controller.refreshShelfOnlineUpdates();
    expect((await record())['updatedAt'], checked['updatedAt']);
    expect((await record())['latestChapter'], '第2章');
    expect(contentRequests, isEmpty);

    final updated = await controller.updateBook(entry);
    expect(updated.id, entry.id);
    expect(controller.lastAddedChapters, 1);
    expect(contentRequests, ['/2']);
    final cleared = await record();
    expect(cleared['updated'], isFalse);
    expect(cleared['latestChapter'], '第2章');
    expect(cleared['updatedAt'], checked['updatedAt']);
    final indexed = (await OnlineEpubMetadata.read(library, updated))!.chapters;
    expect(indexed.map((chapter) => chapter.title), ['第一章', '第2章', '旧番外']);
    expect(indexed.last.href, 'OEBPS/text/chapter_0002.xhtml');
    expect(updateNotifications, greaterThan(1));
    final resumed = (await progress.load(entry.id))!;
    expect(resumed.spineIndex, 2);
    final reopened = await EpubChapterSource.openFile(File(updated.filePath));
    final savedChapter = await reopened.loadAnchorChapter(resumed.spineIndex);
    expect(
      savedChapter.text.substring(savedChapter.offsetFor(resumed.cfi!)!),
      startsWith('原番外正文'),
    );
    reopened.close();
    await reopened.preparationsStopped;
    final retained = (await library.listBookAnnotations(entry.id)).single;
    expect(retained.id, annotation.id);
    expect(retained.startCfi, start);
    expect(retained.endCfi, end);
    expect(retained.quote, '原正文');
    expect(retained.note, '原有想法');
    final revision = updated.contentRevision;
    await controller.updateBook(updated);
    expect(controller.lastAddedChapters, 0);
    expect(contentRequests, ['/2']);
    expect((await library.bookById(entry.id))!.contentRevision, revision);
    await controller.refreshShelfOnlineUpdates();
    expect((await record())['updated'], isFalse);
    expect((await record())['latestChapter'], '第2章');
    datedCatalog = true;
    await library.setSetting(
      'bookshelf.onlineUpdates.v1',
      jsonEncode({
        entry.id: {
          'chapterCount': 3,
          'latestChapter': '第一章',
          'updatedAt': DateTime.parse('2026-10-08T04:42:08.293Z').millisecondsSinceEpoch,
          'updated': false,
        },
      }),
    );
    await controller.refreshShelfOnlineUpdates();
    final corrected = await record();
    expect(corrected['latestChapter'], '第2章');
    expect(corrected['updatedAt'],
        DateTime.parse('2026-11-25T01:41:07.215Z').millisecondsSinceEpoch);
    expect(corrected['updated'], isFalse);
    await library.setSetting(
      'online_reading_progress:${entry.id}',
      '{"spine":1,"finished":true}',
    );
    final requestsBeforeFinishedRefresh = bookInfoRequests;
    await controller.refreshShelfOnlineUpdates();
    expect(
      bookInfoRequests,
      requestsBeforeFinishedRefresh,
      reason: '在线阅读标记读完后应跳过自动更新检查',
    );
    count = 3;
    fail = true;
    await expectLater(
      controller.updateBook(updated),
      throwsA(isA<BookSourceException>()),
    );
    expect((await library.bookById(entry.id))!.contentRevision, revision);
    expect(contentRequests, ['/2', '/3']);
  });
}
