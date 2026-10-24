import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../css/computed_style.dart';

/// 按 CSS 默认（左上、原生尺寸、repeat）把图片平铺到 bounds 内，并裁剪到 bounds。
///
/// 保留给只需要默认行为的调用方（P2-13 的旧入口）。
void paintTiledBackgroundImage(Canvas canvas, ui.Image image, Rect bounds) {
  paintBackgroundImage(canvas, image, bounds);
}

/// 按 `background-repeat/size/position` 绘制背景图（P2-18 收口）。
///
/// 参考阅微 `CSSBackgroundNode.draw()`：默认 `position: 0 0`、`size: auto`
/// （原生尺寸）、`repeat`。`background-origin/clip` 仍按块盒子处理。
///
/// 图片由调用方在帧外解码并缓存后传入；本函数不做解码，也不做网络/文件 IO。
void paintBackgroundImage(
  Canvas canvas,
  ui.Image image,
  Rect bounds, {
  CssBackgroundRepeat repeat = CssBackgroundRepeat.repeat,
  CssBackgroundSize size = const CssBackgroundSize.keyword(
    CssBackgroundSizeMode.auto,
  ),
  CssBackgroundPosition position = const CssBackgroundPosition(
    x: CssLength(0, isPercent: true),
    y: CssLength(0, isPercent: true),
  ),
}) {
  final intrinsicWidth = image.width.toDouble();
  final intrinsicHeight = image.height.toDouble();
  // 空矩形或异常图片尺寸时直接返回，避免空循环或死循环。
  if (bounds.isEmpty || intrinsicWidth <= 0 || intrinsicHeight <= 0) {
    return;
  }
  final tile = _resolveTileSize(
    size,
    intrinsicWidth: intrinsicWidth,
    intrinsicHeight: intrinsicHeight,
    bounds: bounds,
  );
  if (tile.width <= 0 || tile.height <= 0) {
    return;
  }
  // 位置按「剩余空间」解算（CSS background-position 语义）。
  final originX = position.x.resolve(bounds.width - tile.width) ?? 0;
  final originY = position.y.resolve(bounds.height - tile.height) ?? 0;
  final paint = Paint()..filterQuality = FilterQuality.none;
  canvas.save();
  canvas.clipRect(bounds);

  // 平铺时第一块瓦片可能落在 bounds 左侧/上侧，回退到覆盖区间起点。
  final repeatX =
      repeat == CssBackgroundRepeat.repeat ||
      repeat == CssBackgroundRepeat.repeatX;
  final repeatY =
      repeat == CssBackgroundRepeat.repeat ||
      repeat == CssBackgroundRepeat.repeatY;
  final startX = repeatX
      ? bounds.left - originX % tile.width
      : bounds.left + originX;
  final startY = repeatY
      ? bounds.top - originY % tile.height
      : bounds.top + originY;
  final stepX = repeatX ? tile.width : 0.0;
  final stepY = repeatY ? tile.height : 0.0;
  for (var y = startY; y < bounds.bottom; y += stepY == 0 ? bounds.bottom : stepY) {
    for (
      var x = startX;
      x < bounds.right;
      x += stepX == 0 ? bounds.right : stepX
    ) {
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, intrinsicWidth, intrinsicHeight),
        Rect.fromLTWH(x, y, tile.width, tile.height),
        paint,
      );
      if (stepX == 0) {
        break;
      }
    }
    if (stepY == 0) {
      break;
    }
  }
  canvas.restore();
}

/// 计算瓦片尺寸：auto/cover/contain/明确尺寸。
Size _resolveTileSize(
  CssBackgroundSize size, {
  required double intrinsicWidth,
  required double intrinsicHeight,
  required Rect bounds,
}) {
  switch (size.mode) {
    case CssBackgroundSizeMode.auto:
      return Size(intrinsicWidth, intrinsicHeight);
    case CssBackgroundSizeMode.cover:
    case CssBackgroundSizeMode.contain:
      final scaleX = bounds.width / intrinsicWidth;
      final scaleY = bounds.height / intrinsicHeight;
      final scale = size.mode == CssBackgroundSizeMode.cover
          ? (scaleX > scaleY ? scaleX : scaleY)
          : (scaleX < scaleY ? scaleX : scaleY);
      return Size(intrinsicWidth * scale, intrinsicHeight * scale);
    case CssBackgroundSizeMode.explicit:
      final width = size.width?.resolve(bounds.width);
      final height = size.height?.resolve(bounds.height);
      if (width != null && height != null) {
        return Size(width, height);
      }
      if (width != null) {
        return Size(width, width * intrinsicHeight / intrinsicWidth);
      }
      if (height != null) {
        return Size(height * intrinsicWidth / intrinsicHeight, height);
      }
      return Size(intrinsicWidth, intrinsicHeight);
  }
}
