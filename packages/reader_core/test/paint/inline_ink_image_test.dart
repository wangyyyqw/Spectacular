import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/paint/page_renderer.dart';

const _orange = Color(0xFFFC8C23);
const _white = Color(0xFFFFFFFF);

/// 24×24 标记图：左半橙色圆底（模拟注号）、右半白色。
Future<ui.Image> _markerImage() {
  const width = 24;
  const height = 24;
  final pixels = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final color = x < width ~/ 2 ? _orange : _white;
      final offset = (y * width + x) * 4;
      pixels[offset] = (color.r * 255).round();
      pixels[offset + 1] = (color.g * 255).round();
      pixels[offset + 2] = (color.b * 255).round();
      pixels[offset + 3] = 255;
    }
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

Future<ByteData> _render({
  required ui.Image image,
  required bool inkMode,
  Color pageBackground = _white,
}) async {
  final base = ComputedStyle({
    'font-size': '16px',
    'font-family': 'Ahem',
    'line-height': '2',
  });
  final marker = ComputedStyle({
    'background-image': 'url(note.png)',
  }, parent: base);
  final placement = InlineBoxPlacement(
    offset: 0,
    left: 30,
    width: 24,
    height: 24,
    ascent: 20,
    descent: 4,
    spec: InlineBoxSpec(offset: 0, width: 24, height: 24, payload: marker),
  );
  final layout = TextLayoutResult(
    text: 'A',
    width: 80,
    maxWidth: 100,
    height: 40,
    lines: [
      LineBox(
        start: 0,
        end: 1,
        top: 0,
        height: 40,
        baseline: 24,
        width: 80,
        inlineBoxes: [placement],
      ),
    ],
  );
  final page = Paginator(pageHeight: 60)
      .measureChapter(
        blocks: [
          PageBlock.styled(layout: layout, style: base, containingWidth: 100),
        ],
      )
      .pages
      .single;
  final recorder = ui.PictureRecorder();
  PagePainter(
    background: pageBackground,
    inkMode: inkMode,
    imageLookup: (url) => url == 'note.png' ? image : null,
  ).paint(Canvas(recorder), page, pageSize: const Size(100, 60));
  final rendered = await recorder.endRecording().toImage(100, 60);
  final data = await rendered.toByteData(format: ui.ImageByteFormat.rawRgba);
  rendered.dispose();
  return data!;
}

int _count(ByteData bytes, bool Function(int r, int g, int b) matches) {
  var count = 0;
  for (var offset = 0; offset < bytes.lengthInBytes; offset += 4) {
    final r = bytes.getUint8(offset);
    final g = bytes.getUint8(offset + 1);
    final b = bytes.getUint8(offset + 2);
    if (matches(r, g, b)) {
      count += 1;
    }
  }
  return count;
}

/// 统计标记盒内部（30..54 × 4..28）的像素，排除正文文字干扰。
int _countInMarker(ByteData bytes, bool Function(int r, int g, int b) matches) {
  var count = 0;
  for (var y = 6; y < 26; y++) {
    for (var x = 32; x < 52; x++) {
      final offset = (y * 100 + x) * 4;
      if (matches(
        bytes.getUint8(offset),
        bytes.getUint8(offset + 1),
        bytes.getUint8(offset + 2),
      )) {
        count++;
      }
    }
  }
  return count;
}

int _orangePixels(ByteData bytes) =>
    _count(bytes, (r, g, b) => r > 200 && g > 80 && g < 200 && b < 100);

int _markerOrangePixels(ByteData bytes) =>
    _countInMarker(bytes, (r, g, b) => r > 200 && g > 80 && g < 200 && b < 100);

int _markerBlackPixels(ByteData bytes) =>
    _countInMarker(bytes, (r, g, b) => r < 30 && g < 30 && b < 30);

int _markerWhitePixels(ByteData bytes) =>
    _countInMarker(bytes, (r, g, b) => r > 240 && g > 240 && b > 240);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('普通模式保留行内标记图片的原色', () async {
    final bytes = await _render(image: await _markerImage(), inkMode: false);
    expect(_orangePixels(bytes), greaterThan(100));
  });

  test('墨水屏模式把行内标记图的橙色压成黑色', () async {
    final bytes = await _render(image: await _markerImage(), inkMode: true);
    expect(_markerOrangePixels(bytes), 0);
    expect(_markerBlackPixels(bytes), greaterThan(100));
  });

  test('墨水屏模式保留行内标记图的白色部分', () async {
    final bytes = await _render(
      image: await _markerImage(),
      inkMode: true,
      pageBackground: const Color(0xFF000000),
    );
    expect(_markerOrangePixels(bytes), 0);
    expect(_markerWhitePixels(bytes), greaterThan(100));
  });
}
