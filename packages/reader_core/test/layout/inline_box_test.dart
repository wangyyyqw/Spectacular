import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/text_layout.dart';

/// 行级 inline box（`display: inline-block` 的布局侧接口）。
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

  test('行内盒：占请求宽度、后续文字紧随、行高按盒高撑开', () {
    // 文本 "ab" + 盒 120×40 + "cd"；内容宽 400。
    final layout = TextLayoutEngine.layout(
      text: 'abcd',
      style: _style(),
      maxWidth: 400,
      inlineBoxes: const <InlineBoxSpec>[
        InlineBoxSpec(offset: 2, width: 120, height: 40),
      ],
    );
    expect(layout.lineCount, 1);
    final line = layout.lines.single;
    expect(line.inlineBoxes, hasLength(1));
    final box = line.inlineBoxes.single;
    expect(box.offset, 2, reason: '偏移仍是原文坐标');
    expect(box.width, 120);
    expect(box.height, 40);
    expect(box.left, closeTo(32, 0.5), reason: '盒在 "ab" 之后（2 字 × 16）');
    // 后续文字紧随盒右缘：整行宽 = 2 字 + 盒 + 2 字。
    expect(line.width, closeTo(32 + 120 + 32, 1));
    // 行高按盒高撑开（baseline 模式：盒底对齐基线 → 下行延伸 0）。
    expect(line.height, greaterThanOrEqualTo(40 - 0.01));
    expect(line.baseline - line.top, closeTo(40, 0.5));
  });

  test('行内盒放不下时整块换行（不劈开）', () {
    // 内容宽 100：'ab'（32）+ 盒 90 → 放不下，盒整体换到第二行。
    final layout = TextLayoutEngine.layout(
      text: 'ab',
      style: _style(),
      maxWidth: 100,
      inlineBoxes: const <InlineBoxSpec>[
        InlineBoxSpec(offset: 2, width: 90, height: 30),
      ],
    );
    expect(layout.lineCount, 2);
    expect(layout.lines[0].inlineBoxes, isEmpty);
    expect(layout.lines[1].inlineBoxes, hasLength(1));
    expect(layout.lines[1].inlineBoxes.single.left, closeTo(0, 0.5));
    expect(layout.lines[1].inlineBoxes.single.width, 90);
  });

  test('盒宽大于列宽时保持整宽（不压缩、不裁切）', () {
    final layout = TextLayoutEngine.layout(
      text: 'ab',
      style: _style(),
      maxWidth: 60,
      inlineBoxes: const <InlineBoxSpec>[
        InlineBoxSpec(offset: 0, width: 120, height: 30),
      ],
    );
    final box = layout.lines
        .expand((line) => line.inlineBoxes)
        .single;
    expect(box.width, 120);
  });

  test('一个行内盒独占一行时行高 = 盒高，行宽 = 盒宽', () {
    final layout = TextLayoutEngine.layout(
      text: 'X',
      style: _style(),
      maxWidth: 400,
      inlineBoxes: const <InlineBoxSpec>[
        InlineBoxSpec(offset: 0, width: 200, height: 60),
      ],
    );
    final line = layout.lines.single;
    expect(line.height, greaterThanOrEqualTo(60 - 0.01));
    expect(line.width, closeTo(200 + 16, 1), reason: '盒 + 一个字符');
  });

  test('两个行内盒并排：位置按顺序累加', () {
    final layout = TextLayoutEngine.layout(
      text: 'ab',
      style: _style(),
      maxWidth: 400,
      inlineBoxes: const <InlineBoxSpec>[
        InlineBoxSpec(offset: 0, width: 100, height: 20),
        InlineBoxSpec(offset: 1, width: 60, height: 20),
      ],
    );
    final line = layout.lines.single;
    expect(line.inlineBoxes, hasLength(2));
    expect(line.inlineBoxes[0].left, closeTo(0, 0.5));
    expect(line.inlineBoxes[1].left, closeTo(116, 1), reason: '100 盒 + 中间 1 字（16）');
  });

  test('vertical-align: middle 时盒在基线上下均分', () {
    final layout = TextLayoutEngine.layout(
      text: 'ab',
      style: _style(),
      maxWidth: 400,
      inlineBoxes: const <InlineBoxSpec>[
        InlineBoxSpec(
          offset: 1,
          width: 40,
          height: 50,
          verticalAlign: InlineBoxVerticalAlign.middle,
        ),
      ],
    );
    final box = layout.lines.single.inlineBoxes.single;
    expect(box.ascent, closeTo(25, 0.01));
    expect(box.descent, closeTo(25, 0.01));
    expect(layout.lines.single.height, greaterThanOrEqualTo(50 - 0.01));
  });

  test('margin 参与行高：上下各 10 → 行高至少 70', () {
    final layout = TextLayoutEngine.layout(
      text: 'ab',
      style: _style(),
      maxWidth: 400,
      inlineBoxes: const <InlineBoxSpec>[
        InlineBoxSpec(offset: 1, width: 40, height: 50, marginTop: 10, marginBottom: 10),
      ],
    );
    final box = layout.lines.single.inlineBoxes.single;
    expect(box.ascent, closeTo(60, 0.01));
    expect(box.descent, closeTo(10, 0.01));
    expect(layout.lines.single.height, greaterThanOrEqualTo(70 - 0.01));
  });

  test('payload 透传给绘制层', () {
    final payload = <String>['inline-block-content'];
    final layout = TextLayoutEngine.layout(
      text: 'ab',
      style: _style(),
      maxWidth: 400,
      inlineBoxes: <InlineBoxSpec>[
        InlineBoxSpec(offset: 1, width: 30, height: 20, payload: payload),
      ],
    );
    expect(layout.lines.single.inlineBoxes.single.spec.payload, same(payload));
  });

  test('纯文本路径零开销：不传行内盒时 inlineBoxes 为空且行高不变', () {
    final plain = TextLayoutEngine.layout(
      text: 'abcd',
      style: _style(),
      maxWidth: 400,
    );
    expect(plain.lines.single.inlineBoxes, isEmpty);
    expect(plain.lines.single.height, closeTo(24, 0.01));
    expect(plain.lines.single.width, closeTo(64, 0.01));
  });

  test('行内盒跨行时行区间仍是原文坐标（CFI 安全）', () {
    final layout = TextLayoutEngine.layout(
      text: 'abcdefghij',
      style: _style(),
      maxWidth: 100,
      inlineBoxes: const <InlineBoxSpec>[
        InlineBoxSpec(offset: 4, width: 40, height: 20),
      ],
    );
    expect(layout.text, 'abcdefghij');
    for (final line in layout.lines) {
      expect(line.start, greaterThanOrEqualTo(0));
      expect(line.end, lessThanOrEqualTo(layout.text.length));
      expect(line.end, greaterThanOrEqualTo(line.start));
    }
    final box = layout.lines.expand((line) => line.inlineBoxes).single;
    expect(box.offset, 4, reason: '盒偏移是原文坐标');
    expect(box.left, closeTo(0, 0.5), reason: '盒在行首（放不下整块换行）');
  });
}
