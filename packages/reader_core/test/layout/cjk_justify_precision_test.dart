import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/cjk_justify.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/paint/line_spans.dart';

const _family = 'JustifySerif';
const _cjk =
    '一二三四五六七八九十一二三四五六七八九十'
    '一二三四五六七八九十一二三四五六七八九十';
const _mixed =
    '中文English混排测试继续排'
    '中文English混排测试继续排';

Future<void> _loadFont() async {
  final bytes = await File('../../test_fonts/SourceHanSerifSC-Regular.otf')
      .readAsBytes();
  await (FontLoader(
    _family,
  )..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)))).load();
}

ComputedStyle _style({String align = 'justify'}) =>
    ComputedStyle(<String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': _family,
      'text-align': align,
    });

/// 取首行（非末行）的 justify span，测量拉伸后的宽度。
TextPainter _justifiedFirstLine(String text, double target) {
  final style = _style();
  final layout = TextLayoutEngine.layout(
    text: text,
    style: style,
    maxWidth: target,
  );
  expect(layout.lineCount, greaterThan(1), reason: '需要非末行才能 justify');
  final line = layout.lines.first;
  final span = buildLineSpan(
    layout: layout,
    line: line,
    baseStyle: TextLayoutEngine.textStyleFor(style),
  );
  return TextPainter(text: span, textDirection: TextDirection.ltr)..layout();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFont);

  group('三组目标宽误差 <1px（纯中文）', () {
    for (final target in [330.0, 350.0, 390.0]) {
      test('目标宽 ${target.toInt()}', () {
        final painter = _justifiedFirstLine(_cjk, target);
        expect(
          (painter.width - target).abs(),
          lessThan(1.0),
          reason: '拉伸后行宽应等于目标宽，实际 ${painter.width}',
        );
      });
    }
  });

  group('混排行同样收敛到目标宽', () {
    for (final target in [210.0, 230.0]) {
      test('目标宽 ${target.toInt()}', () {
        final painter = _justifiedFirstLine(_mixed, target);
        expect((painter.width - target).abs(), lessThan(1.0));
      });
    }
  });

  test('末字之后没有多余字距', () {
    const target = 330.0;
    final style = _style();
    final layout = TextLayoutEngine.layout(
      text: _cjk,
      style: style,
      maxWidth: target,
    );
    final line = layout.lines.first;
    final lineText = layout.text.substring(line.start, line.end);
    final gaps = cjkJustifyGapOffsets(lineText);
    expect(gaps, isNotEmpty);
    expect(gaps.last, lessThan(lineText.length - 1), reason: '末字不是 gap 起点');

    final painter = _justifiedFirstLine(_cjk, target);
    // 若末字后也加了字距，宽度会超出目标宽约 ls（此处 >1px）。
    expect(painter.width, lessThanOrEqualTo(target + 1.0));
    // 末字墨迹右缘不超过目标宽。
    final boxes = painter.getBoxesForSelection(
      TextSelection(
        baseOffset: lineText.length - 1,
        extentOffset: lineText.length,
      ),
      boxHeightStyle: ui.BoxHeightStyle.tight,
    );
    expect(boxes, isNotEmpty);
    // 末字字距仍是基础值：盒宽约等于单字 advance（16），右缘不超过目标宽 1px（含字形 bearing）。
    expect(boxes.last.right - boxes.last.left, closeTo(16, 1.0));
    expect(boxes.last.right, lessThanOrEqualTo(target + 1.0));
  });

  test('字框不重叠（逐字符紧致盒推进）', () {
    const target = 350.0;
    final style = _style();
    final layout = TextLayoutEngine.layout(
      text: _cjk,
      style: style,
      maxWidth: target,
    );
    final line = layout.lines.first;
    final lineText = layout.text.substring(line.start, line.end);
    final painter = _justifiedFirstLine(_cjk, target);

    var previousRight = 0.0;
    for (var i = 0; i < lineText.length; i++) {
      final boxes = painter.getBoxesForSelection(
        TextSelection(baseOffset: i, extentOffset: i + 1),
        boxHeightStyle: ui.BoxHeightStyle.tight,
      );
      expect(boxes, hasLength(1), reason: '第 $i 字应有一个盒');
      final box = boxes.single;
      expect(
        box.left,
        greaterThanOrEqualTo(previousRight - 0.01),
        reason: '第 $i 字压到前一字',
      );
      expect(box.right, greaterThan(box.left));
      previousRight = box.right;
    }
  });

  test('justifyGapSpacing 均分余量', () {
    expect(justifyGapSpacing(19, 19), 1.0);
    expect(justifyGapSpacing(16, 19), closeTo(16 / 19, 1e-9));
    expect(justifyGapSpacing(0, 19), 0);
    expect(justifyGapSpacing(10, 0), 0);
  });
}
