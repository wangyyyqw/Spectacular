import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/text_layout.dart';

const _text = 'The quick brown fox jumps over the lazy dog. 中文混排测试，用于验证断行。';

ComputedStyle _style({double fontSize = 16}) => ComputedStyle(<String, String>{
  'font-size': '${fontSize}px',
  'line-height': '1.5',
  'font-family': 'Ahem',
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
}
