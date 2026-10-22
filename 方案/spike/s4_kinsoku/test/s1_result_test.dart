// S1：TextPainter 行高/基线是否复现 CSS 行高模型
//
// 运行：flutter test test/s1_result_test.dart
// 输出：s1-result.json
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const String kFontPath =
    '../../../test_fonts/SourceHanSerifSC-Regular.otf';
const String kFontFamily = 'S1CJK';
const String kText = '中文中文中文中文中文中文\nEnglish mixed 中文 text\n第三行中文内容';
const List<(double, double)> kGroups = [(16, 1.5), (20, 1.2), (28, 2.0)];

Future<void> _loadFont() async {
  final bytes = await File(kFontPath).readAsBytes();
  await (FontLoader(kFontFamily)
        ..addFont(Future.value(ByteData.sublistView(bytes))))
      .load();
}

TextPainter _layout(
  String text, {
  required double fontSize,
  double? height,
  TextLeadingDistribution distribution = TextLeadingDistribution.even,
  double maxWidth = 400,
}) {
  return TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: kFontFamily,
        fontSize: fontSize,
        height: height,
        leadingDistribution: distribution,
      ),
    ),
    textDirection: TextDirection.ltr,
    locale: const Locale('zh', 'CN'),
  )..layout(maxWidth: maxWidth);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_loadFont);

  test('S1 行高与基线', () {
    final groups = <Map<String, Object?>>[];
    var maxHeightError = 0.0;
    var maxEvenBaselineError = 0.0;
    var maxProportionalBaselineError = 0.0;

    for (final g in kGroups) {
      final fontSize = g.$1;
      final factor = g.$2;
      final expectedHeight = fontSize * factor;

      // 原始字体行度量：height:null，接近 font ascent/descent
      final raw = _layout(kText, fontSize: fontSize, height: null);
      final rawFirst = raw.computeLineMetrics().first;
      final rawAscent = rawFirst.ascent;
      final rawDescent = rawFirst.descent;

      final even = _layout(kText, fontSize: fontSize, height: factor);
      final evenMetrics = even.computeLineMetrics();

      final proportional = _layout(
        kText,
        fontSize: fontSize,
        height: factor,
        distribution: TextLeadingDistribution.proportional,
      );
      final propMetrics = proportional.computeLineMetrics();

      final lines = <Map<String, Object?>>[];
      var top = 0.0;
      for (var i = 0; i < evenMetrics.length; i++) {
        final m = evenMetrics[i];
        final expectedBaseline =
            top + (expectedHeight - (rawAscent + rawDescent)) / 2 + rawAscent;
        final heightError = (m.height - expectedHeight).abs();
        final baselineError = (m.baseline - expectedBaseline).abs();
        final propBaselineError =
            (propMetrics[i].baseline - expectedBaseline).abs();
        if (heightError > maxHeightError) maxHeightError = heightError;
        if (baselineError > maxEvenBaselineError) {
          maxEvenBaselineError = baselineError;
        }
        if (propBaselineError > maxProportionalBaselineError) {
          maxProportionalBaselineError = propBaselineError;
        }
        lines.add({
          'line': i,
          'top': top,
          'height': m.height,
          'ascent': m.ascent,
          'descent': m.descent,
          'baseline': m.baseline,
          'expectedHeight': expectedHeight,
          'expectedBaseline': expectedBaseline,
          'heightError': heightError,
          'baselineErrorEven': baselineError,
          'baselineErrorProportional': propBaselineError,
          'width': m.width,
        });
        top += m.height;
      }

      groups.add({
        'fontSize': fontSize,
        'lineHeightFactor': factor,
        'rawAscent': rawAscent,
        'rawDescent': rawDescent,
        'lineCount': evenMetrics.length,
        'lines': lines,
      });
    }

    final output = {
      'environment': {
        'flutter': '3.47.5',
        'dart': '3.13.4',
        'platform': Platform.operatingSystem,
        'font': kFontPath,
        'fontSizeGroups': kGroups
            .map((g) => {'fontSize': g.$1, 'lineHeight': g.$2})
            .toList(),
        'measuredAt': DateTime.now().toIso8601String(),
      },
      'groups': groups,
      'summary': {
        'maxHeightError': maxHeightError,
        'maxEvenBaselineError': maxEvenBaselineError,
        'maxProportionalBaselineError': maxProportionalBaselineError,
      },
    };

    File('s1-result.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(output),
    );

    print('maxHeightError=$maxHeightError');
    print('maxEvenBaselineError=$maxEvenBaselineError');
    print('maxProportionalBaselineError=$maxProportionalBaselineError');

    expect(maxHeightError, lessThan(0.5), reason: '行高应等于 fontSize × lineHeight');
    expect(maxEvenBaselineError, lessThan(0.5),
        reason: 'leadingDistribution=even 时基线应匹配 CSS 半行距模型');
  });
}
