import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/paint/page_renderer.dart';

Future<ByteData> _render({bool justify = false, bool shifted = false}) async {
  final base = ComputedStyle({
    'font-size': '16px',
    'font-family': 'Ahem',
    'line-height': '1.5',
  });
  final author = ComputedStyle(
    {'color': '#fc8c23'},
    parent: base,
    hasExplicitTextColor: true,
  );
  final layout = TextLayoutResult(
    text: '甲乙丙',
    width: 64,
    maxWidth: 100,
    height: 24,
    lines: [
      LineBox(
        start: 0,
        end: 3,
        top: 0,
        height: 24,
        baseline: 16,
        width: 64,
        justifyExtra: justify ? 16 : 0,
      ),
    ],
    runs: [
      StyledRun(
        start: 0,
        end: 1,
        style: author,
        baselineShift: shifted ? 3 : 0,
      ),
    ],
  );
  final block = PageBlock.styled(
    layout: layout,
    style: base,
    containingWidth: 100,
  );
  final page = Paginator(pageHeight: 60)
      .measureChapter(blocks: [block])
      .pages
      .single;
  final recorder = ui.PictureRecorder();
  const PagePainter(textColor: Color(0xff222222))
      .paint(Canvas(recorder), page, pageSize: const Size(100, 60));
  final image = await recorder.endRecording().toImage(100, 60);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!;
}

int _orangePixels(ByteData bytes) {
  var count = 0;
  for (var i = 0; i < bytes.lengthInBytes; i += 4) {
    if (bytes.getUint8(i) > 220 &&
        bytes.getUint8(i + 1) > 90 &&
        bytes.getUint8(i + 1) < 180 &&
        bytes.getUint8(i + 2) < 90) {
      count++;
    }
  }
  return count;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('普通行保留作者行内高亮色', () async {
    expect(_orangePixels(await _render()), greaterThan(0));
  });
  test('两端对齐行与普通行同样保留作者行内高亮色', () async {
    expect(_orangePixels(await _render(justify: true)), greaterThan(0));
  });
  test('行内基线偏移不应让主题色覆盖作者高亮色', () async {
    expect(_orangePixels(await _render(shifted: true)), greaterThan(0));
  });
}
