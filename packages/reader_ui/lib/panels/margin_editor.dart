import 'package:flutter/material.dart';

import '../theme/reader_margins.dart';

/// 边距调节器（设计稿「排版 → 边距调节器」）：全屏编辑态，正文可见，
/// 上下各拆「外/内」两段，可一直调到 0 让正文铺进安全区。
///
/// 交互：点数值两侧的箭头步进 1（长按连续），「恢复初始默认值」回到默认，
/// 「取消」丢弃改动，「保留」应用并退出。
class MarginEditor extends StatefulWidget {
  /// 创建编辑器。
  const MarginEditor({
    super.key,
    required this.margins,
    required this.defaults,
    required this.onCancel,
    required this.onApply,
    this.onPreview,
    this.maxOuter = 96,
    this.maxInner = 60,
    this.maxSide = 48,
  });

  /// 当前页边距。
  final ReaderMargins margins;

  /// 恢复默认值。
  final ReaderMargins defaults;

  /// 取消（丢弃改动）。
  final VoidCallback onCancel;

  /// 保留（应用改动）。
  final ValueChanged<ReaderMargins> onApply;

  /// 草稿变化（拖动/步进时实时回调，供上层立即预览排版）。
  final ValueChanged<ReaderMargins>? onPreview;

  /// 上/下外段上限。
  final double maxOuter;

  /// 上/下内段上限。
  final double maxInner;

  /// 左右上限。
  final double maxSide;

  @override
  State<MarginEditor> createState() => _MarginEditorState();
}

class _MarginEditorState extends State<MarginEditor> {
  late ReaderMargins _draft = widget.margins;

  /// 更新草稿并立即通知上层预览（拖动/步进都走这里）。
  void _apply(ReaderMargins next) {
    setState(() => _draft = next);
    widget.onPreview?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      children: <Widget>[
        // 斜纹只画在「留白区」（边距内、正文外的四圈），正文上不盖任何遮罩。
        Positioned.fill(
          child: IgnorePointer(
            child: LayoutBuilder(
              builder: (context, constraints) => CustomPaint(
                painter: _MarginZonePainter(
                  padding: _draft.toPadding(),
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
                  lineColor: theme.colorScheme.primary.withValues(alpha: 0.35),
                ),
                size: constraints.biggest,
              ),
            ),
          ),
        ),
        // 顶部：上外 / 上内
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  _Pill(
                    label: '上外',
                    value: _draft.topOuter,
                    max: widget.maxOuter,
                    onDelta: (delta) => _apply(_draft.copyWith(
                        topOuter: (_draft.topOuter + delta).clamp(
                          0,
                          widget.maxOuter,
                        )),
                    ),
                    key: const ValueKey<String>('margin-top-outer'),
                  ),
                  const SizedBox(width: 12),
                  _Pill(
                    label: '上内',
                    value: _draft.topInner,
                    max: widget.maxInner,
                    onDelta: (delta) => _apply(_draft.copyWith(
                        topInner: (_draft.topInner + delta).clamp(
                          0,
                          widget.maxInner,
                        )),
                    ),
                    key: const ValueKey<String>('margin-top-inner'),
                  ),
                ],
              ),
            ),
          ),
        ),
        // 左右
        Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: _Pill(
                  label: '左',
                  value: _draft.left,
                  max: widget.maxSide,
                  onDelta: (delta) => _apply(_draft.copyWith(
                      left: (_draft.left + delta).clamp(0, widget.maxSide)),
                  ),
                  key: const ValueKey<String>('margin-left'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _Pill(
                  label: '右',
                  value: _draft.right,
                  max: widget.maxSide,
                  onDelta: (delta) => _apply(_draft.copyWith(
                      right: (_draft.right + delta).clamp(0, widget.maxSide)),
                  ),
                  key: const ValueKey<String>('margin-right'),
                ),
              ),
            ],
          ),
        ),
        // 底部：下内 / 下外 + 动作
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    _Pill(
                      label: '下内',
                      value: _draft.bottomInner,
                      max: widget.maxInner,
                      onDelta: (delta) => _apply(_draft.copyWith(
                          bottomInner: (_draft.bottomInner + delta).clamp(
                            0,
                            widget.maxInner,
                          )),
                      ),
                      key: const ValueKey<String>('margin-bottom-inner'),
                    ),
                    const SizedBox(width: 12),
                    _Pill(
                      label: '下外',
                      value: _draft.bottomOuter,
                      max: widget.maxOuter,
                      onDelta: (delta) => _apply(_draft.copyWith(
                          bottomOuter: (_draft.bottomOuter + delta).clamp(
                            0,
                            widget.maxOuter,
                          )),
                      ),
                      key: const ValueKey<String>('margin-bottom-outer'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _ActionBar(
                  onReset: () => _apply(widget.defaults),
                  onCancel: widget.onCancel,
                  onApply: () => widget.onApply(_draft),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 数值胶囊：`⌃ 标签 值 ⌄`，点箭头步进。
class _Pill extends StatelessWidget {
  const _Pill({
    super.key,
    required this.label,
    required this.value,
    required this.max,
    required this.onDelta,
  });

  final String label;
  final double value;
  final double max;
  final ValueChanged<double> onDelta;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      elevation: 3,
      borderRadius: BorderRadius.circular(18),
      child: GestureDetector(
        // 整颗胶囊都可以拖：横向拖动按 6px = 1 连续改值，实时预览。
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) =>
            onDelta(details.delta.dx / 6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _Arrow(
                icon: Icons.keyboard_arrow_up,
                onTap: value >= max ? null : () => onDelta(1),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  '$label ${value.round()}',
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurface,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ),
              _Arrow(
                icon: Icons.keyboard_arrow_down,
                onTap: value <= 0 ? null : () => onDelta(-1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkResponse(
      onTap: onTap,
      radius: 16,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Icon(
          icon,
          size: 18,
          color: onTap == null
              ? scheme.onSurface.withValues(alpha: 0.25)
              : scheme.onSurface.withValues(alpha: 0.8),
        ),
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.onReset,
    required this.onCancel,
    required this.onApply,
  });

  final VoidCallback onReset;
  final VoidCallback onCancel;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      elevation: 2,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextButton.icon(
              key: const ValueKey<String>('margin-reset'),
              onPressed: onReset,
              icon: const Icon(Icons.restore, size: 16),
              label: const Text('恢复初始默认值'),
            ),
            const Divider(height: 1),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextButton.icon(
                  key: const ValueKey<String>('margin-cancel'),
                  onPressed: onCancel,
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('取消'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  key: const ValueKey<String>('margin-apply'),
                  onPressed: onApply,
                  icon: const Icon(Icons.check, size: 16, color: Color(0xFF2B5B84)),
                  label: const Text(
                    '保留',
                    style: TextStyle(color: Color(0xFF2B5B84)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 只画「留白区」的斜纹与边框：正文矩形内不落任何颜色。
class _MarginZonePainter extends CustomPainter {
  _MarginZonePainter({
    required this.padding,
    required this.color,
    required this.lineColor,
  });

  final EdgeInsets padding;
  final Color color;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final body = Rect.fromLTRB(
      padding.left,
      padding.top,
      size.width - padding.right,
      size.height - padding.bottom,
    );
    if (body.width <= 0 || body.height <= 0) {
      return;
    }
    // 四条留白带（上/下/左/右），互相不重叠。
    final zones = <Rect>[
      Rect.fromLTRB(0, 0, size.width, body.top),
      Rect.fromLTRB(0, body.bottom, size.width, size.height),
      Rect.fromLTRB(0, body.top, body.left, body.bottom),
      Rect.fromLTRB(body.right, body.top, size.width, body.bottom),
    ];
    final hatch = Paint()
      ..color = color
      ..strokeWidth = 5;
    for (final zone in zones) {
      if (zone.width <= 0 || zone.height <= 0) {
        continue;
      }
      canvas.save();
      canvas.clipRect(zone);
      const step = 16.0;
      for (double x = zone.left - zone.height;
          x < zone.right;
          x += step) {
        canvas.drawLine(
          Offset(x, zone.top),
          Offset(x + zone.height, zone.bottom),
          hatch,
        );
      }
      canvas.restore();
    }
    // 正文边界线：一眼看出可读区域在哪。
    canvas.drawRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = lineColor,
    );
  }

  @override
  bool shouldRepaint(_MarginZonePainter oldDelegate) =>
      oldDelegate.padding != padding ||
      oldDelegate.color != color ||
      oldDelegate.lineColor != lineColor;
}
