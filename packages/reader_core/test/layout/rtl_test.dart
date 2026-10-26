import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/text_layout.dart';

/// RTL（`direction: rtl`）：baseDirection 与 `start`/`end` 对齐折算。
///
/// Ahem 每字 1em：16px 字号下每字 16 宽、行高 24。
ComputedStyle _style([Map<String, String> overrides = const {}]) =>
    ComputedStyle(<String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'Ahem',
      ...overrides,
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('direction: rtl → baseDirection 为 rtl；LTR 保持', () {
    final rtl = TextLayoutEngine.layout(
      text: 'abcdef',
      style: _style(const {'direction': 'rtl'}),
      maxWidth: 400,
    );
    expect(rtl.isRtl, isTrue);
    final ltr = TextLayoutEngine.layout(
      text: 'abcdef',
      style: _style(),
      maxWidth: 400,
    );
    expect(ltr.isRtl, isFalse);
    // 方向不影响测量的行宽（同样 6 字 × 16）。
    expect(rtl.lines.single.width, closeTo(ltr.lines.single.width, 0.01));
  });

  test('rtl + text-align: start → 行右对齐（x = 内容宽 − 行宽）', () {
    final layout = TextLayoutEngine.layout(
      text: 'abcdef',
      style: _style(const {'direction': 'rtl', 'text-align': 'start'}),
      maxWidth: 200,
    );
    final line = layout.lines.single;
    expect(line.offsetX, closeTo(200 - line.width, 0.01));
    expect(line.offsetX, closeTo(200 - 96, 0.01));
  });

  test('rtl + text-align: end → 行左对齐', () {
    final layout = TextLayoutEngine.layout(
      text: 'abcdef',
      style: _style(const {'direction': 'rtl', 'text-align': 'end'}),
      maxWidth: 200,
    );
    expect(layout.lines.single.offsetX, closeTo(0, 0.01));
  });

  test('rtl + text-align: right 与 start 同侧；left 与 end 同侧', () {
    final right = TextLayoutEngine.layout(
      text: 'abcdef',
      style: _style(const {'direction': 'rtl', 'text-align': 'right'}),
      maxWidth: 200,
    );
    final start = TextLayoutEngine.layout(
      text: 'abcdef',
      style: _style(const {'direction': 'rtl', 'text-align': 'start'}),
      maxWidth: 200,
    );
    expect(right.lines.single.offsetX, closeTo(start.lines.single.offsetX, 0.01));
    final left = TextLayoutEngine.layout(
      text: 'abcdef',
      style: _style(const {'direction': 'rtl', 'text-align': 'left'}),
      maxWidth: 200,
    );
    expect(left.lines.single.offsetX, closeTo(0, 0.01));
  });

  test('ltr + text-align: start 行为不变（行左对齐）', () {
    final layout = TextLayoutEngine.layout(
      text: 'abcdef',
      style: _style(const {'text-align': 'start'}),
      maxWidth: 200,
    );
    expect(layout.lines.single.offsetX, closeTo(0, 0.01));
  });

  test('rtl + center 与 ltr 相同（居中不随方向翻转）', () {
    final rtl = TextLayoutEngine.layout(
      text: 'abcdef',
      style: _style(const {'direction': 'rtl', 'text-align': 'center'}),
      maxWidth: 200,
    );
    final ltr = TextLayoutEngine.layout(
      text: 'abcdef',
      style: _style(const {'text-align': 'center'}),
      maxWidth: 200,
    );
    expect(rtl.lines.single.offsetX, closeTo(ltr.lines.single.offsetX, 0.01));
  });

  test('rtl + text-align-last: end → 末行按物理左对齐', () {
    // 两行内容：末行按 text-align-last 折算（rtl 下 end = 左）。
    final layout = TextLayoutEngine.layout(
      text: 'abcdefghijklmn',
      style: _style(const {
        'direction': 'rtl',
        'text-align': 'justify',
        'text-align-last': 'end',
      }),
      maxWidth: 100,
    );
    expect(layout.lineCount, greaterThan(1));
    expect(layout.lines.last.offsetX, closeTo(0, 0.01));
  });
}
