import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/text/font_metrics.dart';

void main() {
  test('从字体 OS/2.sxHeight 读取真实 x-height 比例', () async {
    final bytes = await File('../../test_fonts/SourceHanSerifSC-Regular.otf')
        .readAsBytes();
    final metrics = FontMetrics.parse(bytes);

    expect(metrics, isNotNull);
    expect(metrics!.xHeightRatio, closeTo(0.514, 0.0001));
  });

  test('font-size-adjust 调整字形字号但保持显式行距', () {
    final style = ComputedStyle(const <String, String>{
      'font-family': '"builtin_song"',
      'font-size': '18px',
      'line-height': '1.5',
      'font-size-adjust': '2',
    });
    final textStyle = TextLayoutEngine.textStyleFor(style);

    expect(textStyle.fontSize!, closeTo(18 * 2 / 0.514, 0.01));
    expect(textStyle.fontSize! * textStyle.height!, closeTo(27, 0.01));
  });

  test('font-size-adjust: none 不改变字号和行距', () {
    final style = ComputedStyle(const <String, String>{
      'font-family': '"builtin_song"',
      'font-size': '18px',
      'line-height': '1.5',
      'font-size-adjust': 'none',
    });
    final textStyle = TextLayoutEngine.textStyleFor(style);

    expect(textStyle.fontSize, 18);
    expect(textStyle.height, 1.5);
  });
}
