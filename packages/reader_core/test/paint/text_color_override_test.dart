import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/paint/page_renderer.dart';

const _pageSize = Size(120, 80);

ComputedStyle _style() => ComputedStyle(const <String, String>{
  'font-size': '16px',
  'line-height': '1.5',
  'font-family': 'Ahem',
  'color': '#000000',
});

Future<ByteData> _render({Color? textColor}) async {
  final style = _style();
  final layout = TextLayoutEngine.layout(
    text: 'aa',
    style: style,
    maxWidth: 100,
  );
  final page = Paginator(pageHeight: 80)
      .measureChapter(
        blocks: [
          PageBlock.styled(layout: layout, style: style, containingWidth: 100),
        ],
      )
      .pages
      .single;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  PagePainter(textColor: textColor).paint(canvas, page, pageSize: _pageSize);
  final image = await recorder.endRecording().toImage(120, 80);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('主题文字色只改绘制颜色、不参与布局', () async {
    final black = await _render();
    final red = await _render(textColor: const Color(0xFFFF0000));

    var blackInk = 0;
    var redInk = 0;
    var reddish = 0;
    for (var i = 0; i < black.lengthInBytes; i += 4) {
      final a = black.getUint32(i);
      final b = red.getUint32(i);
      if (a != 0xFFFFFFFF) {
        blackInk += 1;
      }
      if (b != 0xFFFFFFFF) {
        redInk += 1;
        // RGBA 大端：R 分量 >200 且 G <80 视为红色墨迹（含抗锯齿）。
        if (((b >> 24) & 0xFF) > 200 && ((b >> 16) & 0xFF) < 80) {
          reddish += 1;
        }
      }
    }
    expect(blackInk, greaterThan(0));
    expect(redInk, blackInk, reason: '墨迹像素数不变，只是改色');
    expect(reddish, greaterThan(0), reason: '文字确实变红');
  });
}
