import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';

const _fontFamily = 'S1CJK';
const _fontPath = '../../test_fonts/SourceHanSerifSC-Regular.otf';
const _text = '中文中文中文中文中文中文\nEnglish mixed 中文 text\n第三行中文内容';
const _groups = <(double, double)>[(16, 1.5), (20, 1.2), (28, 2.0)];

Future<void> _loadFont() async {
  final bytes = await File(_fontPath).readAsBytes();
  await (FontLoader(
    _fontFamily,
  )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
}

TextPainter _rawPainter(double fontSize) => TextPainter(
  text: TextSpan(
    text: _text,
    style: TextStyle(fontFamily: _fontFamily, fontSize: fontSize),
  ),
  textDirection: TextDirection.ltr,
)..layout(maxWidth: 400);

TextLayoutResult _layout(
  double fontSize,
  double factor, {
  TextLeadingDistribution distribution = TextLeadingDistribution.even,
}) => TextLayoutEngine.layout(
  text: _text,
  style: ComputedStyle(<String, String>{
    'font-size': '${fontSize}px',
    'line-height': '$factor',
    'font-family': _fontFamily,
  }),
  maxWidth: 400,
  leadingDistribution: distribution,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFont);

  test('三组字号×行高的行高与基线误差 < 0.01px', () {
    var maxHeightError = 0.0;
    var maxBaselineError = 0.0;
    final expectedFirstBaselines = <double>[18.920, 20.650, 40.110];

    for (var g = 0; g < _groups.length; g++) {
      final (fontSize, factor) = _groups[g];
      final expectedHeight = fontSize * factor;
      final raw = _rawPainter(fontSize);
      final rawFirst = raw.computeLineMetrics().first;
      final rawAscent = rawFirst.ascent;
      final rawDescent = rawFirst.descent;

      final layout = _layout(fontSize, factor);
      expect(layout.lineCount, 3);
      var expectedTop = 0.0;
      for (final line in layout.lines) {
        final expectedBaseline =
            expectedTop +
            (expectedHeight - (rawAscent + rawDescent)) / 2 +
            rawAscent;
        maxHeightError = [
          maxHeightError,
          (line.height - expectedHeight).abs(),
        ].reduce((a, b) => a > b ? a : b);
        maxBaselineError = [
          maxBaselineError,
          (line.baseline - expectedBaseline).abs(),
        ].reduce((a, b) => a > b ? a : b);
        expectedTop += expectedHeight;
      }
      expect(
        layout.lines.first.baseline,
        closeTo(expectedFirstBaselines[g], 0.01),
        reason: 'fontSize=$fontSize factor=$factor',
      );
    }

    expect(maxHeightError, lessThan(0.01));
    expect(maxBaselineError, lessThan(0.01));
  });

  test('normal 行高按 Chrome 口径分别取整 ascent 与 descent', () {
    final previous = LineBreaker.preserveFractionalLineHeight;
    LineBreaker.preserveFractionalLineHeight = true;
    addTearDown(() {
      LineBreaker.preserveFractionalLineHeight = previous;
    });

    for (final fontSize in <double>[15, 17]) {
      final metric = _rawPainter(fontSize).computeLineMetrics().first;
      final expected =
          metric.ascent.roundToDouble() + metric.descent.roundToDouble();
      final layout = TextLayoutEngine.layout(
        text: '中文 normal 行高',
        style: ComputedStyle(<String, String>{
          'font-size': '${fontSize}px',
          'font-family': _fontFamily,
        }),
        maxWidth: 400,
      );
      expect(
        layout.lines.first.height,
        closeTo(expected, 0.001),
        reason: 'fontSize=$fontSize',
      );
    }
  });

  test('未使用 even 时基线偏差能被测出', () {
    final even = _layout(28, 2.0);
    final proportional = _layout(
      28,
      2.0,
      distribution: TextLeadingDistribution.proportional,
    );
    final expectedFirstBaseline = 40.110;
    final evenError = (even.lines.first.baseline - expectedFirstBaseline).abs();
    final proportionalError =
        (proportional.lines.first.baseline - expectedFirstBaseline).abs();
    expect(evenError, lessThan(0.01));
    expect(proportionalError, greaterThan(0.5));
  }, skip: '当前 Flutter 引擎版本忽略 TextLeadingDistribution（纯 TextPainter 分别用 '
      'even/proportional 测量得到完全相同的 ascent/baseline），与库代码无关；'
      '引擎恢复该行为后移除 skip。');
}
