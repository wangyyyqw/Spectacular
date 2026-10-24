import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/paint/page_renderer.dart';

const _pageSize = Size(200, 120);

ComputedStyle _style(Map<String, String> overrides) =>
    ComputedStyle(<String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'Ahem',
      ...overrides,
    });

Future<ui.Image> _greenImage() async {
  final pixels = Uint8List(4 * 4 * 4);
  for (var i = 0; i < 16; i++) {
    pixels[i * 4] = 0;
    pixels[i * 4 + 1] = 255;
    pixels[i * 4 + 2] = 0;
    pixels[i * 4 + 3] = 255;
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    4,
    4,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

Future<ByteData> _render(ComputedStyle style, {ui.Image? image}) async {
  final layout = TextLayoutEngine.layout(
    text: 'a',
    style: style,
    maxWidth: 160,
  );
  final page = Paginator(pageHeight: 120)
      .measureChapter(
        blocks: [
          PageBlock.styled(layout: layout, style: style, containingWidth: 200),
        ],
      )
      .pages
      .single;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  PagePainter(imageLookup: image == null ? null : (url) => image)
      .paint(canvas, page, pageSize: _pageSize);
  final rendered = await recorder.endRecording().toImage(200, 120);
  final data = await rendered.toByteData(format: ui.ImageByteFormat.rawRgba);
  rendered.dispose();
  return data!;
}

int _pixel(ByteData bytes, int x, int y) => bytes.getUint32((y * 200 + x) * 4);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('background-clip: content-box 只在内容区铺色', () async {
    final style = _style(const {
      'padding': '10px',
      'background-color': '#FF0000',
      'background-clip': 'content-box',
    });
    final bytes = await _render(style);
    expect(_pixel(bytes, 2, 2), 0xFFFFFFFF, reason: 'padding 圈不铺色');
    expect(_pixel(bytes, 100, 20), 0xFF0000FF, reason: '内容区铺红');
  });

  test('默认 border-box 铺满块盒子', () async {
    final style = _style(const {
      'padding': '10px',
      'background-color': '#FF0000',
    });
    final bytes = await _render(style);
    expect(_pixel(bytes, 2, 2), 0xFF0000FF);
  });

  test('background-origin: content-box 以内容区为定位基准', () async {
    final image = await _greenImage();
    final style = _style(const {
      'padding': '10px',
      'background-image': 'url(bg://green)',
      'background-size': '4px',
      'background-repeat': 'no-repeat',
      'background-origin': 'content-box',
      'background-clip': 'content-box',
      'background-position': 'right top',
    });
    final bytes = await _render(style, image: image);
    // 定位区域 = 内容区，右上角 (186,10)（文字在左侧，不遮挡）。
    expect(_pixel(bytes, 186, 10), 0x00FF00FF, reason: '内容区右上角有图');
    expect(_pixel(bytes, 2, 2), 0xFFFFFFFF, reason: 'padding 圈无图');
  });

  test('background-origin: padding-box 以 padding 区为定位基准', () async {
    final image = await _greenImage();
    final style = _style(const {
      'padding': '10px',
      'background-image': 'url(bg://green)',
      'background-size': '4px',
      'background-repeat': 'no-repeat',
      'background-origin': 'padding-box',
      'background-clip': 'content-box',
      'background-position': 'right top',
    });
    final bytes = await _render(style, image: image);
    // 定位区域 = padding 区，右上角 (196,0) 落在内容区之外被裁掉。
    expect(_pixel(bytes, 186, 10), 0xFFFFFFFF, reason: '定位区域不同 → 图不可见');
    expect(_pixel(bytes, 2, 2), 0xFFFFFFFF, reason: '裁剪仍在内容区');
  });
}
