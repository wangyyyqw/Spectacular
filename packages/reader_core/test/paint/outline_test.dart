import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/paint/page_renderer.dart';

const _width = 160;
const _height = 80;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('outline 按 offset 绘制在边框盒外侧且不裁剪', () async {
    final style = ComputedStyle(const <String, String>{
      'font-size': '10px',
      'line-height': '1',
      'font-family': 'Ahem',
      'color': 'transparent',
      'width': '80px',
      'height': '20px',
      'margin-left': '20px',
      'outline': '4px solid #FF0000',
      'outline-offset': '4px',
    });
    final block = PageBlock.styled(
      layout: TextLayoutEngine.layout(text: ' ', style: style, maxWidth: 80),
      style: style,
      containingWidth: _width.toDouble(),
    );
    final page = Paginator(pageHeight: _height.toDouble())
        .measureChapter(blocks: [block])
        .pages
        .single;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const PagePainter().paint(
      canvas,
      page,
      pageSize: Size(_width.toDouble(), _height.toDouble()),
    );
    final image = await recorder.endRecording().toImage(_width, _height);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    image.dispose();
    Color pixel(int x, int y) {
      final offset = (y * _width + x) * 4;
      return Color.fromARGB(
        bytes.getUint8(offset + 3),
        bytes.getUint8(offset),
        bytes.getUint8(offset + 1),
        bytes.getUint8(offset + 2),
      );
    }

    // 边框盒 x=16..104；offset 4 + 线宽 4，轮廓占 x=12..16。
    expect(pixel(13, 10), const Color(0xFFFF0000));
    expect(pixel(11, 10), const Color(0xFFFFFFFF), reason: 'offset 外留白');
    expect(pixel(60, 26), const Color(0xFFFF0000), reason: '底边外扩');
    expect(pixel(60, 29), const Color(0xFFFFFFFF), reason: '轮廓不侵占更多空间');
  });

  test('圆角容器的虚线 outline 沿圆角路径绘制', () async {
    final style = ComputedStyle(const <String, String>{
      'font-size': '10px',
      'line-height': '1',
      'font-family': 'Ahem',
      'color': 'transparent',
      'width': '80px',
      'height': '20px',
      'margin-left': '20px',
      'border-radius': '10px',
      'outline': '2px dashed #FF0000',
      'outline-offset': '4px',
    });
    final block = PageBlock.styled(
      layout: TextLayoutEngine.layout(text: ' ', style: style, maxWidth: 80),
      style: style,
      containingWidth: _width.toDouble(),
    );
    final page = Paginator(pageHeight: _height.toDouble())
        .measureChapter(blocks: [block])
        .pages
        .single;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const PagePainter().paint(
      canvas,
      page,
      pageSize: Size(_width.toDouble(), _height.toDouble()),
    );
    final image = await recorder.endRecording().toImage(_width, _height);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    image.dispose();

    var minX = _width;
    var minY = _height;
    var maxX = 0;
    var maxY = 0;
    var redPixels = 0;
    var opaqueRedPixels = 0;
    for (var y = 0; y < _height; y++) {
      for (var x = 0; x < _width; x++) {
        final offset = (y * _width + x) * 4;
        final red = bytes.getUint8(offset);
        final green = bytes.getUint8(offset + 1);
        final blue = bytes.getUint8(offset + 2);
        if (red > 200 && red - green > 50 && red - blue > 50) {
          redPixels++;
          minX = minX > x ? x : minX;
          minY = minY > y ? y : minY;
          maxX = maxX < x ? x : maxX;
          maxY = maxY < y ? y : maxY;
          if (green < 30 && blue < 30) {
            opaqueRedPixels++;
          }
        }
      }
    }
    expect(redPixels, greaterThan(0), reason: '虚线仍应可见');
    expect(opaqueRedPixels, greaterThan(0), reason: '虚线按线宽描边，不是填充细缝');
    expect(maxX - minX, greaterThan(70), reason: '轮廓横跨整个边框盒');
    expect(maxY - minY, greaterThan(10), reason: '轮廓沿上下边绘制');

    // 旧实现按四条直边绘制，左上角必有第一段虚线；圆角路径在该点留白。
    final cornerOffset = ((minY + 1) * _width + minX + 1) * 4;
    expect(
      bytes.getUint8(cornerOffset) > 200 &&
          bytes.getUint8(cornerOffset) - bytes.getUint8(cornerOffset + 1) > 50,
      isFalse,
      reason: '虚线 outline 不应保留直角拐点',
    );
  });
}
