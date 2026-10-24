import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// 按 CSS 默认（左上、原生尺寸、repeat）把图片平铺到 bounds 内，并裁剪到 bounds。
///
/// 参考阅微 `CSSBackgroundNode.draw()`：默认 `background-position: 0 0`、
/// `background-size: auto`（原生尺寸）、`background-repeat: repeat`。
/// 本函数只实现这一默认子集，`background-size` / `background-position` /
/// `background-repeat` / `background-clip` 仍未解析，一律按默认值处理。
///
/// 图片由调用方在帧外解码并缓存后传入；本函数不做解码，也不做网络/文件 IO。
/// 平铺起点固定为 [Rect.left]、[Rect.top]，超出 bounds 的部分由裁剪丢弃。
void paintTiledBackgroundImage(Canvas canvas, ui.Image image, Rect bounds) {
  final tileWidth = image.width.toDouble();
  final tileHeight = image.height.toDouble();
  // 空矩形或异常图片尺寸时直接返回，避免空循环或死循环。
  if (bounds.isEmpty || tileWidth <= 0 || tileHeight <= 0) {
    return;
  }
  final columns = (bounds.width / tileWidth).ceil();
  final rows = (bounds.height / tileHeight).ceil();
  // 原生尺寸平铺不需要插值，关掉滤波保证像素与图片一致。
  final paint = Paint()..filterQuality = FilterQuality.none;
  canvas.save();
  canvas.clipRect(bounds);
  for (var row = 0; row < rows; row++) {
    for (var column = 0; column < columns; column++) {
      canvas.drawImage(
        image,
        Offset(bounds.left + column * tileWidth, bounds.top + row * tileHeight),
        paint,
      );
    }
  }
  canvas.restore();
}
