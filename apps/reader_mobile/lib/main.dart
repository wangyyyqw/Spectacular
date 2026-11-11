import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:reader_core/reader_core.dart';
import 'package:reader_ui/reader_ui.dart';

import 'diagnostics/reader_log.dart';
import 'home/home_shell.dart';
import 'library/library_store.dart';
import 'reader/reader_text_warmup.dart';
import 'storage/db.dart';
import 'storage/drift_progress_store.dart';
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
  // P4-01/P4-02：打开业务库（书库/进度/标注/搜索索引）。库损坏或版本
  // 过新时记录错误并继续启动，不让数据库问题拖垮阅读。
  final database = await AppDatabase.tryOpenDefault(
    onError: (error, stack) => unawaited(
      log.log(
        'db_open_failed',
        fields: <String, Object?>{'error': error, 'stack': stack},
      ),
    ),
  );
  if (database != null) {
    await log.log(
      'db_ready',
      fields: <String, Object?>{'schema_version': database.schemaVersion},
    );
  }

  assert(readerCorePackageName == 'reader_core');
  assert(readerUiPackageName == 'reader_ui');
  // 书库走 drift（P4-04）：数据库不可用时退回内存模式，书架为空但可启动。
  final library = database == null
      ? LibraryStore.memory()
      : LibraryStore(database: database);
  if (database != null) {
    await prepareLibraryStorage(library, log);
  }
  // P4-10：进度写 reading_progress 表；数据库不可用时退回内存存储。
  final ReaderProgressStore progressStore = database == null
      ? MemoryReaderProgressStore()
      : DriftProgressStore(database);
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
  runApp(ReaderApp(library: library, progressStore: progressStore));
}

/// 应用壳：四底栏（书架/统计/书评/我的）+ EPUB 导入 + 阅读页。
class ReaderApp extends StatelessWidget {
  /// 创建应用。
  const ReaderApp({
    super.key,
    required this.library,
    required this.progressStore,
  });

  /// 书架存储。
  final LibraryStore library;

  /// 进度存储。
  final ReaderProgressStore progressStore;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Spectacular Reader',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: HomeShell(library: library, progressStore: progressStore),
    );
  }
}
