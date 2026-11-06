import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/text_layout.dart';

const _text = 'The quick brown fox jumps over the lazy dog. 中文混排测试，用于验证断行。';

ComputedStyle _style({double fontSize = 16, String? textTransform}) =>
    ComputedStyle(<String, String>{
      'font-size': '${fontSize}px',
      'line-height': '1.5',
      'font-family': 'Ahem',
      'text-transform': ?textTransform,
    });

TextPainter _referencePainter(
  String text,
  double maxWidth, {
  double fontSize = 16,
}) {
  final style = _style(fontSize: fontSize);
  return TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontSize: style.fontSize,
        height: style.lineHeightFactor,
        leadingDistribution: TextLeadingDistribution.even,
        fontFamily: style.fontFamily,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: maxWidth);
}

void main() {
  test('3 个宽度下 LineBox 数与 computeLineMetrics 一致', () {
    for (final width in <double>[120, 220, 420]) {
      final layout = TextLayoutEngine.layout(
        text: _text,
        style: _style(),
        maxWidth: width,
      );
      final reference = _referencePainter(_text, width);
      expect(
        layout.lineCount,
        reference.computeLineMetrics().length,
        reason: 'width=$width',
      );
      expect(layout.lines, isNotEmpty);
      expect(layout.width, greaterThan(0));
      expect(layout.height, greaterThan(0));
    }
  });

  test('行框 top/height/baseline 自洽', () {
    final layout = TextLayoutEngine.layout(
      text: _text,
      style: _style(),
      maxWidth: 220,
    );
    var expectedTop = 0.0;
    for (final line in layout.lines) {
      expect(line.top, closeTo(expectedTop, 0.001));
      expect(line.height, closeTo(24, 0.001));
      expect(line.baseline, greaterThanOrEqualTo(line.top));
      expect(line.baseline, lessThanOrEqualTo(line.bottom));
      expect(line.width, greaterThan(0));
      expectedTop += line.height;
    }
    expect(layout.height, closeTo(expectedTop, 0.001));
    expect(layout.height, closeTo(layout.lines.length * 24, 0.001));
  });

  test('窄宽度行数不少于宽宽度', () {
    final narrow = TextLayoutEngine.layout(
      text: _text,
      style: _style(),
      maxWidth: 120,
    );
    final wide = TextLayoutEngine.layout(
      text: _text,
      style: _style(),
      maxWidth: 420,
    );
    expect(narrow.lineCount, greaterThanOrEqualTo(wide.lineCount));
  });

  test('空文本产生 0 行', () {
    final layout = TextLayoutEngine.layout(
      text: '',
      style: _style(),
      maxWidth: 200,
    );
    expect(layout.lineCount, 0);
    expect(layout.height, 0);
  });

  test('字号与行高被消费', () {
    // ASCII 文本：Ahem 全覆盖，不触发 CJK 回退链换字体（度量稳定）。
    final text = 'First line\nSecond line';
    final style16 = _style(fontSize: 16);
    final style20 = _style(fontSize: 20);
    final layout16 = TextLayoutEngine.layout(
      text: text,
      style: style16,
      maxWidth: 400,
    );
    final layout20 = TextLayoutEngine.layout(
      text: text,
      style: style20,
      maxWidth: 400,
    );
    expect(layout16.lineCount, 2);
    expect(layout20.lineCount, 2);
    expect(layout16.lines.first.height, closeTo(24, 0.001));
    expect(layout20.lines.first.height, closeTo(30, 0.001));
  });

  test('无限宽时单行', () {
    final layout = TextLayoutEngine.layout(
      text: 'short',
      style: _style(),
      maxWidth: double.infinity,
    );
    expect(layout.lineCount, 1);
  });

  test('批量宽度与逐段无界排版一致', () {
    final style = _style();
    final texts = <String>['中', '文', 'hello', 'world', '，', '。', 'A1'];
    final measured = TextLayoutEngine.measureTextWidths(
      texts: texts,
      style: style,
    );

    for (final text in texts) {
      final expected = TextLayoutEngine.layout(
        text: text,
        style: style,
        maxWidth: double.infinity,
      ).width;
      expect(measured[text], closeTo(expected, 0.01), reason: text);
    }
  });

  test('批量宽度应用文字变换和缩放', () {
    final style = _style(textTransform: 'uppercase');
    const textScaleFactor = 1.25;
    final texts = <String>['reader', 'Table 2', '中文'];
    final measured = TextLayoutEngine.measureTextWidths(
      texts: texts,
      style: style,
      textScaleFactor: textScaleFactor,
    );

    for (final text in texts) {
      final expected = TextLayoutEngine.layout(
        text: text,
        style: style,
        maxWidth: double.infinity,
        textScaleFactor: textScaleFactor,
      ).width;
      expect(measured[text], closeTo(expected, 0.01), reason: text);
    }
  });

  test('批量宽度去重并忽略空文本，保留硬换行', () {
    final measured = TextLayoutEngine.measureTextWidths(
      texts: const <String>['same', '', 'same', 'first\nsecond'],
      style: _style(),
    );

    expect(measured.keys, unorderedEquals(<String>['same', 'first\nsecond']));
    expect(measured['same'], greaterThan(0));
    final multiline = TextLayoutEngine.layout(
      text: 'first\nsecond',
      style: _style(),
      maxWidth: double.infinity,
    );
    expect(measured['first\nsecond'], closeTo(multiline.width, 0.01));
  });
}
