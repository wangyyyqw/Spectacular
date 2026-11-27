import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';

import 'reader_log.dart';

class ReaderLogPage extends StatefulWidget {
  const ReaderLogPage({super.key});

  @override
  State<ReaderLogPage> createState() => _ReaderLogPageState();
}

class _ReaderLogPageState extends State<ReaderLogPage> {
  final _log = ReaderLog.instance;
  late Future<String> _text = _log.exportText();
  bool _busy = false;

  Future<void> _export() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _log.log('export_logs');
      await _log.share();
    } catch (error, stackTrace) {
      recordAppError('log_export_failed', error, stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('日志导出失败')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    if (_busy) return;
    final confirmed = await showReaderConfirmDialog(
      context: context,
      title: '清理日志',
      message: '将清理本机诊断日志（含历史会话），保留上传失败记录。确定清理吗？',
      confirmLabel: '清理',
      destructive: true,
      confirmKey: const ValueKey('logs-clear-confirm'),
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      await _log.clear();
      if (mounted) setState(() => _text = _log.exportText());
    } catch (error, stackTrace) {
      recordAppError('log_clear_failed', error, stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('日志清理失败')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('诊断日志'),
      actions: [
        IconButton(
          tooltip: '导出诊断日志',
          onPressed: _busy ? null : _export,
          icon: const AppIcon(AppGlyph.share),
        ),
        IconButton(
          key: const ValueKey('logs-clear'),
          tooltip: '清理日志',
          onPressed: _busy ? null : _clear,
          icon: const AppIcon(AppGlyph.deleteSweep),
        ),
      ],
    ),
    body: SafeArea(
      child: FutureBuilder<String>(
        future: _text,
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('日志读取失败'));
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SelectableText(snapshot.data!.isEmpty ? '暂无日志' : snapshot.data!),
          );
        },
      ),
    ),
  );
}
