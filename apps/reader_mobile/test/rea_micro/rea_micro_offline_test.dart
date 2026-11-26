import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/rea_micro/rea_micro_api_client.dart';
import 'package:reader_mobile/rea_micro/rea_micro_controller.dart';
import 'package:reader_mobile/rea_micro/rea_micro_models.dart';
import 'package:reader_mobile/rea_micro/rea_micro_store.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_ui/annotations/annotation.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/test_epub.dart';

void main() {
  test('断网重开数据库后合并新增时段与笔记，重连先上传再刷新，不重复计时', () async {
    final folder = await Directory.systemTemp.createTemp('reader-offline-');
    final file = File('${folder.path}/reader.sqlite');
    final today = DateTime(2026, 11, 26, 12);
    var online = true;
    var seconds = 100;
    var writes = 0;
    final serverAcceptedTime = Completer<void>();
    final confirmTime = Completer<void>();
    var noteWrites = 0;
    var reviewWrites = 0;
    var noteDeletes = 0;
    final marks = <Map<String, dynamic>>[
      {
        'id': 17,
        'bookId': '8',
        'kind': 1,
        'startCfi': '旧位置',
        'endCfi': '旧位置',
        'note': '旧想法',
      },
    ];
    late LibraryStore library;
    late AppDatabase database;
    late ReaMicroController controller;
    void open() {
      database = AppDatabase(NativeDatabase(file));
      library = LibraryStore(
        database: database,
        directoryProvider: () async => folder,
      );
      controller = ReaMicroController(
        library: library,
        now: () => today,
        appVersion: () async => '测试',
        progressStore: MemoryReaderProgressStore(),
        enableLanLoginServer: false,
        api: ReaMicroApiClient(
          client: MockClient((request) async {
            if (!online) throw const SocketException('测试断网');
            final endpoint = request.url.pathSegments.last;
            final body = jsonDecode(request.body) as Map;
            Object data = {};
            if (endpoint == 'get-user-info') {
              data = {
                'id': 9,
                'userType': 3,
                'vipExpireTime': '2099-01-01',
                'totalReadTime': seconds,
              };
            } else if (endpoint == 'get-read-time-chart') {
              data = [
                {
                  'day': '2026-11-26',
                  'duration': seconds,
                  'readingDuration': seconds,
                },
              ];
            } else if (endpoint.contains('read-duration')) {
              data = {
                'totalDuration': seconds,
                'readDays': 1,
                'bookCount': 1,
                'days': [
                  {
                    'day': endpoint.contains('week')
                        ? today.weekday
                        : today.day,
                    'duration': seconds,
                  },
                ],
              };
            } else if (endpoint.contains('read-record-list')) {
              data = [
                {
                  'bookId': 8,
                  'cloudBookId': 11,
                  'name': '离线书',
                  'totalReadTime': seconds,
                },
              ];
            } else if (endpoint == 'get-mark-list') {
              data = marks;
            } else if (endpoint == 'get-mark-book-list') {
              data = [
                {
                  'bookId': 8,
                  'cloudBookId': 11,
                  'bookName': '离线书',
                  'thoughtCount': marks.length,
                },
              ];
            } else if (endpoint == 'delete-mark') {
              noteDeletes++;
              marks.removeWhere((mark) => mark['id'] == body['id']);
            } else if (endpoint.contains('milestone-list')) {
              data = [];
            } else if (endpoint == 'update-read-time-by-date') {
              writes++;
              for (final log
                  in (body['sessionLogs'] as List)
                      .cast<Map<String, dynamic>>()) {
                seconds += log['duration'] as int;
              }
              serverAcceptedTime.complete();
              await confirmTime.future;
              data = {'sessionAccountingSupported': true};
            } else if (endpoint == 'batch-upsert-mark') {
              noteWrites++;
              marks.add({
                ...Map<String, dynamic>.from(
                  (body['items'] as List).single as Map,
                ),
                'id': 42,
              });
              data = [
                {'id': 42, 'success': true},
              ];
            } else if (endpoint == 'rate-review') {
              expect(body['comment'], '离线书评');
              reviewWrites++;
            }
            return http.Response.bytes(
              utf8.encode(jsonEncode({'code': 0, 'data': data})),
              200,
            );
          }),
        ),
      );
    }

    Future<void> close() async {
      controller.dispose();
      await database.close();
    }

    open();
    addTearDown(() async {
      await close();
      await folder.delete(recursive: true);
    });
    final store = ReaMicroStore(library);
    await store.saveToken('账号甲');
    final book = await library.importBytes(buildTestEpub(title: '离线书'));
    await store.saveSyncBooks({
      book.id: const ReaMicroBookSyncIdentity(cloudBookId: 11, userBookId: 8),
    });
    await controller.initialize();
    expect(controller.cloudStats!.overview.totalDurationSeconds, 100);
    await controller.loadBookRecords(ReaMicroRecordPeriod.week, today);
    await controller.loadMarkBooks();
    online = false;
    await controller.refresh();
    expect(controller.offline, isTrue);
    final deletion = await controller.deleteNote(
      book.id,
      ReaderAnnotation(
        id: 'mark-cloud-17',
        type: ReaderAnnotationType.thought,
        startCfi: '旧位置',
        endCfi: '旧位置',
        quote: '旧',
        createdAt: today,
        updatedAt: today,
      ),
      cloudId: 17,
    );
    expect(deletion.success, isTrue);
    await library.readingSessionStore()!.add(
      bookId: book.id,
      startedAt: today,
      endedAt: today.add(const Duration(seconds: 60)),
    );
    await library.importBookAnnotation(
      book.id,
      ReaderAnnotation(
        id: '本地标注',
        type: ReaderAnnotationType.thought,
        startCfi: 'epubcfi(/6/2!/4/2/1:0)',
        endCfi: 'epubcfi(/6/2!/4/2/1:1)',
        quote: '字',
        note: '离线想法',
        createdAt: today,
        updatedAt: today,
      ),
    );
    expect(
      (await controller.saveReview(
        cloudBookId: 11,
        rating: 8,
        comment: '离线书评',
        publish: false,
      )).success,
      isTrue,
    );
    await close();
    open();
    await controller.initialize();
    expect(controller.cloudStats!.overview.totalDurationSeconds, 160);
    expect(controller.heatmapChart.single.durationSeconds, 160);
    expect(controller.cloudStats!.month.totalDurationSeconds, 160);
    expect(controller.cloudStats!.week.days.single.durationSeconds, 160);
    expect(
      (await controller.loadBookRecords(
        ReaMicroRecordPeriod.week,
        today.add(const Duration(days: 1)),
      )).single.totalReadTimeSeconds,
      160,
    );
    expect((await controller.loadMarkBooks()).single.thoughtCount, 1);
    expect(await controller.loadBookMarks(bookId: 8, cloudBookId: 11), isEmpty);
    expect((await controller.loadBookReview(11))!.comment, '离线书评');
    expect((writes, noteWrites, reviewWrites), (0, 0, 0));
    final refreshed = Completer<void>();
    controller.pageRefresh.addListener(() {
      if (!refreshed.isCompleted) refreshed.complete();
    });
    online = true;
    controller.handleAppResumed();
    await serverAcceptedTime.future.timeout(const Duration(seconds: 5));
    final simultaneousRead = controller.loadBookRecords(
      ReaMicroRecordPeriod.week,
      today,
    );
    await Future<void>.delayed(Duration.zero);
    confirmTime.complete();
    expect((await simultaneousRead).single.totalReadTimeSeconds, 160);
    await refreshed.future.timeout(const Duration(seconds: 5));
    expect((writes, noteWrites, reviewWrites), (1, 1, 1));
    expect(noteDeletes, 1);
    expect(controller.offline, isFalse);
    expect(controller.cloudStats!.overview.totalDurationSeconds, 160);
    await controller.syncReadingSessions();
    expect(writes, 1);
    await close();
    open();
    await ReaMicroStore(library).clearAuth();
    await ReaMicroStore(library).saveToken('账号乙');
    online = false;
    await controller.initialize();
    expect(controller.cloudStats, isNull);
    expect(await controller.loadBookReview(11), isNull);
  });
}
