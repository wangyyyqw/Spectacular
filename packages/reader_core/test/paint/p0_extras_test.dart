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

ComputedStyle _style([Map<String, String> overrides = const {}]) =>
    ComputedStyle(<String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'Ahem',
      ...overrides,
    });

Future<ui.Image> _checkerImage() async {
  final pixels = Uint8List(4 * 4 * 4);
  for (var y = 0; y < 4; y++) {
    for (var x = 0; x < 4; x++) {
      final red = ((x ~/ 2) + (y ~/ 2)) % 2 == 0;
      final offset = (y * 4 + x) * 4;
      pixels[offset] = red ? 255 : 0;
      pixels[offset + 1] = red ? 0 : 255;
      pixels[offset + 2] = 0;
      pixels[offset + 3] = 255;
    }
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

Future<ByteData> _render(
  String text,
  ComputedStyle style,
  ui.Image? image,
) async {
  final layout = TextLayoutEngine.layout(
    text: text,
    style: style,
    maxWidth: 200,
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
  const PagePainter(imageLookup: _lookup)
      .paint(canvas, page, pageSize: _pageSize);
  final rendered = await recorder.endRecording().toImage(200, 120);
  final data = await rendered.toByteData(format: ui.ImageByteFormat.rawRgba);
  rendered.dispose();
  return data!;
}

ui.Image? _currentImage;

ui.Image? _lookup(String url) => url == 'bg://checker' ? _currentImage : null;

int _pixel(ByteData bytes, int x, int y) => bytes.getUint32((y * 200 + x) * 4);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    _currentImage = await _checkerImage();
  });

  test('background-repeat: no-repeat 只画一块', () async {
    final style = _style(const {
      'background-image': 'url(bg://checker)',
      'background-repeat': 'no-repeat',
    });
    final bytes = await _render(' ', style, _currentImage);
    expect(_pixel(bytes, 0, 0), isNot(0xFFFFFFFF));
    expect(_pixel(bytes, 8, 0), 0xFFFFFFFF, reason: '第二块不存在');
  });

  test('background-repeat: repeat-x 只铺一行', () async {
    final style = _style(const {
      'background-image': 'url(bg://checker)',
      'background-repeat': 'repeat-x',
    });
    final bytes = await _render(' ', style, _currentImage);
    expect(_pixel(bytes, 6, 0), isNot(0xFFFFFFFF), reason: '同一行第二块');
    expect(_pixel(bytes, 0, 8), 0xFFFFFFFF, reason: '第二行不铺');
  });

  test('background-size: cover 铺满块盒子', () async {
    final style = _style(const {
      'background-image': 'url(bg://checker)',
      'background-size': 'cover',
      'background-repeat': 'no-repeat',
    });
    final bytes = await _render(' ', style, _currentImage);
    // 块高 24，宽 200：cover 后瓦片覆盖整个块盒子。
    expect(_pixel(bytes, 190, 20), isNot(0xFFFFFFFF));
  });

  test('background-position: center 居中', () async {
    final style = _style(const {
      'background-image': 'url(bg://checker)',
      'background-size': '4px 4px',
      'background-repeat': 'no-repeat',
      'background-position': 'center',
    });
    final bytes = await _render(' ', style, _currentImage);
    expect(_pixel(bytes, 0, 0), 0xFFFFFFFF, reason: '左上无图');
    expect(_pixel(bytes, 100, 12), isNot(0xFFFFFFFF), reason: '居中处有图');
  });

  test('text-shadow 在文字右下方投影', () async {
    final plain = await _render(
      'aa',
      _style(const {'font-family': 'Ahem'}),
      null,
    );
    final shadowed = await _render(
      'aa',
      _style(const {'text-shadow': '6px 6px 0 #FF0000', 'font-family': 'Ahem'}),
      null,
    );
    // 阴影应出现在字形右下方 6px 处：找红色像素。
    var redCount = 0;
    for (var y = 0; y < 120; y++) {
      for (var x = 0; x < 200; x++) {
        final value = _pixel(shadowed, x, y);
        if (value == _pixel(plain, x, y)) {
          continue;
        }
        final r = (value >> 24) & 0xFF;
        final g = (value >> 16) & 0xFF;
        final b = (value >> 8) & 0xFF;
        if (r > 200 && g < 60 && b < 60) {
          redCount += 1;
        }
      }
    }
    expect(redCount, greaterThan(0), reason: '阴影产生了红色像素');
  });
}
