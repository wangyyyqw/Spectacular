import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/rea_micro/rea_micro_api_client.dart';
import 'package:reader_mobile/rea_micro/rea_micro_controller.dart';
import 'package:reader_mobile/rea_micro/rea_micro_models.dart';
import 'package:reader_mobile/rea_micro/rea_micro_store.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/test_epub.dart';

void main() {
  for (final (missing, historical) in [
    (true, false),
    (false, false),
    (true, true),
  ]) {
    test(
      '未关联首次进度${historical
          ? '补齐旧在线快照'
          : missing
          ? '不存在则上传且不计失败'
          : '权限失败则保留待传并计失败'}',
      () async {
        final library = LibraryStore.memory();
        final book = await library.importBytes(buildTestEpub(title: '首次进度'));
        final store = ReaMicroStore(library);
        await store.saveToken('test');
        await store.saveSyncBooks({
          book.id: const ReaMicroBookSyncIdentity(
            cloudBookId: 0,
            userBookId: 47560,
          ),
        });
        if (historical) {
          await library.setSetting(
            'online_reading_progress:${book.id}',
            jsonEncode({
              'revision': '在线正文版本',
              'spine': 0,
              'page': 1,
              'cfi': 'epubcfi(/6/2!/4/2/1)',
              'percent': .25,
              'title': '第一章',
            }),
          );
        }
        final uploads = <Map<String, dynamic>>[];
        final api = ReaMicroApiClient(
          baseUrl: 'https://example.test/',
          client: MockClient((request) async {
            Object? response = {'code': 0, 'data': <String, Object?>{}};
            if (request.url.path.endsWith('get-read-progress')) {
              response = {
                'code': 2,
                'message': missing
                    ? 'record not found'
                    : 'book permission denied',
              };
            } else if (request.url.path.endsWith('update-read-progress')) {
              uploads.add(jsonDecode(request.body) as Map<String, dynamic>);
            }
            return http.Response(
              jsonEncode(response),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        );
        final raw = MemoryReaderProgressStore();
        final controller = ReaMicroController(
          library: library,
          api: api,
          store: store,
          progressStore: raw,
          enableLanLoginServer: false,
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        if (!historical) {
          await controller.trackedProgressStore!.save(
            book.id,
            const ReaderProgress(
              spineIndex: 0,
              pageIndex: 1,
              cfi: 'epubcfi(/6/2!/4/2/1)',
              readingPercent: .25,
              chapterTitle: '第一章',
            ),
          );
        }
        final result = await controller.syncProgress();
        final states = await store.loadProgressStates();
        final budget = await store.loadUploadRetryBudget();
        expect(result.success, missing);
        expect(states[book.id]!.dirty, !missing);
        expect(budget['retries'], 0);
        expect(budget['failed'], missing ? isEmpty : contains('progress'));
        if (missing) {
          expect(uploads.single['bookId'], 47560);
          expect(uploads.single['cfi'], 'epubcfi(/6/2!/4/2/1)');
          expect(uploads.single['progress'], .25);
        } else {
          expect(uploads, isEmpty);
        }
        expect(await store.loadLinks(), isEmpty);
      },
    );
  }
}
