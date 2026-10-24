import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/text/script.dart';

/// 两个族指向同一字体文件，度量一致，便于对比「分段前后布局尺寸不变」。
const _familyCjk = 'ScriptA';
const _familyLatin = 'ScriptB';

const _text = '中文abc中文混排验证，字形覆盖分段。';

/// 假字形表：CJK（含全角标点）归 ScriptA，其余可打印 ASCII 归 ScriptB。
bool _fakeHasGlyph(String family, int codeUnit) {
  if (family == _familyCjk) {
    return isCjkCodePoint(codeUnit);
  }
  if (family == _familyLatin) {
    return codeUnit >= 0x20 && codeUnit <= 0x7E;
  }
  return false;
}

ComputedStyle _style({double fontSize = 16}) => ComputedStyle(<String, String>{
  'font-size': '${fontSize}px',
  'line-height': '1.5',
  'font-family': '$_familyCjk, $_familyLatin',
});

TextLayoutResult _layout({
  double maxWidth = 320,
  List<StyledRun> runs = const <StyledRun>[],
  bool Function(String family, int codeUnit)? hasGlyph,
  String text = _text,
}) => TextLayoutEngine.layout(
  text: text,
  style: _style(),
  maxWidth: maxWidth,
  runs: runs,
  hasGlyph: hasGlyph,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final file = File('../../test_fonts/SourceHanSerifSC-Regular.otf');
    if (!file.existsSync()) {
      return;
    }
    final bytes = ByteData.view(file.readAsBytesSync().buffer);
    for (final family in <String>[_familyCjk, _familyLatin]) {
      await (FontLoader(family)..addFont(Future<ByteData>.value(bytes))).load();
    }
  });

  test('缺省 hasGlyph 不产生族分段', () {
    final layout = _layout();
    expect(layout.runs, isEmpty);
    expect(layout.lineCount, greaterThan(0));
  });

  test('传入 hasGlyph 后按族切分，runs 升序不重叠', () {
    final layout = _layout(hasGlyph: _fakeHasGlyph);
    expect(layout.runs, isNotEmpty);
    expect(layout.runs.map((run) => run.style.fontFamily).toSet(), <String>{
      _familyCjk,
      _familyLatin,
    });
    // 全角逗号、句号属于 CJK 标点，归 ScriptA；ASCII 字母归 ScriptB。
    final latin = layout.runs.where(
      (run) => run.style.fontFamily == _familyLatin,
    );
    expect(latin, isNotEmpty);
    for (final run in latin) {
      final slice = _text.substring(run.start, run.end);
      expect(slice, matches(RegExp(r'^[a-zA-Z]+$')));
    }
    for (var i = 1; i < layout.runs.length; i++) {
      expect(
        layout.runs[i].start,
        greaterThanOrEqualTo(layout.runs[i - 1].end),
        reason: '区间必须升序且不重叠',
      );
    }
    expect(layout.runs.first.start, 0);
    expect(layout.runs.last.end, _text.length);
  });

  test('族分段不改变行数与各行内容', () {
    final plain = _layout();
    final fallback = _layout(hasGlyph: _fakeHasGlyph);
    expect(fallback.lineCount, plain.lineCount);
    for (var i = 0; i < plain.lines.length; i++) {
      expect(fallback.lines[i].start, plain.lines[i].start, reason: '行 $i');
      expect(fallback.lines[i].end, plain.lines[i].end, reason: '行 $i');
    }
    // 同一字体度量下，族的切换不改变行宽与行高。
    expect(fallback.width, closeTo(plain.width, 0.001));
    expect(fallback.height, closeTo(plain.height, 0.001));
  });

  test('行内区间只叠加字体族，字号等保持原值', () {
    final inline = StyledRun(start: 2, end: 5, style: _style(fontSize: 24));
    final layout = _layout(
      maxWidth: 600,
      runs: <StyledRun>[inline],
      hasGlyph: _fakeHasGlyph,
    );
    final inside = layout.runs
        .where((run) => run.start == 2 && run.end == 5)
        .toList();
    expect(inside, hasLength(1), reason: '同行内区间内同族不应被拆碎');
    expect(inside.single.style.fontSize, 24);
    expect(inside.single.style.fontFamily, _familyLatin);

    final outside = layout.runs.where((run) => run.end <= 2);
    expect(outside, isNotEmpty);
    for (final run in outside) {
      expect(run.style.fontSize, 16);
    }
    expect(outside.first.style.fontFamily, _familyCjk);
  });

  test('hasGlyph 缺省时 layout.runs 原样返回调用方区间', () {
    final inline = StyledRun(start: 0, end: 2, style: _style(fontSize: 20));
    final layout = _layout(runs: <StyledRun>[inline]);
    expect(layout.runs, hasLength(1));
    expect(layout.runs.single.start, 0);
    expect(layout.runs.single.end, 2);
    expect(layout.runs.single.style.fontSize, 20);
  });
}
