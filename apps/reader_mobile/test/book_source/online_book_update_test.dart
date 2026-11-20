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
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/storage/drift_progress_store.dart';

void main() {
  test('正式更新入口只请求新增正文，再次更新无下载且失败保留原书', () async {
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
        },
        'ruleToc': {
          'chapterList': r'$.chapters[*]',
          'chapterName': r'$.title',
          'chapterUrl': r'$.url',
        },
        'ruleContent': {'content': r'$.content'},
      }),
    );
    final entry = await library.importBytes(
      const OnlineEpubBuilder().build(
        const OnlineEpubInput(
          title: '在线书',
          author: '作者',
          sourceName: '测试源',
          bookUrl: 'https://example.test/book',
          chapters: [
            OnlineEpubChapter(
              title: '第一章',
              html: '<p>原正文</p>',
              sourceUrl: 'https://example.test/1',
            ),
          ],
        ),
      ),
    );
    final document = await EpubChapterSource.openFile(File(entry.filePath));
    final chapter = await document.loadAnchorChapter(0);
    final start = chapter.cfiAt(chapter.text.indexOf('原正文'))!;
    final end = chapter.cfiAt(chapter.text.indexOf('原正文') + 3)!;
    final progress = DriftProgressStore(db);
    await progress.save(
      entry.id,
      ReaderProgress(
        spineIndex: 0,
        pageIndex: 0,
        cfi: start,
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
    var fail = false;
    final contentRequests = <String>[];
    final service = BookSourceService(
      cookieStore: cookies,
      httpClient: BookSourceHttpClient(
        cookieStore: cookies,
        client: MockClient((request) async {
          final path = request.url.path;
          if (path == '/book') {
            return http.Response(
              jsonEncode({
                'name': '在线书',
                'author': '作者',
                'toc': 'https://example.test/toc',
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
    final updated = await controller.updateBook(entry);
    expect(updated.id, entry.id);
    expect(controller.lastAddedChapters, 1);
    expect(contentRequests, ['/2']);
    expect((await progress.load(entry.id))!.cfi, start);
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
