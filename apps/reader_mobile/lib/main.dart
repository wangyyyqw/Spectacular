import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:reader_core/reader_core.dart';
import 'package:reader_ui/reader_ui.dart';

import 'diagnostics/reader_log.dart';
import 'storage/file_progress_store.dart';
import 'reader/demo_source.dart';

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
  await log.log('app_start', fields: <String, Object?>{'book': 'demo-30'});

  assert(readerCorePackageName == 'reader_core');
  assert(readerUiPackageName == 'reader_ui');
  runApp(ReaderApp(store: FileReaderProgressStore()));
}

/// 应用壳：M0 最小阅读页 + 诊断日志导出。
class ReaderApp extends StatefulWidget {
  /// 创建应用。
  const ReaderApp({super.key, required this.store});

  /// 进度存储。
  final ReaderProgressStore store;

  @override
  State<ReaderApp> createState() => _ReaderAppState();
}

class _ReaderAppState extends State<ReaderApp> {
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();
  ReaderSession? _session;
  ReaderProgress? _lastProgress;
  String? _lastLayoutKey;
  String? _lastError;
  bool _exporting = false;

  void _onSessionReady(ReaderSession session) {
    _session = session;
    session.addListener(_onSessionChanged);
    unawaited(
      ReaderLog.instance.log(
        'reader_open',
        fields: <String, Object?>{'book': 'demo-30'},
      ),
    );
  }

  void _onSessionChanged() {
    final session = _session;
    if (session == null) {
      return;
    }
    final error = session.error;
    if (error != null && '$error' != _lastError) {
      _lastError = '$error';
      unawaited(
        ReaderLog.instance.log(
          'reader_error',
          fields: <String, Object?>{'error': error},
        ),
      );
    }
    final progress = session.progress;
    if (progress != null && progress != _lastProgress) {
      _lastProgress = progress;
      unawaited(
        ReaderLog.instance.log(
          'page_turn',
          fields: <String, Object?>{
            'spine': progress.spineIndex,
            'page': progress.pageIndex,
            'text': session.currentText.replaceAll('\n', ' ').trim().length > 40
                ? session.currentText
                      .replaceAll('\n', ' ')
                      .trim()
                      .substring(0, 40)
                : session.currentText.replaceAll('\n', ' ').trim(),
          },
        ),
      );
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _exportLogs() async {
    if (_exporting) {
      return;
    }
    setState(() => _exporting = true);
    final log = ReaderLog.instance;
    try {
      await log.log('export_logs');
      final path = await log.exportFile();
      await log.share();
      await log.log('export_success', fields: <String, Object?>{'path': path});
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('日志已导出：${path ?? '分享面板已打开'}')),
      );
    } catch (error) {
      await log.log('export_error', fields: <String, Object?>{'error': error});
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('日志导出失败：$error')),
      );
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  @override
  void dispose() {
    _session?.removeListener(_onSessionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _lastProgress;
    return MaterialApp(
      title: 'Spectacular Reader',
      scaffoldMessengerKey: _messengerKey,
      home: Scaffold(
        appBar: AppBar(
          title: Text(
            progress == null
                ? 'Spectacular Reader'
                : '第 ${progress.spineIndex + 1} 章 · 第 ${progress.pageIndex + 1} 页',
          ),
          actions: [
            IconButton(
              tooltip: '导出日志',
              onPressed: _exporting ? null : _exportLogs,
              icon: _exporting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.ios_share),
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            // ReaderPage 默认留白 20/16；把实际内容区传给示例源，
            // 避免固定 480 高度在手机上留下半屏空白。
            final width = (constraints.maxWidth - 40)
                .clamp(120, 2000)
                .toDouble();
            // 全面屏手势区用 viewPadding 兜住（SafeArea 在 edge-to-edge 下为 0）。
            final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
            final height = (constraints.maxHeight - 32 - bottomInset)
                .clamp(120, 3000)
                .toDouble();
            // 每档尺寸只记一次，便于真机验收核对内容区与手势区（P2-36）。
            final layoutKey =
                '${constraints.maxWidth}x${constraints.maxHeight}'
                '-${bottomInset.toStringAsFixed(1)}';
            if (layoutKey != _lastLayoutKey) {
              _lastLayoutKey = layoutKey;
              unawaited(
                ReaderLog.instance.log(
                  'layout',
                  fields: <String, Object?>{
                    'constraints_w': constraints.maxWidth,
                    'constraints_h': constraints.maxHeight,
                    'padding_bottom': bottomInset,
                    'content_width': width,
                    'content_height': height,
                    'dpr': MediaQuery.devicePixelRatioOf(context),
                  },
                ),
              );
            }
            return ReaderPage(
              key: ValueKey<String>('${width.toInt()}x${height.toInt()}'),
              source: DemoChapterSource(
                contentWidth: width,
                contentHeight: height,
              ),
              store: widget.store,
              bookId: 'demo-30',
              onSessionReady: _onSessionReady,
            );
          },
        ),
      ),
    );
  }
}
