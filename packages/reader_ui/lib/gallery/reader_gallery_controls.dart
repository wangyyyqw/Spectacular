import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reader_core/api.dart' show PageGallery;

/// 透明手势层；画面仍由正文绘制器绘制，切帧不创建新的分页。
class ReaderGalleryControls extends StatefulWidget {
  const ReaderGalleryControls({
    super.key,
    required this.gallery,
    required this.index,
    required this.foreground,
    required this.onChanged,
    this.onPreview,
  });

  final PageGallery gallery;
  final int index;
  final Color foreground;
  final ValueChanged<int> onChanged;
  final VoidCallback? onPreview;

  @override
  State<ReaderGalleryControls> createState() => _ReaderGalleryControlsState();
}

class _ReaderGalleryControlsState extends State<ReaderGalleryControls> {
  double _distance = 0;
  bool _focused = false;

  int get _count => widget.gallery.frames.length;
  int get _index => _count == 0 ? 0 : widget.index.clamp(0, _count - 1);

  void _step(int delta) {
    if (_count < 2) return;
    final next = (_index + delta).clamp(0, _count - 1);
    if (next != _index) widget.onChanged(next);
  }

  void _endDrag(DragEndDetails details) {
    final speed = details.primaryVelocity ?? 0;
    if (_distance.abs() < 24 && speed.abs() < 500) return;
    final direction = _distance.abs() >= 24 ? _distance : speed;
    _step(direction < 0 ? 1 : -1);
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowRight && _count > 1) {
      _step(1);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft && _count > 1) {
      _step(-1);
    } else if (event.logicalKey == LogicalKeyboardKey.enter &&
        widget.onPreview != null) {
      widget.onPreview!();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  String get _label {
    final caption = widget.gallery.frames[_index].content.slices
        .map((slice) => slice.block.layout.text.replaceAll('\uFFFC', '').trim())
        .where((text) => text.isNotEmpty)
        .join('\n');
    return caption.isEmpty ? '图片画廊' : '图片画廊\n$caption';
  }

  String _value(int index) => '第 ${index + 1} 幅，共 $_count 幅';

  @override
  Widget build(BuildContext context) {
    if (_count == 0) return const SizedBox.shrink();
    return Focus(
      onKeyEvent: _key,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: _accessibleControls(context),
    );
  }

  Widget _accessibleControls(BuildContext context) => Semantics(
    label: _label,
    value: _value(_index),
    increasedValue: _index < _count - 1 ? _value(_index + 1) : null,
    decreasedValue: _index > 0 ? _value(_index - 1) : null,
    hint: _count > 1 ? '左右滑动切换图片' : '点按查看原图',
    button: widget.onPreview != null,
    onTap: widget.onPreview,
    onIncrease: _index < _count - 1 ? () => _step(1) : null,
    onDecrease: _index > 0 ? () => _step(-1) : null,
    child: _gesture(context),
  );

  Widget _gesture(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    excludeFromSemantics: true,
    // 消费长按，避免父阅读器把画廊占位块当作正文选区。
    onLongPress: () {},
    onHorizontalDragStart: _count > 1 ? (_) => _distance = 0 : null,
    onHorizontalDragUpdate: _count > 1
        ? (details) => _distance += details.delta.dx
        : null,
    onHorizontalDragEnd: _count > 1 ? _endDrag : null,
    child: _indicator(context),
  );

  Widget _indicator(BuildContext context) => SizedBox.expand(
    child: _count < 2
        ? null
        : Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              height: widget.gallery.indicatorExtent,
              child: Center(
                child: ExcludeSemantics(
                  child: Text(
                    '${_index + 1} / $_count',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: widget.foreground,
                      decoration: _focused ? TextDecoration.underline : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
  );
}
