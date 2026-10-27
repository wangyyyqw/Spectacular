import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';

/// `text-indent`（CSS Text 3 §3.1）：首行缩进可以是负值（外凸），
/// 只影响首行、不影响后续行。
ComputedStyle _style(
  Map<String, String> overrides, {
  double containingWidth = 200,
}) => ComputedStyle(
  <String, String>{
    'font-size': '17px',
    'line-height': '1.6',
    'font-family': 'Ahem',
    ...overrides,
  },
  containingWidth: containingWidth,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('正缩进：只有首行右移，行宽减少', () {
    final layout = TextLayoutEngine.layout(
      text: '首行缩进两字然后继续排很长很长的一行文字观察换行',
      style: _style(const {'text-indent': '2em'}),
      maxWidth: 200,
    );
    final first = layout.lines.first;
    expect(first.offsetX, closeTo(34, 0.5));
    expect(layout.lines[1].offsetX, 0);
    expect(first.width, lessThanOrEqualTo(200 - 34 + 0.5));
  });

  test('负缩进：首行外凸到内容盒左侧、行宽变大', () {
    final layout = TextLayoutEngine.layout(
      text: '负缩进首行外凸然后继续排版观察第二行顶格',
      style: _style(const {'text-indent': '-2em'}),
      maxWidth: 200,
    );
    final first = layout.lines.first;
    expect(first.offsetX, closeTo(-34, 0.5));
    expect(first.width, greaterThan(200 - 34));
    expect(layout.lines[1].offsetX, 0);
  });

  test('百分比缩进按内容宽解算', () {
    final layout = TextLayoutEngine.layout(
      text: '百分之十缩进的首行与后续行',
      // 百分比以包含块宽解算（浏览器同口径）。
      style: _style(const {'text-indent': '10%'}, containingWidth: 300),
      maxWidth: 300,
    );
    expect(layout.lines.first.offsetX, closeTo(30, 0.5));
  });
}
