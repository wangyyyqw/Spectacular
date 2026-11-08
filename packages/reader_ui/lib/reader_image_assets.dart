part of 'reader_page.dart';

/// 分开收集当前可见资源和可选预取资源，避免相邻分帧挤掉正文图片。
class _PageImageAssets {
  _PageImageAssets(this.frameOf, {required this.includeGalleryAdjacent});

  final int Function(PageGallery) frameOf;
  final bool includeGalleryAdjacent;
  final urls = <String>{};
  final requiredUrls = <String>{};
  final _visited = <PageBlock>{};

  void addPage(PageContent page, {bool required = false}) {
    for (final slice in page.slices) {
      _addBlock(slice.block, required);
    }
    final background = page.background;
    if (background != null) _addUrl(background.imageUrl, required);
  }

  void _addUrl(String? url, bool required) {
    if (url == null || url.isEmpty) return;
    urls.add(url);
    if (required) requiredUrls.add(url);
  }

  void _addStyle(ComputedStyle? style, bool required) {
    if (style == null) return;
    for (final layer in style.backgroundLayers) {
      _addUrl(layer.image, required);
    }
    _addUrl(style.borderImage?.url, required);
  }

  void _addBlock(PageBlock block, bool required) {
    if (!_visited.add(block)) return;
    _addStyle(block.style, required);
    final gallery = block.gallery;
    if (gallery != null) _addGallery(gallery, required);
    _addLayout(block.layout, required);
    for (final fragment in block.containers) {
      _addStyle(fragment.container.style, required);
    }
    for (final image in block.inlineImages) {
      _addUrl(image.url, required);
    }
    final cells = block.table?.cells;
    if (cells == null) return;
    for (final cell in cells) {
      _addStyle(cell.style, required);
      _addLayout(cell.layout, required);
    }
  }

  void _addLayout(TextLayoutResult layout, bool required) {
    for (final run in layout.runs) {
      _addStyle(run.style, required);
    }
    for (final line in layout.lines) {
      for (final placement in line.inlineBoxes) {
        final payload = placement.spec.payload;
        if (payload is PageBlock) _addBlock(payload, required);
      }
    }
  }

  void _addGallery(PageGallery gallery, bool required) {
    if (gallery.frames.isEmpty) return;
    final current = frameOf(gallery).clamp(0, gallery.frames.length - 1);
    // 先遍历当前帧，重复载荷也能先归入必需集合。
    addPage(gallery.frames[current].content, required: required);
    if (!includeGalleryAdjacent) return;
    for (final index in [current - 1, current + 1]) {
      if (index >= 0 && index < gallery.frames.length) {
        addPage(gallery.frames[index].content);
      }
    }
  }
}
