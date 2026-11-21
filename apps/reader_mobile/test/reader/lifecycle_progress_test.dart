import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/diagnostics/reader_log.dart';
import 'package:reader_mobile/reader/epub_reader_page.dart';
import 'package:reader_mobile/storage/reading_session_store.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';

import '../support/reader_pump.dart';
import '../support/test_epub.dart';

Uint8List _corpusBook(String name) {
  var directory = Directory.current;
  while (true) {
    final candidate = Directory('${directory.path}/test_corpus');
    if (candidate.existsSync()) {
      return File('${candidate.path}/$name').readAsBytesSync();
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('缺少 test_corpus/$name');
    }
    directory = parent;
  }
}

class _CountingStore implements ReaderProgressStore {
  final Map<String, ReaderProgress> items = <String, ReaderProgress>{};
  int writes = 0;

  @override
  Future<ReaderProgress?> load(String bookId) async => items[bookId];

  @override
  Future<void> save(String bookId, ReaderProgress progress) async {
    writes += 1;
    items[bookId] = progress;
  }

  @override
  Future<void> clear(String bookId) async {
    items.remove(bookId);
  }

  @override
  Future<Map<String, ReaderProgress>> snapshot() async => Map.of(items);
}

class _DelayedRejectingStore extends _CountingStore {
  bool rejectSaves = false;
  final started = Completer<void>();
  final reject = Completer<void>();

  @override
  Future<void> save(String bookId, ReaderProgress progress) async {
    if (!rejectSaves) return super.save(bookId, progress);
    if (!started.isCompleted) started.complete();
    await reject.future;
    throw const ReaderProgressSaveException(ReaderProgressSaveResult.stale);
  }
}

class _ReadingDurationStore implements ReadingSessionCheckpointStore {
  final items = <ReadingSession>[];
  int saves = 0;
  Completer<void>? historyReady;

  @override
  Future<void> add({
    required String bookId,
    required DateTime startedAt,
    required DateTime endedAt,
    int pageTurns = 0,
    int charactersRead = 0,
  }) async {}

  @override
  Future<List<ReadingSession>> list() async {
    await historyReady?.future;
    return List.of(items);
  }

  @override
  Future<int> save(ReadingSession session, {int? sessionId}) async {
    saves++;
    if (sessionId == null) {
      items.add(session);
      return items.length - 1;
    }
    items[sessionId] = session;
    return sessionId;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('退出后保存失败保留旧位置并记录诊断，不显示浮动提示', (tester) async {
    final log = ReaderLog.instance;
    log.resetForTest();
    addTearDown(log.resetForTest);
    final store = _DelayedRejectingStore();
    addTearDown(() {
      if (!store.reject.isCompleted) store.reject.complete();
    });
    var closed = false;
    final book = buildTestEpub(paragraphs: List.filled(30, '翻页后需要保存。' * 100));
    await store.save(
      'late-close-progress',
      const ReaderProgress(spineIndex: 0, pageIndex: 0),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => EpubReaderPage(
                    bytes: book,
                    bookId: 'late-close-progress',
                    store: store,
                    onClosed: () => closed = true,
                  ),
                ),
              ),
              child: const Text('书架阅读'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('书架阅读'));
    await pumpReaderUntil(tester, find.byType(ReaderView));
    await tester.pumpAndSettle();
    final before = Map<String, ReaderProgress>.of(store.items);
    expect(before, isNotEmpty, reason: '先保存有效位置再模拟后续写入失败');
    store.rejectSaves = true;
    final view = tester.getRect(find.byType(ReaderView));
    await tester.tapAt(view.topRight + Offset(-4, view.height * 0.4));
    await pumpReaderUntilComplete(
      tester,
      () => store.started.isCompleted,
      description: '等待保存开始',
    );
    Navigator.of(tester.element(find.byType(ReaderView))).pop();
    await tester.pumpAndSettle();
    expect(find.text('书架阅读'), findsOneWidget);
    store.reject.complete();
    await pumpReaderUntilComplete(
      tester,
      () => closed,
      description: '退出保存检查结束',
    );
    await tester.pump();

    expect(store.items, before, reason: '失败写入不能覆盖已保存位置');
    final diagnostic = await pumpReaderTask(tester, log.exportText());
    expect(
      ' | reader_progress_close_failed'.allMatches(diagnostic),
      hasLength(1),
      reason: '退出失败只记录一次',
    );
    expect(diagnostic, contains('error_type=ReaderProgressSaveException'));
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('正式阅读页定时保存，退出尾段不等待进度写入且不计退出耗时', (tester) async {
    final store = _DelayedRejectingStore();
    final durations = _ReadingDurationStore();
    addTearDown(() {
      if (!store.reject.isCompleted) store.reject.complete();
    });
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: EpubReaderPage(
          bytes: buildTestEpub(paragraphs: List.filled(30, '计时不等待进度保存。' * 100)),
          bookId: 'duration-close',
          store: store,
          readingSessions: durations,
          onClosed: () => closed = true,
        ),
      ),
    );
    await pumpReaderUntil(tester, find.byType(ReaderView));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(durations.items, hasLength(1), reason: '定时保存不等待退出');
    store.rejectSaves = true;
    final view = tester.getRect(find.byType(ReaderView));
    await tester.tapAt(view.topRight + Offset(-4, view.height * 0.4));
    await pumpReaderUntilComplete(
      tester,
      () => store.started.isCompleted,
      description: '进度写入开始',
    );
    final beforeExit = durations.saves;
    await tester.pumpWidget(const SizedBox.shrink());
    expect(durations.saves, greaterThan(beforeExit), reason: '进度等待期间也先保存阅读尾段');
    final stoppedAt = durations.items.single.endedAt;
    await tester.pump(const Duration(seconds: 30));
    expect(durations.items.single.endedAt, stoppedAt, reason: '退出后的等待不算阅读时间');
    store.reject.complete();
    await pumpReaderUntilComplete(tester, () => closed, description: '阅读页保存结束');
    expect(tester.takeException(), isNull);
  });

  testWidgets('历史时长加载延迟时保留全部历史，已落盘的当前片段只累计一次', (tester) async {
    final history = Completer<void>();
    final durations = _ReadingDurationStore()..historyReady = history;
    // 已保存时长不依赖记录的时钟值早于本次打开时间。
    final previous = DateTime.now().add(const Duration(days: 1));
    durations.items.add(
      ReadingSession(
        bookId: 'late-duration',
        startedAt: previous,
        endedAt: previous.add(const Duration(hours: 1)),
        duration: const Duration(hours: 1),
      ),
    );
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: EpubReaderPage(
          bytes: buildTestEpub(),
          bookId: 'late-duration',
          store: _CountingStore(),
          readingSessions: durations,
          onClosed: () => closed = true,
        ),
      ),
    );
    await pumpReaderUntil(tester, find.byType(ReaderView));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(durations.items, hasLength(2));
    final current = durations.items.last.duration;
    history.complete();
    await tester.pump();

    final page = tester.widget<ReaderPage>(find.byType(ReaderPage));
    expect(page.readingDuration!.value, const Duration(hours: 1) + current);
    await tester.pumpWidget(const SizedBox.shrink());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await pumpReaderUntilComplete(
      tester,
      () => closed,
      description: '延迟基线阅读页释放',
    );
  });

  testWidgets('切换后台立即保存最后阅读位置', (tester) async {
    final store = _CountingStore();
    var closed = false;
    store.items['lifecycle-progress'] = const ReaderProgress(
      spineIndex: 0,
      pageIndex: 0,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: EpubReaderPage(
          bytes: _corpusBook('basic.epub'),
          bookId: 'lifecycle-progress',
          bookTitle: '生命周期进度',
          store: store,
          onClosed: () => closed = true,
        ),
      ),
    );
    await pumpReaderUntil(tester, find.byType(ReaderView));
    final before = store.items['lifecycle-progress'];
    expect(before, isNotNull);

    final view = tester.getRect(find.byType(ReaderView));
    await tester.tapAt(view.topRight + Offset(-4, view.height * 0.4));
    await pumpReaderUntilComplete(
      tester,
      () => store.items['lifecycle-progress'] != before,
      description: '首次翻页进度写入',
    );
    expect(
      store.items['lifecycle-progress'],
      isNot(before),
      reason: '首次真实翻页立即写入，短会话退出也不丢位置',
    );
    final afterPageTurn = store.items['lifecycle-progress'];

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    final saved = store.items['lifecycle-progress'];
    expect(saved, isNotNull);
    expect(saved, afterPageTurn, reason: '后台保存不丢刚刚写入的页面');
    await tester.pumpWidget(const SizedBox.shrink());
    tester.binding.scheduleForcedFrame();
    await pumpReaderUntilComplete(tester, () => closed, description: '后台阅读页释放');
  });
}
