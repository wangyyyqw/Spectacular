import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/paint/page_renderer.dart';

/// `border-image` 九宫格（CSS Backgrounds §6）：真书用
/// `border: 20px solid transparent; border-image: url(frame.png) 50 repeat`
/// 做章首花纹框。
const _w = 200;
const _h = 200;

/// 40×40 四象限图：左上红、右上绿、左下蓝、右下黄（各 20×20 = 50%）。
Future<ui.Image> _quadImage() async {
  const size = 40;
  final pixels = Uint8List(size * size * 4);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final i = (y * size + x) * 4;
      final left = x < size ~/ 2;
      final top = y < size ~/ 2;
      final (r, g, b) = switch ((top, left)) {
        (true, true) => (255, 0, 0),
        (true, false) => (0, 255, 0),
        (false, true) => (0, 0, 255),
        (false, false) => (255, 255, 0),
      };
      pixels[i] = r;
      pixels[i + 1] = g;
      pixels[i + 2] = b;
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

Future<ByteData> _render(ui.Image image, String borderImage) async {
  final style = ComputedStyle(<String, String>{
    'font-size': '16px',
    'line-height': '1',
    'font-family': 'Ahem',
    'margin': '0',
    'width': '160px',
    'height': '160px',
    'border': '20px solid transparent',
    'border-image': borderImage,
  });
  final block = PageBlock.styled(
    layout: TextLayoutEngine.layout(text: '', style: style, maxWidth: 160),
    style: style,
    containingWidth: 160,
  );
  final page = Paginator(pageHeight: 300)
      .measureChapter(blocks: [block])
      .pages
      .first;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  PagePainter(
    background: const Color(0xFFFFFFFF),
    imageLookup: (url) => url == 'frame' ? image : null,
  ).paint(
    canvas,
    page,
    pageSize: Size(_w.toDouble(), _h.toDouble()),
  );
  final result = await recorder.endRecording().toImage(_w, _h);
  final data = (await result.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  result.dispose();
  return data;
}

int _r(ByteData b, int x, int y) => b.getUint8((y * _w + x) * 4);
int _g(ByteData b, int x, int y) => b.getUint8((y * _w + x) * 4 + 1);
int _b(ByteData b, int x, int y) => b.getUint8((y * _w + x) * 4 + 2);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('九宫格四角取图片对应象限', () async {
    final image = await _quadImage();
    final data = await _render(
      image,
      'url(frame) 50% 50% 50% 50% repeat',
    );
    // 盒 160×160、边框 20px；四角采样点取边框区域内侧。
    expect(_r(data, 5, 5), greaterThan(200), reason: '左上角应为红色');
    expect(_g(data, 5, 5), lessThan(80));
    expect(_g(data, 170, 5), greaterThan(200), reason: '右上角应为绿色');
    expect(_b(data, 5, 170), greaterThan(200), reason: '左下角应为蓝色');
    expect(_r(data, 170, 170), greaterThan(200), reason: '右下角应为黄色');
    expect(_g(data, 170, 170), greaterThan(200));
    image.dispose();
  });

  test('fill 关键字补中间区域', () async {
    final image = await _quadImage();
    // 25% 切割：中间源区域还有 20×20，fill 时铺到内容盒。
    final data = await _render(image, 'url(frame) 25% fill repeat');
    // 中心（内容盒）应被源图中心区域填充（不再是纯白背景）。
    final r = _r(data, 100, 100);
    final g = _g(data, 100, 100);
    final b = _b(data, 100, 100);
    expect(r + g + b, lessThan(700), reason: '中间不应是纯白背景');
    image.dispose();
  });

  test('fill 中间区域按源图尺寸重复而不是拉伸', () async {
    final image = await _quadImage();
    final data = await _render(image, 'url(frame) 25% fill repeat');
    // 内容区 160×160，源中心 20×20 按边框缩放成 40×40 后平铺 4×4；
    // 该采样点落在右侧绿色源象限，拉伸时会错误落到左侧红色源象限。
    expect(_r(data, 55, 35), lessThan(80));
    expect(_g(data, 55, 35), greaterThan(120));
    image.dispose();
  });

  test('无 border-image 时边框保持透明（不画图片）', () async {
    final image = await _quadImage();
    final data = await _render(image, 'none');
    expect(_r(data, 5, 5), greaterThan(245));
    image.dispose();
  });
}
