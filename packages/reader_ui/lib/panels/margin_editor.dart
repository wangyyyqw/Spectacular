import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../icons/app_icon.dart';
import '../page_furniture/page_furniture.dart';
import '../theme/reader_margins.dart';

/// 边距调节器（设计稿「排版 → 边距调节器」）：全屏编辑态，正文可见，
/// 上下各拆「外/内」两段，可一直调到 0 让正文铺进安全区。
///
/// 交互：点箭头步进 1，或沿对应方向拖动，按钮与边距按 1:1 同步移动；
/// 「恢复默认」回到默认，「取消」丢弃改动，「保存」应用并退出。
class MarginEditor extends StatefulWidget {
  /// 创建编辑器。
  const MarginEditor({
    super.key,
    required this.margins,
    required this.defaults,
    required this.onCancel,
    required this.onApply,
    this.onPreview,
    this.onDragChanged,
    this.showPageFurniture = true,
    this.headerHeight = PageFurniture.headerHeight,
    this.footerHeight = PageFurniture.footerHeight,
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

  /// 保存（应用改动）。
  final ValueChanged<ReaderMargins> onApply;

  /// 草稿变化（拖动/步进时实时回调，供上层预览排版）。
  final ValueChanged<ReaderMargins>? onPreview;

  /// 拖动开始/结束时通知上层，供正文预览合并重排；草稿仍逐次更新。
  final ValueChanged<bool>? onDragChanged;

  /// 是否按页眉页脚槽计算正文位置；关闭时内段直接连接屏幕外侧。
  final bool showPageFurniture;
  final double headerHeight;
  final double footerHeight;

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
  int _activeDrags = 0;

  void _dragChanged(bool dragging) {
    _activeDrags += dragging ? 1 : -1;
    widget.onDragChanged?.call(_activeDrags > 0);
  }

  /// 更新草稿并立即通知上层预览（拖动/步进都走这里）。
  void _apply(ReaderMargins next) {
    if (next == _draft) return;
    setState(() => _draft = next);
    widget.onPreview?.call(next);
  }

  EdgeInsets get _bodyPadding => _draft.toBodyPadding(
    showFurniture: widget.showPageFurniture,
    headerHeight: widget.headerHeight,
    footerHeight: widget.footerHeight,
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        children: <Widget>[
          _buildZones(context, constraints.biggest),
          _verticalControls(top: true),
          _sideControls(),
          _verticalControls(top: false),
        ],
      ),
    );
  }

  Widget _buildZones(BuildContext context, Size size) {
    final scheme = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          key: const ValueKey<String>('margin-zone-painter'),
          painter: _MarginZonePainter(
            outerPadding: _draft.toOuterPadding(),
            bodyPadding: _bodyPadding,
            showPageFurniture: widget.showPageFurniture,
            headerHeight: widget.headerHeight,
            footerHeight: widget.footerHeight,
            color: scheme.onSurface.withValues(alpha: 0.06),
            shadowColor: scheme.onSurface.withValues(alpha: 0.1),
            lineColor: scheme.primary.withValues(alpha: 0.35),
          ),
          size: size,
        ),
      ),
    );
  }

  Widget _verticalControls({required bool top}) => Positioned(
    top: top ? 0 : null,
    bottom: top ? null : 0,
    left: 0,
    right: 0,
    child: SafeArea(
      top: top,
      bottom: !top,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.only(top: top ? 12 : 0, bottom: top ? 0 : 12),
            child: _verticalRow(top: top),
          ),
          // 操作栏固定在底部，调节按钮在它上方移动，避免拖到保存按钮下面。
          if (!top) ...<Widget>[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '拖动调节 · 点数值精调 · 单位 dp',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  backgroundColor: Theme.of(context).colorScheme.surface,
                ),
              ),
            ),
            _buildActions(),
            const SizedBox(height: 8),
          ],
        ],
      ),
    ),
  );

  Widget _verticalRow({required bool top}) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: top ? CrossAxisAlignment.start : CrossAxisAlignment.end,
    children: <Widget>[
      _verticalControl(top: top, outer: top),
      const SizedBox(width: 12),
      _verticalControl(top: top, outer: !top),
    ],
  );

  Widget _verticalControl({required bool top, required bool outer}) {
    final value = _verticalValue(top: top, outer: outer);
    final offset = outer
        ? value
        : (top ? _bodyPadding.top : _bodyPadding.bottom);
    final max = outer ? widget.maxOuter : widget.maxInner;
    return Padding(
      padding: EdgeInsets.only(top: top ? offset : 0, bottom: top ? 0 : offset),
      child: _Pill(
        key: ValueKey<String>(
          'margin-${top ? 'top' : 'bottom'}-${outer ? 'outer' : 'inner'}',
        ),
        label: '${top ? '上' : '下'}${outer ? '外' : '内'}',
        axis: Axis.vertical,
        dragSign: top ? 1 : -1,
        value: value,
        max: max,
        onDelta: (delta) => _changeVertical(delta, top: top, outer: outer),
        onDragChanged: _dragChanged,
      ),
    );
  }

  double _verticalValue({required bool top, required bool outer}) => top
      ? (outer ? _draft.topOuter : _draft.topInner)
      : (outer ? _draft.bottomOuter : _draft.bottomInner);

  void _changeVertical(double delta, {required bool top, required bool outer}) {
    final max = outer ? widget.maxOuter : widget.maxInner;
    final next = (_verticalValue(top: top, outer: outer) + delta).clamp(
      0.0,
      max,
    );
    _apply(
      _draft.copyWith(
        topOuter: top && outer ? next : null,
        topInner: top && !outer ? next : null,
        bottomOuter: !top && outer ? next : null,
        bottomInner: !top && !outer ? next : null,
      ),
    );
  }

  Widget _sideControls() => Center(
    child: SafeArea(
      top: false,
      bottom: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 按上限预留移动空间，窄屏也保持按钮宽度稳定，左右不会相互覆盖。
          final width = (constraints.maxWidth / 2 - widget.maxSide - 8).clamp(
            52.0,
            100.0,
          );
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              _sideControl(left: true, width: width),
              _sideControl(left: false, width: width),
            ],
          );
        },
      ),
    ),
  );

  Widget _sideControl({required bool left, required double width}) {
    final value = left ? _draft.left : _draft.right;
    return Padding(
      padding: EdgeInsets.only(
        left: left ? 8 + value : 0,
        right: left ? 0 : 8 + value,
      ),
      child: SizedBox(
        width: width,
        child: _Pill(
          key: ValueKey<String>('margin-${left ? 'left' : 'right'}'),
          label: left ? '左' : '右',
          dragSign: left ? 1 : -1,
          value: value,
          max: widget.maxSide,
          onDelta: (delta) => _changeSide(delta, left: left),
          onDragChanged: _dragChanged,
        ),
      ),
    );
  }

  void _changeSide(double delta, {required bool left}) {
    final current = left ? _draft.left : _draft.right;
    final next = (current + delta).clamp(0.0, widget.maxSide);
    _apply(
      _draft.copyWith(left: left ? next : null, right: left ? null : next),
    );
  }

  Widget _buildActions() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        _ActionCapsule(
          key: const ValueKey<String>('margin-cancel'),
          onTap: widget.onCancel,
          icon: AppGlyph.close,
          label: '取消',
        ),
        _ActionCapsule(
          key: const ValueKey<String>('margin-reset'),
          onTap: () => _apply(widget.defaults),
          icon: AppGlyph.restore,
          label: '恢复默认',
        ),
        _ActionCapsule(
          key: const ValueKey<String>('margin-apply'),
          onTap: () => widget.onApply(_draft),
          icon: AppGlyph.check,
          label: '保存',
          primary: true,
        ),
      ],
    ),
  );
}

/// 数值胶囊：`⌃ 标签 值 ⌄`，点箭头步进或在胶囊上沿对应方向拖动。
class _Pill extends StatefulWidget {
  const _Pill({
    super.key,
    required this.label,
    required this.value,
    required this.max,
    required this.onDelta,
    required this.onDragChanged,
    this.axis = Axis.horizontal,
    this.dragSign = 1,
  });

  final String label;
  final double value;
  final double max;
  final ValueChanged<double> onDelta;
  final ValueChanged<bool> onDragChanged;

  /// 拖动方向：上/下两组胶囊用垂直拖动，左右用水平拖动。
  final Axis axis;

  /// 指针沿轴移动时转成数值的方向；下边距与右边界取反，使胶囊随手指移动。
  final double dragSign;

  @override
  State<_Pill> createState() => _PillState();
}

class _PillState extends State<_Pill> {
  bool _dragging = false;
  Offset _lastPosition = Offset.zero;

  Future<void> _editValue() async {
    final value = await showDialog<double>(
      context: context,
      builder: (_) => _MarginValueDialog(
        label: widget.label,
        value: widget.value,
        max: widget.max,
      ),
    );
    if (value != null && mounted) widget.onDelta(value - widget.value);
  }

  double _axisDelta(Offset delta) =>
      (widget.axis == Axis.horizontal ? delta.dx : delta.dy) * widget.dragSign;

  void _dragStart(DragStartDetails details) {
    _lastPosition = details.globalPosition;
    setState(() => _dragging = true);
    widget.onDragChanged(true);
  }

  void _dragUpdate(DragUpdateDetails details) {
    // 按钮也在移动，必须以屏幕坐标计增量，避免局部坐标产生抵消或跳变。
    final delta = details.globalPosition - _lastPosition;
    _lastPosition = details.globalPosition;
    widget.onDelta(_axisDelta(delta));
  }

  void _dragEnd() {
    if (!_dragging) return;
    setState(() => _dragging = false);
    widget.onDragChanged(false);
  }

  GestureRecognizerFactoryWithHandlers<T>
  _dragFactory<T extends DragGestureRecognizer>(T Function() create) =>
      GestureRecognizerFactoryWithHandlers<T>(
        create,
        (recognizer) => recognizer
          ..onStart = _dragStart
          ..onUpdate = _dragUpdate
          ..onCancel = _dragEnd
          ..dragStartBehavior = DragStartBehavior.down
          // 仅降低拖动阈值，不改变箭头点击的容差；小幅移动即可开始调节。
          ..gestureSettings = const DeviceGestureSettings(touchSlop: 2)
          ..onEnd = (_) => _dragEnd(),
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final horizontal = widget.axis == Axis.horizontal;
    return Material(
      color: _dragging ? scheme.primaryContainer : scheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(
          color: _dragging ? scheme.primary : scheme.outlineVariant,
        ),
      ),
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: <Type, GestureRecognizerFactory>{
          if (horizontal)
            HorizontalDragGestureRecognizer:
                _dragFactory<HorizontalDragGestureRecognizer>(
                  () => HorizontalDragGestureRecognizer(debugOwner: this),
                )
          else
            VerticalDragGestureRecognizer:
                _dragFactory<VerticalDragGestureRecognizer>(
                  () => VerticalDragGestureRecognizer(debugOwner: this),
                ),
        },
        child: _buildContent(scheme),
      ),
    );
  }

  Widget _buildContent(ColorScheme scheme) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _Arrow(
          icon: AppGlyph.chevronUp,
          onTap: widget.value >= widget.max ? null : () => widget.onDelta(1),
        ),
        Flexible(child: _buildValue(scheme)),
        _Arrow(
          icon: AppGlyph.chevronDown,
          onTap: widget.value <= 0 ? null : () => widget.onDelta(-1),
        ),
      ],
    ),
  );

  // 固定标签宽度，个位与两位数切换时按钮不会横向抖动。
  Widget _buildValue(ColorScheme scheme) => InkWell(
    key: ValueKey('margin-value-${widget.label}'),
    onTap: _editValue,
    child: SizedBox(
      width: (widget.label.length + 3) * 12,
      height: 36,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          '${widget.label} ${_formatMargin(widget.value)}',
          style: TextStyle(
            fontSize: 12,
            color: _dragging ? scheme.onPrimaryContainer : scheme.onSurface,
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
      ),
    ),
  );
}

String _formatMargin(double value) =>
    value.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');

/// 精调输入与拖动共用增量回调，保留预览、取消和保存语义。
class _MarginValueDialog extends StatefulWidget {
  const _MarginValueDialog({
    required this.label,
    required this.value,
    required this.max,
  });

  final String label;
  final double value;
  final double max;

  @override
  State<_MarginValueDialog> createState() => _MarginValueDialogState();
}

class _MarginValueDialogState extends State<_MarginValueDialog> {
  late final _initialText = _formatMargin(widget.value);
  late final _controller = TextEditingController(text: _initialText);

  double? get _value {
    final text = _controller.text.trim();
    // 显示一位小数；未编辑确认时保留拖动产生的原始精度。
    final value = text == _initialText ? widget.value : double.tryParse(text);
    return value != null && value.isFinite && value >= 0 && value <= widget.max
        ? value
        : null;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('${widget.label}边距'),
    content: TextField(
      key: const ValueKey('margin-value-input'),
      controller: _controller,
      autofocus: true,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(
        labelText: '边距',
        suffixText: 'dp',
        helperText: '范围 0–${widget.max.round()}',
        errorText: _value == null ? '请输入范围内的数值' : null,
      ),
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) {
        if (_value != null) Navigator.of(context).pop(_value);
      },
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(
        key: const ValueKey('margin-value-confirm'),
        onPressed: _value == null
            ? null
            : () => Navigator.of(context).pop(_value),
        child: const Text('应用数值'),
      ),
    ],
  );
}

class _Arrow extends StatelessWidget {
  const _Arrow({required this.icon, required this.onTap});

  final AppGlyph icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkResponse(
      onTap: onTap,
      radius: 16,
      child: SizedBox(
        width: 24,
        height: 36,
        child: Center(
          child: AppIcon(
            icon,
            size: 18,
            color: onTap == null
                ? scheme.onSurface.withValues(alpha: 0.25)
                : scheme.onSurface.withValues(alpha: 0.8),
          ),
        ),
      ),
    );
  }
}

class _ActionCapsule extends StatelessWidget {
  const _ActionCapsule({
    super.key,
    required this.onTap,
    required this.icon,
    required this.label,
    this.primary = false,
  });

  final VoidCallback onTap;
  final AppGlyph icon;
  final String label;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = primary ? scheme.onPrimary : scheme.onSurfaceVariant;
    return Material(
      color: primary ? scheme.primary : scheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: _buildLabel(foreground),
        ),
      ),
    );
  }

  Widget _buildLabel(Color foreground) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      AppIcon(icon, size: 14, color: foreground),
      const SizedBox(width: 4),
      Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: foreground,
          fontWeight: primary ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    ],
  );
}

/// 只画留白区的斜纹与边框：正文矩形、页眉页脚槽内不落任何颜色。
class _MarginZonePainter extends CustomPainter {
  _MarginZonePainter({
    required this.outerPadding,
    required this.bodyPadding,
    required this.showPageFurniture,
    required this.headerHeight,
    required this.footerHeight,
    required this.color,
    required this.shadowColor,
    required this.lineColor,
  });

  final EdgeInsets outerPadding;
  final EdgeInsets bodyPadding;
  final bool showPageFurniture;
  final double headerHeight;
  final double footerHeight;
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
    final topFurniture = showPageFurniture ? headerHeight : 0.0;
    final bottomFurniture = showPageFurniture ? footerHeight : 0.0;
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
      oldDelegate.headerHeight != headerHeight ||
      oldDelegate.footerHeight != footerHeight ||
      oldDelegate.color != color ||
      oldDelegate.shadowColor != shadowColor ||
      oldDelegate.lineColor != lineColor;
}
