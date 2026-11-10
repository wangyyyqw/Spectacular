import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/paint/page_renderer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('透明虚线邻边仍决定实线边的楔形斜接', () async {
    final style = ComputedStyle(const {
      'font-size': '10px',
      'color': 'transparent',
      'height': '20px',
      'border-width': '15px',
      'border-style': 'dashed dashed dashed solid',
      'border-color': 'transparent transparent transparent #ab2524',
    });
    final block = PageBlock.styled(
      layout: TextLayoutEngine.layout(text: ' ', style: style, maxWidth: 40),
      style: style,
      containingWidth: 70,
    );
    final page = Paginator(pageHeight: 70)
        .measureChapter(blocks: [block])
        .pages
        .single;
    final recorder = ui.PictureRecorder();
    const PagePainter().paint(
      Canvas(recorder),
      page,
      pageSize: const Size(70, 70),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(70, 70);
    try {
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      List<int> pixel(int x, int y) => List.generate(
        4,
        (channel) => bytes.getUint8((y * 70 + x) * 4 + channel),
      );
      expect(pixel(2, 10), [171, 37, 36, 255]);
      expect(pixel(12, 10), [255, 255, 255, 255], reason: '透明顶边把实线内角切成斜边');
      expect(pixel(12, 25), [171, 37, 36, 255]);
      expect(pixel(12, 40), [255, 255, 255, 255], reason: '透明底边也保留十五像素厚度');
    } finally {
      image.dispose();
      picture.dispose();
    }
  });

  test('天赋卡四像素顶边与一像素侧边按梯形斜角连接', () async {
    final style = ComputedStyle({
      'font-size': '10px',
      'color': 'transparent',
      'height': '20px',
      'border': '1px solid #332a1e',
      'border-top': '4px solid #b8860b',
      'border-bottom': '4px solid #b8860b',
    });
    final block = PageBlock.styled(
      layout: TextLayoutEngine.layout(text: ' ', style: style, maxWidth: 38),
      style: style,
      containingWidth: 40,
    );
    final page = Paginator(pageHeight: 50)
        .measureChapter(blocks: [block])
        .pages
        .single;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(10);
    const PagePainter().paint(canvas, page, pageSize: const Size(40, 50));
    final image = await recorder.endRecording().toImage(400, 500);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    image.dispose();
    List<int> pixel(int x, int y) => List.generate(
      4,
      (channel) => bytes.getUint8((y * 400 + x) * 4 + channel),
    );
    const gold = [184, 134, 11, 255];
    const side = [51, 42, 30, 255];
    expect(pixel(5, 5), gold, reason: '左上外角应属于金色顶边');
    expect(pixel(5, 35), side, reason: '同一横坐标靠近内角应属于深色侧边');
    expect(pixel(394, 5), gold, reason: '右上外角同样斜接');
    expect(pixel(394, 35), side);
    expect(pixel(200, 20), gold, reason: '顶边中央厚度仍为四像素');
  });
}
