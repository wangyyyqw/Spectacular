import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_mobile/reader/epub/book_page_counter.dart';
import 'package:reader_ui/reader_session.dart';

class _PendingChapter implements ChapterLoadHandle {
  _PendingChapter(this.spine) {
    unawaited(result.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
  }

  final int spine;
  final Completer<List<PageContent>> _completion = Completer();
  bool cancelled = false;

  @override
  Future<List<PageContent>> get result => _completion.future;

  @override
  void cancel() {
    cancelled = true;
    if (!_completion.isCompleted) {
      _completion.completeError(const ChapterLoadCancelled());
    }
  }

  void finish(int count) {
    if (_completion.isCompleted) return;
    _completion.complete([
      for (var page = 0; page < count; page++)
        PageContent(
          spineIndex: spine,
          pageIndex: page,
          slices: const [],
          usedHeight: 0,
          pageHeight: 100,
          topPadding: 0,
        ),
    ]);
  }

  void fail() => _completion.completeError(StateError('本章暂时读取失败'));
}

class _PendingScheduler {
  final requests = <_PendingChapter>[];
  ChapterLoadHandle schedule(int spine) {
    final request = _PendingChapter(spine);
    requests.add(request);
    return request;
  }
}

class _MemoryCountStore implements BookPageCountStore {
  final saved = <String, Map<int, int>>{};
  final loaded = <String>[];
  Completer<Map<int, int>>? pendingLoad;

  @override
  Future<Map<int, int>> load(String layoutKey) async {
    loaded.add(layoutKey);
    final pending = pendingLoad;
    return pending == null
        ? Map<int, int>.of(saved[layoutKey] ?? {})
        : pending.future;
  }

  @override
  Future<void> save(String layoutKey, Map<int, int> counts) async {
    saved[layoutKey] = Map<int, int>.of(counts);
  }
}

Future<void> _until(bool Function() condition) async {
  final watch = Stopwatch()..start();
  while (!condition() && watch.elapsed < const Duration(seconds: 2)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(condition(), isTrue, reason: '等待计页状态或调度结果完成');
}

void main() {
  test('当前章直接计入，后台只排剩余章且累计等于串行总数', () async {
    final scheduler = _PendingScheduler();
    final counter = BookPageCounter(
      chapterCount: 3,
      isMissing: (_) => false,
      schedule: scheduler.schedule,
    );
    addTearDown(counter.close);
    await counter.useLayout('layout-a');
    counter.recordChapter('layout-a', 0, 4);
    counter.setActive(true);
    await _until(() => scheduler.requests.length == 1);
    expect(scheduler.requests.single.spine, 1);
    scheduler.requests.single.finish(5);
    await _until(() => scheduler.requests.length == 2);
    scheduler.requests.last.finish(6);
    await _until(() => counter.state.value.isComplete);
    expect(counter.state.value.completedPages, 15);
    expect(scheduler.requests.map((request) => request.spine), [1, 2]);
  });

  test('暂停立即取消在途章节，恢复只续排未完成章', () async {
    final scheduler = _PendingScheduler();
    final counter = BookPageCounter(
      chapterCount: 2,
      isMissing: (_) => false,
      schedule: scheduler.schedule,
    );
    addTearDown(counter.close);
    await counter.useLayout('layout-a');
    counter.recordChapter('layout-a', 0, 3);
    counter.setActive(true);
    await _until(() => scheduler.requests.length == 1);
    counter.setActive(false);
    expect(scheduler.requests.first.cancelled, isTrue);
    expect(counter.state.value.status, BookPageCountStatus.paused);
    expect(counter.state.value.completedPages, 3);
    counter.setActive(true);
    await _until(() => scheduler.requests.length == 2);
    expect(scheduler.requests.last.spine, 1);
    scheduler.requests.last.finish(7);
    await _until(() => counter.state.value.isComplete);
    expect(counter.state.value.completedPages, 10);
  });

  test('失败章保持未完成，下次恢复重试且保留已排结果', () async {
    final scheduler = _PendingScheduler();
    final counter = BookPageCounter(
      chapterCount: 2,
      isMissing: (_) => false,
      schedule: scheduler.schedule,
    );
    addTearDown(counter.close);
    await counter.useLayout('layout-a');
    counter.recordChapter('layout-a', 0, 3);
    counter.setActive(true);
    await _until(() => scheduler.requests.isNotEmpty);
    scheduler.requests.single.fail();
    await _until(() => counter.state.value.failedSpines.isNotEmpty);
    expect(counter.state.value.isComplete, isFalse);
    expect(counter.state.value.label, '已排 3 页');
    counter.setActive(false);
    counter.setActive(true);
    await _until(() => scheduler.requests.length == 2);
    scheduler.requests.last.finish(4);
    await _until(() => counter.state.value.isComplete);
    expect(counter.state.value.completedPages, 7);
  });

  test('布局切换丢弃旧请求，切回复用对应配置计数', () async {
    final scheduler = _PendingScheduler();
    final counter = BookPageCounter(
      chapterCount: 2,
      isMissing: (_) => false,
      schedule: scheduler.schedule,
    );
    addTearDown(counter.close);
    await counter.useLayout('layout-a');
    counter.recordChapter('layout-a', 0, 3);
    counter.setActive(true);
    await _until(() => scheduler.requests.length == 1);
    counter.setActive(false);
    await counter.useLayout('layout-b');
    expect(scheduler.requests.first.cancelled, isTrue);
    counter.recordChapter('layout-a', 1, 99);
    counter.recordChapter('layout-b', 0, 8);
    counter.setActive(true);
    await _until(() => scheduler.requests.length == 2);
    scheduler.requests.last.finish(9);
    await _until(() => counter.state.value.isComplete);
    expect(counter.state.value.completedPages, 17);
    counter.setActive(false);
    await counter.useLayout('layout-a');
    counter.setActive(true);
    expect(counter.state.value.completedPages, 3);
    await _until(() => scheduler.requests.length == 3);
    expect(scheduler.requests.last.spine, 1);
  });

  test('缓存读取晚于前台排版时，以前台实测计数为准并等待落盘', () async {
    final store = _MemoryCountStore()..pendingLoad = Completer();
    final scheduler = _PendingScheduler();
    final counter = BookPageCounter(
      chapterCount: 1,
      isMissing: (_) => false,
      schedule: scheduler.schedule,
      store: store,
    );
    addTearDown(counter.close);
    final restoring = counter.useLayout('layout-a');
    counter.recordChapter('layout-a', 0, 5);
    store.pendingLoad!.complete({0: 99});
    await restoring;
    await counter.flush();
    expect(store.saved['layout-a'], {0: 5});
    counter.setActive(true);
    expect(counter.state.value.completedPages, 5);
    expect(counter.state.value.isComplete, isTrue);
    expect(scheduler.requests, isEmpty);
  });

  test('重新打开同一布局复用完成计数，不重复调度', () async {
    final store = _MemoryCountStore()..saved['layout-a'] = {0: 3, 1: 4};
    final scheduler = _PendingScheduler();
    final counter = BookPageCounter(
      chapterCount: 2,
      isMissing: (_) => false,
      schedule: scheduler.schedule,
      store: store,
    );
    addTearDown(counter.close);
    await counter.useLayout('layout-a');
    counter.setActive(true);
    expect(counter.state.value.isComplete, isTrue);
    expect(counter.state.value.completedPages, 7);
    await counter.useLayout('layout-a');
    counter.setActive(true);
    expect(scheduler.requests, isEmpty);
  });

  test('缓存尚未恢复时暂停不覆盖已完成计数，落盘等待恢复合并', () async {
    final store = _MemoryCountStore()
      ..saved['layout-a'] = {0: 7, 1: 8}
      ..pendingLoad = Completer();
    final counter = BookPageCounter(
      chapterCount: 2,
      isMissing: (_) => false,
      schedule: _PendingScheduler().schedule,
      store: store,
    );
    addTearDown(counter.close);
    final restoring = counter.useLayout('layout-a');
    counter.recordChapter('layout-a', 0, 7);
    counter.setActive(true);
    counter.setActive(false);
    var flushed = false;
    final flush = counter.flush().then((_) => flushed = true);
    await Future<void>.delayed(Duration.zero);
    expect(store.saved['layout-a'], {0: 7, 1: 8});
    expect(flushed, isFalse);
    store.pendingLoad!.complete({0: 7, 1: 8});
    await restoring;
    await flush;
    expect(store.saved['layout-a'], {0: 7, 1: 8});
  });

  test('晚绑定读取持久缓存并保留状态身份和已有前台计数', () async {
    final store = _MemoryCountStore()..saved['layout-a'] = {0: 99, 1: 4};
    final scheduler = _PendingScheduler();
    final counter = BookPageCounter(
      chapterCount: 2,
      isMissing: (_) => false,
      schedule: scheduler.schedule,
    );
    addTearDown(counter.close);
    final state = counter.state;
    await counter.useLayout('layout-a');
    counter.recordChapter('layout-a', 0, 5);
    await counter.bindStore(store);
    await counter.flush();
    counter.setActive(true);
    expect(identical(counter.state, state), isTrue);
    expect(state.value.completedPages, 9);
    expect(state.value.isComplete, isTrue);
    expect(store.saved['layout-a'], {0: 5, 1: 4});
    await counter.bindStore(store);
    await counter.useLayout('layout-a');
    expect(store.loaded, ['layout-a']);
    expect(scheduler.requests, isEmpty);
  });

  test('晚绑定取消在途计页，恢复合并并发前台结果后才落盘', () async {
    final cached = {0: 99, 1: 99, 2: 7};
    final store = _MemoryCountStore()
      ..saved['layout-a'] = cached
      ..pendingLoad = Completer();
    final scheduler = _PendingScheduler();
    final counter = BookPageCounter(
      chapterCount: 3,
      isMissing: (_) => false,
      schedule: scheduler.schedule,
    );
    addTearDown(counter.close);
    await counter.useLayout('layout-a');
    counter.recordChapter('layout-a', 0, 3);
    counter.setActive(true);
    await _until(() => scheduler.requests.length == 1);
    final binding = counter.bindStore(store);
    expect(scheduler.requests.single.cancelled, isTrue);
    counter.recordChapter('layout-a', 0, 5);
    counter.recordChapter('layout-a', 1, 6);
    var flushed = false;
    final flush = counter.flush().then((_) => flushed = true);
    await Future<void>.delayed(Duration.zero);
    expect(flushed, isFalse);
    expect(store.saved['layout-a'], cached);
    expect(scheduler.requests.length, 1);
    store.pendingLoad!.complete(cached);
    await binding;
    await flush;
    await _until(() => counter.state.value.isComplete);
    expect(counter.state.value.completedPages, 18);
    expect(store.saved['layout-a'], {0: 5, 1: 6, 2: 7});
    expect(scheduler.requests.length, 1);
  });

  for (final failOldLoad in [false, true]) {
    test('再次绑定隔离旧存储晚到${failOldLoad ? '错误' : '结果'}', () async {
      final oldStore = _MemoryCountStore()..pendingLoad = Completer();
      final nextStore = _MemoryCountStore()..saved['layout-a'] = {1: 7};
      final scheduler = _PendingScheduler();
      final counter = BookPageCounter(
        chapterCount: 3,
        isMissing: (_) => false,
        schedule: scheduler.schedule,
      );
      addTearDown(counter.close);
      await counter.useLayout('layout-a');
      counter.recordChapter('layout-a', 0, 4);
      final oldBinding = counter.bindStore(oldStore);
      await counter.bindStore(nextStore);
      if (failOldLoad) {
        oldStore.pendingLoad!.completeError(StateError('旧存储读取失败'));
      } else {
        oldStore.pendingLoad!.complete({0: 99, 2: 99});
      }
      await oldBinding;
      await counter.flush();
      counter.setActive(true);
      expect(counter.state.value.completedPages, 11);
      expect(counter.state.value.completedChapters, 2);
      expect(counter.state.value.isComplete, isFalse);
      expect(counter.persistenceError, isNull);
      expect(nextStore.saved['layout-a'], {0: 4, 1: 7});
      await _until(() => scheduler.requests.isNotEmpty);
      expect(scheduler.requests.single.spine, 2);
    });
  }

  test('晚绑定恢复期间切布局，旧结果不回填新布局', () async {
    final pending = Completer<Map<int, int>>();
    final store = _MemoryCountStore()
      ..pendingLoad = pending
      ..saved['layout-b'] = {0: 2, 1: 3};
    final scheduler = _PendingScheduler();
    final counter = BookPageCounter(
      chapterCount: 2,
      isMissing: (_) => false,
      schedule: scheduler.schedule,
    );
    addTearDown(counter.close);
    await counter.useLayout('layout-a');
    counter.recordChapter('layout-a', 0, 5);
    final binding = counter.bindStore(store);
    store.pendingLoad = null;
    await counter.useLayout('layout-b');
    counter.recordChapter('layout-b', 0, 4);
    pending.complete({0: 99, 1: 99});
    await binding;
    await counter.flush();
    counter.setActive(true);
    expect(counter.state.value.layoutKey, 'layout-b');
    expect(counter.state.value.completedPages, 7);
    expect(counter.state.value.isComplete, isTrue);
    expect(store.saved, {
      'layout-b': {0: 4, 1: 3},
    });
    expect(scheduler.requests, isEmpty);
  });

  test('晚绑定恢复期间关闭，晚到缓存不保存或继续调度', () async {
    final store = _MemoryCountStore()..pendingLoad = Completer();
    final scheduler = _PendingScheduler();
    final counter = BookPageCounter(
      chapterCount: 2,
      isMissing: (_) => false,
      schedule: scheduler.schedule,
    );
    addTearDown(counter.close);
    await counter.useLayout('layout-a');
    counter.recordChapter('layout-a', 0, 5);
    final binding = counter.bindStore(store);
    counter.setActive(true);
    var notifications = 0;
    counter.state.addListener(() => notifications++);
    counter.close();
    store.pendingLoad!.complete({0: 99, 1: 99});
    await binding;
    await counter.flush();
    expect(notifications, 0);
    expect(store.saved, isEmpty);
    expect(scheduler.requests, isEmpty);
    final unused = _MemoryCountStore();
    await counter.bindStore(unused);
    expect(unused.loaded, isEmpty);
  });

  test('逐章完成通知最多每 250ms 一次，最终快照包含全部计数', () async {
    final counter = BookPageCounter(
      chapterCount: 3,
      isMissing: (_) => false,
      schedule: _PendingScheduler().schedule,
    );
    addTearDown(counter.close);
    await counter.useLayout('layout-a');
    var notifications = 0;
    counter.state.addListener(() => notifications++);
    counter.recordChapter('layout-a', 0, 1);
    counter.recordChapter('layout-a', 1, 2);
    counter.recordChapter('layout-a', 2, 3);
    expect(notifications, 0);
    await _until(() => counter.state.value.isComplete);
    expect(notifications, 1);
    expect(counter.state.value.completedPages, 6);
  });

  test('遍历期间发现缺章不会重入或重复调度', () async {
    final scheduler = _PendingScheduler();
    var missing = false;
    final counter = BookPageCounter(
      chapterCount: 2,
      isMissing: (spine) => missing && spine == 0,
      schedule: scheduler.schedule,
    );
    addTearDown(counter.close);
    await counter.useLayout('layout-a');
    missing = true;
    counter.setActive(true);
    await _until(() => scheduler.requests.isNotEmpty);
    expect(scheduler.requests.map((request) => request.spine), [1]);
    scheduler.requests.single.finish(2);
    await _until(() => counter.state.value.isComplete);
    expect(counter.state.value.completedPages, 2);
  });
}
