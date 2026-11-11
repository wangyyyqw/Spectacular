import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/page_background.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/paint/page_renderer.dart';

const _red = Color(0xFFFF0000);
const _green = Color(0xFF00FF00);
const _blue = Color(0xFF0000FF);
const _yellow = Color(0xFFFFFF00);
const _white = Color(0xFFFFFFFF);
const _spaceX = CssBackgroundRepeat.axes(
  CssBackgroundRepeatMode.space,
  CssBackgroundRepeatMode.noRepeat,
);
const _roundX = CssBackgroundRepeat.axes(
  CssBackgroundRepeatMode.round,
  CssBackgroundRepeatMode.noRepeat,
);

Future<ui.Image> _redImage() {
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    Uint8List.fromList([
      for (var i = 0; i < 4; i++) ...[255, 0, 0, 255],
    ]),
    2,
    2,
    ui.PixelFormat.rgba8888,
    done.complete,
  );
  return done.future;
}

Future<ByteData> _render(
  Size size,
  PageBackground background, {
  ui.Image? image,
}) async {
  final page = PageContent(
    spineIndex: 0,
    pageIndex: 0,
    slices: const [],
    usedHeight: 0,
    pageHeight: size.height,
    topPadding: 0,
    background: background,
  );
  return _renderPage(size, page, image: image);
}

Future<ByteData> _renderPage(
  Size size,
  PageContent page, {
  ui.Image? image,
}) async {
  final recorder = ui.PictureRecorder();
  PagePainter(imageLookup: (_) => image)
      .paint(Canvas(recorder), page, pageSize: size);
  final picture = recorder.endRecording();
  final output = await picture.toImage(size.width.toInt(), size.height.toInt());
  final data = await output.toByteData(format: ui.ImageByteFormat.rawRgba);
  output.dispose();
  picture.dispose();
  return data!;
}

Future<ByteData> _renderBlock(Map<String, String> properties) async {
  const size = Size(200, 120);
  final style = ComputedStyle({
    'font-size': '16px',
    'font-family': 'Ahem',
    'color': 'transparent',
    ...properties,
  });
  final layout = TextLayoutEngine.layout(
    text: '正文',
    style: style,
    maxWidth: size.width,
  );
  final page = Paginator(pageHeight: size.height)
      .measureChapter(
        blocks: [
          PageBlock.styled(
            layout: layout,
            style: style,
            containingWidth: size.width,
          ),
        ],
      )
      .pages
      .single;
  return _renderPage(size, page);
}

Color _pixel(ByteData data, int width, int x, int y) {
  final offset = (y * width + x) * 4;
  return Color.fromARGB(
    data.getUint8(offset + 3),
    data.getUint8(offset),
    data.getUint8(offset + 1),
    data.getUint8(offset + 2),
  );
}

void _nearColor(Color actual, Color expected) {
  expect(actual.r, closeTo(expected.r, 0.04));
  expect(actual.g, closeTo(expected.g, 0.04));
  expect(actual.b, closeTo(expected.b, 0.04));
  expect(actual.a, closeTo(expected.a, 0.01));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ui.Image image;
  setUpAll(() async => image = await _redImage());
  tearDownAll(() => image.dispose());

  test('整页 space 背景首尾有图，中间空隙露出底色', () async {
    final data = await _render(
      const Size(30, 12),
      const PageBackground(
        layers: [
          CssBackgroundLayer(
            image: 'tile',
            repeat: _spaceX,
            size: CssBackgroundSize.explicit(
              width: CssLength(12),
              height: CssLength(6),
            ),
          ),
        ],
      ),
      image: image,
    );
    expect(_pixel(data, 30, 1, 2), _red);
    expect(_pixel(data, 30, 29, 2), _red);
    expect(_pixel(data, 30, 14, 2), _white);
    expect(_pixel(data, 30, 1, 8), _white);
  });

  test('round 图片按新尺寸重新解算另一轴 auto 和底部定位', () async {
    final data = await _render(
      const Size(30, 12),
      const PageBackground(
        layers: [
          CssBackgroundLayer(
            image: 'tile',
            repeat: _roundX,
            size: CssBackgroundSize.explicit(width: CssLength(12)),
            position: CssBackgroundPosition(
              x: CssLength(0),
              y: CssLength(100, isPercent: true),
            ),
          ),
        ],
      ),
      image: image,
    );
    expect(_pixel(data, 30, 2, 0), _white, reason: '三张 10px 瓦片使 auto 高也为 10px');
    expect(_pixel(data, 30, 29, 3), _red);
    expect(_pixel(data, 30, 15, 11), _red);
  });

  test('渐变和图片对双轴 space/round 使用相同的明确瓦片尺寸', () async {
    const repeat = CssBackgroundRepeat.axes(
      CssBackgroundRepeatMode.space,
      CssBackgroundRepeatMode.round,
    );
    const size = CssBackgroundSize.explicit(
      width: CssLength(12),
      height: CssLength(5),
    );
    final raster = await _render(
      const Size(30, 12),
      const PageBackground(
        layers: [CssBackgroundLayer(image: 'tile', repeat: repeat, size: size)],
      ),
      image: image,
    );
    final gradient = await _render(
      const Size(30, 12),
      const PageBackground(
        layers: [
          CssBackgroundLayer(
            gradient: CssLinearGradient(
              stops: [
                CssGradientStop(color: _blue),
                CssGradientStop(color: _blue),
              ],
            ),
            repeat: repeat,
            size: size,
          ),
        ],
      ),
    );
    for (final x in [1, 14, 29]) {
      for (final y in [1, 6, 11]) {
        final gap = x == 14;
        expect(_pixel(raster, 30, x, y), gap ? _white : _red);
        expect(_pixel(gradient, 30, x, y), gap ? _white : _blue);
      }
    }
  });

  test('锥形渐变以页面中心为圆心，从十二点方向顺时针均分颜色', () async {
    final data = await _render(
      const Size(100, 60),
      const PageBackground(
        layers: [
          CssBackgroundLayer(
            gradient: CssConicGradient(
              stops: [
                CssGradientStop(color: _red),
                CssGradientStop(color: _green),
                CssGradientStop(color: _blue),
                CssGradientStop(color: _yellow),
                CssGradientStop(color: _red),
              ],
            ),
          ),
        ],
      ),
    );
    _nearColor(_pixel(data, 100, 50, 1), _red);
    _nearColor(_pixel(data, 100, 98, 30), _green);
    _nearColor(_pixel(data, 100, 50, 58), _blue);
    _nearColor(_pixel(data, 100, 1, 30), _yellow);
  });

  test('锥形渐变遵循多背景首层在上和透明混合，缺图不遮住其他层', () async {
    const translucentBlue = Color(0x800000FF);
    final data = await _render(
      const Size(30, 12),
      const PageBackground(
        layers: [
          CssBackgroundLayer(image: 'missing'),
          CssBackgroundLayer(
            gradient: CssConicGradient(
              stops: [
                CssGradientStop(color: translucentBlue),
                CssGradientStop(color: translucentBlue),
              ],
            ),
          ),
          CssBackgroundLayer(
            gradient: CssConicGradient(
              stops: [
                CssGradientStop(color: _red),
                CssGradientStop(color: _red),
              ],
            ),
          ),
        ],
      ),
    );
    _nearColor(_pixel(data, 30, 20, 8), const Color(0xFF7F0080));
  });

  test('CSS 锥形渐变经文本块测量和分页后遵循圆角裁剪', () async {
    final data = await _renderBlock({
      'height': '60px',
      'background-image': 'conic-gradient(red, red)',
      'border-radius': '20px',
    });
    expect(_pixel(data, 200, 1, 1), _white);
    expect(_pixel(data, 200, 198, 1), _white);
    expect(_pixel(data, 200, 1, 58), _white);
    expect(_pixel(data, 200, 100, 30), _red);
    expect(_pixel(data, 200, 100, 80), _white, reason: '块外不绘制渐变');
  });

  test('CSS 锥形渐变遵循内容区 origin 和 clip，padding 保持透明', () async {
    final data = await _renderBlock({
      'height': '40px',
      'padding': '10px',
      'background-image': 'conic-gradient(blue, blue)',
      'background-origin': 'content-box',
      'background-clip': 'content-box',
    });
    expect(_pixel(data, 200, 100, 5), _white);
    expect(_pixel(data, 200, 5, 20), _white);
    expect(_pixel(data, 200, 195, 20), _white);
    expect(_pixel(data, 200, 100, 20), _blue);
    expect(_pixel(data, 200, 100, 55), _white);
  });
}
