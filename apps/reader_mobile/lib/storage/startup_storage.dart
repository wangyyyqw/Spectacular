import 'package:flutter/foundation.dart';
import 'package:reader_ui/reader_session.dart';

import '../diagnostics/reader_log.dart';
import '../library/library_store.dart';
import 'db.dart';
import 'drift_progress_store.dart';

/// 启动存储与恢复入口；打开失败时保留同一份临时存储，等待用户重试。
class StartupStorage extends ChangeNotifier {
  /// 数据库创建、书库目录与诊断导出可注入，测试只使用自己的临时数据。
  StartupStorage({
    ReaderLog? log,
    Future<AppDatabase?> Function()? openDatabase,
    LibraryStore Function(AppDatabase)? createLibrary,
    Future<void> Function()? exportDiagnostics,
  }) : _log = log ?? ReaderLog.instance,
       _openDatabase = openDatabase ?? AppDatabase.openDefault,
       _createLibrary = createLibrary ?? _defaultLibrary,
       _exportDiagnostics = exportDiagnostics;

  final ReaderLog _log;
  final Future<AppDatabase?> Function() _openDatabase;
  final LibraryStore Function(AppDatabase) _createLibrary;
  final Future<void> Function()? _exportDiagnostics;
  LibraryStore _library = LibraryStore.memory();
  ReaderProgressStore _progressStore = MemoryReaderProgressStore();
  Future<bool>? _openTask;
  bool _disposed = false;

  /// 当前书库；恢复成功后替换为真实数据库上的存储。
  LibraryStore get library => _library;

  /// 与当前书库使用同一数据库的阅读进度存储。
  ReaderProgressStore get progressStore => _progressStore;

  /// 临时模式不能读取原库，也不能持久化新内容。
  bool get isTemporary => !_library.supportsPersistence;

  /// 正在尝试打开数据库，界面据此阻止重复操作。
  bool get isOpening => _openTask != null;

  static LibraryStore _defaultLibrary(AppDatabase database) =>
      LibraryStore(database: database);

  /// 首次打开与重试共用入口；并发请求复用同一任务。
  Future<bool> retry() {
    if (_disposed) return Future<bool>.value(false);
    if (!isTemporary) return Future<bool>.value(true);
    final pending = _openTask;
    if (pending != null) return pending;
    final task = _openTask = Future<bool>.microtask(_retry);
    notifyListeners();
    return task;
  }

  Future<bool> _retry() async {
    try {
      if (_disposed) return false;
      return await _openStorage();
    } finally {
      _openTask = null;
      if (!_disposed) notifyListeners();
    }
  }

  Future<bool> _openStorage() async {
    AppDatabase? database;
    try {
      database = await _openDatabase();
      if (database == null) {
        await _log.log('db_open_failed');
        return false;
      }
      return await _activateDatabase(database);
    } catch (error, stack) {
      if (database != null) await _closeDatabase(database);
      await _log.log(
        'db_open_failed',
        fields: {'error': error, 'stack': stack},
      );
      return false;
    }
  }

  Future<bool> _activateDatabase(AppDatabase database) async {
    // drift 构造时尚未打开；必须完成版本检查，才能读取书库或清理文件。
    await database.warmUp();
    if (_disposed) {
      await _closeDatabase(database);
      return false;
    }
    final library = _createLibrary(database);
    await prepareLibraryStorage(library, _log);
    await _log.log(
      'db_ready',
      fields: {'schema_version': database.schemaVersion},
    );
    if (_disposed) {
      await _closeDatabase(database);
      return false;
    }
    _library = library;
    _progressStore = DriftProgressStore(database);
    return true;
  }

  Future<void> _closeDatabase(AppDatabase database) async {
    try {
      await database.close();
    } catch (error, stack) {
      await _log.log(
        'db_close_failed',
        fields: {'error': error, 'stack': stack},
      );
    }
  }

  /// 导出经过脱敏的诊断；失败不影响临时模式或下一次重试。
  Future<bool> exportDiagnostics() async {
    try {
      await _log.log('storage_diagnostics_export');
      if (_exportDiagnostics == null) {
        await _log.share();
      } else {
        await _exportDiagnostics();
      }
      return true;
    } catch (error, stack) {
      await _log.log(
        'storage_diagnostics_export_failed',
        fields: {'error': error, 'stack': stack},
      );
      return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// 清理当前书库孤儿；文件不可读时记录错误并让应用继续启动。
Future<void> prepareLibraryStorage(LibraryStore library, ReaderLog log) async {
  if (!library.supportsPersistence) return;
  try {
    final swept = await library.sweepOrphans();
    if (swept.removed > 0) {
      await log.log(
        'library_swept',
        fields: {'entries': swept.removed, 'bytes': swept.bytes},
      );
    }
  } catch (error, stack) {
    await log.log(
      'library_prepare_failed',
      fields: {'error': error, 'stack': stack},
    );
  }
}
