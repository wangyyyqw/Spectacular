import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/text_layout.dart';

ComputedStyle _style() => ComputedStyle(const <String, String>{
  'font-size': '16px',
  'line-height': '1.5',
  'font-family': 'Ahem',
});

TextPainter _painter(String text, double width) => TextPainter(
  text: TextSpan(
    text: text,
    style: const TextStyle(
      fontSize: 16,
      height: 1.5,
      leadingDistribution: TextLeadingDistribution.even,
      fontFamily: 'Ahem',
    ),
  ),
  textDirection: TextDirection.ltr,
)..layout(maxWidth: width);

TextLayoutResult _layout(String text, double width) =>
    TextLayoutEngine.layout(text: text, style: _style(), maxWidth: width);

void main() {
  test('中英混排行边界', () {
    const text = '中文English混排测试继续';
    final layout = _layout(text, 100);
    expect(
      layout.lines.map((line) => (line.start, line.end)).toList(),
      <(int, int)>[(0, 2), (2, 8), (8, 14), (14, 15)],
    );
    expect(
      layout.lines.map((line) => text.substring(line.start, line.end)).join(),
      text,
    );
  });

  test('换行符与空行边界', () {
    const text = '第一行\n第二行\n\n第四行';
    final layout = _layout(text, 200);
    expect(
      layout.lines.map((line) => (line.start, line.end)).toList(),
      <(int, int)>[(0, 3), (4, 7), (8, 8), (9, 12)],
    );
    expect(layout.lineCount, 4);
    // 可见字符被完整覆盖，换行符不属于任何行。
    final visible = <int>{
      for (var i = 0; i < text.length; i++)
        if (text[i] != '\n') i,
    };
    final covered = <int>{
      for (final line in layout.lines)
        for (var i = line.start; i < line.end; i++) i,
    };
    expect(covered, visible);
  });

  test('长英文单词强制断行', () {
    const text = 'internationalization_verylongword';
    final layout = _layout(text, 120);
    expect(
      layout.lines.map((line) => (line.start, line.end)).toList(),
      <(int, int)>[(0, 7), (7, 14), (14, 21), (21, 28), (28, 33)],
    );
    expect(
      layout.lines.map((line) => text.substring(line.start, line.end)).join(),
      text,
    );
  });

  test('行边界与 getLineBoundary 一致', () {
    const text = '中文English混排测试继续\n长单词internationalization';
    final layout = _layout(text, 100);
    final painter = _painter(text, 100);
    for (final line in layout.lines) {
      final boundary = painter.getLineBoundary(
        TextPosition(offset: line.start),
      );
      expect(boundary.start, line.start);
      expect(boundary.end, line.end);
    }
  });

  test('边界单调、无重叠、不丢字符', () {
    const text = '中文English混排测试继续\ninternationalization\n\n结束';
    final layout = _layout(text, 120);
    var previousEnd = 0;
    for (final line in layout.lines) {
      expect(line.start, greaterThanOrEqualTo(previousEnd));
      expect(line.end, greaterThanOrEqualTo(line.start));
      previousEnd = line.end;
    }
    final visible = <int>{
      for (var i = 0; i < text.length; i++)
        if (text[i] != '\n') i,
    };
    final covered = <int>{
      for (final line in layout.lines)
        for (var i = line.start; i < line.end; i++) i,
    };
    expect(covered, visible);
  });
}
