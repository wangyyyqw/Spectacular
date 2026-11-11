import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/page_renderer.dart';

const _width = 240;
const _height = 100;

ComputedStyle _style(Map<String, String> properties) =>
    ComputedStyle(<String, String>{
      'font-size': '32px',
      'line-height': '1.5',
      'font-family': 'Ahem',
      'color': '#000000',
      ...properties,
    });

Future<ByteData> _render() async {
  final base = _style(const {});
  final span = _style(const {
    'color': '#00000000',
    'background-color': '#ff0000',
    'margin': '0 0 0 8px',
    'padding': '8px',
  });
  final layout = TextLayoutEngine.layout(
    text: 'ABCD',
    style: base,
    maxWidth: _width.toDouble(),
    runs: [
      for (var offset = 0; offset < 4; offset++)
        StyledRun(start: offset, end: offset + 1, style: span),
    ],
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

bool _isRed(ByteData bytes, int x, int y) {
  final offset = (y * _width + x) * 4;
  return bytes.getUint8(offset) > 240 &&
      bytes.getUint8(offset + 1) < 10 &&
      bytes.getUint8(offset + 2) < 10;
}

int _redRunsAt(ByteData bytes, int y) {
  var runs = 0;
  var inRun = false;
  for (var x = 0; x < _width; x++) {
    final red = _isRed(bytes, x, y);
    if (red && !inRun) {
      runs++;
    }
    inRun = red;
  }
  return runs;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('连续 span 的水平 margin 将文字背景分隔为独立方块', () async {
    final bytes = await _render();
    var maxRuns = 0;
    for (var y = 0; y < _height; y++) {
      maxRuns = math.max(maxRuns, _redRunsAt(bytes, y));
    }
    expect(maxRuns, 4, reason: '四个 span 应各绘制一块背景，margin 区域保持页面底色');
  });
}
