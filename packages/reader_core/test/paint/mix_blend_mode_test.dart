import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/paint/page_renderer.dart';

/// `mix-blend-mode`（CSS Compositing §5）：背景色与页面背景按指定模式混合。
const _w = 120;
const _h = 120;

Future<ByteData> _render(Map<String, String> overrides) async {
  final style = ComputedStyle(<String, String>{
    'font-size': '16px',
    'line-height': '1',
    'font-family': 'Ahem',
    'margin': '0',
    'width': '80px',
    'height': '80px',
    'background-color': '#ff0000',
    ...overrides,
  });
  final block = PageBlock.styled(
    layout: TextLayoutEngine.layout(text: '', style: style, maxWidth: 80),
    style: style,
    containingWidth: 80,
  );
  final page = Paginator(pageHeight: _h.toDouble())
      .measureChapter(blocks: [block])
      .pages
      .first;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  // 页面背景用中灰：混合结果才能与「纯红覆盖」区分开。
  PagePainter(background: const Color(0xFF808080)).paint(
    canvas,
    page,
    pageSize: Size(_w.toDouble(), _h.toDouble()),
  );
  final image = await recorder.endRecording().toImage(_w, _h);
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  image.dispose();
  return data;
}

int _r(ByteData b, int x, int y) => b.getUint8((y * _w + x) * 4);
int _g(ByteData b, int x, int y) => b.getUint8((y * _w + x) * 4 + 1);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('multiply：红 × 中灰 → 红通道减半（不再是纯红）', () async {
    final normal = await _render(const {});
    final multiply = await _render(const {'mix-blend-mode': 'multiply'});
    expect(_r(normal, 40, 40), greaterThan(240), reason: 'normal 是纯红');
    expect(_r(multiply, 40, 40), lessThan(200), reason: '混合后红通道变暗');
    expect(_g(multiply, 40, 40), lessThan(20), reason: '绿通道仍接近 0');
  });

  test('screen：红 + 中灰 → 红通道饱和', () async {
    final screen = await _render(const {'mix-blend-mode': 'screen'});
    expect(_r(screen, 40, 40), greaterThan(240));
    expect(_g(screen, 40, 40), greaterThan(100), reason: 'screen 抬亮绿通道');
  });
}
