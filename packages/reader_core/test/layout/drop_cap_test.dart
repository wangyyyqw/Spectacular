import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/parser.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/text_layout.dart';

/// P7-28：首字下沉近似——`::first-letter` 伪元素不支持，记诊断并以
/// 「段首大字 run」近似渲染（首行放大、基线对齐、后续行正常）；
/// `initial-letter` 属性解析登记。
void main() {
  test('::first-letter 作者规则不生效并记近似诊断', () {
    final sheet = CssParser.parse(
      'p::first-letter { font-size: 3em; float: left; } p { color: red; }',
    );
    expect(
      sheet.warnings.any((w) => w.startsWith('E_FIRST_LETTER_APPROXIMATED')),
      isTrue,
    );
    expect(sheet.warnings.any((w) => w.contains('p::first-letter')), isTrue);
    expect(sheet.rules, hasLength(2), reason: '规则保留但伪元素选择器不匹配');
  });

  test('initial-letter 解析与继承', () {
    ComputedStyle parse(String value) => ComputedStyle(<String, String>{
      'font-size': '16px',
      'initial-letter': value,
    });
    expect(parse('normal').initialLetterLines, isNull);
    expect(parse('3').initialLetterLines, 3.0);
    expect(parse('2 3').initialLetterLines, 2.0, reason: '第二值忽略');
    final parent = parse('2');
    final child = ComputedStyle(
      const <String, String>{'color': 'red'},
      parent: parent,
      explicitProperties: const <String>{'color'},
    );
    expect(child.initialLetterLines, 2.0, reason: '可继承');
  });

  test('段首大字 run：首行放大且基线对齐、后续行正常（近似渲染核心）', () {
    final style = ComputedStyle(const <String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'Ahem',
    });
    final big = ComputedStyle(<String, String>{
      'font-size': '32px',
      'line-height': '1.5',
      'font-family': 'Ahem',
    });
    final layout = TextLayoutEngine.layout(
      text: '下沉段首字后接正文内容继续排',
      style: style,
      maxWidth: 160,
      runs: <StyledRun>[
        StyledRun(start: 0, end: 1, style: big),
      ],
    );
    expect(layout.lineCount, greaterThanOrEqualTo(2));
    // 首行由 32px 字主导：行高 = 48（32 × 1.5）。
    expect(layout.lines.first.height, closeTo(48, 0.5));
    // 后续行回归 24。
    expect(layout.lines[1].height, closeTo(24, 0.5));
    // 基线对齐：首行基线随大字下移（基线 = top + ascent）。
    expect(layout.lines.first.baseline, greaterThan(layout.lines.first.top + 24));
  });

  test('纯字母段首不误触发近似（无大字 run 时行高正常）', () {
    final style = ComputedStyle(const <String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'Ahem',
      'initial-letter': '3',
    });
    // 属性登记不代表自动放大：无匹配 run 时布局与现状一致
    // （放大由样式引擎按段首 run 驱动，随作者样式接线启用）。
    final layout = TextLayoutEngine.layout(
      text: 'abc def ghi',
      style: style,
      maxWidth: 160,
    );
    expect(layout.lines.first.height, closeTo(24, 0.5));
  });
}
