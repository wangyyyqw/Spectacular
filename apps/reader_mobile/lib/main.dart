import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reader_core/reader_core.dart';
import 'package:reader_ui/reader_ui.dart';

import 'diagnostics/reader_log.dart';
import 'home/home_shell.dart';
import 'library/library_store.dart';
import 'storage/db.dart';
import 'storage/drift_progress_store.dart';
import 'storage/file_progress_store.dart';
import 'storage/startup_storage.dart';

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
  if (database != null && await prepareLibraryStorage(library, log)) {
    // 旧书封面回填放后台，不拖慢启动。
    unawaited(
      library
          .backfillCovers()
          .then((filled) async {
            if (filled > 0) {
              await log.log(
                'covers_backfilled',
                fields: <String, Object?>{'books': filled},
              );
            }
          })
          .catchError((Object error, StackTrace stack) async {
            await log.log(
              'covers_backfill_failed',
              fields: <String, Object?>{'error': error, 'stack': stack},
            );
          }),
    );
  }
  // P4-10：进度写 reading_progress 表；数据库不可用时退回内存存储。
  final ReaderProgressStore progressStore;
  if (database == null) {
    progressStore = FileReaderProgressStore.memory();
  } else {
    final driftStore = DriftProgressStore(database);
    // 旧版 reader_progress.json 一次性迁入表（幂等）。
    await prepareProgressStorage(
      driftStore,
      getApplicationSupportDirectory,
      log,
    );
    progressStore = driftStore;
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
      theme: ThemeData.from(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3F51B5)),
      ),
      home: HomeShell(library: library, progressStore: progressStore),
    );
  }
}
