import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../library/library_store.dart';
import '../storage/import_queue.dart';
import 'cloud_accounts.dart';
import 'cloud_download.dart';
import 'cloud_models.dart';

enum CloudImportStatus {
  waiting,
  downloading,
  importing,
  completed,
  failed,
  cancelled,
}

class CloudImportItem {
  CloudImportItem(this.file);
  final CloudEntry file;
  CloudImportStatus status = CloudImportStatus.waiting;
  int received = 0, total = 0;
  String? error;
  bool loginRequired = false;
  ImportJob? job;
  File? localFile;
  double? get progress => switch (status) {
    CloudImportStatus.downloading =>
      total > 0 ? (received / total).clamp(0.0, 1.0) : null,
    CloudImportStatus.importing => job?.progress,
    CloudImportStatus.completed => 1,
    _ => null,
  };
  String get label => switch (status) {
    CloudImportStatus.waiting => '等待下载',
    CloudImportStatus.downloading =>
      total > 0 ? '下载中 ${(progress! * 100).floor()}%' : '正在下载',
    CloudImportStatus.importing => '正在导入',
    CloudImportStatus.completed => '已导入书架',
    CloudImportStatus.failed => error ?? '导入失败',
    CloudImportStatus.cancelled => '已取消',
  };
}

/// 网盘下载文件交给原有导入队列，所有书库写入仍走既有校验与去重。
class CloudImportController extends ChangeNotifier {
  CloudImportController({
    required this.provider,
    required this.account,
    required this.accounts,
    required LibraryStore library,
    Future<Directory> Function()? temporaryDirectory,
    CloudBookDownload Function()? downloadFactory,
  }) : _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
       _downloadFactory = downloadFactory ?? CloudBookDownload.new,
       queue = ImportQueue(
         library,
         readFile: (path) => File(path).readAsBytes(),
       ) {
    queue.addListener(_notify);
  }

  final CloudProviderApi provider;
  final CloudAccount account;
  final CloudAccountStore accounts;
  final ImportQueue queue;
  final Future<Directory> Function() _temporaryDirectory;
  final CloudBookDownload Function() _downloadFactory;
  final List<CloudImportItem> items = [];
  CloudBookDownload? _download;
  Directory? _directory;
  bool busy = false, _cancelled = false, _disposed = false;
  Future<void>? _operation;
  Future<void>? _closing;

  Future<void> start(List<CloudEntry> files) async {
    if (busy || _disposed || _closing != null) return;
    final existing = {for (final item in items) item.file.id: item};
    for (final file in files.where((file) => file.isBook)) {
      final item = existing[file.id];
      if (item == null) {
        final added = CloudImportItem(file);
        items.add(added);
        existing[file.id] = added;
      } else if (item.status == CloudImportStatus.failed ||
          item.status == CloudImportStatus.cancelled) {
        _resetDownload(item);
      }
    }
    if (!items.any((item) => item.status == CloudImportStatus.waiting)) return;
    await _run();
  }

  Future<void> retry(CloudImportItem item, {String? encoding}) async {
    if (busy || _disposed || _closing != null) return;
    if (item.status != CloudImportStatus.failed &&
        item.status != CloudImportStatus.cancelled) {
      return;
    }
    if (encoding != null && item.job != null) {
      _cancelled = false;
      busy = true;
      item.status = CloudImportStatus.importing;
      item.error = null;
      item.loginRequired = false;
      _notify();
      queue.retry(item.job!.id, encoding: encoding);
      _operation = _finishImport(item).whenComplete(() {
        busy = false;
        _notify();
      });
      return _operation;
    }
    _resetDownload(item);
    await _run();
  }

  void _resetDownload(CloudImportItem item) {
    item.status = CloudImportStatus.waiting;
    item.received = 0;
    item.total = 0;
    item.error = null;
    item.loginRequired = false;
    item.job = null;
    item.localFile = null;
  }

  Future<void> _run() async {
    busy = true;
    _cancelled = false;
    _notify();
    _operation = _pump().whenComplete(() {
      busy = false;
      _notify();
    });
    await _operation;
  }

  Future<void> _pump() async {
    try {
      _directory ??= await (await _temporaryDirectory()).createTemp(
        'cloud-books-',
      );
      for (final item in items) {
        if (_cancelled || _disposed) break;
        if (item.status != CloudImportStatus.waiting) continue;
        await _import(item);
      }
    } catch (_) {
      for (final item in items.where(
        (item) => item.status == CloudImportStatus.waiting,
      )) {
        item.status = CloudImportStatus.failed;
        item.error = '无法创建下载目录，请检查存储空间';
      }
    }
  }

  Future<void> _import(CloudImportItem item) async {
    try {
      item.status = CloudImportStatus.downloading;
      item.received = 0;
      item.total = item.file.size;
      _notify();
      final source = await provider.resolve(account, item.file);
      if (_cancelled || _disposed) throw const CloudDownloadCancelled();
      await accounts.save(account);
      if (_cancelled || _disposed) throw const CloudDownloadCancelled();
      final file = File(
        p.join(
          _directory!.path,
          '${items.indexOf(item)}${p.extension(item.file.name).toLowerCase()}',
        ),
      );
      _download = _downloadFactory();
      item.localFile = await _download!.save(
        source,
        file,
        onProgress: (received, total) {
          item.received = received;
          item.total = total;
          _notify();
        },
      );
      if (_cancelled || _disposed) throw const CloudDownloadCancelled();
      item.status = CloudImportStatus.importing;
      item.job = queue.enqueuePath(file.path, fallbackTitle: item.file.name);
      _notify();
      await _finishImport(item);
    } catch (error) {
      item.status = _cancelled || _disposed
          ? CloudImportStatus.cancelled
          : CloudImportStatus.failed;
      item.error = error is CloudException ? error.message : '网盘导入失败，请重试';
      item.loginRequired = error is CloudException && error.loginRequired;
    } finally {
      _download = null;
      _notify();
    }
  }

  Future<void> _finishImport(CloudImportItem item) async {
    final job = item.job!;
    while (!job.isFinished) {
      if (_cancelled || _disposed) queue.cancel(job.id);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    await queue.drain();
    item.status = switch (job.status) {
      ImportStatus.succeeded => CloudImportStatus.completed,
      ImportStatus.cancelled => CloudImportStatus.cancelled,
      _ => CloudImportStatus.failed,
    };
    item.error = job.error;
    if (job.status == ImportStatus.succeeded && item.localFile != null) {
      await item.localFile!.delete();
      item.localFile = null;
    }
  }

  void cancel() {
    _cancelled = true;
    _download?.cancel();
    for (final item in items) {
      if (item.status == CloudImportStatus.waiting) {
        item.status = CloudImportStatus.cancelled;
      }
      if (item.job case final job? when !job.isFinished) queue.cancel(job.id);
    }
    _notify();
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    cancel();
    await _operation;
    // 导入取消后需等正在读取的文件释放，再删除这次会话的暂存目录。
    await queue.drain();
    queue.dispose();
    if (_directory != null && await _directory!.exists()) {
      await _directory!.delete(recursive: true);
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    cancel();
    _disposed = true;
    unawaited(close());
    super.dispose();
  }
}
