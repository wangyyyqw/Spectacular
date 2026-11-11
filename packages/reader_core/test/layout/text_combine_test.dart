import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';

/// 縦中横（CSS Writing Modes §9.1）：竖排下 `text-combine-upright: all` 把
/// 2–4 位连续数字合并成一个正立块，纵向只占 1em。
ComputedStyle _style(Map<String, String> overrides) =>
    ComputedStyle(<String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'Ahem',
      'writing-mode': 'vertical-rl',
      ...overrides,
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('4 位年份合并成一个 1em 块（后面汉字各 1em）', () {
    final metrics = TextLayoutEngine.verticalGlyphMetrics(
      '2024年',
      _style(const {'text-combine-upright': 'all'}),
    );
    expect(metrics, hasLength(2), reason: '2024 合并 + 「年」');
    expect(metrics.first.combine, isTrue);
    expect(metrics.first.advance, 16, reason: '縦中横纵向占 1em');
    expect(metrics.first.upright, isTrue);
    expect(metrics.last.advance, 16);
  });

  test('未声明时不合并（逐位旋转）', () {
    final metrics = TextLayoutEngine.verticalGlyphMetrics('2024', _style(const {}));
    expect(metrics, hasLength(4));
    expect(metrics.every((m) => !m.combine), isTrue);
  });

  test('单个数字不合并；5 位以上只合并前 4 位', () {
    final single = TextLayoutEngine.verticalGlyphMetrics(
      '7月',
      _style(const {'text-combine-upright': 'all'}),
    );
    expect(single.first.combine, isFalse);

    final five = TextLayoutEngine.verticalGlyphMetrics(
      '12345',
      _style(const {'text-combine-upright': 'all'}),
    );
    expect(five.first.combine, isTrue);
    expect(five.first.end - five.first.start, 4);
    expect(five.last.combine, isFalse);
  });
}
