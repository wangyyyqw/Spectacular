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
}
