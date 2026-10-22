import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/prototype/vertical_demo.dart';

const String _text = '「山中何所有，岭上多白云。」不堪持赠君也';

void main() {
  test('20 字样本按右起列排版，列序与阅读顺序正确', () {
    final layout = VerticalLayout(text: _text, fontSize: 16, pageHeight: 160);
    final glyphs = layout.layout();

    expect(glyphs, hasLength(20));
    expect(layout.rowsPerColumn, 10);
    expect(glyphs.where((glyph) => glyph.column == 0), hasLength(10));
    expect(glyphs.where((glyph) => glyph.column == 1), hasLength(10));

    // 第一列在右侧：第 0 列 x 大于第 1 列 x。
    expect(glyphs.first.dx, greaterThan(glyphs.last.dx));

    // 列内自上而下。
    final firstColumn = glyphs.take(10).toList();
    for (var i = 1; i < firstColumn.length; i++) {
      expect(firstColumn[i].dy, greaterThan(firstColumn[i - 1].dy));
    }

    // 阅读顺序与原文一致。
    expect(layout.readingText(), _text);
  });

  test('竖排标点被标记为旋转，普通汉字不旋转', () {
    final glyphs = VerticalLayout(
      text: _text,
      fontSize: 16,
      pageHeight: 160,
    ).layout();

    final rotated = glyphs.where((glyph) => glyph.rotated).map((g) => g.char);
    expect(rotated, containsAll(<String>['「', '，', '。', '」']));
    expect(rotated, isNot(contains('山')));

    final byChar = <String, VerticalGlyph>{
      for (final glyph in glyphs) glyph.char: glyph,
    };
    expect(byChar['「']!.rotated, isTrue);
    expect(byChar['山']!.rotated, isFalse);
  });

  test('超出容量时抛出明确错误', () {
    expect(
      () => VerticalLayout(
        text: '字' * 200,
        fontSize: 16,
        pageHeight: 160,
      ).layout(),
      throwsStateError,
    );
  });

  testWidgets('竖排原型页面可渲染', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: VerticalDemoPage()));
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.text('竖排原型（P0-19）'), findsOneWidget);
  });
}
