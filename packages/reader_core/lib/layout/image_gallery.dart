import 'dart:ui' show Offset, Rect;

import '../css/computed_style.dart';
import '../position/cfi.dart';
import 'box_model.dart';
import 'line_breaker.dart';
import 'paginator.dart';

/// 多看画廊的一帧；继续使用正文的排版与绘制载荷。
class PageGalleryFrame {
  const PageGalleryFrame({
    required this.cfi,
    required this.content,
    this.imageUrl,
  });

  /// 分帧容器的原始 CFI，重复图片引用仍有独立位置。
  final String cfi;

  /// 本帧图片、题注和容器的完整排版。
  final PageContent content;

  /// 本帧主图的书内路径，供原图预览使用。
  final String? imageUrl;
}

/// 多帧共用一个内容盒；选择状态属于 UI，不进入分页与持久化数据。
class PageGallery {
  PageGallery({
    required this.cfi,
    required List<PageGalleryFrame> frames,
    required this.left,
    required this.width,
    required this.height,
    this.scale = 1,
    this.indicatorExtent = 0,
  }) : frames = List<PageGalleryFrame>.unmodifiable(frames);

  /// 多帧画廊为帧序号预留的高度，避免压住作者题注。
  static const double indicatorHeight = 24;

  /// 外层画廊容器的原始 CFI。
  final String cfi;

  /// 作者定义的分帧顺序，建立后不可修改。
  final List<PageGalleryFrame> frames;

  /// 内容盒在正文坐标中的横向起点。
  final double left;

  /// 内容盒宽度，不含边框和内边距。
  final double width;

  /// 内容盒高度，包含帧序号预留空间。
  final double height;

  /// 超高画廊整组等比缩放，所有帧使用同一比例。
  final double scale;

  /// 本画廊实际预留的帧序号高度，单帧为零。
  final double indicatorExtent;

  /// 图片和题注可使用的高度。
  double get contentHeight => height - indicatorExtent;

  /// 按真实容器路径定位分帧，不按图片地址或字符串前缀猜位置。
  int? frameIndexForCfi(String? value) {
    final parsed = value == null ? null : EpubCfi.parse(value);
    if (parsed == null) return null;
    final target = parsed.rangeStart ?? parsed;
    for (var index = 0; index < frames.length; index++) {
      final root = EpubCfi.parse(frames[index].cfi);
      if (root != null && _containsPath(root, target)) return index;
    }
    return null;
  }

  static bool _containsPath(EpubCfi root, EpubCfi target) {
    if (root.segments.length != target.segments.length) return false;
    for (var segment = 0; segment < root.segments.length; segment++) {
      final prefix = root.segments[segment].steps;
      final steps = target.segments[segment].steps;
      if (prefix.length > steps.length) return false;
      if (segment < root.segments.length - 1 && prefix.length != steps.length) {
        return false;
      }
      for (var index = 0; index < prefix.length; index++) {
        if (prefix[index].index != steps[index].index) return false;
      }
    }
    return true;
  }
}

/// 画廊的页内命中区域；绘制与交互共用分页后的内容起点。
class PageGalleryRegion {
  const PageGalleryRegion({required this.gallery, required this.rect});
  final PageGallery gallery;
  final Rect rect;
}

/// 覆盖切片不推进流位置，段前间距与上内缩不进入画廊手势区。
Iterable<PageGalleryRegion> galleryRegionsOf(PageContent page) sync* {
  var y = page.topPadding;
  for (final slice in page.slices) {
    final top = slice.overlay ? (slice.absoluteTop ?? y) : y;
    final gallery = slice.block.gallery;
    if (gallery != null &&
        gallery.frames.isNotEmpty &&
        gallery.width > 0 &&
        gallery.height > 0 &&
        slice.block.style?.visibility != CssVisibility.hidden &&
        slice.block.style?.visibility != CssVisibility.collapse &&
        slice.block.effectiveOpacity > 0) {
      yield PageGalleryRegion(
        gallery: gallery,
        rect: Rect.fromLTWH(
          gallery.left,
          top + slice.leadingExtent,
          gallery.width,
          gallery.height,
        ),
      );
    }
    if (!slice.overlay) y += slice.height;
  }
}

/// 当前画廊帧主图在页内坐标中的可见矩形。
///
/// [contentOrigin] 和 [containingWidth] 必须与绘制正文时使用的内容区左上角、
/// 内容宽度一致。命中只覆盖主图元素，不包含题注、序号或画廊留白。
Rect? galleryImageRectOf(
  PageGallery gallery,
  int frameIndex, {
  required Offset contentOrigin,
  required double containingWidth,
}) {
  if (gallery.frames.isEmpty ||
      gallery.scale <= 0 ||
      gallery.contentHeight <= 0 ||
      containingWidth <= 0) {
    return null;
  }
  final index = frameIndex.clamp(0, gallery.frames.length - 1);
  final frame = gallery.frames[index];
  final imageUrl = frame.imageUrl;
  if (imageUrl == null) return null;

  final imageBox = _galleryImageBox(frame.content, imageUrl, containingWidth);
  if (imageBox == null || imageBox.isEmpty) return null;

  final scale = gallery.scale;
  final frameLeft =
      contentOrigin.dx +
      gallery.width * (1 - scale) / 2 +
      (imageBox.left - gallery.left) * scale;
  final frameTop = contentOrigin.dy + imageBox.top * scale;
  final rect = Rect.fromLTWH(
    frameLeft,
    frameTop,
    imageBox.width * scale,
    imageBox.height * scale,
  );
  return rect.intersect(
    Rect.fromLTWH(
      contentOrigin.dx,
      contentOrigin.dy,
      gallery.width,
      gallery.contentHeight,
    ),
  );
}

Rect? _galleryImageBox(
  PageContent page,
  String imageUrl,
  double containingWidth,
) {
  var y = page.topPadding;
  for (final slice in page.slices) {
    final top = slice.overlay ? (slice.absoluteTop ?? y) : y;
    if (!slice.overlay) y += slice.height;
    final block = slice.block;
    final style = block.style;
    if (style == null ||
        style.visibility != CssVisibility.visible ||
        block.effectiveOpacity <= 0 ||
        block.gallery != null) {
      continue;
    }
    if (style.backgroundImage == imageUrl) {
      return _galleryBlockImageBox(slice, top, containingWidth);
    }
    final inlineBox = _galleryInlineImageBox(slice, top, imageUrl);
    if (inlineBox != null) return inlineBox;
  }
  return null;
}

Rect _galleryBlockImageBox(
  PageBlockSlice slice,
  double top,
  double containingWidth,
) {
  final block = slice.block;
  final style = block.style!;
  final model = BoxModel.fromStyle(style, containingWidth: containingWidth);
  final borders = style.borders;
  final ownTop = block.containers.isEmpty
      ? block.topInset
      : style.padding.top + (borders.top.isVisible ? borders.top.width : 0);
  final ownBottom = block.containers.isEmpty
      ? block.bottomInset
      : style.padding.bottom +
            (borders.bottom.isVisible ? borders.bottom.width : 0);
  final boxTop = slice.leadingExtent != 0
      ? top + slice.leadingExtent - ownTop
      : top;
  final boxBottom = slice.trailingExtent != 0
      ? top + slice.height - slice.trailingExtent + ownBottom
      : top + slice.height;
  final boxLeft = slice.overlay
      ? slice.leftInset + style.margin.left
      : style.margin.left;
  final boxWidth =
      model.resolveContentWidth(containingWidth) + model.horizontalInset;
  return Rect.fromLTRB(boxLeft, boxTop, boxLeft + boxWidth, boxBottom);
}

Rect? _galleryInlineImageBox(
  PageBlockSlice slice,
  double top,
  String imageUrl,
) {
  final block = slice.block;
  final offsets = {
    for (final image in block.inlineImages)
      if (image.url == imageUrl) image.offset,
  };
  if (offsets.isEmpty) return null;
  final left = _galleryInlineLeft(slice);
  var lineTop = top + slice.leadingExtent;
  for (var index = slice.startLine; index < slice.endLine; index++) {
    final line = block.layout.lines[index];
    for (final placement in line.inlineBoxes) {
      if (!placement.spec.replacesPlaceholder ||
          !offsets.contains(placement.offset) ||
          !_visibleInlineImage(placement)) {
        continue;
      }
      // 与行内替换图绘制共用已排定的盒和基线；上外边距不属于图片命中区。
      return Rect.fromLTWH(
        left + line.offsetX + placement.left,
        lineTop +
            placement.topIn(line.baseline - line.top) +
            placement.spec.marginTop,
        placement.width,
        placement.height,
      );
    }
    lineTop += line.height;
  }
  return null;
}

double _galleryInlineLeft(PageBlockSlice slice) {
  final style = slice.block.style!;
  final inset = slice.overlay && style.isOutOfFlow
      ? style.padding.left +
            (style.borders.left.isVisible ? style.borders.left.width : 0)
      : 0;
  return slice.leftInset + style.margin.left + inset;
}

bool _visibleInlineImage(InlineBoxPlacement placement) {
  final payload = placement.spec.payload;
  final style = switch (payload) {
    PageBlock() => payload.style,
    ComputedStyle() => payload,
    _ => null,
  };
  return (payload is! PageBlock || payload.effectiveOpacity > 0) &&
      (style == null ||
          style.visibility == CssVisibility.visible &&
              style.effectiveOpacity > 0);
}
