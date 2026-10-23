import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';

ComputedStyle _style({double fontSize = 16}) => ComputedStyle(<String, String>{
  'font-size': '${fontSize}px',
  'line-height': '1.5',
  'font-family': 'Ahem',
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final file = File('../../test_fonts/SourceHanSerifSC-Regular.otf');
    if (!file.existsSync()) {
      return;
    }
    final bytes = ByteData.view(file.readAsBytesSync().buffer);
    final loader = FontLoader('P202Kinsoku')
      ..addFont(Future<ByteData>.value(bytes));
    await loader.load();
  });
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
  test('行内图片占位符不拆', () {
    const text = '甲\uFFFC乙丙';
    final layout = TextLayoutEngine.layout(
      text: text,
      style: _style(),
      maxWidth: 48,
    );
    expect(
      layout.lines.map((line) => text.substring(line.start, line.end)).join(),
      text,
    );
    expect(text.substring(0, text.length), contains('\uFFFC'));
  });

  test('禁则：标点不落行首（S4 字体）', () {
    const text = '一二三四五六七八九十，后续内容';
    final style = ComputedStyle(const <String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'P202Kinsoku',
    });
    final layout = TextLayoutEngine.layout(
      text: text,
      style: style,
      maxWidth: 160,
    );
    for (final line in layout.lines) {
      final lineText = text.substring(line.start, line.end);
      expect(lineText.startsWith('，'), isFalse, reason: '标点落行首: $lineText');
      expect(lineText.startsWith('。'), isFalse);
    }
  });

  _p202BoundaryTests();
}

void _p202BoundaryTests() {
  test('首行缩进与尾段重排', () {
    final style = ComputedStyle(const <String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'Ahem',
      'text-indent': '32px',
    });
    final layout = TextLayoutEngine.layout(
      text: 'abcdefghijklmnop',
      style: style,
      maxWidth: 160,
    );
    expect(layout.lines, hasLength(2));
    expect(layout.lines.first.end, 8);
    expect(layout.lines.first.indent, 32);
    expect(layout.lines.first.isLastLine, isFalse);
    expect(layout.lines.last.isLastLine, isTrue);
    expect(
      layout.lines
          .map((line) => layout.text.substring(line.start, line.end))
          .join(),
      'abcdefghijklmnop',
    );
  });

  test('硬换行标记与末行判定', () {
    final layout = TextLayoutEngine.layout(
      text: 'a\nb',
      style: _style(),
      maxWidth: 200,
    );
    expect(layout.lineCount, 2);
    expect(layout.lines[0].isHardBreak, isTrue);
    expect(layout.lines[0].isLastLine, isFalse);
    expect(layout.lines[1].isHardBreak, isFalse);
    expect(layout.lines[1].isLastLine, isTrue);
  });

  test('负 letter-spacing 允许且行宽非负', () {
    final style = ComputedStyle(const <String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'Ahem',
      'letter-spacing': '-4px',
    });
    final layout = TextLayoutEngine.layout(
      text: 'abcdef',
      style: style,
      maxWidth: 200,
    );
    expect(layout.lines, isNotEmpty);
    expect(layout.lines.every((line) => line.width >= 0), isTrue);
    expect(style.letterSpacing, -4);
  });

  test('极大字号不崩溃且按行切分', () {
    final style = ComputedStyle(const <String, String>{
      'font-size': '200px',
      'line-height': '1',
      'font-family': 'Ahem',
    });
    final layout = TextLayoutEngine.layout(
      text: '中文',
      style: style,
      maxWidth: 48,
    );
    expect(layout.lineCount, greaterThanOrEqualTo(1));
    expect(layout.lines.every((line) => line.end - line.start <= 3), isTrue);
  });
}
