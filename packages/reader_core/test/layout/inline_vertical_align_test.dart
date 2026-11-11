import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';

/// 行内竖直几何（CSS 2.1 §10.8）与 Chromium 对照。
///
/// 案例取自 `tool/css_parity/cases/05-vertical-align.json`：17px / 行高 1.8
/// 的正文里插 0.7em 的 `<sup>` / `<sub>`，浏览器该段高 32.47；行盒取
/// 「块 strut ∪ 各 run 的 line-height 盒（按 vertical-align 平移）」。
const _fontFamily = 'S1CJK';
const _fontPath = '../../test_fonts/SourceHanSerifSC-Regular.otf';

Future<void> _loadFont() async {
  final bytes = await File(_fontPath).readAsBytes();
  await (FontLoader(
    _fontFamily,
  )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
}

ComputedStyle _style([Map<String, String> overrides = const {}]) =>
    ComputedStyle(<String, String>{
      'font-size': '17px',
      'line-height': '1.8',
      'font-family': _fontFamily,
      ...overrides,
    });

TextLayoutResult _layout(
  String text, {
  List<StyledRun> runs = const <StyledRun>[],
  double width = 350,
}) => TextLayoutEngine.layout(
  text: text,
  style: _style(),
  maxWidth: width,
  runs: runs,
);

/// 按旧口径（阅微 0.4em/0.15em）写入 run，验证排版层会按父字号重算。
StyledRun _runOn(ComputedStyle style, int start, int end) => StyledRun(
  start: start,
  end: end,
  style: style,
  baselineShift: style.verticalAlignShift,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFont);

  test('sup/sub 行高按行内盒上/下沿扩展（浏览器 32.47，容差 1px）', () {
    const text = '基线对比 x2 + y1 结束';
    final plain = _layout(text);
    final sup = _style(const {
      'font-size': '11.9px',
      'vertical-align': 'super',
    });
    final sub = _style(const {'font-size': '11.9px', 'vertical-align': 'sub'});
    final layout = _layout(
      text,
      runs: <StyledRun>[_runOn(sup, 6, 7), _runOn(sub, 11, 12)],
    );

    final height = layout.lines.single.height;
    expect(height, greaterThan(plain.lines.single.height + 0.5));
    expect(height, closeTo(32.47, 1.0), reason: '浏览器该段高 32.47');
    // 只向下长：块基线不动，后续行顺延靠行高。
    expect(
      layout.lines.single.baseline,
      closeTo(plain.lines.single.baseline, 0.01),
    );
    expect(layout.height, closeTo(height, 0.01));
  });

  test('super/sub 偏移沿用计算样式（父字号口径），排版层不改写', () {
    const text = '基线对比 x2 + y1 结束';
    final sup = _style(const {
      'font-size': '11.9px',
      'vertical-align': 'super',
    });
    final sub = _style(const {'font-size': '11.9px', 'vertical-align': 'sub'});
    final layout = _layout(
      text,
      runs: <StyledRun>[_runOn(sup, 6, 7), _runOn(sub, 11, 12)],
    );

    // 父级 17px 下 Chromium 的 super ≈ -6.67、sub ≈ +4.4（父字号口径）。
    final supShift = layout.runs[0].baselineShift;
    final subShift = layout.runs[1].baselineShift;
    expect(supShift, closeTo(sup.verticalAlignShift, 0.01));
    expect(subShift, closeTo(sub.verticalAlignShift, 0.01));
    expect(supShift, inInclusiveRange(-7.2, -6.0), reason: '父字号 17px 的 super');
    expect(subShift, inInclusiveRange(3.5, 4.8), reason: '父字号 17px 的 sub');
  });

  test('调用方漏写 baselineShift 时按计算样式公式兜底', () {
    const text = '上下标 E=mc2';
    final sup = _style(const {
      'font-size': '11.9px',
      'vertical-align': 'super',
    });
    final layout = _layout(
      text,
      runs: <StyledRun>[StyledRun(start: 3, end: 4, style: sup)],
    );
    expect(layout.runs.single.baselineShift, closeTo(-6.33, 0.2));
    expect(
      layout.runs.single.baselineShift,
      closeTo(sup.verticalAlignShift, 0.01),
      reason: '兜底公式与 ComputedStyle 一致',
    );
  });

  test('text-top / text-bottom / middle 生效且不撑高小字号行内盒', () {
    const text = '偏移值 上移 与 text-top text-bottom middle';
    final t = _style(const {'font-size': '12px', 'vertical-align': 'text-top'});
    final b = _style(const {
      'font-size': '12px',
      'vertical-align': 'text-bottom',
    });
    final m = _style(const {'font-size': '12px', 'vertical-align': 'middle'});
    final plain = _layout(text);
    final layout = _layout(
      text,
      runs: <StyledRun>[
        StyledRun(start: 4, end: 6, style: t),
        StyledRun(start: 9, end: 17, style: t),
        StyledRun(start: 18, end: 29, style: b),
        StyledRun(start: 30, end: 36, style: m),
      ],
    );

    final textTop = layout.runs[0].baselineShift;
    final textBottom = layout.runs[2].baselineShift;
    final middle = layout.runs[3].baselineShift;
    expect(textTop, lessThan(-2), reason: 'text-top 上移，盒顶对齐父内容区顶');
    expect(textBottom, inInclusiveRange(-2, 0.0), reason: 'text-bottom 略上移');
    expect(middle, inInclusiveRange(-1, 2), reason: 'middle 按 x-height 居中');
    // 12px 的行内盒比 17px strut 小，行高不变（浏览器同段 30.6）。
    expect(
      layout.lines.single.height,
      closeTo(plain.lines.single.height, 0.01),
    );
  });

  test('大字号行内盒越出行盒继续撑高', () {
    const text = '基线对比 x2 结束';
    final sup = _style(const {'font-size': '32px', 'vertical-align': 'super'});
    final plain = _layout(text);
    final layout = _layout(text, runs: <StyledRun>[_runOn(sup, 6, 7)]);
    expect(layout.lines.single.height, greaterThan(plain.height + 10));
  });

  test('无 vertical-align 时不改基线偏移（沿用调用方写入值）', () {
    const text = 'abcdef';
    final layout = _layout(
      text,
      runs: <StyledRun>[
        StyledRun(start: 1, end: 3, style: _style(), baselineShift: -3),
      ],
    );
    expect(layout.runs.single.baselineShift, -3);
  });

  // Ahem 16px/1.5：字体盒 ascent 12.8 / descent 3.2，行高 24；13px 子盒
  // 半行距 3.25。用来验证「按行内盒上/下沿撑高」的确定性数值。
  test('Ahem：常规上标按盒上沿撑高 3.25px', () {
    final plain = _ahemLayout('abcdefgh', 64);
    final layout = _ahemLayout(
      'abcdefgh',
      64,
      runs: <StyledRun>[
        StyledRun(start: 4, end: 7, style: _ahemStyle(13), baselineShift: -6.4),
      ],
    );
    expect(plain.lineCount, 2);
    expect(layout.lines[1].height, closeTo(27.25, 0.6));
    expect(layout.lines[0].height, closeTo(24, 0.01), reason: '首行不受影响');
  });

  test('Ahem：常规下标按盒下沿撑高 1.05px', () {
    final layout = _ahemLayout(
      'abcdefgh',
      64,
      runs: <StyledRun>[
        StyledRun(start: 4, end: 7, style: _ahemStyle(13), baselineShift: 2.4),
      ],
    );
    expect(layout.lines[1].height, closeTo(25.05, 0.6));
  });

  test('Ahem：偏移为 0 的 run 不改行高', () {
    final plain = _ahemLayout('abcdefgh', 64);
    final layout = _ahemLayout(
      'abcdefgh',
      64,
      runs: <StyledRun>[StyledRun(start: 4, end: 7, style: _ahemStyle(13))],
    );
    for (var i = 0; i < plain.lineCount; i++) {
      expect(layout.lines[i].height, closeTo(plain.lines[i].height, 0.01));
    }
  });

  test('长度型 vertical-align 撑高行盒（枚举仍是 baseline）', () {
    const text = '基线对比 x2 结束';
    final raised = _style(const {
      'font-size': '12px',
      'vertical-align': '20px',
    });
    final layout = _layout(
      text,
      runs: <StyledRun>[
        StyledRun(
          start: 6,
          end: 7,
          style: raised,
          baselineShift: raised.verticalAlignShift,
        ),
      ],
    );
    // 枚举仍为 baseline，偏移只在 verticalAlignShift 上（= -20）。
    expect(raised.verticalAlign, CssVerticalAlign.baseline);
    expect(layout.runs.single.baselineShift, closeTo(-20, 0.01));
    expect(layout.lines.single.height, greaterThan(40), reason: '上移 20 撑高行盒');
  });

  test('长度型下移同样撑高行盒', () {
    const text = '基线对比 x2 结束';
    final lowered = _style(const {'vertical-align': '-12px'});
    final layout = _layout(
      text,
      runs: <StyledRun>[
        StyledRun(
          start: 6,
          end: 7,
          style: lowered,
          baselineShift: lowered.verticalAlignShift,
        ),
      ],
    );
    expect(layout.runs.single.baselineShift, closeTo(12, 0.01));
    expect(layout.lines.single.height, greaterThan(40), reason: '下移 12 撑高行盒');
  });

  test('小幅长度偏移不撑高（与 Chrome 一致）', () {
    const text = '基线对比 x2 结束';
    final plain = _layout(text);
    final tiny = _style(const {'font-size': '12px', 'vertical-align': '2px'});
    final layout = _layout(
      text,
      runs: <StyledRun>[
        StyledRun(
          start: 6,
          end: 7,
          style: tiny,
          baselineShift: tiny.verticalAlignShift,
        ),
      ],
    );
    expect(
      layout.lines.single.height,
      closeTo(plain.lines.single.height, 0.01),
    );
  });
}

ComputedStyle _ahemStyle([double? fontSize]) => ComputedStyle(<String, String>{
  'font-size': fontSize == null ? '16px' : '${fontSize}px',
  'line-height': '1.5',
  'font-family': 'Ahem',
});
TextLayoutResult _ahemLayout(
  String text,
  double width, {
  List<StyledRun> runs = const <StyledRun>[],
}) => TextLayoutEngine.layout(
  text: text,
  style: _ahemStyle(),
  maxWidth: width,
  runs: runs,
);
