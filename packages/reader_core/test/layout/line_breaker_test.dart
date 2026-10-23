import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';

ComputedStyle _style({double fontSize = 16}) => ComputedStyle(<String, String>{
  'font-size': '${fontSize}px',
  'line-height': '1.5',
  'font-family': 'Ahem',
});

void main() {
  test('窄宽钳制到 3em 并只告警一次', () {
    final warnings = <LineBreakWarning>[];
    final breaker = LineBreaker(onWarning: warnings.add);
    final style = _style();
    final first = breaker.layout(
      text: '中文窄宽样本，用于验证三 em 下限。',
      style: style,
      maxWidth: 20,
    );
    expect(first.maxWidth, 48);
    expect(breaker.tooNarrow, isTrue);
    expect(breaker.warningCount, 1);
    expect(warnings, hasLength(1));
    expect(warnings.single.code, 'layout.tooNarrow');
    expect(warnings.single.requestedWidth, 20);
    expect(warnings.single.minimumWidth, 48);
    expect(first.lines, isNotEmpty);
    expect(
      first.lines.every((line) => line.width <= first.maxWidth + 0.001),
      isTrue,
    );

    breaker.layout(text: '再次窄宽', style: style, maxWidth: 10);
    expect(warnings, hasLength(1), reason: '同一断行器只记录一次告警');
    expect(breaker.lastWarning, same(warnings.single));
  });

  test('正常宽度不钳制、不告警', () {
    final warnings = <LineBreakWarning>[];
    final breaker = LineBreaker(onWarning: warnings.add);
    final result = breaker.layout(
      text: '正常宽度文本',
      style: _style(),
      maxWidth: 320,
    );
    expect(result.maxWidth, 320);
    expect(breaker.tooNarrow, isFalse);
    expect(breaker.warningCount, 0);
    expect(warnings, isEmpty);
  });

  test('无限宽不触发下限', () {
    final breaker = LineBreaker();
    final result = breaker.layout(
      text: 'short',
      style: _style(),
      maxWidth: double.infinity,
    );
    expect(result.maxWidth, double.infinity);
    expect(result.lineCount, 1);
    expect(breaker.tooNarrow, isFalse);
  });

  test('字号变化时下限按 3em 折算', () {
    final breaker = LineBreaker();
    final result = breaker.layout(
      text: '字号 20',
      style: _style(fontSize: 20),
      maxWidth: 30,
    );
    expect(result.maxWidth, 60);
    expect(breaker.lastWarning!.minimumWidth, 60);
  });

  test('TextLayoutEngine 可注入断行器观察钳制', () {
    final warnings = <LineBreakWarning>[];
    final breaker = LineBreaker(onWarning: warnings.add);
    final result = TextLayoutEngine.layout(
      text: '引擎断行',
      style: _style(),
      maxWidth: 1,
      lineBreaker: breaker,
    );
    expect(result.maxWidth, 48);
    expect(warnings, hasLength(1));
  });
}
