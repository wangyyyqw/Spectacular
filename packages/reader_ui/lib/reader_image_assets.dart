part of 'reader_page.dart';

/// 分开收集当前可见资源和可选预取资源，避免相邻分帧挤掉正文图片。
class _PageImageAssets {
  _PageImageAssets(
    this.frameOf, {
    required this.includeGalleryAdjacent,
    required this.pageWidth,
  });

  final int Function(PageGallery) frameOf;
  final bool includeGalleryAdjacent;
  final double pageWidth;
  final urls = <String>{};
  final requiredUrls = <String>{};
  final displayWidths = <String, double>{};
  final _visiting = <PageBlock>{};

  void addPage(PageContent page, {bool required = false, double scale = 1}) {
    for (final slice in page.slices) {
      _addBlock(slice.block, required, scale: scale);
    }
    final background = page.background;
    if (background != null) {
      for (final layer in background.effectiveLayers) {
        _addUrl(layer.image, required, pageWidth * scale);
      }
    }
  }

  void _addUrl(String? url, bool required, double width) {
    if (url == null || url.isEmpty) return;
    urls.add(url);
    if (required) requiredUrls.add(url);
    final displayWidth = width.isFinite && width > 0 ? width : pageWidth;
    final previous = displayWidths[url];
    if (previous == null || displayWidth > previous) {
      displayWidths[url] = displayWidth;
    }
  }

  void _addStyle(ComputedStyle? style, bool required, double width) {
    if (style == null) return;
    for (final layer in style.backgroundLayers) {
      _addUrl(layer.image, required, width);
    }
    _addUrl(style.borderImage?.url, required, width);
  }

  void _addBlock(
    PageBlock block,
    bool required, {
    double? borderWidth,
    double scale = 1,
  }) {
    // 相同载荷可在不同尺寸或可见范围复用，仅防循环，不跳过更大的用途。
    if (!_visiting.add(block)) return;
    try {
      final width = borderWidth ?? _blockWidth(block);
      _addStyle(block.style, required, width * scale);
      final gallery = block.gallery;
      if (gallery != null) _addGallery(gallery, required, scale);
      final inlineWidths = _addLayout(block.layout, required, width, scale);
      for (final fragment in block.containers) {
        _addStyle(
          fragment.container.style,
          required,
          fragment.container.width * scale,
        );
      }
      _addInlineImages(block, required, inlineWidths, width, scale);
      for (final cell in block.table?.cells ?? const <TableCellRender>[]) {
        final rowBackground = cell.rowBackground;
        if (rowBackground != null) {
          _addStyle(
            rowBackground.style,
            required,
            rowBackground.rect.width * scale,
          );
        }
        _addStyle(cell.style, required, cell.rect.width * scale);
        _addLayout(cell.layout, required, cell.rect.width, scale);
      }
    } finally {
      _visiting.remove(block);
    }
  }

  double _blockWidth(PageBlock block) {
    final style = block.style;
    if (style == null) return pageWidth;
    final model = BoxModel.fromStyle(style, containingWidth: pageWidth);
    if (block.floatSide != null) {
      final width = block.layout.maxWidth.isFinite
          ? block.layout.maxWidth
          : block.layout.width;
      return model.borderBoxWidth(width);
    }
    if (model.contentWidth == null &&
        (block.isReplaced || block.layout.isVertical)) {
      return model.borderBoxWidth(block.layout.width);
    }
    return model.borderBoxWidth(model.resolveContentWidth(pageWidth));
  }

  Map<int, double> _addLayout(
    TextLayoutResult layout,
    bool required,
    double width,
    double scale,
  ) {
    for (final run in layout.runs) {
      _addStyle(run.style, required, width * scale);
    }
    final replacedWidths = <int, double>{};
    for (final placement in layout.lines.expand((line) => line.inlineBoxes)) {
      final boxWidth = placement.vertical
          ? placement.ascent + placement.descent
          : placement.width;
      if (placement.spec.replacesPlaceholder) {
        final previous = replacedWidths[placement.offset];
        if (previous == null || boxWidth > previous) {
          replacedWidths[placement.offset] = boxWidth;
        }
      }
      final payload = placement.spec.payload;
      if (payload is PageBlock) {
        _addBlock(payload, required, borderWidth: boxWidth, scale: scale);
      } else if (payload is ComputedStyle) {
        _addStyle(payload, required, boxWidth * scale);
      }
    }
    return replacedWidths;
  }

  void _addInlineImages(
    PageBlock block,
    bool required,
    Map<int, double> replacedWidths,
    double availableWidth,
    double scale,
  ) {
    for (final image in block.inlineImages) {
      // 元数据只作后备，不能把已经排成缩略图的替换盒再次按整页解码。
      final replacedWidth = replacedWidths[image.offset];
      final aspect = image.aspectRatio;
      final declaredWidth =
          image.width ??
          (aspect == null
              ? null
              : (image.height ?? block.style?.fontSize ?? 16) * aspect);
      // 显式图片宽度可溢出父块，只有未知宽度才沿用父块宽。
      final width = replacedWidth ?? declaredWidth ?? availableWidth;
      _addUrl(image.url, required, width * scale);
    }
  }

  void _addGallery(PageGallery gallery, bool required, double scale) {
    if (gallery.frames.isEmpty) return;
    final current = frameOf(gallery).clamp(0, gallery.frames.length - 1);
    final frameScale = scale * gallery.scale;
    // 先遍历当前帧，重复载荷也能先归入必需集合。
    addPage(
      gallery.frames[current].content,
      required: required,
      scale: frameScale,
    );
    if (!includeGalleryAdjacent) return;
    for (final index in [current - 1, current + 1]) {
      if (index >= 0 && index < gallery.frames.length) {
        addPage(gallery.frames[index].content, scale: frameScale);
      }
    }
  }
}
