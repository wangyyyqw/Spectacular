import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../page_furniture/page_furniture.dart';
import '../theme/reader_margins.dart';

/// 边距调节器（设计稿「排版 → 边距调节器」）：全屏编辑态，正文可见，
/// 上下各拆「外/内」两段，可一直调到 0 让正文铺进安全区。
///
/// 交互：点数值两侧的箭头步进 1，或在胶囊上沿对应方向拖动；
/// 「恢复初始默认值」回到默认，「取消」丢弃改动，「保留」应用并退出。
class MarginEditor extends StatefulWidget {
  /// 创建编辑器。
  const MarginEditor({
    super.key,
    required this.margins,
    required this.defaults,
    required this.onCancel,
    required this.onApply,
    this.onPreview,
    this.showPageFurniture = true,
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

  /// 是否按页眉页脚槽计算正文位置；关闭时内段直接连接屏幕外侧。
  final bool showPageFurniture;

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

  EdgeInsets get _bodyPadding => _draft.toBodyPadding(
    showFurniture: widget.showPageFurniture,
    headerHeight: PageFurniture.headerHeight,
    footerHeight: PageFurniture.footerHeight,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        children: <Widget>[
          // 斜纹只画在外段和页眉页脚与正文之间的内段，正文不盖遮罩。
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                key: const ValueKey<String>('margin-zone-painter'),
                painter: _MarginZonePainter(
                  outerPadding: _draft.toOuterPadding(),
                  bodyPadding: _bodyPadding,
                  showPageFurniture: widget.showPageFurniture,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
                  shadowColor: theme.colorScheme.onSurface.withValues(
                    alpha: 0.1,
                  ),
                  lineColor: theme.colorScheme.primary.withValues(alpha: 0.35),
                ),
                size: constraints.biggest,
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
                      axis: Axis.vertical,
                      value: _draft.topOuter,
                      max: widget.maxOuter,
                      onDelta: (delta) => _apply(
                        _draft.copyWith(
                          topOuter: (_draft.topOuter + delta).clamp(
                            0,
                            widget.maxOuter,
                          ),
                        ),
                      ),
                      key: const ValueKey<String>('margin-top-outer'),
                    ),
                    const SizedBox(width: 12),
                    _Pill(
                      label: '上内',
                      axis: Axis.vertical,
                      value: _draft.topInner,
                      max: widget.maxInner,
                      onDelta: (delta) => _apply(
                        _draft.copyWith(
                          topInner: (_draft.topInner + delta).clamp(
                            0,
                            widget.maxInner,
                          ),
                        ),
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
                    onDelta: (delta) => _apply(
                      _draft.copyWith(
                        left: (_draft.left + delta).clamp(0, widget.maxSide),
                      ),
                    ),
                    key: const ValueKey<String>('margin-left'),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _Pill(
                    label: '右',
                    dragSign: -1,
                    value: _draft.right,
                    max: widget.maxSide,
                    onDelta: (delta) => _apply(
                      _draft.copyWith(
                        right: (_draft.right + delta).clamp(0, widget.maxSide),
                      ),
                    ),
                    key: const ValueKey<String>('margin-right'),
                  ),
                ),
              ],
            ),
          ),
          // 底部：下内 / 下外
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
                        axis: Axis.vertical,
                        dragSign: -1,
                        value: _draft.bottomInner,
                        max: widget.maxInner,
                        onDelta: (delta) => _apply(
                          _draft.copyWith(
                            bottomInner: (_draft.bottomInner + delta).clamp(
                              0,
                              widget.maxInner,
                            ),
                          ),
                        ),
                        key: const ValueKey<String>('margin-bottom-inner'),
                      ),
                      const SizedBox(width: 12),
                      _Pill(
                        label: '下外',
                        axis: Axis.vertical,
                        dragSign: -1,
                        value: _draft.bottomOuter,
                        max: widget.maxOuter,
                        onDelta: (delta) => _apply(
                          _draft.copyWith(
                            bottomOuter: (_draft.bottomOuter + delta).clamp(
                              0,
                              widget.maxOuter,
                            ),
                          ),
                        ),
                        key: const ValueKey<String>('margin-bottom-outer'),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        _CompactAction(
                          key: const ValueKey<String>('margin-reset'),
                          onTap: () => _apply(widget.defaults),
                          icon: Icons.restore,
                          label: '恢复默认',
                        ),
                        _CompactAction(
                          key: const ValueKey<String>('margin-cancel'),
                          onTap: widget.onCancel,
                          icon: Icons.close,
                          label: '取消',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 保存放在屏幕 3/4 高度，避开底部预览，并使用轻量胶囊。
          Positioned(
            top: constraints.maxHeight * 0.75,
            left: 0,
            right: 0,
            child: Center(
              child: _ApplyCapsule(onTap: () => widget.onApply(_draft)),
            ),
          ),
        ],
      ),
    );
  }
}

/// 数值胶囊：`⌃ 标签 值 ⌄`，点箭头步进或在胶囊上沿对应方向拖动。
class _Pill extends StatefulWidget {
  const _Pill({
    super.key,
    required this.label,
    required this.value,
    required this.max,
    required this.onDelta,
    this.axis = Axis.horizontal,
    this.dragSign = 1,
  });

  final String label;
  final double value;
  final double max;
  final ValueChanged<double> onDelta;

  /// 拖动方向：上/下两组胶囊用垂直拖动，左右用水平拖动。
  final Axis axis;

  /// 指针沿轴移动时转成数值的方向；下边距与右边界取反，使胶囊随手指移动。
  final double dragSign;

  @override
  State<_Pill> createState() => _PillState();
}

class _PillState extends State<_Pill> {
  bool _dragging = false;

  double _axisDelta(Offset delta) =>
      (widget.axis == Axis.horizontal ? delta.dx : delta.dy) * widget.dragSign;

  void _dragStart(DragStartDetails details) {
    setState(() => _dragging = true);
  }

  void _dragUpdate(DragUpdateDetails details) {
    // 6 逻辑像素对应 1 个边距单位；把每帧增量直接交给上层，拖动连续且
    // 边界沿手指方向移动。不要缓存到阈值后再结算，否则慢速拖动会失效。
    widget.onDelta(_axisDelta(details.delta) / 6);
  }

  void _dragEnd(DragEndDetails details) {
    if (mounted) {
      setState(() => _dragging = false);
    }
  }

  void _dragCancel() {
    if (mounted) {
      setState(() => _dragging = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      elevation: _dragging ? 6 : 3,
      borderRadius: BorderRadius.circular(18),
      child: GestureDetector(
        // 整颗胶囊接收拖动；箭头仍作为子级点击目标，移动超过手势阈值后
        // 拖动识别器获胜，不会出现只有箭头能点、胶囊拖不动的情况。
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragStart: widget.axis == Axis.horizontal
            ? _dragStart
            : null,
        onHorizontalDragUpdate: widget.axis == Axis.horizontal
            ? _dragUpdate
            : null,
        onHorizontalDragEnd: widget.axis == Axis.horizontal ? _dragEnd : null,
        onHorizontalDragCancel: widget.axis == Axis.horizontal
            ? _dragCancel
            : null,
        onVerticalDragStart: widget.axis == Axis.vertical ? _dragStart : null,
        onVerticalDragUpdate: widget.axis == Axis.vertical ? _dragUpdate : null,
        onVerticalDragEnd: widget.axis == Axis.vertical ? _dragEnd : null,
        onVerticalDragCancel: widget.axis == Axis.vertical ? _dragCancel : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _Arrow(
                icon: Icons.keyboard_arrow_up,
                onTap: widget.value >= widget.max
                    ? null
                    : () => widget.onDelta(1),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  '${widget.label} ${widget.value.round()}',
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
                onTap: widget.value <= 0 ? null : () => widget.onDelta(-1),
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

class _ApplyCapsule extends StatelessWidget {
  const _ApplyCapsule({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      elevation: 2,
      shape: const StadiumBorder(),
      child: InkWell(
        key: const ValueKey<String>('margin-apply'),
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.check, size: 15, color: Color(0xFF2B5B84)),
              SizedBox(width: 4),
              Text(
                '保留',
                style: TextStyle(
                  color: Color(0xFF2B5B84),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactAction extends StatelessWidget {
  const _CompactAction({
    super.key,
    required this.onTap,
    required this.icon,
    required this.label,
  });

  final VoidCallback onTap;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface.withValues(alpha: 0.94),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 14, color: scheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 只画留白区的斜纹与边框：正文矩形、页眉页脚槽内不落任何颜色。
class _MarginZonePainter extends CustomPainter {
  _MarginZonePainter({
    required this.outerPadding,
    required this.bodyPadding,
    required this.showPageFurniture,
    required this.color,
    required this.shadowColor,
    required this.lineColor,
  });

  final EdgeInsets outerPadding;
  final EdgeInsets bodyPadding;
  final bool showPageFurniture;
  final Color color;
  final Color shadowColor;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final body = Rect.fromLTRB(
      bodyPadding.left,
      bodyPadding.top,
      size.width - bodyPadding.right,
      size.height - bodyPadding.bottom,
    );
    if (body.width <= 0 || body.height <= 0) {
      return;
    }
    final topFurniture = showPageFurniture ? PageFurniture.headerHeight : 0.0;
    final bottomFurniture = showPageFurniture
        ? PageFurniture.footerHeight
        : 0.0;
    final topInnerStart = outerPadding.top + topFurniture;
    final bottomInnerEnd = size.height - outerPadding.bottom - bottomFurniture;
    // 外段与页眉页脚到正文的内段分别绘制；内段为 0 时自然不产生阴影。
    final topInner = Rect.fromLTRB(0, topInnerStart, size.width, body.top);
    final bottomInner = Rect.fromLTRB(
      0,
      body.bottom,
      size.width,
      bottomInnerEnd,
    );
    final zones = <Rect>[
      Rect.fromLTRB(0, 0, size.width, outerPadding.top),
      topInner,
      bottomInner,
      Rect.fromLTRB(
        0,
        size.height - outerPadding.bottom,
        size.width,
        size.height,
      ),
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
      for (double x = zone.left - zone.height; x < zone.right; x += step) {
        canvas.drawLine(
          Offset(x, zone.top),
          Offset(x + zone.height, zone.bottom),
          hatch,
        );
      }
      canvas.restore();
    }
    _paintInnerShadow(canvas, topInner, fromTop: true);
    _paintInnerShadow(canvas, bottomInner, fromTop: false);
    // 正文边界线：一眼看出可读区域在哪。
    canvas.drawRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = lineColor,
    );
  }

  /// 页眉页脚与正文之间的间距非 0 时画一层贴近正文的柔和阴影。
  void _paintInnerShadow(Canvas canvas, Rect zone, {required bool fromTop}) {
    if (zone.width <= 0 || zone.height <= 0) {
      return;
    }
    final shader = LinearGradient(
      begin: fromTop ? Alignment.topCenter : Alignment.bottomCenter,
      end: fromTop ? Alignment.bottomCenter : Alignment.topCenter,
      colors: <Color>[shadowColor.withValues(alpha: 0), shadowColor],
    ).createShader(zone);
    canvas.drawRect(zone, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_MarginZonePainter oldDelegate) =>
      oldDelegate.outerPadding != outerPadding ||
      oldDelegate.bodyPadding != bodyPadding ||
      oldDelegate.showPageFurniture != showPageFurniture ||
      oldDelegate.color != color ||
      oldDelegate.shadowColor != shadowColor ||
      oldDelegate.lineColor != lineColor;
}
