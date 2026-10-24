import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';

/// P7-09：上下标借行距（Reeden 630 号 §2-3 / fixups N5）。
///
/// `baselineShift` 只平移墨迹不参与行盒计算：常规上标（0.83em + super
/// 偏移）借已有行距，行高与相邻行一致；极端大字号/大偏移越出行盒时
/// 该行才被撑高。
ComputedStyle _style({double? fontSize}) => ComputedStyle(<String, String>{
  'font-size': fontSize == null ? '16px' : '${fontSize}px',
  'line-height': '1.5',
  'font-family': 'Ahem',
});

TextLayoutResult _layout(
  String text,
  double width, {
  List<StyledRun> runs = const <StyledRun>[],
}) => TextLayoutEngine.layout(
  text: text,
  style: _style(),
  maxWidth: width,
  runs: runs,
);

void main() {
  // Ahem：字形框 = em 方块（ascent 0.8em / descent 0.2em）。
  // 16px × 1.5 → 行高 24、even 分布 ascent = 4 + 12.8 = 16.8。

  test('常规上标借行距：行高与相邻行一致（差 <0.5px）', () {
    // 8 字符两行；第二行前 3 字为上标（0.83em≈13px，偏移 -0.4em≈-6.4）。
    final layout = _layout(
      'abcdefgh',
      64,
      runs: <StyledRun>[
        StyledRun(
          start: 4,
          end: 7,
          style: _style(fontSize: 13),
          baselineShift: -6.4,
        ),
      ],
    );
    expect(layout.lineCount, 2);
    final diff = (layout.lines[0].height - layout.lines[1].height).abs();
    expect(diff, lessThan(0.5), reason: '上标行与常规行行高跳变 $diff');
  });

  test('常规下标同理借行距', () {
    final layout = _layout(
      'abcdefgh',
      64,
      runs: <StyledRun>[
        StyledRun(
          start: 4,
          end: 7,
          style: _style(fontSize: 13),
          baselineShift: 2.4,
        ),
      ],
    );
    expect(layout.lineCount, 2);
    final diff = (layout.lines[0].height - layout.lines[1].height).abs();
    expect(diff, lessThan(0.5));
  });

  test('极端大字号上标越出行盒才撑高', () {
    // 32px 字形 + 偏移 -24：墨迹顶部远超行盒 ascent，该行应显著撑高。
    // 32px 字符在 64 宽下两字一行，故产出 3 行；含上标的行高 64
    // （自然 48 + 向上生长 16），首行不受影响。
    final layout = _layout(
      'abcdefgh',
      64,
      runs: <StyledRun>[
        StyledRun(
          start: 4,
          end: 7,
          style: _style(fontSize: 32),
          baselineShift: -24,
        ),
      ],
    );
    expect(layout.lineCount, 3);
    expect(layout.lines[1].height, greaterThan(48 + 10),
        reason: '越出后应在自然行盒 48 之上继续撑高');
    expect(layout.lines[0].height, closeTo(24, 0.5));
  });

  test('对照：无偏移的大字号仍按自然行盒（撑高由字号本身决定）', () {
    final layout = _layout(
      'abcdefgh',
      64,
      runs: <StyledRun>[
        StyledRun(start: 4, end: 7, style: _style(fontSize: 32)),
      ],
    );
    expect(layout.lines[1].height, greaterThan(24));
  });

  test('无偏移区间不触发借行距路径（结果与不传 run 一致）', () {
    final plain = _layout('abcdefgh', 64);
    final withZeroShift = _layout(
      'abcdefgh',
      64,
      runs: <StyledRun>[
        StyledRun(start: 4, end: 7, style: _style(fontSize: 13), baselineShift: 0),
      ],
    );
    expect(withZeroShift.lineCount, plain.lineCount);
    for (var i = 0; i < plain.lineCount; i++) {
      expect(withZeroShift.lines[i].height, closeTo(plain.lines[i].height, 0.01));
    }
  });
}
