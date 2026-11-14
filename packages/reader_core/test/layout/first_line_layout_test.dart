import 'package:flutter/painting.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';

const _text = 'abcdefghijklmnopqrstuvwx';

ComputedStyle _style([Map<String, String> values = const {}]) => ComputedStyle({
  'font-family': 'Ahem',
  'font-size': '16px',
  'line-height': '1.5',
  'word-break': 'break-all',
  ...values,
});

StyledRun _run(
  ComputedStyle style, {
  String text = _text,
  double leading = 0,
  double trailing = 0,
}) => StyledRun(
  start: 0,
  end: text.length,
  style: style,
  inlineLeadingInset: leading,
  inlineTrailingInset: trailing,
);

ComputedStyle _styleAt(
  TextLayoutResult result,
  ComputedStyle body,
  int offset,
) =>
    result.runs
        .where((run) => run.start <= offset && offset < run.end)
        .map((run) => run.style)
        .firstOrNull ??
    body;

List<Object?> _geometry(TextLayoutResult result) => [
  result.text,
  result.maxWidth,
  result.width,
  result.height,
  for (final line in result.lines)
    [
      line.start,
      line.end,
      line.top,
      line.height,
      line.baseline,
      line.width,
      line.indent,
      line.isLastLine,
      line.isHardBreak,
      line.offsetX,
      line.spacing?.fingerprint,
      for (final box in line.inlineBoxes)
        [box.offset, box.left, box.width, box.height, box.spec.payload],
    ],
  for (final run in result.runs)
    [
      run.start,
      run.end,
      run.style.fontSize,
      run.style.lineHeight,
      run.style.color,
      run.leadingInset,
      run.trailingInset,
    ],
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('首行大字号决定实际断点，续行恢复正文行宽、行高和绘制样式', () {
    final body = _style();
    final first = _style({'font-size': '32px', 'color': 'red'});
    final result = TextLayoutEngine.layout(
      text: _text,
      style: body,
      maxWidth: 128,
      firstLineStyle: first,
    );

    expect(result.lines.map((line) => (line.start, line.end)), [
      (0, 4),
      (4, 12),
      (12, 20),
      (20, 24),
    ]);
    expect(result.lines.map((line) => line.width), [128, 128, 128, 64]);
    expect(result.lines.map((line) => line.height), [48, 24, 24, 24]);
    expect(result.lines.map((line) => line.top), [0, 48, 72, 96]);
    expect(result.height, 120);
    expect(_styleAt(result, body, 3).fontSize, 32);
    expect(_styleAt(result, body, 3).color, const Color(0xffff0000));
    expect(_styleAt(result, body, 4).fontSize, 16);
    expect(_styleAt(result, body, 4).color, const Color(0xff000000));
    expect(result.inputRuns, isEmpty);
  });

  test('显式 span 字号覆盖首行继承，未声明字号的 span 仅在首行变大', () {
    final body = _style();
    final first = _style({'font-size': '32px', 'color': 'red'});
    final runs = [
      StyledRun(
        start: 0,
        end: 2,
        style: ComputedStyle({
          'font-size': '24px',
          'color': 'green',
        }, parent: body),
      ),
      StyledRun(
        start: 2,
        end: _text.length,
        style: ComputedStyle({}, parent: body),
      ),
    ];
    final result = TextLayoutEngine.layout(
      text: _text,
      style: body,
      maxWidth: 112,
      runs: runs,
      firstLineStyle: first,
    );

    expect(result.lines.first.end, 4, reason: '两个 24px 字加两个 32px 字占 112px');
    expect(result.lines.first.width, 112);
    expect(_styleAt(result, body, 0).fontSize, 24);
    expect(_styleAt(result, body, 0).color, const Color(0xff008000));
    expect(_styleAt(result, body, 2).fontSize, 32);
    expect(_styleAt(result, body, 2).color, const Color(0xffff0000));
    expect(_styleAt(result, body, 4).fontSize, 16);
    expect(_styleAt(result, body, 4).color, const Color(0xff000000));
  });

  test('首尾行内占宽只保留原边界，不在首行切点重复生成', () {
    const text = 'abcdefghijklmno';
    final body = _style();
    final first = _style({'font-size': '32px'});
    StyledRun run(ComputedStyle parent) => _run(
      ComputedStyle({}, parent: parent),
      text: text,
      leading: 8,
      trailing: 12,
    );

    for (final suppliedRuns in [false, true]) {
      final result = TextLayoutEngine.layout(
        text: text,
        style: body,
        maxWidth: 144,
        runs: [run(body)],
        firstLineStyle: first,
        firstLineRuns: suppliedRuns ? [run(first)] : null,
      );

      expect(result.lines.map((line) => (line.start, line.end)), [
        (0, 4),
        (4, 13),
        (13, 15),
      ]);
      expect(result.lines.map((line) => line.width), [136, 144, 44]);
      expect(
        result.runs.map(
          (run) => (run.start, run.end, run.leadingInset, run.trailingInset),
        ),
        [(0, 4, 8, 0), (4, 15, 0, 12)],
      );
      final edges = result.lines.expand((line) => line.inlineBoxes).toList();
      expect(edges, hasLength(2));
      expect(edges.first.offset, 0);
      expect(edges.first.width, 8);
      expect(edges.first.spec.payload, InlineSpacingEdge.leading);
      expect(edges.last.offset, text.length);
      expect(edges.last.width, 12);
      expect(edges.last.spec.payload, InlineSpacingEdge.trailing);
      expect(result.lines[1].inlineBoxes, isEmpty);
    }
  });

  test('相对首尾留白使用所在行的字号，续行不重复首边距', () {
    const text = 'abcdefghijklmno';
    final body = _style();
    final first = _style({'font-size': '32px'});
    StyledRun run(ComputedStyle parent) => StyledRun(
      start: 0,
      end: text.length,
      style: ComputedStyle({'padding': '0 1em'}, parent: parent),
    );

    for (final suppliedRuns in [false, true]) {
      final result = TextLayoutEngine.layout(
        text: text,
        style: body,
        maxWidth: 144,
        runs: [run(body)],
        firstLineStyle: first,
        firstLineRuns: suppliedRuns ? [run(first)] : null,
      );

      expect(result.lines.map((line) => (line.start, line.end)), [
        (0, 3),
        (3, 12),
        (12, 15),
      ]);
      expect(result.lines.map((line) => line.width), [128, 144, 64]);
      expect(result.lines.first.inlineBoxes.single.width, 32);
      expect(result.lines[1].inlineBoxes, isEmpty);
      expect(result.lines.last.inlineBoxes.single.width, 16);
      expect(
        result.runs.map(
          (run) => (run.start, run.end, run.leadingInset, run.trailingInset),
        ),
        [(0, 3, 32, 0), (3, 15, 0, 16)],
      );
    }
  });

  test('被首行挤到续行的行内首边距改用正文计算值', () {
    const text = 'abcdefghijklmno';
    final body = _style();
    final result = TextLayoutEngine.layout(
      text: text,
      style: body,
      maxWidth: 144,
      runs: [
        StyledRun(
          start: 4,
          end: text.length,
          style: ComputedStyle({'padding': '0 1em'}, parent: body),
        ),
      ],
      firstLineStyle: _style({'font-size': '32px'}),
    );

    expect(result.lines.map((line) => (line.start, line.end)), [
      (0, 4),
      (4, 12),
      (12, 15),
    ]);
    expect(result.lines.map((line) => line.width), [128, 144, 64]);
    expect(result.lines.first.inlineBoxes, isEmpty);
    final leading = result.lines[1].inlineBoxes.single;
    expect(leading.offset, 4);
    expect(leading.spec.payload, InlineSpacingEdge.leading);
    expect(leading.width, 16);
    expect(result.lines.last.inlineBoxes.single.width, 16);
  });

  test('在首行结束的行内元素使用首行末边距', () {
    final body = _style();
    final result = TextLayoutEngine.layout(
      text: _text,
      style: body,
      maxWidth: 144,
      runs: [
        StyledRun(
          start: 0,
          end: 2,
          style: ComputedStyle({'padding-right': '1em'}, parent: body),
        ),
      ],
      firstLineStyle: _style({'font-size': '32px'}),
    );

    expect(result.lines.first.end, 3);
    expect(result.lines.first.width, 128);
    final trailing = result.lines.first.inlineBoxes.single;
    expect(trailing.offset, 2);
    expect(trailing.spec.payload, InlineSpacingEdge.trailing);
    expect(trailing.width, 32);
    expect(result.lines.skip(1).expand((line) => line.inlineBoxes), isEmpty);
  });

  test('相对留白从零变为非零或从非零变为零时保留原文边界', () {
    const text = 'abcdefghijklmno';
    for (final (padding, leading, width) in [
      ('calc(1em - 16px)', 16.0, 144.0),
      ('calc(32px - 1em)', 0.0, 128.0),
    ]) {
      final body = _style();
      final result = TextLayoutEngine.layout(
        text: text,
        style: body,
        maxWidth: 144,
        runs: [
          StyledRun(
            start: 0,
            end: text.length,
            style: ComputedStyle({'padding-left': padding}, parent: body),
          ),
        ],
        firstLineStyle: _style({'font-size': '32px'}),
      );

      expect(result.text, text);
      expect(result.lines.map((line) => (line.start, line.end)), [
        (0, 4),
        (4, 13),
        (13, 15),
      ]);
      expect(result.lines.first.width, width);
      expect(result.lines.first.inlineBoxes.single.offset, 0);
      expect(result.lines.first.inlineBoxes.single.width, leading);
      expect(result.lines.skip(1).expand((line) => line.inlineBoxes), isEmpty);
    }
  });

  test('提供首行 runs 时同步和异步保留相同行几何、样式及盒边界', () async {
    final body = _style();
    final first = _style({'font-size': '32px', 'color': 'red'});
    final runs = [_run(body, leading: 3, trailing: 5)];
    final firstRuns = [_run(first, leading: 6, trailing: 10)];

    for (final width in [96.0, 128.0, 160.0]) {
      final synchronous = TextLayoutEngine.layout(
        text: _text,
        style: body,
        maxWidth: width,
        runs: runs,
        firstLineStyle: first,
        firstLineRuns: firstRuns,
      );
      var checks = 0;
      final asynchronous = await TextLayoutEngine.layoutAsync(
        text: _text,
        style: body,
        maxWidth: width,
        runs: runs,
        firstLineStyle: first,
        firstLineRuns: firstRuns,
        checkpoint: () async {
          checks++;
        },
      );

      expect(_geometry(asynchronous), _geometry(synchronous), reason: '$width');
      expect(checks, greaterThan(0));
      expect(asynchronous.inputRuns.single.end, _text.length);
      expect(asynchronous.inputRuns.single.style.fontSize, 16);
      expect(asynchronous.firstLineRuns!.single.end, _text.length);
      expect(asynchronous.firstLineRuns!.single.style.fontSize, 32);
    }
  });

  test('使用完整 inputRuns 变宽重排后重新决定首行范围和续行样式', () {
    final body = _style();
    final first = _style({'font-size': '32px'});
    final runs = [
      _run(ComputedStyle({'color': 'green'}, parent: body)),
    ];
    final firstRuns = [
      _run(ComputedStyle({'color': 'red'}, parent: first)),
    ];
    final wide = TextLayoutEngine.layout(
      text: _text,
      style: body,
      maxWidth: 160,
      runs: runs,
      firstLineStyle: first,
      firstLineRuns: firstRuns,
    );
    final narrow = TextLayoutEngine.layout(
      text: wide.text,
      style: body,
      maxWidth: 96,
      runs: wide.inputRuns,
      firstLineStyle: wide.firstLineStyle,
      firstLineRuns: wide.firstLineRuns,
    );

    expect(wide.lines.first.end, 5);
    expect(narrow.lines.first.end, 3);
    expect(wide.sourceRuns!.single.start, 0);
    expect(wide.sourceRuns!.single.end, _text.length);
    expect(wide.sourceRuns!.single.style.fontSize, 16);
    expect(narrow.inputRuns.single.end, _text.length);
    expect(narrow.firstLineRuns!.single.end, _text.length);
    expect(_styleAt(narrow, body, 2).fontSize, 32);
    expect(_styleAt(narrow, body, 2).color, const Color(0xffff0000));
    expect(_styleAt(narrow, body, 3).fontSize, 16);
    expect(_styleAt(narrow, body, 3).color, const Color(0xff008000));
  });
}
