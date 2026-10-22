// S3：letterSpacing 做 CJK 两端对齐的精度
//
// 运行：flutter test test/s3_result_test.dart
// 输出：s3-result.json
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const String kFontPath =
    '../../../参考/anx-reader-develop/assets/fonts/SourceHanSerifSC-Regular.otf';
const String kFontFamily = 'S3CJK';
const double kFontSize = 16;
const String kText = '一二三四五六七八九十一二三四五六七八九十'; // 20 个全角字
const List<double> kTargets = [320, 336, 400];

Future<void> _loadFont() async {
  final bytes = await File(kFontPath).readAsBytes();
  await (FontLoader(kFontFamily)
        ..addFont(Future.value(ByteData.sublistView(bytes))))
      .load();
}

TextPainter _layout({
  required double maxWidth,
  double letterSpacing = 0,
  TextAlign align = TextAlign.left,
}) {
  return TextPainter(
    text: TextSpan(
      text: kText,
      style: TextStyle(
        fontFamily: kFontFamily,
        fontSize: kFontSize,
        letterSpacing: letterSpacing,
      ),
    ),
    textDirection: TextDirection.ltr,
    textAlign: align,
    locale: const Locale('zh', 'CN'),
  )..layout(maxWidth: maxWidth);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_loadFont);

  test('S3 CJK 字距对齐', () {
    final natural = _layout(maxWidth: double.infinity);
    final naturalWidth = natural.width;
    final charCount = kText.length;

    final cases = <Map<String, Object?>>[];
    var maxWidthError = 0.0;
    var maxOverlap = 0.0;
    var maxCaretGapDelta = 0.0;

    for (final target in kTargets) {
      final extra = target - naturalWidth;
      final ls = extra / charCount;
      final p = _layout(maxWidth: target, letterSpacing: ls);
      final metrics = p.computeLineMetrics();
      final widthError = (p.width - target).abs();
      if (widthError > maxWidthError) maxWidthError = widthError;

      // 字框重叠检测
      var overlap = 0.0;
      final boxes = <Map<String, double>>[];
      for (var i = 0; i < charCount; i++) {
        final list = p.getBoxesForSelection(
          TextSelection(baseOffset: i, extentOffset: i + 1),
          boxHeightStyle: ui.BoxHeightStyle.tight,
        );
        if (list.isEmpty) continue;
        final box = list.first;
        boxes.add({'index': i.toDouble(), 'left': box.left, 'right': box.right, 'width': box.right - box.left});
      }
      for (var i = 0; i + 1 < boxes.length; i++) {
        final cur = boxes[i];
        final next = boxes[i + 1];
        final o = cur['right']! - next['left']!;
        if (o > overlap) overlap = o;
      }
      if (overlap > maxOverlap) maxOverlap = overlap;

      final lastBox = p.getBoxesForSelection(
        TextSelection(baseOffset: charCount - 1, extentOffset: charCount),
        boxHeightStyle: ui.BoxHeightStyle.tight,
      ).first;
      final firstBox = p.getBoxesForSelection(
        const TextSelection(baseOffset: 0, extentOffset: 1),
        boxHeightStyle: ui.BoxHeightStyle.tight,
      ).first;
      final rightGap = target - lastBox.right;

      // 逐字 caret 间距
      var minGap = double.infinity;
      var maxGap = -double.infinity;
      for (var i = 0; i < charCount; i++) {
        final a = p.getOffsetForCaret(TextPosition(offset: i), Rect.zero);
        final b = p.getOffsetForCaret(TextPosition(offset: i + 1), Rect.zero);
        final gap = b.dx - a.dx;
        if (gap < minGap) minGap = gap;
        if (gap > maxGap) maxGap = gap;
      }
      final caretGapDelta = maxGap - minGap;
      if (caretGapDelta > maxCaretGapDelta) maxCaretGapDelta = caretGapDelta;

      cases.add({
        'target': target,
        'naturalWidth': naturalWidth,
        'extra': extra,
        'letterSpacing': ls,
        'measuredWidth': p.width,
        'widthError': widthError,
        'lineCount': metrics.length,
        'lineWidths': metrics.map((m) => m.width).toList(),
        'maxBoxOverlap': overlap,
        'firstBoxLeft': firstBox.left,
        'lastBoxRight': lastBox.right,
        'rightGap': rightGap,
        'caretMinGap': minGap,
        'caretMaxGap': maxGap,
        'firstBoxes': boxes.take(3).toList(),
      });
    }

    // 系统 TextAlign.justify 对纯中文的效果
    final justify = _layout(maxWidth: 400, align: TextAlign.justify);
    final justifyWidth = justify.width;
    final justifyLines =
        justify.computeLineMetrics().map((m) => m.width).toList();

    final output = {
      'environment': {
        'flutter': '3.47.5',
        'dart': '3.13.4',
        'platform': Platform.operatingSystem,
        'font': kFontPath,
        'fontSize': kFontSize,
        'text': kText,
        'charCount': charCount,
        'measuredAt': DateTime.now().toIso8601String(),
      },
      'naturalWidth': naturalWidth,
      'cases': cases,
      'textAlignJustifyOnly': {
        'width': justifyWidth,
        'lineWidths': justifyLines,
      },
      'summary': {
        'maxWidthError': maxWidthError,
        'maxBoxOverlap': maxOverlap,
        'maxCaretGapDelta': maxCaretGapDelta,
      },
    };

    File('s3-result.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(output),
    );

    print('naturalWidth=$naturalWidth');
    for (final c in cases) {
      print('target=${c['target']} ls=${c['letterSpacing']} '
          'width=${c['measuredWidth']} error=${c['widthError']} '
          'overlap=${c['maxBoxOverlap']} rightGap=${c['rightGap']} '
          'caretGap=[${c['caretMinGap']}, ${c['caretMaxGap']}]');
    }
    print('TextAlign.justify only: width=$justifyWidth lines=$justifyLines');
    print('maxWidthError=$maxWidthError maxBoxOverlap=$maxOverlap '
        'maxCaretGapDelta=$maxCaretGapDelta');

    for (final c in cases) {
      expect((c['lineCount'] as int), 1, reason: '单行不应换行：$c');
    }
    expect(maxWidthError, lessThan(1.0), reason: '行宽误差应 < 1px');
    expect(maxOverlap, lessThanOrEqualTo(0.01), reason: '字符框不应重叠');
  });
}
