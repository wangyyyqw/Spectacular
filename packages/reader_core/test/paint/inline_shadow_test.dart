import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/paint/page_renderer.dart';

Future<ByteData> _render({required bool positioned, bool inset = false}) async {
  final base = ComputedStyle({
    'font-size': '16px',
    'font-family': 'Ahem',
    'line-height': '2',
  });
  final badge = ComputedStyle({
    'box-shadow': inset ? 'inset 0 0 0 4px #ff0000' : '6px 0 0 2px #ff0000',
    if (inset) 'background-color': '#ffffff',
  }, parent: base);
  final placement = InlineBoxPlacement(
    offset: 0,
    left: 30,
    width: 24,
    height: 24,
    ascent: 20,
    descent: 4,
    spec: InlineBoxSpec(offset: 0, width: 24, height: 24, payload: badge),
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
        inlineBoxes: positioned ? [placement] : [],
      ),
    ],
    runs: positioned ? [] : [StyledRun(start: 0, end: 1, style: badge)],
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
  const PagePainter().paint(
    Canvas(recorder),
    page,
    pageSize: const Size(100, 60),
  );
  final image = await recorder.endRecording().toImage(100, 60);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!;
}

int _redPixels(ByteData data) {
  var count = 0;
  for (var offset = 0; offset < data.lengthInBytes; offset += 4) {
    if (data.getUint8(offset) > 200 &&
        data.getUint8(offset + 1) < 60 &&
        data.getUint8(offset + 2) < 60) {
      count++;
    }
  }
  return count;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final positioned in [false, true]) {
    final name = positioned ? '独立行内盒' : '普通行内样式';
    test('$name 无背景边框时仍绘制外阴影', () async {
      expect(
        _redPixels(await _render(positioned: positioned)),
        greaterThan(20),
      );
    });
    test('$name 内阴影绘制在背景之上', () async {
      expect(
        _redPixels(await _render(positioned: positioned, inset: true)),
        greaterThan(20),
      );
    });
  }
}
