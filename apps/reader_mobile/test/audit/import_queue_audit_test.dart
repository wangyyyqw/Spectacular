import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/import_queue.dart';

import '../support/test_epub.dart';

/// 用明确闸门控制首轮导入，避免依赖计时制造竞态。
class _GatedLibrary extends LibraryStore {
  _GatedLibrary() : super.memory();

  final gate = Completer<void>();
  int calls = 0;
  bool failFirst = false;

  @override
  Future<BookEntry> importBytes(
    Uint8List bytes, {
    String? fallbackTitle,
    void Function(double progress)? onProgress,
    bool Function()? isCancelled,
    BookImportConflictHandler? onConflict,
  }) async {
    calls++;
    if (calls == 1) {
      await gate.future;
      if (failFirst) throw const LibraryImportException('模拟导入失败');
    }
    return super.importBytes(
      bytes,
      fallbackTitle: fallbackTitle,
      onProgress: onProgress,
      isCancelled: isCancelled,
      onConflict: onConflict,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('执行中取消后立即重试：先清理首轮结果，再执行第二轮', () async {
    final library = _GatedLibrary();
    final queue = ImportQueue(library);
    addTearDown(queue.dispose);
    final job = queue.enqueue(buildTestEpub(title: '立即重试'));

    queue.cancel(job.id);
    queue.retry(job.id);
    library.gate.complete();
    await queue.drain();

    expect(job.status, ImportStatus.succeeded);
    expect(job.attempts, 2);
    expect(library.calls, 2);
    expect((await library.list()).single.title, '立即重试');
  });

  test('释放队列在提交前取消在途及排队任务，不再通知', () async {
    final library = _GatedLibrary();
    final queue = ImportQueue(library);
    final first = queue.enqueue(buildTestEpub(title: '在途'));
    final second = queue.enqueue(buildTestEpub(title: '排队'));
    queue.dispose();
    library.gate.complete();
    await queue.drain();

    expect(first.status, ImportStatus.cancelled);
    expect(second.status, ImportStatus.cancelled);
    expect(await library.list(), isEmpty);
    expect(library.calls, 1);
  });

  test('取消首轮后底层报错，仍完成真正的重试并串行处理后续书籍', () async {
    final library = _GatedLibrary()..failFirst = true;
    final queue = ImportQueue(library);
    addTearDown(queue.dispose);
    final first = queue.enqueue(buildTestEpub(title: '重试第一本'));
    final second = queue.enqueue(buildTestEpub(title: '排队第二本'));
    expect(first.canRetry, isFalse);
    expect(second.canRetry, isFalse);
    queue.cancel(first.id);
    queue.retry(first.id);
    library.gate.complete();
    await queue.drain();

    expect(first.status, ImportStatus.succeeded);
    expect(first.attempts, 2);
    expect(second.status, ImportStatus.succeeded);
    expect(second.attempts, 1);
    expect(library.calls, 3);
    expect(await library.list(), hasLength(2));
    expect(first.bytes, isNull);
    expect(second.bytes, isNull);
  });
}
