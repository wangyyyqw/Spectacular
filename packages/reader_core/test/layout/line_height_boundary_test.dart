import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';

ComputedStyle _style({
  String? indent,
  double fontSize = 16,
  double lineHeight = 1.5,
}) => ComputedStyle(<String, String>{
  'font-size': '${fontSize}px',
  'line-height': '$lineHeight',
  'font-family': 'Ahem',
  'text-indent': ?indent,
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('空段落产出零行且高度为 0', () {
    final layout = TextLayoutEngine.layout(
      text: '',
      style: _style(),
      maxWidth: 200,
    );
    expect(layout.lineCount, 0);
    expect(layout.height, 0);
  });

  test('段内空行保留一行行高', () {
    final layout = TextLayoutEngine.layout(
      text: 'a\n\nb',
      style: _style(),
      maxWidth: 200,
    );
    expect(layout.lineCount, 3);
    for (final line in layout.lines) {
      expect(line.height, closeTo(24, 0.01));
    }
    expect(layout.lines[1].start, layout.lines[1].end, reason: '中间行为空行');
    expect(layout.height, closeTo(72, 0.01));
  });

  test('br 硬换行行高正常，段尾 br 不产生空行', () {
    final hard = TextLayoutEngine.layout(
      text: 'a\nb',
      style: _style(),
      maxWidth: 200,
    );
    expect(hard.lineCount, 2);
    expect(hard.lines[0].isHardBreak, isTrue);
    expect(hard.lines.every((line) => (line.height - 24).abs() < 0.01), isTrue);

    final trailing = TextLayoutEngine.layout(
      text: 'a\n',
      style: _style(),
      maxWidth: 200,
    );
    expect(trailing.lineCount, 1, reason: '段尾换行被剥离，不产生额外空行');
    expect(trailing.height, closeTo(24, 0.01));
  });

  test('混排字号行高取该行最大值，且不影响其它行', () {
    final layout = TextLayoutEngine.layout(
      text: 'ab\ncd',
      style: _style(),
      maxWidth: 200,
      runs: [StyledRun(start: 3, end: 5, style: _style(fontSize: 24))],
    );
    expect(layout.lineCount, 2);
    expect(layout.lines[0].height, closeTo(24, 0.01));
    expect(layout.lines[1].height, closeTo(36, 0.01), reason: '24px × 1.5');
  });

  test('超出行高的行内元素撑高所在行', () {
    final layout = TextLayoutEngine.layout(
      text: 'abcdefghijklmnop',
      style: _style(),
      maxWidth: 64,
      runs: [StyledRun(start: 4, end: 8, style: _style(lineHeight: 3))],
    );
    expect(layout.lineCount, 4);
    expect(layout.lines[0].height, closeTo(24, 0.01));
    expect(layout.lines[1].height, closeTo(48, 0.01), reason: '16px × 3.0');
    expect(layout.lines[2].height, closeTo(24, 0.01));
    expect(layout.lines[3].height, closeTo(24, 0.01));
  });

  test('首行缩进的尾段仍应用行内样式', () {
    final layout = TextLayoutEngine.layout(
      text: 'abcdefghijklmnop',
      style: _style(indent: '32px'),
      maxWidth: 160,
      runs: [StyledRun(start: 9, end: 12, style: _style(fontSize: 24))],
    );
    expect(layout.lineCount, 2);
    expect(layout.lines[0].height, closeTo(24, 0.01));
    expect(layout.lines[1].height, closeTo(36, 0.01), reason: '尾段重排仍带 run');
    expect(layout.runs, hasLength(1));
  });

  test('行内样式区间越界被裁剪且不影响行高', () {
    final layout = TextLayoutEngine.layout(
      text: 'abc',
      style: _style(),
      maxWidth: 200,
      runs: [StyledRun(start: 2, end: 99, style: _style(fontSize: 24))],
    );
    expect(layout.lines.single.height, closeTo(36, 0.01));
    expect(layout.runs.single.start, 2);
    expect(layout.runs.single.end, 3);
  });
}
