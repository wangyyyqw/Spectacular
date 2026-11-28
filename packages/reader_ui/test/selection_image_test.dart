import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_ui/selection/selection.dart';
import 'package:reader_ui/selection/selection_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('按正式行框裁图，统一输入高度且只保留选中文字墨迹', () async {
    final style = ComputedStyle(const {
      'font-family': 'Ahem',
      'font-size': '20px',
      'line-height': '1.5',
      'color': '#ffffff',
      'background-color': '#800000',
      'text-decoration': 'underline',
    });
    final page = Paginator(pageHeight: 400)
        .measureChapter(
          blocks: [
            PageBlock(
              style: style,
              layout: TextLayoutEngine.layout(
                text: 'ABCDEFGHIJKLMNOPQRST',
                style: style,
                maxWidth: 100,
              ),
            ),
          ],
        )
        .pages
        .single;
    final lines = TextHitTester.lineBoxes(page);
    expect(lines.length, greaterThanOrEqualTo(3));
    TextHit at(PageLineBox line, int offset) => TextHit(
      lineBox: line,
      charOffset: offset,
      textOffset: line.textOffset + offset,
      atLineStart: offset == 0,
      atLineEnd: offset == line.text.length,
    );
    final selection = ReaderSelection.normalized(
      at(lines[0], 2),
      at(lines[2], 3),
    );
    final images = await SelectionImage.captureLines(page, selection).toList();
    expect(images, hasLength(3));
    var darkPixels = 0;
    final widths = <int>[];
    for (final bytes in images) {
      final codec = await ui.instantiateImageCodec(bytes);
      final image = (await codec.getNextFrame()).image;
      expect(image.height, 72);
      widths.add(image.width);
      final pixels = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      for (var i = 0; i < pixels.lengthInBytes; i += 4) {
        final r = pixels.getUint8(i);
        expect(pixels.getUint8(i + 1), r, reason: '不能带入作者彩色背景');
        expect(pixels.getUint8(i + 2), r);
        if (r < 128) darkPixels++;
      }
      expect(pixels.getUint32(0), 0xffffffff, reason: '四周必须保留白色边距');
      image.dispose();
      codec.dispose();
    }
    expect(darkPixels, greaterThan(0));
    expect(widths.first, lessThan(widths[1]), reason: '首尾只裁选中的字符');
    expect(widths.last, lessThan(widths[1]));
    await expectLater(
      SelectionImage.captureLines(
        page,
        ReaderSelection.normalized(at(lines[0], 2), at(lines[0], 2)),
      ).toList(),
      throwsFormatException,
    );
  });
}
