import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/cjk_justify.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/paint/line_spans.dart';
import 'package:reader_core/text/script.dart';

const _family = 'JustifySerif';
// 40 个全角字：目标宽 330/350/390 时首行必然是「非末行」。
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

ComputedStyle _justifyStyle() => ComputedStyle(const <String, String>{
  'font-size': '16px',
  'line-height': '1.5',
  'font-family': _family,
  'text-align': 'justify',
});

TextLayoutResult _layout(String text, double target) => TextLayoutEngine.layout(
  text: text,
  style: _justifyStyle(),
  maxWidth: target,
);

TextPainter _justifiedFirstLine(TextLayoutResult layout) {
  final span = buildLineSpan(
    layout: layout,
    line: layout.lines.first,
    baseStyle: TextLayoutEngine.textStyleFor(_justifyStyle()),
  );
  return TextPainter(text: span, textDirection: TextDirection.ltr)..layout();
}

List<ui.TextBox> _charBoxes(TextPainter painter, int length) => [
  for (var i = 0; i < length; i++)
    painter
        .getBoxesForSelection(
          TextSelection(baseOffset: i, extentOffset: i + 1),
          boxHeightStyle: ui.BoxHeightStyle.tight,
        )
        .single,
];

/// S3 断言①：拉伸后行宽与目标宽误差 < 1px。
void _expectWidth(TextPainter painter, double target) {
  expect(
    (painter.width - target).abs(),
    lessThan(1.0),
    reason: '拉伸后行宽应等于目标宽，实际 ${painter.width}',
  );
}

/// S3 断言②：逐字符紧致盒单调推进，字框不重叠。
void _expectNoOverlap(List<ui.TextBox> boxes) {
  var previousRight = 0.0;
  for (var i = 0; i < boxes.length; i++) {
    final box = boxes[i];
    expect(
      box.left,
      greaterThanOrEqualTo(previousRight - 0.01),
      reason: '第 $i 字压到前一字',
    );
    expect(box.right, greaterThan(box.left), reason: '第 $i 字盒宽必须为正');
    previousRight = box.right;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CJK 判定口径（P2-19 修正 isCjk 范围）', () {
    test('ASCII 与半角标点不算 CJK', () {
      expect(containsCjk('abc123'), isFalse);
      expect(containsCjk('a.b,c!'), isFalse);
      expect(isCjkCodePoint(0x41), isFalse);
      expect(isCjkCodePoint(0x2E), isFalse);
    });

    test('汉字、假名、谚文、全角标点算 CJK', () {
      for (final rune in ['中', 'あ', 'ア', '한', '，', '。', '、', '　']) {
        expect(containsCjk(rune), isTrue, reason: rune);
      }
    });

    test('扩展区汉字算 CJK', () {
      expect(containsCjk('𠀀'), isTrue);
      expect(containsCjk('㐀'), isTrue);
    });
  });

  group('可分配 gap（§8.4）', () {
    test('纯中文 20 字 → 19 个 gap', () {
      const text = '一二三四五六七八九十一二三四五六七八九十';
      expect(text.runes.length, 20);
      final gaps = cjkJustifyGapOffsets(text);
      expect(gaps, hasLength(19));
      expect(gaps, List<int>.generate(18, (i) => i) + [18]);
    });

    test('中英混排按规则扣除拉丁词内部间隙', () {
      const text = '中文English混排测试继续排';
      expect(text.runes.length, 16);
      final gaps = cjkJustifyGapOffsets(text);
      expect(gaps, <int>[0, 1, 8, 9, 10, 11, 12, 13, 14]);
      expect(gaps, hasLength(9));
    });

    test('标点边界：CJK 标点与其相邻字符可拉伸', () {
      expect(cjkJustifyGapOffsets('中文，测试。'), <int>[0, 1, 2, 3, 4]);
      expect(cjkJustifyGapOffsets('“中文”'), <int>[0, 1, 2]);
    });

    test('末字之后没有 gap', () {
      expect(cjkJustifyGapOffsets('中文'), <int>[0]);
      expect(cjkJustifyGapOffsets('中'), isEmpty);
      expect(cjkJustifyGapOffsets(''), isEmpty);
    });

    test('含换行的间隙跳过', () {
      expect(cjkJustifyGapOffsets('中文\n对齐'), <int>[0, 3]);
    });

    test('代理对按代码单元计偏移', () {
      expect(cjkJustifyGapOffsets('中𠀀文'), <int>[0, 1]);
    });

    test('CJK 与拉丁/数字相邻可拉伸，拉丁内部不拉伸', () {
      expect(cjkJustifyGapOffsets('中文abc测试'), <int>[0, 1, 4, 5]);
      expect(cjkJustifyGapOffsets('中a'), <int>[0]);
      expect(cjkJustifyGapOffsets('a中'), <int>[0]);
      expect(cjkJustifyGapOffsets('12中'), <int>[1]);
      expect(cjkJustifyGapOffsets('中1'), <int>[0]);
    });

    test('西文行只拉伸词间空格', () {
      expect(cjkJustifyGapOffsets('ab cd ef'), <int>[2, 5]);
      expect(cjkJustifyGapOffsets('abcdef'), isEmpty);
      expect(cjkJustifyGapOffsets('ab\ncd'), isEmpty);
      expect(cjkJustifyGapOffsets('a.b,c'), isEmpty);
    });

    test('单字符行无 gap', () {
      expect(cjkJustifyGapOffsets('a'), isEmpty);
      expect(cjkJustifyGapOffsets('中'), isEmpty);
    });
  });

  group('S3 断言：参数化三组目标宽（纯中文）', () {
    setUpAll(_loadFont);

    for (final target in [330.0, 350.0, 390.0]) {
      test('目标宽 ${target.toInt()}：宽度误差 / 末字不额外加距 / 字框不重叠', () {
        final layout = _layout(_cjk, target);
        expect(layout.lineCount, greaterThan(1), reason: '需要非末行才能 justify');
        final line = layout.lines.first;
        final lineText = layout.text.substring(line.start, line.end);
        final painter = _justifiedFirstLine(layout);
        _expectWidth(painter, target);

        final boxes = _charBoxes(painter, lineText.length);
        _expectNoOverlap(boxes);

        // 末字不在 gap 集合：盒宽仍是单字 advance（16），右缘不超目标宽 1px。
        final gaps = cjkJustifyGapOffsets(lineText);
        expect(gaps.last, lessThan(lineText.length - 1));
        final last = boxes.last;
        expect(last.right - last.left, closeTo(16, 1.0));
        expect(last.right, lessThanOrEqualTo(target + 1.0));
      });
    }
  });

  group('S3 断言：参数化混排目标宽', () {
    setUpAll(_loadFont);

    for (final target in [210.0, 230.0]) {
      test('目标宽 ${target.toInt()}：宽度误差 / 字框不重叠', () {
        final layout = _layout(_mixed, target);
        expect(layout.lineCount, greaterThan(1));
        final lineText = layout.text.substring(
          layout.lines.first.start,
          layout.lines.first.end,
        );
        final painter = _justifiedFirstLine(layout);
        _expectWidth(painter, target);
        _expectNoOverlap(_charBoxes(painter, lineText.length));
      });
    }
  });

  group('S3 对比：整行加字距会在末字后多出 ls', () {
    setUpAll(_loadFont);

    test('gap 方案末字起点比整行方案右移约 ls', () {
      const target = 330.0;
      final layout = _layout(_cjk, target);
      final line = layout.lines.first;
      final lineText = layout.text.substring(line.start, line.end);
      final baseStyle = TextLayoutEngine.textStyleFor(_justifyStyle());
      final gaps = cjkJustifyGapOffsets(lineText);
      final ls = justifyGapSpacing(line.justifyExtra, gaps.length);

      final gapPainter = _justifiedFirstLine(layout);
      final wholePainter = TextPainter(
        text: TextSpan(
          text: lineText,
          style: baseStyle.copyWith(
            letterSpacing:
                (baseStyle.letterSpacing ?? 0) +
                justifyGapSpacing(line.justifyExtra, lineText.length),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      // 两种方案总宽都接近目标宽，差别在末字位置：整行方案把最后一个 ls 留在末字之后。
      expect((gapPainter.width - target).abs(), lessThan(1.0));
      expect((wholePainter.width - target).abs(), lessThan(1.0));
      final gapLast = gapPainter
          .getOffsetForCaret(
            TextPosition(offset: lineText.length - 1),
            Rect.zero,
          )
          .dx;
      final wholeLast = wholePainter
          .getOffsetForCaret(
            TextPosition(offset: lineText.length - 1),
            Rect.zero,
          )
          .dx;
      expect(
        gapLast - wholeLast,
        closeTo(ls, 0.6),
        reason: 'gap 方案把尾部 ls 移到了字符之间（ls=$ls）',
      );
    });
  });

  test('justifyGapSpacing 均分余量', () {
    expect(justifyGapSpacing(19, 19), 1.0);
    expect(justifyGapSpacing(16, 19), closeTo(16 / 19, 1e-9));
    expect(justifyGapSpacing(0, 19), 0);
    expect(justifyGapSpacing(10, 0), 0);
  });
}
