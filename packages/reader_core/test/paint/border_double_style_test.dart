import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/paint/page_renderer.dart';

const _width = 200;
const _height = 160;

ComputedStyle _style() => ComputedStyle(const {
  'font-size': '16px',
  'line-height': '1',
  'font-family': 'Ahem',
  'margin': '0',
  'width': '100px',
  'height': '60px',
  'border': '12px double #000000',
  'border-radius': '8px',
  'background-color': '#FFFFFF',
});

Future<ByteData> _render() async {
  final style = _style();
  final block = PageBlock.styled(
    layout: TextLayoutEngine.layout(text: '', style: style, maxWidth: 100),
    style: style,
    containingWidth: 100,
  );
  final page = Paginator(pageHeight: _height.toDouble())
      .measureChapter(blocks: [block])
      .pages
      .single;
  final recorder = ui.PictureRecorder();
  PagePainter(background: const Color(0xFFFF0000)).paint(
    Canvas(recorder),
    page,
    pageSize: Size(_width.toDouble(), _height.toDouble()),
  );
  final image = await recorder.endRecording().toImage(_width, _height);
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  image.dispose();
  return data;
}

List<int> _pixel(ByteData data, int x, int y) => List.generate(
  4,
  (channel) => data.getUint8((y * _width + x) * 4 + channel),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('double 边框使用连续圆角双环且保留三等分线宽', () async {
    final data = await _render();

    expect(_pixel(data, 0, 0), [255, 0, 0, 255], reason: '外环圆角外应露出页底');
    expect(_pixel(data, 50, 1), [0, 0, 0, 255], reason: '外侧黑线');
    expect(_pixel(data, 50, 6), [255, 255, 255, 255], reason: '两条黑线之间留白');
    expect(_pixel(data, 50, 10), [0, 0, 0, 255], reason: '内侧黑线');
  });
}
