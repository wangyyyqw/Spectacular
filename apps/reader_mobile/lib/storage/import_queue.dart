import 'dart:async';

import 'package:flutter/foundation.dart';

import '../library/library_store.dart';

/// 导入任务状态。
enum ImportStatus {
  /// 排队中。
  queued,

  /// 执行中。
  running,

  /// 已完成。
  succeeded,

  /// 失败（可重试）。
  failed,

  /// 已取消。
  cancelled,
}

/// 一个导入任务（P4-03）。
///
/// 任务持有原始字节：失败/取消后可原样重试；成功后释放字节，避免长
/// 队列把整本书留在内存里。
class ImportJob {
  ImportJob({
    required this.id,
    required this.bytes,
    this.fallbackTitle,
    this.updateBookId,
  });

  /// 强制覆盖的当前书籍标识；普通导入为空。
  final String? updateBookId;

  /// 任务标识。
  final String id;

  /// 文件名兜底标题（OPF 缺失时用）。
  final String? fallbackTitle;

  /// 原始字节；成功后置空释放，失败/取消后保留用于重试。
  Uint8List? bytes;

  /// 当前状态。
  ImportStatus status = ImportStatus.queued;

  /// 进度 0～1。
  double progress = 0;

  /// 成功后的书库条目。
  BookEntry? entry;

  /// 失败原因（用户可读）。
  String? error;

  /// 失败错误码（P3-27 拒绝文案映射用）。
  String? errorCode;

  /// 已尝试次数。
  int attempts = 0;

  /// 是否已结束（成功/失败/取消）。
  bool get isFinished =>
      status == ImportStatus.succeeded ||
      status == ImportStatus.failed ||
      status == ImportStatus.cancelled;

  /// 是否可重试（失败或取消且仍持有字节）。
  bool get canRetry =>
      bytes != null &&
      (status == ImportStatus.failed || status == ImportStatus.cancelled);
}

/// 串行导入队列（P4-03）。
///
/// 导入是重任务（解包 + 解析 + 统计 + 索引），必须排队执行：一次只跑
/// 一个任务，UI 不阻塞；提交前取消只清理暂存文件，提交后视为成功，
/// 失败可重试。
class ImportQueue extends ChangeNotifier {
  /// 创建队列。
  ImportQueue(this._library);

  final LibraryStore _library;
  final List<ImportJob> _jobs = <ImportJob>[];
  bool _pumping = false;
  bool _disposed = false;
  ImportJob? _runningJob;
  final Set<String> _retryAfterRun = <String>{};
  int _sequence = 0;

  /// 全部任务（含已结束，按入队顺序）。
  List<ImportJob> get jobs => List<ImportJob>.unmodifiable(_jobs);

  /// 正在执行的任务。
  ImportJob? get activeJob {
    for (final job in _jobs) {
      if (job.status == ImportStatus.running) {
        return job;
      }
    }
    return null;
  }

  /// 排队中的任务数。
  int get pendingCount =>
      _jobs.where((job) => job.status == ImportStatus.queued).length;

  /// 是否还有未完成的任务。
  bool get isBusy => activeJob != null || pendingCount > 0;

  /// 是否已完成所有任务（可用于收起进度条）。
  bool get isIdle => !isBusy;

  /// 入队一本 EPUB；立即返回任务，实际导入在后台串行执行。
  ImportJob enqueue(
    Uint8List bytes, {
    String? fallbackTitle,
    String? updateBookId,
  }) {
    if (_disposed) throw StateError('导入队列已释放');
    final job = ImportJob(
      id: 'job-${_sequence++}',
      bytes: bytes,
      fallbackTitle: fallbackTitle,
      updateBookId: updateBookId,
    );
    _jobs.add(job);
    _notify();
    unawaited(_pump());
    return job;
  }

  /// 取消任务：提交前停止；已提交的结果不会调用删书逻辑。
  void cancel(String jobId) {
    if (_disposed) return;
    final job = _jobOf(jobId);
    if (job == null || job.isFinished) {
      return;
    }
    job.status = ImportStatus.cancelled;
    job.error = '已取消';
    _notify();
  }

  /// 重试失败/已取消的任务。
  void retry(String jobId) {
    if (_disposed) return;
    final job = _jobOf(jobId);
    if (job == null || !job.canRetry || job.status == ImportStatus.running) {
      return;
    }
    if (identical(job, _runningJob)) {
      // 底层导入仍在进行；先保留取消状态完成清理，再排入下一轮。
      _retryAfterRun.add(job.id);
      return;
    }
    _resetForRetry(job);
    _notify();
    unawaited(_pump());
  }

  void _resetForRetry(ImportJob job) {
    job
      ..status = ImportStatus.queued
      ..progress = 0
      ..error = null
      ..errorCode = null
      ..entry = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _retryAfterRun.clear();
    for (final job in _jobs) {
      if (job.status == ImportStatus.queued ||
          job.status == ImportStatus.running) {
        job.status = ImportStatus.cancelled;
        job.error = '已取消';
      }
    }
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// 等待队列跑空（测试/退出前用）。
  Future<void> drain() async {
    // `_pumping` 在最后一个任务结束后才复位，等它一并归零，避免
    // 调用方（如测试 tearDown）先 dispose 再被 notify。
    while (isBusy || _pumping) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  ImportJob? _jobOf(String jobId) {
    for (final job in _jobs) {
      if (job.id == jobId) {
        return job;
      }
    }
    return null;
  }

  ImportJob? _nextQueued() {
    for (final job in _jobs) {
      if (job.status == ImportStatus.queued) {
        return job;
      }
    }
    return null;
  }

  /// 串行泵：一次一个任务，直到队列为空。
  Future<void> _pump() async {
    if (_pumping) {
      return;
    }
    _pumping = true;
    try {
      while (true) {
        final job = _nextQueued();
        if (job == null) {
          break;
        }
        _runningJob = job;
        await _run(job);
        _runningJob = null;
        if (_retryAfterRun.remove(job.id)) _resetForRetry(job);
      }
    } finally {
      _pumping = false;
      _notify();
    }
  }

  Future<void> _run(ImportJob job) async {
    final bytes = job.bytes;
    if (bytes == null) {
      job.status = ImportStatus.failed;
      job.error = '导入数据已释放';
      return;
    }
    job
      ..status = ImportStatus.running
      ..attempts += 1
      ..progress = 0.02;
    _notify();
    try {
      void progress(double value) {
        if (job.status != ImportStatus.running) {
          return;
        }
        job.progress = 0.05 + value * 0.9;
        _notify();
      }

      final entry = job.updateBookId == null
          ? await _library.importBytes(
              bytes,
              fallbackTitle: job.fallbackTitle,
              onProgress: progress,
              isCancelled: () => job.status == ImportStatus.cancelled,
            )
          : await _library.updateBytes(
              job.updateBookId!,
              bytes,
              onProgress: progress,
              isCancelled: () => job.status == ImportStatus.cancelled,
            );
      job
        ..entry = entry
        ..progress = 1
        ..status = ImportStatus.succeeded
        ..bytes = null;
    } on LibraryImportException catch (error) {
      if (job.status == ImportStatus.cancelled) return;
      job
        ..status = ImportStatus.failed
        ..error = error.message
        ..errorCode = error.errorCode;
    } catch (error) {
      if (job.status == ImportStatus.cancelled) return;
      job
        ..status = ImportStatus.failed
        ..error = '$error';
    } finally {
      _notify();
    }
  }
}
