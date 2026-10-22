// S3 补充：整行 letterSpacing 与“按可分配间隙 + 单字符 SpanStyle”对比
//
// 运行：flutter test test/s3_gap_result_test.dart
// 输出：s3-gap-result.json
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const String kFontPath =
    '../../../test_fonts/SourceHanSerifSC-Regular.otf';
const String kFontFamily = 'S3GAP';
const double kFontSize = 16;
const String kPureCjk = '一二三四五六七八九十一二三四五六七八九十';
const String kMixed = '中文English混排测试继续排';
const List<double> kTargets = [336, 400];

Future<void> _loadFont() async {
  final bytes = await File(kFontPath).readAsBytes();
  await (FontLoader(kFontFamily)
        ..addFont(Future.value(ByteData.sublistView(bytes))))
      .load();
}

bool _isLatinWordPart(String c) {
  final r = c.runes.first;
  return (r >= 0x30 && r <= 0x39) || (r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A);
}

/// 行内可分配间隙的索引：字符 i 与 i+1 之间。
List<int> _gapIndices(String text) {
  final runes = text.runes.toList();
  final out = <int>[];
  for (var i = 0; i + 1 < runes.length; i++) {
    final c1 = String.fromCharCode(runes[i]);
    final c2 = String.fromCharCode(runes[i + 1]);
    if (c1 == '\n' || c2 == '\n') continue;
    if (_isLatinWordPart(c1) && _isLatinWordPart(c2)) continue;
    out.add(i);
  }
  return out;
}

TextPainter _layoutWholeRun(String text, double target, double baseSpacing) {
  final natural = _layoutPlain(text).width;
  final ls = (target - natural) / text.length;
  return TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: kFontFamily,
        fontSize: kFontSize,
        letterSpacing: baseSpacing + ls,
      ),
    ),
    textDirection: TextDirection.ltr,
    locale: const Locale('zh', 'CN'),
  )..layout(maxWidth: target);
}

TextPainter _layoutPerGap(String text, double target, double baseSpacing) {
  final natural = _layoutPlain(text).width;
  final gaps = _gapIndices(text);
  final ls = (target - natural) / gaps.length;
  final runes = text.runes.map(String.fromCharCode).toList();
  final spans = <InlineSpan>[];
  final gapSet = gaps.toSet();
  for (var i = 0; i < runes.length; i++) {
    spans.add(TextSpan(
      text: runes[i],
      style: TextStyle(
        fontFamily: kFontFamily,
        fontSize: kFontSize,
        letterSpacing: gapSet.contains(i) ? baseSpacing + ls : baseSpacing,
      ),
    ));
  }
  return TextPainter(
    text: TextSpan(children: spans),
    textDirection: TextDirection.ltr,
    locale: const Locale('zh', 'CN'),
  )..layout(maxWidth: target);
}

TextPainter _layoutPlain(String text, {double letterSpacing = 0}) {
  return TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: kFontFamily,
        fontSize: kFontSize,
        letterSpacing: letterSpacing,
      ),
    ),
    textDirection: TextDirection.ltr,
    locale: const Locale('zh', 'CN'),
  )..layout();
}

Map<String, Object?> _measure(
  String text,
  double target,
  TextPainter Function() build,
) {
  final p = build();
  final metrics = p.computeLineMetrics();
  final lastIndex = text.length - 1;
  final lastCaret = p.getOffsetForCaret(TextPosition(offset: lastIndex), Rect.zero);
  final endCaret = p.getOffsetForCaret(TextPosition(offset: text.length), Rect.zero);
  final lastBox = p.getBoxesForSelection(
    TextSelection(baseOffset: lastIndex, extentOffset: text.length),
    boxHeightStyle: ui.BoxHeightStyle.tight,
  ).first;
  final firstBox = p.getBoxesForSelection(
    const TextSelection(baseOffset: 0, extentOffset: 1),
    boxHeightStyle: ui.BoxHeightStyle.tight,
  ).first;
  return {
    'width': p.width,
    'lineCount': metrics.length,
    'lineWidths': metrics.map((m) => m.width).toList(),
    'firstBoxLeft': firstBox.left,
    'lastCaretX': lastCaret.dx,
    'endCaretX': endCaret.dx,
    'lastBoxLeft': lastBox.left,
    'lastBoxRight': lastBox.right,
    'rightGap': target - lastBox.right,
    'widthError': (p.width - target).abs(),
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFont);

  test('整行 vs 按 gap 分配', () {
    final cases = <Map<String, Object?>>[];
    var maxGapError = 0.0;
    var maxBoxOverlap = 0.0;

    for (final text in <String>[kPureCjk, kMixed]) {
      final natural = _layoutPlain(text).width;
      final gaps = _gapIndices(text);
      for (final target in kTargets) {
        final whole = _measure(text, target,
            () => _layoutWholeRun(text, target, 0));
        final perGap = _measure(text, target,
            () => _layoutPerGap(text, target, 0));

        if ((perGap['widthError'] as double) > maxGapError) {
          maxGapError = perGap['widthError'] as double;
        }

        // 字框重叠检查（gap 方案）
        final p = _layoutPerGap(text, target, 0);
        final boxes = <double>[];
        for (var i = 0; i < text.length; i++) {
          final b = p.getBoxesForSelection(
            TextSelection(baseOffset: i, extentOffset: i + 1),
            boxHeightStyle: ui.BoxHeightStyle.tight,
          ).first;
          boxes.add(b.right);
        }
        var overlap = 0.0;
        for (var i = 0; i + 1 < boxes.length; i++) {
          final next = p.getBoxesForSelection(
            TextSelection(baseOffset: i + 1, extentOffset: i + 2),
            boxHeightStyle: ui.BoxHeightStyle.tight,
          ).first;
          final o = boxes[i] - next.left;
          if (o > overlap) overlap = o;
        }
        if (overlap > maxBoxOverlap) maxBoxOverlap = overlap;

        cases.add({
          'text': text,
          'target': target,
          'naturalWidth': natural,
          'gapCount': gaps.length,
          'wholeRun': whole,
          'perGap': perGap,
        });
      }
    }

    final output = {
      'environment': {
        'flutter': '3.47.5',
        'dart': '3.13.4',
        'platform': Platform.operatingSystem,
        'font': kFontPath,
        'fontSize': kFontSize,
        'measuredAt': DateTime.now().toIso8601String(),
      },
      'cases': cases,
      'summary': {
        'maxGapWidthError': maxGapError,
        'maxGapBoxOverlap': maxBoxOverlap,
      },
    };

    File('s3-gap-result.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(output),
    );

    for (final c in cases) {
      final w = c['wholeRun'] as Map<String, Object?>;
      final g = c['perGap'] as Map<String, Object?>;
      print('target=${c['target']} text=${(c['text'] as String).length}字 '
          'gaps=${c['gapCount']}');
      print('  whole: width=${w['width']} error=${w['widthError']} '
          'lastLeft=${w['lastBoxLeft']} lastCaret=${w['lastCaretX']} '
          'rightGap=${w['rightGap']}');
      print('  gap  : width=${g['width']} error=${g['widthError']} '
          'lastLeft=${g['lastBoxLeft']} lastCaret=${g['lastCaretX']} '
          'rightGap=${g['rightGap']}');
    }
    print('maxGapWidthError=$maxGapError maxGapBoxOverlap=$maxBoxOverlap');

    expect(maxGapError, lessThan(1.0), reason: 'gap 方案宽度误差 <1px');
    expect(maxBoxOverlap, lessThanOrEqualTo(0.01), reason: '字框不应重叠');

    // 间隙数与“末字起点更靠右”是 gap 方案相对整行方案的核心差异
    for (final c in cases) {
      final text = c['text'] as String;
      final target = c['target'] as double;
      final natural = c['naturalWidth'] as double;
      final gaps = c['gapCount'] as int;
      final whole = c['wholeRun'] as Map<String, Object?>;
      final perGap = c['perGap'] as Map<String, Object?>;
      final expectedGaps = text == kPureCjk ? 19 : 9;
      expect(gaps, expectedGaps, reason: '可分配间隙数');
      if (target > natural) {
        expect(
          (perGap['lastCaretX'] as double) > (whole['lastCaretX'] as double),
          isTrue,
          reason: 'gap 方案末字应比整行方案更靠右：$text target=$target',
        );
      }
    }
  });
}
