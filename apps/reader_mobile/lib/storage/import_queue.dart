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
  });

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
  bool get canRetry => bytes != null && status != ImportStatus.succeeded;
}

/// 串行导入队列（P4-03）。
///
/// 导入是重任务（解包 + 解析 + 统计 + 索引），必须排队执行：一次只跑
/// 一个任务，UI 不阻塞；任务可取消（已落盘的书会被删除，不留半成品）、
/// 失败可重试。
class ImportQueue extends ChangeNotifier {
  /// 创建队列。
  ImportQueue(this._library);

  final LibraryStore _library;
  final List<ImportJob> _jobs = <ImportJob>[];
  bool _pumping = false;
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
  ImportJob enqueue(Uint8List bytes, {String? fallbackTitle}) {
    final job = ImportJob(
      id: 'job-${_sequence++}',
      bytes: bytes,
      fallbackTitle: fallbackTitle,
    );
    _jobs.add(job);
    notifyListeners();
    unawaited(_pump());
    return job;
  }

  /// 取消任务：排队中的直接取消；执行中的等落盘后清理，不留半成品。
  void cancel(String jobId) {
    final job = _jobOf(jobId);
    if (job == null || job.isFinished) {
      return;
    }
    job.status = ImportStatus.cancelled;
    job.error = '已取消';
    notifyListeners();
  }

  /// 重试失败/已取消的任务。
  void retry(String jobId) {
    final job = _jobOf(jobId);
    if (job == null || !job.canRetry || job.status == ImportStatus.running) {
      return;
    }
    job
      ..status = ImportStatus.queued
      ..progress = 0
      ..error = null
      ..errorCode = null
      ..entry = null;
    notifyListeners();
    unawaited(_pump());
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
        await _run(job);
      }
    } finally {
      _pumping = false;
      notifyListeners();
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
    notifyListeners();
    try {
      final entry = await _library.importBytes(
        bytes,
        fallbackTitle: job.fallbackTitle,
        onProgress: (value) {
          // 取消后不再改写进度，但底层不能中断，等落盘后统一清理。
          if (job.status != ImportStatus.running) {
            return;
          }
          job.progress = 0.05 + value * 0.9;
          notifyListeners();
        },
      );
      if (job.status == ImportStatus.cancelled) {
        // 取消发生在落盘之后：删掉刚写入的书与文件，避免半成品。
        await _library.remove(entry.id);
        job.progress = 0;
        return;
      }
      job
        ..entry = entry
        ..progress = 1
        ..status = ImportStatus.succeeded
        ..bytes = null;
    } on LibraryImportException catch (error) {
      job
        ..status = ImportStatus.failed
        ..error = error.message
        ..errorCode = error.errorCode;
    } catch (error) {
      job
        ..status = ImportStatus.failed
        ..error = '$error';
    } finally {
      notifyListeners();
    }
  }
}
