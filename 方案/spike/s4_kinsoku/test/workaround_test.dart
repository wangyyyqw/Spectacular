// 附加实验：给省略号对插入零宽粘合字符，验证引擎断行是否被阻止。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const String kFontPath =
    '../../../参考/anx-reader-develop/assets/fonts/SourceHanSerifSC-Regular.otf';

late double unit;

Future<void> loadFont() async {
  final bytes = await File(kFontPath).readAsBytes();
  await (FontLoader('S4CJK')..addFont(Future.value(ByteData.sublistView(bytes))))
      .load();
}

TextPainter layout(String text, double width) => TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(fontFamily: 'S4CJK', fontSize: 16, height: 1),
      ),
      textDirection: TextDirection.ltr,
      locale: const Locale('zh', 'CN'),
    )..layout(maxWidth: width);

List<String> lines(String text, double width) {
  final p = layout(text, width);
  final out = <String>[];
  var start = 0;
  for (var i = 0; i < p.computeLineMetrics().length && start < text.length; i++) {
    final r = p.getLineBoundary(TextPosition(offset: start));
    final end = r.end <= start ? text.length : r.end.clamp(0, text.length);
    out.add(text.substring(start, end));
    start = end;
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadFont();
    final p = TextPainter(
      text: const TextSpan(text: '中', style: TextStyle(fontFamily: 'S4CJK', fontSize: 16)),
      textDirection: TextDirection.ltr,
    )..layout();
    unit = p.width;
  });

  test('省略号宽度扫描', () {
    for (var u = 1; u <= 6; u++) {
      print('u=$u -> ${lines('「……」', u * unit)}');
    }
  });

  test('省略号粘合对比', () {
    for (final variant in <String, String>{
      '原始': '「……」',
      'U+2060': '「…\u2060…」',
      'U+FEFF': '「…\uFEFF…」',
    }.entries) {
      final l = lines(variant.value, 2 * unit);
      print('${variant.key}: $l  (width=${layout(variant.value, 2 * unit).width})');
    }
  });
}
