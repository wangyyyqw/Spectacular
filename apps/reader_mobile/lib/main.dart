import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:reader_core/reader_core.dart';
import 'package:reader_ui/reader_ui.dart';

import 'diagnostics/reader_log.dart';
import 'home/home_shell.dart';
import 'library/library_store.dart';
import 'storage/file_progress_store.dart';

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
  runApp(
    ReaderApp(
      library: LibraryStore(),
      progressStore: FileReaderProgressStore(),
    ),
  );
}

/// 应用壳：四底栏（书架/统计/书评/我的）+ EPUB 导入 + 阅读页。
class ReaderApp extends StatelessWidget {
  /// 创建应用。
  const ReaderApp({super.key, required this.library, required this.progressStore});

  /// 书架存储。
  final LibraryStore library;

  /// 进度存储。
  final FileReaderProgressStore progressStore;

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
