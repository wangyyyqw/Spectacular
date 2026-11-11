import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/paint/page_renderer.dart';

/// `backdrop-filter`（CSS Filter Effects §5）：元素背后区域按页面背景近似
/// 铺一层再走滤镜。语料里只有半透明装饰框用它（`blur(10px) brightness(90%)`）。
const _w = 160;
const _h = 160;

/// 8×8 黑白棋盘（重复平铺成页面背景）。
Future<ui.Image> _checker() async {
  const size = 8;
  final pixels = Uint8List(size * size * 4);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final i = (y * size + x) * 4;
      final white = (x + y) % 2 == 0;
      final value = white ? 255 : 0;
      pixels[i] = value;
      pixels[i + 1] = value;
      pixels[i + 2] = value;
      pixels[i + 3] = 255;
    }
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
  final descriptor = ui.ImageDescriptor.raw(
    buffer,
    width: size,
    height: size,
    pixelFormat: ui.PixelFormat.rgba8888,
  );
  final codec = await descriptor.instantiateCodec();
  final frame = await codec.getNextFrame();
  return frame.image;
}

Future<ByteData> _render(
  ui.Image checker, {
  required Map<String, String> overrides,
}) async {
  final style = ComputedStyle(<String, String>{
    'font-size': '16px',
    'line-height': '1',
    'font-family': 'Ahem',
    'margin': '20px',
    'width': '80px',
    'height': '80px',
    'background-color': 'transparent',
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
  PagePainter(
    background: const Color(0xFFFFFFFF),
    pageBackgroundImage: checker,
  ).paint(canvas, page, pageSize: Size(_w.toDouble(), _h.toDouble()));
  final image = await recorder.endRecording().toImage(_w, _h);
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  image.dispose();
  return data;
}

/// 块内区域的亮度标准差（模糊后应显著下降）。
double _stdDevInBlock(ByteData b) {
  final values = <double>[];
  for (var y = 30; y < 90; y++) {
    for (var x = 30; x < 90; x++) {
      values.add(b.getUint8((y * _w + x) * 4).toDouble());
    }
  }
  final mean = values.reduce((a, c) => a + c) / values.length;
  final variance =
      values.map((v) => (v - mean) * (v - mean)).reduce((a, c) => a + c) /
      values.length;
  return math.sqrt(variance);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('backdrop-filter: blur 让块内棋盘变平滑', () async {
    final checker = await _checker();
    final plain = await _render(checker, overrides: const {});
    final blurred = await _render(
      checker,
      overrides: const {'backdrop-filter': 'blur(10px)'},
    );
    expect(
      _stdDevInBlock(blurred),
      lessThan(_stdDevInBlock(plain) * 0.6),
      reason: '模糊后的亮度标准差应明显低于未滤波',
    );
    checker.dispose();
  });

  test('未声明 backdrop-filter 时不额外绘制（棋盘保持锐利）', () async {
    final checker = await _checker();
    final plain = await _render(checker, overrides: const {});
    expect(_stdDevInBlock(plain), greaterThan(40));
    checker.dispose();
  });
}
