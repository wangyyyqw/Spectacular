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

  test('行内盒左右外边距参与换行，但不扩大边框盒', () {
    final layout = TextLayoutEngine.layout(
      text: 'ab',
      style: _style(),
      maxWidth: 100,
      inlineBoxes: const [
        InlineBoxSpec(
          offset: 2,
          width: 60,
          height: 24,
          marginLeft: 5,
          marginRight: 10,
        ),
      ],
    );
    expect(layout.lineCount, 2);
    final line = layout.lines.last;
    expect(line.inlineBoxes.single.width, 60);
    expect(line.inlineBoxes.single.left, closeTo(5, 0.5));
    expect(line.width, closeTo(75, 1));
  });

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
    // 行高按盒高撑开；基线 = 盒内最后一行的基线（CSS 10.8.1，overflow:visible），
    // 所以基线略高于盒底（下沉量 = half-leading + 字体 descent）。
    expect(line.height, greaterThanOrEqualTo(40 - 0.01));
    final box2 = line.inlineBoxes.single;
    expect(box2.ascent + box2.descent, greaterThanOrEqualTo(40 - 0.01));
    expect(line.baseline - line.top, closeTo(box2.ascent, 0.01));
    expect(box2.descent, greaterThan(0), reason: '基线不在盒底（半行距下沉）');
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

  test('vertical-align: middle 时盒中点对齐父基线上方半个 x 高度', () {
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
    expect(box.ascent, closeTo(29, 0.01));
    expect(box.descent, closeTo(21, 0.01));
    expect(layout.lines.single.height, greaterThanOrEqualTo(50 - 0.01));
  });

  test('middle 对齐按父字号缩放，并合并正文 strut 与盒子上下沿', () {
    for (final scale in [1.0, 1.5]) {
      final style = _style({'font-size': '24px', 'line-height': '2'});
      final plain = TextLayoutEngine.layout(
        text: 'ab',
        style: style,
        maxWidth: 400,
        textScaleFactor: scale,
      ).lines.single;
      final line = TextLayoutEngine.layout(
        text: 'ab',
        style: style,
        maxWidth: 400,
        textScaleFactor: scale,
        inlineBoxes: const [
          InlineBoxSpec(
            offset: 1,
            width: 40,
            height: 40,
            marginBottom: 2,
            verticalAlign: InlineBoxVerticalAlign.middle,
          ),
        ],
      ).lines.single;
      final box = line.inlineBoxes.single;
      expect(box.ascent, closeTo(21 + 6 * scale, .01));
      expect(box.descent, closeTo(21 - 6 * scale, .01));
      expect(line.baseline, greaterThanOrEqualTo(plain.baseline));
      expect(line.height - line.baseline, greaterThanOrEqualTo(box.descent));
      expect(
        line.height - line.baseline,
        greaterThanOrEqualTo(plain.height - plain.baseline),
      );
    }
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
    expect(box.ascent + box.descent, closeTo(70, 0.01), reason: '盒高 50 + 上下 margin 10/10');
    expect(box.ascent, greaterThan(50), reason: '含上 margin 且基线在盒底之上');
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

  test('53 场景：102 处 120×34 行内盒 → 仍 1 行，盒底对齐基线并撑高行盒', () {
    // 复现 cases/53-display-position.json：'行内块对照：' + inline-block 120×34 + 收尾文字。
    final layout = TextLayoutEngine.layout(
      text: '行内块对照：结束时',
      style: _style(const {'line-height': '1.6'}),
      maxWidth: 350,
      inlineBoxes: const <InlineBoxSpec>[
        InlineBoxSpec(offset: 6, width: 120, height: 34),
      ],
    );
    expect(layout.lineCount, 1, reason: '102+120+收尾 ≈ 273 < 350，不该换行');
    final line = layout.lines.single;
    final box = line.inlineBoxes.single;
    // Ahem 每字 16px → 6 字后 96（真实字体 17px 下 = 102，与 53 用例一致）。
    expect(box.left, closeTo(96, 0.5));
    expect(box.width, 120);
    expect(box.height, 34);
    // 基线 = 盒内最后一行基线（Chrome 实测：基线在盒底之上约半行距 + descent）。
    expect(box.ascent, lessThan(34));
    expect(box.ascent + box.descent, greaterThanOrEqualTo(34));
    expect(line.baseline - line.top, closeTo(box.ascent, 0.01));
    // 盒比行高（24）高 → 行盒被撑到 ≥34。
    expect(line.height, greaterThanOrEqualTo(34));
  });

  test('行盒高 = max(行高, 盒 margin box 高)（Chrome 口径，不是 ascent+descent 相加）', () {
    // Ahem 16px / line-height 1.5 → 行高 24。
    final tall = TextLayoutEngine.layout(
      text: 'ab',
      style: _style(const {'line-height': '1.5'}),
      maxWidth: 400,
      inlineBoxes: const <InlineBoxSpec>[
        InlineBoxSpec(offset: 0, width: 40, height: 60),
      ],
    );
    final tallLine = tall.lines.single;
    expect(tallLine.height, closeTo(60, 0.01), reason: '盒高 60 > 行高 24');
    final tallBox = tallLine.inlineBoxes.single;
    expect(tallLine.baseline - tallLine.top, closeTo(tallBox.ascent, 0.01));

    // 盒比行高矮 → 行盒高保持行高，不多算盒的 ascent+descent。
    final small = TextLayoutEngine.layout(
      text: 'ab',
      style: _style(const {'line-height': '1.5'}),
      maxWidth: 400,
      inlineBoxes: const <InlineBoxSpec>[
        InlineBoxSpec(offset: 0, width: 40, height: 10),
      ],
    );
    expect(small.lines.single.height, closeTo(24, 0.5), reason: '行高 24 主导');
  });

  test('实测基线的盒按上下延伸与文字 strut 合成行高', () {
    final plain = TextLayoutEngine.layout(
      text: 'ab',
      style: _style(),
      maxWidth: 400,
    ).lines.single;
    final layout = TextLayoutEngine.layout(
      text: 'ab',
      style: _style(),
      maxWidth: 400,
      inlineBoxes: const [
        InlineBoxSpec(
          offset: 1,
          width: 40,
          height: 24,
          marginTop: 3,
          marginBottom: 4,
          contentBaseline: 28,
        ),
      ],
    );
    final line = layout.lines.single;
    expect(line.inlineBoxes.single.ascent, 31);
    expect(line.height, closeTo(31 + plain.height - plain.baseline, .01));
  });

  test('实测末行基线可在边框盒外，不把溢出内容高当成 margin 盒高', () {
    final plain = TextLayoutEngine.layout(
      text: 'ab',
      style: _style(),
      maxWidth: 400,
    ).lines.single;
    final layout = TextLayoutEngine.layout(
      text: 'ab',
      style: _style(),
      maxWidth: 400,
      inlineBoxes: const [
        InlineBoxSpec(
          offset: 1,
          width: 40,
          height: 20,
          contentHeight: 96,
          contentBaseline: 70,
        ),
      ],
    );
    final line = layout.lines.single;
    expect(line.inlineBoxes.single.descent, -50);
    expect(line.baseline, 70);
    expect(line.height, closeTo(70 + plain.height - plain.baseline, .01));
  });

  test('盒内内容溢出：行盒高取内容高（53 的 120×34 盒内 2 行 → 54.38）', () {
    final layout = TextLayoutEngine.layout(
      text: 'ab',
      style: _style(const {'line-height': '1.5'}),
      maxWidth: 400,
      inlineBoxes: const <InlineBoxSpec>[
        InlineBoxSpec(offset: 0, width: 120, height: 34, contentHeight: 54.38),
      ],
    );
    final line = layout.lines.single;
    expect(line.height, closeTo(54.38, 0.01), reason: 'Chrome：盒内溢出计入行盒高');
    final overflowBox = line.inlineBoxes.single;
    // 基线 = 盒内最后一行基线：比行盒底高出一段（half-leading + 字体 descent）。
    expect(overflowBox.ascent, lessThan(54.38));
    expect(overflowBox.ascent + overflowBox.descent, closeTo(54.38, 0.01));
    expect(line.baseline - line.top, closeTo(overflowBox.ascent, 0.01));
  });

  test('盒占位进入行宽：advance ≈ 文字宽 + 盒宽（T3 的 A/B 口径）', () {
    final without = TextLayoutEngine.layout(
      text: 'abcdefgh',
      style: _style(),
      maxWidth: 400,
    );
    final withBox = TextLayoutEngine.layout(
      text: 'abcdefgh',
      style: _style(),
      maxWidth: 400,
      inlineBoxes: const <InlineBoxSpec>[
        InlineBoxSpec(offset: 4, width: 120, height: 34),
      ],
    );
    final boxes = withBox.lines
        .expand((line) => line.inlineBoxes)
        .fold<double>(0, (sum, box) => sum + box.width);
    expect(
      withBox.lines.single.width,
      greaterThanOrEqualTo(without.lines.single.width + boxes - 0.01),
      reason: 'advance ≥ 文字宽 + 盒宽之和',
    );
    expect(withBox.lines.single.advanceWidth, greaterThanOrEqualTo(boxes));
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
