import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/reader/epub_reader_page.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('正常退出后才拒绝保存，在书架提示旧位置保留', (tester) async {
    final store = _DelayedRejectingStore();
    addTearDown(() {
      if (!store.reject.isCompleted) store.reject.complete();
    });
    var closed = false;
    final book = buildTestEpub(paragraphs: List.filled(30, '翻页后需要保存。' * 100));
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

    expect(find.text('本次位置未保存，保留上次保存位置：书籍已更新'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
