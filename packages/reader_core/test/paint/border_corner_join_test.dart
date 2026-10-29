import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/paint/page_renderer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
