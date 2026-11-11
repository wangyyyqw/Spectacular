import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../css/background_values.dart';
import '../css/length.dart';
import 'background_tiles.dart';

/// 按 CSS 默认（左上、原生尺寸、repeat）把图片平铺到 bounds 内，并裁剪到 bounds。
///
/// 保留给只需要默认行为的调用方（P2-13 的旧入口）。
void paintTiledBackgroundImage(Canvas canvas, ui.Image image, Rect bounds) {
  paintBackgroundImage(canvas, image, bounds);
}

/// 按 `background-repeat/size/position` 绘制背景图（P2-18 收口）。
///
/// 参考阅微 `CSSBackgroundNode.draw()`：默认 `position: 0 0`、`size: auto`
/// （原生尺寸）、`repeat`。[bounds] 是定位区，显式 [paintingBounds] 是裁剪区。
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
  ColorFilter? colorFilter,
  Rect? paintingBounds,
}) {
  final clip = paintingBounds ?? bounds;
  if (!bounds.isFinite || bounds.isEmpty || !clip.isFinite || clip.isEmpty) {
    return;
  }
  final intrinsic = Size(image.width.toDouble(), image.height.toDouble());
  final source = Offset.zero & intrinsic;
  final layer = CssBackgroundLayer(
    repeat: repeat,
    size: size,
    position: position,
  );
  final paint = Paint()
    ..filterQuality = FilterQuality.medium
    ..colorFilter = colorFilter;
  canvas.save();
  canvas.clipRect(clip);
  for (final tile in backgroundTileRects(
    bounds,
    layer,
    intrinsicSize: intrinsic,
    paintingBounds: paintingBounds,
  )) {
    canvas.drawImageRect(image, source, tile, paint);
  }
  canvas.restore();
}
