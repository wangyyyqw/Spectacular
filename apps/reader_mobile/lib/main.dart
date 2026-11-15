import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:reader_core/reader_core.dart';
import 'package:reader_ui/reader_ui.dart';

import 'diagnostics/reader_log.dart';
import 'home/home_shell.dart';
import 'library/library_store.dart';
import 'reader/reader_text_warmup.dart';
import 'storage/startup_storage.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final log = ReaderLog.instance;
  FlutterError.onError = (details) {
    unawaited(
      log.log(
        'flutter_error',
        fields: <String, Object?>{
          'message': details.exceptionAsString(),
          'library': details.library,
          'context': details.context,
        },
      ),
    );
    FlutterError.presentError(details);
  };
  ui.PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(
      log.log(
        'platform_error',
        fields: <String, Object?>{'error': error, 'stack': stack},
      ),
    );
    return false;
  };
  await log.initialize();
  await log.log('app_start');
  assert(readerCorePackageName == 'reader_core');
  assert(readerUiPackageName == 'reader_ui');
  // 数据库不可用时仍可启动，界面显示临时模式并提供同一路径的重试。
  final storage = StartupStorage(log: log);
  await storage.retry();
  try {
    warmUpReaderTextRendering();
  } catch (error, stack) {
    unawaited(
      log.log(
        'text_warmup_failed',
        fields: <String, Object?>{'error': '$error', 'stack': '$stack'},
      ),
    );
  }
  runApp(ReaderApp.withStorage(storage: storage));
}

/// 应用壳：四底栏（书架/统计/书评/我的）+ EPUB 导入 + 阅读页。
class ReaderApp extends StatelessWidget {
  /// 创建应用。
  const ReaderApp({
    super.key,
    required LibraryStore library,
    required ReaderProgressStore progressStore,
  }) : _library = library,
       _progressStore = progressStore,
       _startupStorage = null;

  /// 正式启动入口，监听数据库失败与恢复后的存储替换。
  ReaderApp.withStorage({super.key, required StartupStorage storage})
    : _library = storage.library,
      _progressStore = storage.progressStore,
      _startupStorage = storage;

  final LibraryStore _library;
  final ReaderProgressStore _progressStore;
  final StartupStorage? _startupStorage;

  /// 当前书架存储，恢复成功后随启动存储更新。
  LibraryStore get library => _startupStorage?.library ?? _library;

  /// 当前进度存储，与恢复后的书库绑定同一数据库。
  ReaderProgressStore get progressStore =>
      _startupStorage?.progressStore ?? _progressStore;

  @override
  Widget build(BuildContext context) {
    final storage = _startupStorage;
    if (storage == null) return _buildApp(library, progressStore);
    return ListenableBuilder(
      listenable: storage,
      builder: (context, child) => _buildApp(
        storage.library,
        storage.progressStore,
        recovery: storage.isTemporary ? storage : null,
      ),
    );
  }

  Widget _buildApp(
    LibraryStore library,
    ReaderProgressStore progressStore, {
    StartupStorage? recovery,
  }) {
    return MaterialApp(
      title: 'Spectacular Reader',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: HomeShell(
        key: ObjectKey(library),
        library: library,
        progressStore: progressStore,
        storageRecovery: recovery,
      ),
    );
  }
}
