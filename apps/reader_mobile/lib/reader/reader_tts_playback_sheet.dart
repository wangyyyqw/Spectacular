import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';

import 'reader_settings.dart';
import 'reader_tts_controller.dart';

/// 听书控制与原文定位集中在一个面板，关闭面板不改变播放。
class ReaderTtsPlaybackSheet extends StatefulWidget {
  const ReaderTtsPlaybackSheet({
    super.key,
    required this.controller,
    required this.onStart,
    required this.onSettings,
    required this.onReturn,
  });

  final ReaderTtsController controller;
  final Future<void> Function() onStart;
  final Future<void> Function() onSettings;
  final Future<void> Function() onReturn;

  @override
  State<ReaderTtsPlaybackSheet> createState() => _ReaderTtsPlaybackSheetState();
}

class _ReaderTtsPlaybackSheetState extends State<ReaderTtsPlaybackSheet> {
  bool _busy = false;

  Future<void> _act(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('听书操作失败：${_errorText(error)}')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _errorText(Object error) =>
      error is StateError ? error.message : '$error';

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: ValueListenableBuilder<ReaderTtsSnapshot>(
        valueListenable: widget.controller.state,
        builder: (context, snapshot, _) => _controls(context, snapshot),
      ),
    ),
  );

  Widget _controls(BuildContext context, ReaderTtsSnapshot snapshot) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('听书', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        _status(snapshot),
        _excerpt(snapshot),
        const SizedBox(height: 20),
        _primary(snapshot),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const ValueKey('tts-settings'),
          onPressed: _busy ? null : () => _act(widget.onSettings),
          icon: const AppIcon(AppGlyph.tune),
          label: Text(widget.controller.hasSession ? '听书设置 · 下段生效' : '听书设置'),
        ),
        if (widget.controller.hasSession ||
            snapshot.phase == ReaderTtsPhase.failed)
          _sessionActions(),
      ],
    );
  }

  Widget _status(ReaderTtsSnapshot snapshot) {
    final label = switch (snapshot.phase) {
      ReaderTtsPhase.idle => '从当前阅读位置开始',
      ReaderTtsPhase.loading => '正在准备语音',
      ReaderTtsPhase.playing => '正在朗读',
      ReaderTtsPhase.paused => '已暂停',
      ReaderTtsPhase.completed => '朗读完成',
      ReaderTtsPhase.failed => '听书失败',
    };
    return Row(
      children: [
        if (snapshot.phase == ReaderTtsPhase.loading) ...[
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(child: Text(label, key: const ValueKey('tts-status'))),
        Text(snapshot.mode == ReaderTtsMode.offline ? '离线伴听' : '系统语音'),
      ],
    );
  }

  Widget _excerpt(ReaderTtsSnapshot snapshot) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (snapshot.chunk != null) ...[
          const SizedBox(height: 12),
          Text(
            snapshot.chapterTitle.isEmpty
                ? '第 ${snapshot.chunk!.spineIndex + 1} 章'
                : snapshot.chapterTitle,
          ),
        ],
        if (snapshot.text.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(snapshot.text, maxLines: 4, overflow: TextOverflow.ellipsis),
        ],
        if (snapshot.error != null) ...[
          const SizedBox(height: 8),
          Text(
            _errorText(snapshot.error!),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }

  Widget _sessionActions() => Wrap(
    alignment: WrapAlignment.spaceBetween,
    children: [
      TextButton.icon(
        key: const ValueKey('tts-return'),
        onPressed: _busy || widget.controller.position == null
            ? null
            : () => _act(widget.onReturn),
        icon: const AppIcon(AppGlyph.locateCurrent),
        label: const Text('回到朗读位置'),
      ),
      TextButton.icon(
        key: const ValueKey('tts-stop'),
        onPressed: _busy ? null : () => _act(widget.controller.stop),
        icon: const AppIcon(AppGlyph.stop),
        label: const Text('结束听书'),
      ),
    ],
  );

  Widget _primary(ReaderTtsSnapshot snapshot) {
    final paused = snapshot.phase == ReaderTtsPhase.paused;
    final active = widget.controller.hasSession;
    final action = !active
        ? widget.onStart
        : paused
        ? widget.controller.resume
        : widget.controller.pause;
    return FilledButton.icon(
      key: ValueKey(
        active ? (paused ? 'tts-resume' : 'tts-pause') : 'tts-start',
      ),
      onPressed: _busy ? null : () => _act(action),
      icon: AppIcon(active && !paused ? AppGlyph.pause : AppGlyph.play),
      label: Text(
        !active
            ? snapshot.phase == ReaderTtsPhase.failed
                  ? '重试朗读'
                  : '开始朗读'
            : paused
            ? '继续朗读'
            : '暂停朗读',
      ),
    );
  }
}
