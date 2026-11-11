import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_core/paint/paragraph_cache.dart';

Future<Uint8List> _pixels(void Function(Canvas) paint) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(const Color(0xffffffff), BlendMode.src);
  paint(canvas);
  final picture = recorder.endRecording();
  final image = await picture.toImage(160, 120);
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!.buffer.asUint8List();
}

PageContent _page(ComputedStyle style, InlineBoxVerticalAlign align) =>
    Paginator(pageHeight: 120)
        .measureChapter(
          blocks: [
            PageBlock(
              layout: TextLayoutEngine.layout(
                text: 'ab',
                style: style,
                maxWidth: 160,
                inlineBoxes: [
                  InlineBoxSpec(
                    offset: 0,
                    width: 40,
                    height: 60,
                    contentBaseline: 50,
                    verticalAlign: align,
                  ),
                ],
              ),
              style: style,
            ),
          ],
        )
        .pages
        .single;

Future<void> _expectPixels(
  PageContent page,
  TextPainter reference,
  Offset offset,
) async {
  final expected = await _pixels((canvas) => reference.paint(canvas, offset));
  final cache = ParagraphCache();
  addTearDown(cache.dispose);
  for (final paragraphCache in [null, cache, cache]) {
    final actual = await _pixels(
      (canvas) =>
          PagePainter(paragraphCache: paragraphCache)
              .paint(canvas, page, pageSize: const Size(160, 120)),
    );
    expect(actual, orderedEquals(expected));
  }
  expect(cache.hits, greaterThan(0));
}

void _expectSelection(PageContent page, TextPainter reference, Offset offset) {
  final expected = reference
      .getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 2))
      .single
      .toRect()
      .shift(offset);
  final box = TextHitTester.lineBoxes(page).single;
  final actual = TextHitTester.selectionRects(
    box,
    0,
    2,
  ).single.shift(box.rect.topLeft);
  expect(actual.left, closeTo(expected.left, .01));
  expect(actual.right, closeTo(expected.right, .01));
  expect(actual.top, closeTo(expected.top, .01));
  expect(actual.bottom, closeTo(expected.bottom, .01));
  final caret = TextHitTester.caretOffset(box, const TextPosition(offset: 0));
  expect(caret.dx, closeTo(offset.dx, .01));
  expect(caret.dy, closeTo(offset.dy, .01));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final align in [
    InlineBoxVerticalAlign.baseline,
    InlineBoxVerticalAlign.middle,
  ]) {
    test('$align 行内盒撑高纯文本行后，正文绘制和选区沿用同一基线', () async {
      final style = ComputedStyle({
        'font-family': 'Ahem',
        'font-size': '20px',
        'line-height': '1.2',
      });
      final page = _page(style, align);
      final line = page.slices.single.block.layout.lines.single;
      final reference = TextPainter(
        text: TextSpan(text: 'ab', style: TextLayoutEngine.textStyleFor(style)),
        textDirection: TextDirection.ltr,
      )..layout();
      addTearDown(reference.dispose);
      final offset = Offset(
        40,
        line.baseline - reference.computeLineMetrics().single.baseline,
      );
      await _expectPixels(page, reference, offset);
      _expectSelection(page, reference, offset);
    });
  }
}
