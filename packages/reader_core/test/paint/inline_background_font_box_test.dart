import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/page_renderer.dart';

/// 章号一类的行内 span：字号小于父级，背景色 + 内边距 + 圆角。
/// 继承来的 line-height 只作用于行盒，不能把背景撑到整行高度。
const _width = 240;
const _height = 120;
const _lineHeight = 29.64;

ComputedStyle _style(Map<String, String> properties) =>
    ComputedStyle(<String, String>{
      'font-size': '22.8px',
      'line-height': '${_lineHeight}px',
      'font-family': 'Ahem',
      'color': '#000000',
      ...properties,
    });

Future<ByteData> _render() async {
  final base = _style(const {'text-align': 'center'});
  final span = _style(const {
    'font-size': '11.875px',
    'background-color': '#ff0000',
    'padding': '2px 4px 1px 4px',
    'border-radius': '10px',
  });
  final layout = TextLayoutEngine.layout(
    text: 'AB',
    style: base,
    maxWidth: _width.toDouble(),
    // 行内 span 继承父级计算出的 29.64px 行高。
    runs: [StyledRun(start: 0, end: 2, style: span)],
  );
  final page = Paginator(pageHeight: _height.toDouble())
      .measureChapter(
        blocks: [
          PageBlock.styled(
            layout: layout,
            style: base,
            containingWidth: _width.toDouble(),
          ),
        ],
      )
      .pages
      .single;
  final recorder = ui.PictureRecorder();
  const PagePainter().paint(
    Canvas(recorder),
    page,
    pageSize: Size(_width.toDouble(), _height.toDouble()),
  );
  final image = await recorder.endRecording().toImage(_width, _height);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!;
}

({int top, int bottom}) _bounds(
  ByteData bytes,
  bool Function(int, int) test, {
  int fromY = 0,
  int toY = _height,
}) {
  var top = _height, bottom = -1;
  for (var y = fromY; y < toY; y++) {
    for (var x = 0; x < _width; x++) {
      if (test(x, y)) {
        top = math.min(top, y);
        bottom = math.max(bottom, y);
      }
    }
  }
  return (top: top, bottom: bottom);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('行内背景按字体内容盒加内边距，不被继承行高撑高', () async {
    final bytes = await _render();
    bool red(int x, int y) {
      final offset = (y * _width + x) * 4;
      return bytes.getUint8(offset) > 200 &&
          bytes.getUint8(offset + 1) < 40 &&
          bytes.getUint8(offset + 2) < 40;
    }

    bool ink(int x, int y) {
      final offset = (y * _width + x) * 4;
      return bytes.getUint8(offset) < 40 &&
          bytes.getUint8(offset + 1) < 40 &&
          bytes.getUint8(offset + 2) < 40;
    }

    final box = _bounds(bytes, red);
    // Ahem 字体盒 = 1em，上下 padding 2 + 1：11.875 + 3 ≈ 15。
    // 圆角与抗锯齿会让首末像素略窄，按 2 像素容差比较。
    final boxHeight = box.bottom - box.top + 1;
    expect(
      boxHeight,
      closeTo(11.875 + 3, 2.5),
      reason: '背景高 = 字体内容盒 + padding，而不是行高 $_lineHeight',
    );
    expect(boxHeight, lessThan(_lineHeight - 8), reason: '不能沿用整行高度绘制背景');

    final glyphs = _bounds(bytes, ink, fromY: box.top, toY: box.bottom + 1);
    final boxCenter = (box.top + box.bottom) / 2;
    final inkCenter = (glyphs.top + glyphs.bottom) / 2;
    expect(
      inkCenter,
      closeTo(boxCenter, 2),
      reason: '字形在背景内垂直居中（上下 padding 2/1，允许像素取整）',
    );
  });
}
