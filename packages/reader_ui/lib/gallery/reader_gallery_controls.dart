import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reader_core/api.dart' show PageGallery;

/// 透明分页手势层；画面仍由正文绘制器绘制，拖动不创建新的正文分页。
/// 构造参数保留独立的语义、预览和绘制回调，便于宿主按需接入。
class ReaderGalleryControls extends StatefulWidget {
  const ReaderGalleryControls({
    super.key,
    required this.gallery,
    required this.index,
    required this.foreground,
    required this.onChanged,
    this.onPreview,
    this.onPositionChanged,
    this.animate = true,
  });

  final PageGallery gallery;
  final int index;
  final Color foreground;
  final ValueChanged<int> onChanged;
  final VoidCallback? onPreview;
  final ValueChanged<double?>? onPositionChanged;
  final bool animate;

  @override
  State<ReaderGalleryControls> createState() => _ReaderGalleryControlsState();
}

class _ReaderGalleryControlsState extends State<ReaderGalleryControls> {
  late final _pager = PageController(initialPage: _index, keepPage: false);
  double _distance = 0;
  bool _focused = false;
  int? _target;

  int get _count => widget.gallery.frames.length;
  int get _index => _count == 0 ? 0 : widget.index.clamp(0, _count - 1);
  bool get _animate =>
      widget.animate && !MediaQuery.disableAnimationsOf(context);

  @override
  void didUpdateWidget(ReaderGalleryControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index == widget.index &&
        oldWidget.gallery == widget.gallery) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pager.hasClients) return;
      if ((_pager.page! - _index).abs() > 0.001) _pager.jumpToPage(_index);
    });
  }

  @override
  void dispose() {
    _pager.dispose();
    final clearPosition = widget.onPositionChanged;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => clearPosition?.call(null),
    );
    super.dispose();
  }

  void _step(int delta) {
    if (_count < 2) return;
    final next = ((_target ?? _index) + delta).clamp(0, _count - 1);
    if (next == (_target ?? _index)) return;
    if (!_animate || !_pager.hasClients) {
      widget.onChanged(next);
      return;
    }
    _target = next;
    unawaited(
      _pager.animateToPage(
        next,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _endDrag(DragEndDetails details) {
    final speed = details.primaryVelocity ?? 0;
    final threshold = widget.gallery.width / 3;
    if (_distance.abs() < threshold && speed.abs() < 500) return;
    final direction = speed.abs() >= 500 ? speed : _distance;
    _step(direction < 0 ? 1 : -1);
  }

  bool _scroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _target = null;
    }
    if (notification is ScrollUpdateNotification) {
      final metrics = notification.metrics;
      // page 会钳住首尾，直接用像素位置让纸面同步显示边界回弹。
      widget.onPositionChanged?.call(
        metrics.pixels / metrics.viewportDimension,
      );
    } else if (notification is ScrollEndNotification) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _settled());
    }
    return true;
  }

  void _settled() {
    if (!mounted ||
        _count == 0 ||
        !_pager.hasClients ||
        _pager.position.isScrollingNotifier.value) {
      return;
    }
    final selected = (_pager.page ?? _index).round().clamp(0, _count - 1);
    _target = null;
    widget.onPositionChanged?.call(null);
    if (selected != _index) widget.onChanged(selected);
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
    onHorizontalDragStart: _count > 1 && !_animate
        ? (_) => _distance = 0
        : null,
    onHorizontalDragUpdate: _count > 1 && !_animate
        ? (details) => _distance += details.delta.dx
        : null,
    onHorizontalDragEnd: _count > 1 && !_animate ? _endDrag : null,
    child: Stack(
      fit: StackFit.expand,
      children: [if (_count > 1 && _animate) _pages(), _indicator(context)],
    ),
  );

  Widget _pages() => ExcludeSemantics(
    child: NotificationListener<ScrollNotification>(
      onNotification: _scroll,
      child: PageView.builder(
        controller: _pager,
        physics: const BouncingScrollPhysics(),
        scrollBehavior: ScrollConfiguration.of(context)
            .copyWith(scrollbars: false, overscroll: false),
        itemCount: _count,
        itemBuilder: (_, _) => const SizedBox.expand(),
      ),
    ),
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
