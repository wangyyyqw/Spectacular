import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/text_spacing.dart';

const _style = TextStyle(fontFamily: 'Ahem', fontSize: 20, letterSpacing: 1);

double _width(TextSpan span) {
  final painter = TextPainter(text: span, textDirection: TextDirection.ltr)
    ..layout();
  try {
    return painter.width;
  } finally {
    painter.dispose();
  }
}

List<Object?> _geometry(TextSpan span, double width, double scale) {
  final painter = TextPainter(
    text: span,
    textDirection: TextDirection.ltr,
    textScaler: TextScaler.linear(scale),
  )..layout(maxWidth: width);
  try {
    return [
      painter.size,
      for (final metric in painter.computeLineMetrics())
        [
          metric.hardBreak,
          metric.ascent,
          metric.descent,
          metric.unscaledAscent,
          metric.height,
          metric.width,
          metric.left,
          metric.baseline,
          metric.lineNumber,
        ],
      for (var offset = 0; offset < span.toPlainText().length; offset++)
        [
          painter.getLineBoundary(TextPosition(offset: offset)),
          for (final box in painter.getBoxesForSelection(
            TextSelection(baseOffset: offset, extentOffset: offset + 1),
          ))
            [box.left, box.top, box.right, box.bottom, box.direction],
        ],
    ];
  } finally {
    painter.dispose();
  }
}

const _prefix = 'Aa\u0301👨‍👩‍👧‍👦';
const _suffix = 'ffi AV\n';

({TextSpan source, TextSpan legacy}) _spacingTrees(
  TextStyle style,
  TextStyle? childStyle,
) {
  final merged = style.merge(childStyle);
  return (
    source: TextSpan(
      style: style,
      text: '$_prefix，$_suffix',
      children: [TextSpan(text: '小，乙a\u0301', style: childStyle)],
    ),
    // 旧实现对每个未调整片段都显式写入完整的合并样式。
    legacy: TextSpan(
      style: style,
      children: [
        TextSpan(text: _prefix, style: style),
        TextSpan(text: '，', style: style.copyWith(letterSpacing: 3)),
        TextSpan(text: _suffix, style: style),
        TextSpan(
          style: childStyle,
          children: [
            TextSpan(text: '小', style: merged),
            TextSpan(text: '，', style: merged.copyWith(letterSpacing: 3)),
            TextSpan(text: '乙a\u0301', style: merged),
          ],
        ),
      ],
    ),
  );
}

void _expectLegacyGeometry(TextStyle style, TextStyle? childStyle) {
  final trees = _spacingTrees(style, childStyle);
  final second = _prefix.length + 1 + _suffix.length + 1;
  final actual = applyTextSpacing(
    trees.source,
    LineSpacing(
      glyphs: {
        _prefix.length: GlyphSpacing(offset: _prefix.length, letterSpacing: 2),
        second: GlyphSpacing(offset: second, letterSpacing: 2),
      },
    ),
  );
  expect((actual.children!.first as TextSpan).style, isNull);
  final child = actual.children!.last as TextSpan;
  expect((child.children!.first as TextSpan).style, style.merge(childStyle));
  expect(actual.toPlainText(), trees.legacy.toPlainText());
  for (final width in [61.0, 121.5, double.infinity]) {
    for (final scale in [1.0, 1.25]) {
      expect(
        _geometry(actual, width, scale),
        _geometry(trees.legacy, width, scale),
        reason: '$style / $childStyle / $width / $scale',
      );
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('完整样式去重与旧树的行度量和字盒精确一致，部分样式保留合并值', () {
    for (final leading in [null, ...TextLeadingDistribution.values]) {
      for (final height in [null, 1.0, 1.6]) {
        final style = _style.copyWith(
          height: height,
          leadingDistribution: leading,
        );
        for (final childStyle in [
          null,
          const TextStyle(color: Color(0xFFFF0000)),
          for (final childLeading in TextLeadingDistribution.values)
            TextStyle(
              fontSize: 29,
              height: 1.1,
              leadingDistribution: childLeading,
            ),
        ]) {
          _expectLegacyGeometry(style, childStyle);
        }
      }
    }
  });

  test('区间切片保留无文本样式节点，完整区间与原树相同', () {
    const source = TextSpan(
      style: _style,
      children: [
        TextSpan(
          style: TextStyle(color: Color(0xFFFF0000)),
          children: [TextSpan(text: '甲乙')],
        ),
        TextSpan(text: '丙丁'),
      ],
    );
    final actual = sliceTextSpan(source, 0, 4);
    expect(actual, source);
    expect(actual.text, isNull);
    expect((actual.children!.first as TextSpan).text, isNull);
    expect(_width(actual), _width(source));
  });

  test('已调整段落的首行切片与独立首行间距树精确相同', () {
    const source = TextSpan(
      style: _style,
      children: [TextSpan(text: '甲，乙。丙')],
    );
    const first = GlyphSpacing(offset: 1, letterSpacing: 2);
    final paragraph = applyTextSpacing(
      source,
      LineSpacing(
        glyphs: const {1: first, 3: GlyphSpacing(offset: 3, letterSpacing: 3)},
      ),
    );
    final line = applyTextSpacing(
      sliceTextSpan(source, 0, 3),
      LineSpacing(glyphs: const {1: first}),
    );
    final prefix = sliceTextSpan(paragraph, 0, 3);
    expect(prefix, line);
    expect(prefix.toPlainText(), '甲，乙');
    expect(_width(prefix), _width(line));
  });

  test('稀疏间距保持组合字符和 emoji 整体，内部偏移不产生调整', () {
    const text = 'a\u0301👨‍👩‍👧‍👦中';
    final chinese = text.indexOf('中');
    final actual = applyTextSpacing(
      const TextSpan(text: text, style: _style),
      LineSpacing(
        glyphs: {
          1: const GlyphSpacing(offset: 1, letterSpacing: 9),
          3: const GlyphSpacing(offset: 3, letterSpacing: 9),
          chinese: GlyphSpacing(offset: chinese, letterSpacing: 2),
        },
      ),
    );
    final expected = TextSpan(
      style: _style,
      children: [
        TextSpan(text: text.substring(0, chinese)),
        TextSpan(text: '中', style: _style.copyWith(letterSpacing: 3)),
      ],
    );
    expect(actual.toPlainText(), text);
    expect(_width(actual), _width(expected));
  });

  test('跨样式子节点的尾空格只隐藏实际字簇，原文保留', () {
    const source = TextSpan(
      style: _style,
      text: '甲',
      children: [
        TextSpan(
          text: 'a\u0301 \t',
          style: TextStyle(color: Color(0xFFFF0000)),
        ),
      ],
    );
    final actual = applyTextSpacing(source, LineSpacing(trailingSpaceStart: 2));
    expect(actual.toPlainText(), '甲a\u0301 \t');
    expect(
      _width(actual),
      _width(const TextSpan(text: '甲a\u0301', style: _style)),
    );
  });

  test('样式节点切开代理码对时仍按各节点字簇调整，不触发反向越界', () {
    const source = TextSpan(
      style: _style,
      text: '\uD83D',
      children: [TextSpan(text: '\uDC68a\u0301甲')],
    );
    final actual = applyTextSpacing(
      source,
      LineSpacing(glyphs: const {1: GlyphSpacing(offset: 1, letterSpacing: 2)}),
    );
    final expected = TextSpan(
      style: _style,
      children: [
        const TextSpan(text: '\uD83D', style: _style),
        TextSpan(
          children: [
            TextSpan(text: '\uDC68', style: _style.copyWith(letterSpacing: 3)),
            const TextSpan(text: 'a\u0301甲', style: _style),
          ],
        ),
      ],
    );
    expect(actual.toPlainText(), source.toPlainText());
    expect(_width(actual), _width(expected));
  });

  test('稀疏对齐和隐藏标记沿用字簇首偏移与样式继承', () {
    const text = '甲a\u0301乙';
    final source = const TextSpan(
      style: _style,
      children: [
        TextSpan(text: '甲a\u0301'),
        TextSpan(text: '乙', style: TextStyle(fontSize: 30)),
      ],
    );
    final actual = applyTextSpacing(
      source,
      LineSpacing(justifyGaps: const [0, 2]),
      justifyExtra: 8,
      hiddenPlaceholders: const {3},
      replacedPlaceholders: const {3},
    );
    final expected = TextSpan(
      style: _style,
      children: [
        TextSpan(text: '甲', style: _style.copyWith(letterSpacing: 5)),
        const TextSpan(text: 'a\u0301'),
        TextSpan(
          text: '乙',
          style: _style.copyWith(fontSize: 0, letterSpacing: 0, wordSpacing: 0),
        ),
      ],
    );
    expect(actual.toPlainText(), text);
    expect(_width(actual), _width(expected));
  });
}
