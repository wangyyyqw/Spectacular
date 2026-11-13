import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

part 'image_preview_frame.dart';
part 'image_preview_viewport.dart';

/// 一张待预览的图片；加载器持有原始句柄，预览克隆并释放显示句柄。
class ImagePreviewItem {
  const ImagePreviewItem({
    required this.loadOriginal,
    this.thumbnail,
    this.loadThumbnail,
  });

  /// 原图加载失败返回 null，已有缩略图继续显示。
  final Future<ui.Image?> Function() loadOriginal;

  /// 显示本帧时查询阅读缓存，不持有缓存的原始句柄。
  final ui.Image? Function()? thumbnail;

  /// 只预热当前与相邻帧的缩略图，原图仍仅在选中后加载。
  final Future<ui.Image?> Function()? loadThumbnail;
}

/// 缩略图先显示，当前原图就绪后替换；支持切图、双击和双指缩放。
class ImagePreviewPage extends StatefulWidget {
  ImagePreviewPage({
    super.key,
    required Future<ui.Image?> Function() loadOriginal,
    ui.Image? thumbnail,
  }) : items = List<ImagePreviewItem>.unmodifiable([
         ImagePreviewItem(
           loadOriginal: loadOriginal,
           thumbnail: () => thumbnail,
         ),
       ]),
       initialIndex = 0,
       animate = true,
       onChanged = null;

  ImagePreviewPage.gallery({
    super.key,
    required List<ImagePreviewItem> items,
    this.initialIndex = 0,
    this.onChanged,
    this.animate = true,
  }) : items = List<ImagePreviewItem>.unmodifiable(items) {
    if (items.isEmpty) throw ArgumentError('画廊至少需要一张图片');
  }

  final List<ImagePreviewItem> items;
  final int initialIndex;
  final ValueChanged<int>? onChanged;
  final bool animate;

  @override
  State<ImagePreviewPage> createState() => _ImagePreviewPageState();
}

class _ImagePreviewPageState extends State<ImagePreviewPage> {
  late int _index;
  late final PageController _pager;
  int? _target;
  bool _canZoom = false;

  int get _count => widget.items.length;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, _count - 1);
    _pager = PageController(initialPage: _index, keepPage: false);
  }

  @override
  void didUpdateWidget(ImagePreviewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _index = _index.clamp(0, _count - 1);
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  void _step(int delta) {
    final next = ((_target ?? _index) + delta).clamp(0, _count - 1);
    if (next == (_target ?? _index)) return;
    _target = next;
    if (!widget.animate || MediaQuery.disableAnimationsOf(context)) {
      _pager.jumpToPage(next);
    } else {
      unawaited(
        _pager.animateToPage(
          next,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  bool _scroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _target = null;
    } else if (notification is ScrollEndNotification) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _settled());
    }
    return false;
  }

  void _settled() {
    if (!mounted ||
        !_pager.hasClients ||
        _pager.position.isScrollingNotifier.value) {
      return;
    }
    final selected = (_pager.page ?? _index).round().clamp(0, _count - 1);
    _target = null;
    if (selected == _index) return;
    setState(() {
      _index = selected;
      _canZoom = widget.items[selected].thumbnail?.call() != null;
    });
    widget.onChanged?.call(selected);
  }

  void _imageReady(bool ready) {
    if (mounted && ready != _canZoom) setState(() => _canZoom = ready);
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      unawaited(Navigator.of(context).maybePop());
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft && _count > 1) {
      _step(-1);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
        _count > 1) {
      _step(1);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    onKeyEvent: _key,
    child: Scaffold(
      backgroundColor: Colors.black,
      appBar: _appBar(),
      body: _ImagePreviewViewport(
        index: _index,
        pager: _count > 1 ? _pager : null,
        canZoom: _canZoom,
        animate: widget.animate,
        child: _pages(),
      ),
      bottomNavigationBar: _navigation(),
    ),
  );

  AppBar _appBar() => AppBar(
    automaticallyImplyLeading: false,
    backgroundColor: Colors.transparent,
    foregroundColor: Colors.white,
    centerTitle: true,
    title: _counter(),
    actions: [
      IconButton(
        key: const ValueKey<String>('preview-close'),
        icon: const Icon(Icons.close),
        tooltip: '关闭',
        onPressed: () => Navigator.of(context).pop(),
      ),
    ],
  );

  Widget _pages() => NotificationListener<ScrollNotification>(
    onNotification: _scroll,
    child: PageView.builder(
      controller: _pager,
      physics: const NeverScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      allowImplicitScrolling: true,
      scrollBehavior: ScrollConfiguration.of(context)
          .copyWith(scrollbars: false, overscroll: false),
      itemCount: _count,
      itemBuilder: (_, index) => _ImagePreviewFrame(
        key: ValueKey((index, widget.items[index])),
        item: widget.items[index],
        active: index == _index,
        onReady: index == _index ? _imageReady : null,
      ),
    ),
  );

  Widget _counter() => Semantics(
    liveRegion: true,
    label: '第 ${_index + 1} 张，共 $_count 张',
    child: ExcludeSemantics(
      child: Text(
        _count > 1 ? '${_index + 1} / $_count' : '图片预览',
        style: const TextStyle(
          color: Colors.white,
          fontFeatures: [ui.FontFeature.tabularFigures()],
        ),
      ),
    ),
  );

  Widget _navigation() => SafeArea(
    top: false,
    minimum: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    child: Row(
      children: [
        if (_count > 1)
          IconButton(
            tooltip: '上一张',
            color: Colors.white,
            disabledColor: Colors.white24,
            onPressed: _index > 0 ? () => _step(-1) : null,
            icon: const Icon(Icons.chevron_left),
          ),
        const Expanded(
          child: Text(
            '双击或双指缩放',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70),
          ),
        ),
        if (_count > 1)
          IconButton(
            tooltip: '下一张',
            color: Colors.white,
            disabledColor: Colors.white24,
            onPressed: _index < _count - 1 ? () => _step(1) : null,
            icon: const Icon(Icons.chevron_right),
          ),
      ],
    ),
  );
}
