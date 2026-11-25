import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';

import 'reader_tts_controller.dart';

/// 阅读页底部的悬浮听书控制条。
class ReaderTtsPlaybackSheet extends StatefulWidget {
  const ReaderTtsPlaybackSheet({
    super.key,
    required this.controller,
    required this.onVoice,
    required this.onSpeed,
    required this.onTimer,
    required this.onCancel,
    this.coverPath,
    this.speedLabel,
    this.timerLabel,
  });

  final ReaderTtsController controller;
  final Future<void> Function() onVoice;
  final Future<void> Function() onSpeed;
  final Future<void> Function() onTimer;
  final Future<void> Function() onCancel;

  /// 书库封面文件；为空时显示占位图标。
  final String? coverPath;

  /// 语速按钮提示（按当前引擎区分文案）；为空时只显示「语速」。
  final String? speedLabel;
  final String? timerLabel;

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
  Widget build(BuildContext context) =>
      ValueListenableBuilder<ReaderTtsSnapshot>(
        valueListenable: widget.controller.state,
        builder: (context, snapshot, _) {
          final failed = snapshot.phase == ReaderTtsPhase.failed;
          if (!widget.controller.hasSession && !failed) {
            return const SizedBox.shrink();
          }
          final paused = snapshot.phase == ReaderTtsPhase.paused;
          final loading = snapshot.phase == ReaderTtsPhase.loading;
          final colors = Theme.of(context).colorScheme;
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width - 32,
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Material(
                color: colors.surface,
                elevation: 0,
                shape: StadiumBorder(
                  side: BorderSide(color: colors.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 3,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _cover(colors),
                      const SizedBox(width: 12),
                      _button(
                        key: const ValueKey('tts-voice'),
                        tooltip: '音色',
                        icon: const Icon(Icons.record_voice_over_outlined),
                        onPressed: () => _act(widget.onVoice),
                      ),
                      const SizedBox(width: 12),
                      _button(
                        key: const ValueKey('tts-speed'),
                        tooltip: widget.speedLabel ?? '语速',
                        icon: const Icon(Icons.speed),
                        onPressed: failed ? null : () => _act(widget.onSpeed),
                      ),
                      const SizedBox(width: 12),
                      _button(
                        key: const ValueKey('tts-timer'),
                        tooltip: widget.timerLabel == null
                            ? '定时'
                            : '定时 · ${widget.timerLabel}',
                        icon: Icon(
                          widget.timerLabel == null
                              ? Icons.timer_outlined
                              : Icons.timer,
                        ),
                        onPressed: failed ? null : () => _act(widget.onTimer),
                      ),
                      const SizedBox(width: 12),
                      _button(
                        key: ValueKey(
                          failed
                              ? 'tts-retry'
                              : paused
                              ? 'tts-resume'
                              : 'tts-pause',
                        ),
                        tooltip: failed
                            ? '重试当前段'
                            : paused
                            ? '继续'
                            : loading
                            ? '正在准备语音，可暂停'
                            : '暂停',
                        icon: failed
                            ? const Icon(Icons.refresh)
                            : loading
                            ? SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  value: MediaQuery.disableAnimationsOf(context)
                                      ? 0.75
                                      : null,
                                ),
                              )
                            : AppIcon(paused ? AppGlyph.play : AppGlyph.pause),
                        onPressed: failed
                            ? () {
                                // retry 的 Future 覆盖整段播放，不能等待它再解锁控制条。
                                unawaited(
                                  widget.controller.retry(
                                    widget.controller.settings,
                                  ),
                                );
                              }
                            : () => _act(
                                paused
                                    ? widget.controller.resume
                                    : widget.controller.pause,
                              ),
                      ),
                      const SizedBox(width: 12),
                      _button(
                        key: const ValueKey('tts-cancel'),
                        tooltip: '取消',
                        icon: const AppIcon(AppGlyph.close),
                        onPressed: () => _act(widget.onCancel),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );

  /// 浮条最前方的圆形封面，只展示不响应点击。
  /// 左边距与取消按钮的右边距一致（都取自浮条自身的水平内边距）。
  Widget _cover(ColorScheme colors) => Semantics(
    image: true,
    label: '图书封面',
    child: ClipOval(
      child: SizedBox.square(
        key: const ValueKey('tts-cover'),
        dimension: 36,
        child: widget.coverPath == null
            ? _coverPlaceholder(colors)
            : Image.file(
                File(widget.coverPath!),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) =>
                    _coverPlaceholder(colors),
              ),
      ),
    ),
  );

  Widget _coverPlaceholder(ColorScheme colors) => ColoredBox(
    color: colors.surfaceContainerHighest,
    child: Icon(
      Icons.menu_book_outlined,
      size: 18,
      color: colors.onSurface.withValues(alpha: 0.7),
    ),
  );

  /// 实心圆形按钮：任何状态下底色都不透明，只有图标随可用状态变淡。
  Widget _button({
    required Key key,
    required String tooltip,
    required Widget icon,
    required VoidCallback? onPressed,
  }) {
    final colors = Theme.of(context).colorScheme;
    final enabled = !_busy && onPressed != null;
    return Tooltip(
      message: tooltip,
      child: Material(
        key: key,
        color: colors.surfaceContainerHighest,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onPressed : null,
          child: SizedBox.square(
            dimension: 40,
            child: Center(
              child: IconTheme(
                data: IconThemeData(
                  size: 22,
                  color: enabled
                      ? colors.onSurface
                      : colors.onSurface.withValues(alpha: 0.38),
                ),
                child: icon,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
