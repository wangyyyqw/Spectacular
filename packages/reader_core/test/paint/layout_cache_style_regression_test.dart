import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout_cache.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_core/paint/paragraph_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final reversed in [false, true]) {
    test('同文缓存${reversed ? '反向' : '正向'}访问及换主题实际绘制当前行内颜色', () async {
      final geometry = TextLayoutCache();
      final paragraphs = ParagraphCache();
      addTearDown(paragraphs.dispose);
      final base = ComputedStyle(const {
        'font-family': 'Ahem',
        'font-size': '20px',
        'line-height': '1.5',
      });
      final colors = reversed
          ? ['blue', 'red', 'blue']
          : ['red', 'blue', 'red'];
      TextLayoutResult? previous;
      for (final color in colors) {
        final runStyle = ComputedStyle({'color': color}, parent: base);
        final layout = geometry.layout(
          text: 'AAAA',
          style: base,
          maxWidth: 180,
          runs: [StyledRun(start: 0, end: 4, style: runStyle)],
        );
          if (previous != null) {
          expect(identical(layout.lines, previous.lines), isTrue);
          }
        previous = layout;
        final page = Paginator(pageHeight: 100)
            .measureChapter(
              blocks: [
                PageBlock.styled(
                  layout: layout,
                  style: base,
                  containingWidth: 180,
                ),
              ],
            )
            .pages
            .single;
        final recorder = ui.PictureRecorder();
        PagePainter(paragraphCache: paragraphs)
            .paint(Canvas(recorder), page, pageSize: const Size(200, 100));
        final picture = recorder.endRecording();
        final image = await picture.toImage(200, 100);
        final data = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        var red = 0;
        var blue = 0;
        for (var i = 0; i < data.lengthInBytes; i += 4) {
          if (data.getUint8(i) > 200 && data.getUint8(i + 2) < 50) red++;
          if (data.getUint8(i + 2) > 200 && data.getUint8(i) < 50) blue++;
        }
        expect(color == 'red' ? red : blue, greaterThan(0));
        expect(color == 'red' ? blue : red, 0);
        image.dispose();
        picture.dispose();
      }
      expect(geometry.hits, 2, reason: '颜色变化复用文本几何');
    });
  }

  test('clip/ellipsis 正反访问次序均与独立布局一致', () {
    for (final order in [
      ['clip', 'ellipsis'],
      ['ellipsis', 'clip'],
    ]) {
      final cache = TextLayoutCache();
      for (final overflow in order) {
        final style = ComputedStyle({
          'font-size': '20px',
          'font-family': 'Ahem',
          'white-space': 'nowrap',
          'overflow': 'hidden',
          'text-overflow': overflow,
        });
        final actual = cache.layout(
          text: 'A' * 20,
          style: style,
          maxWidth: 100,
        );
        final expected = TextLayoutEngine.layout(
          text: 'A' * 20,
          style: style,
          maxWidth: 100,
        );
        expect(actual.ellipsized, expected.ellipsized);
        expect(actual.lines.first.end, expected.lines.first.end);
      }
    }
  });
}
