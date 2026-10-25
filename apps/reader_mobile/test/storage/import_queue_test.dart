import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/import_queue.dart';

import '../support/test_epub.dart';

/// 慢速书库：给「执行中取消」留出窗口。
class _SlowLibrary extends LibraryStore {
  _SlowLibrary() : super.memory();

  @override
  Future<BookEntry> importBytes(
    Uint8List bytes, {
    String? fallbackTitle,
    void Function(double progress)? onProgress,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 30));
    return super.importBytes(
      bytes,
      fallbackTitle: fallbackTitle,
      onProgress: onProgress,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('串行导入 3 本：全部成功、进度到 1、顺序与入队一致', () async {
    final library = LibraryStore.memory();
    final queue = ImportQueue(library);
    addTearDown(queue.dispose);
    final progressByJob = <String, List<double>>{};
    queue.addListener(() {
      final job = queue.activeJob;
      if (job == null) {
        return;
      }
      final series = progressByJob.putIfAbsent(job.id, () => <double>[]);
      if (series.isEmpty || series.last != job.progress) {
        series.add(job.progress);
      }
    });

    final jobs = <ImportJob>[
      for (var i = 0; i < 3; i++)
        queue.enqueue(buildTestEpub(title: '书$i'), fallbackTitle: 'book$i'),
    ];
    expect(
      jobs.every((job) => job.status != ImportStatus.succeeded),
      isTrue,
      reason: 'enqueue 立即返回，不等待导入完成',
    );
    await queue.drain();

    expect(queue.isIdle, isTrue);
    expect(jobs.map((job) => job.status), everyElement(ImportStatus.succeeded));
    expect(jobs.map((job) => job.progress), everyElement(1.0));
    final books = await library.list();
    expect(books.length, 3);
    expect(
      books.map((book) => book.title).toSet(),
      {'书0', '书1', '书2'},
    );
    for (final series in progressByJob.values) {
      for (var i = 1; i < series.length; i++) {
        expect(
          series[i],
          greaterThanOrEqualTo(series[i - 1]),
          reason: '单个任务的进度单调不减',
        );
      }
    }
  });

  test('取消排队中的任务：不导入且无残留', () async {
    final library = _SlowLibrary();
    final queue = ImportQueue(library);
    addTearDown(queue.dispose);
    final first = queue.enqueue(buildTestEpub(title: '保留'));
    final second = queue.enqueue(buildTestEpub(title: '取消'));

    queue.cancel(second.id);
    await queue.drain();

    expect(first.status, ImportStatus.succeeded);
    expect(second.status, ImportStatus.cancelled);
    final books = await library.list();
    expect(books.length, 1);
    expect(books.single.title, '保留');
  });

  test('取消执行中的任务：落盘后清理，书架无半成品', () async {
    final library = _SlowLibrary();
    final queue = ImportQueue(library);
    addTearDown(queue.dispose);
    final job = queue.enqueue(buildTestEpub(title: '运行中取消'));
    while (job.status != ImportStatus.running) {
      await Future<void>.delayed(Duration.zero);
    }
    queue.cancel(job.id);
    await queue.drain();

    expect(job.status, ImportStatus.cancelled);
    expect(await library.list(), isEmpty, reason: '已落盘的书被清理');
  });

  test('失败任务可重试，重试仍失败时记录尝试次数', () async {
    final library = LibraryStore.memory();
    final queue = ImportQueue(library);
    addTearDown(queue.dispose);
    final job = queue.enqueue(Uint8List.fromList(<int>[1, 2, 3, 4]));
    await queue.drain();

    expect(job.status, ImportStatus.failed);
    expect(job.attempts, 1);
    expect(job.error, isNotNull);

    queue.retry(job.id);
    await queue.drain();
    expect(job.status, ImportStatus.failed);
    expect(job.attempts, 2, reason: '重试真正重新执行');
  });

  test('重试取消的任务：成功后进度与状态复位', () async {
    final library = _SlowLibrary();
    final queue = ImportQueue(library);
    addTearDown(queue.dispose);
    final job = queue.enqueue(buildTestEpub(title: '先取消再重试'));
    while (job.status != ImportStatus.running) {
      await Future<void>.delayed(Duration.zero);
    }
    queue.cancel(job.id);
    await queue.drain();
    expect(job.status, ImportStatus.cancelled);

    queue.retry(job.id);
    await queue.drain();
    expect(job.status, ImportStatus.succeeded);
    expect(job.progress, 1.0);
    expect((await library.list()).single.title, '先取消再重试');
  });
}
