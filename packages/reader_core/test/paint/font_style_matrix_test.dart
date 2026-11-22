import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show ByteData, FontLoader;
import 'package:flutter_test/flutter_test.dart';

/// P7-08：S5 补测 italic 维度。
///
/// S5 只实测了 regular+bold；字体注册模型按 family→(weight, italic)
/// 二元组组织。CJK 测试字体无真斜体文件，验证口径改为
/// 「italic 维度被引擎消费」：仅注册 regular 时 `fontStyle: italic` 会
/// 触发合成倾斜（synthetic oblique），像素差 >0 即证明 (weight, italic)
/// 二元组被完整传递；权重维度在 italic 之下仍能选面。
Future<int> _diffPixels(ui.Image a, ui.Image b) async {
  final bytesA = await a.toByteData();
  final bytesB = await b.toByteData();
  a.dispose();
  b.dispose();
  if (bytesA == null || bytesB == null) {
    return -1;
  }
  var diff = 0;
  for (var i = 0; i < bytesA.lengthInBytes; i += 4) {
    if (bytesA.getUint8(i) != bytesB.getUint8(i) ||
        bytesA.getUint8(i + 1) != bytesB.getUint8(i + 1) ||
        bytesA.getUint8(i + 2) != bytesB.getUint8(i + 2) ||
        bytesA.getUint8(i + 3) != bytesB.getUint8(i + 3)) {
      diff += 1;
    }
  }
  return diff;
}

Future<ui.Image> _render({
  required String family,
  int weight = 400,
  bool italic = false,
}) async {
  const text = '斜体补测 ABC 123 中文';
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: family,
        fontSize: 20,
        fontWeight: FontWeight.values[(weight / 100).round() - 1],
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        color: const ui.Color(0xFF000000),
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: 400);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  painter.paint(canvas, ui.Offset.zero);
  final image = await recorder.endRecording().toImage(420, 60);
  painter.dispose();
  return image;
}

bool fontsLoaded = false;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final regular = File('../../test_fonts/SourceHanSerifSC-Regular.otf');
    final bold = File('../../test_fonts/SourceHanSerifSC-Bold.otf');
    if (!regular.existsSync() || !bold.existsSync()) {
      return;
    }
    final loader = FontLoader('S5StyleMatrix')
      ..addFont(Future<ByteData>.value(ByteData.view(regular.readAsBytesSync().buffer)))
      ..addFont(Future<ByteData>.value(ByteData.view(bold.readAsBytesSync().buffer)));
    await loader.load();
    fontsLoaded = true;
  });

  test('对照：同参数两次渲染逐像素一致', () async {
    final a = await _render(family: 'S5StyleMatrix');
    final b = await _render(family: 'S5StyleMatrix');
    expect(await _diffPixels(a, b), 0);
  });

  test('italic 维度被消费：仅 regular 时合成倾斜生效（像素差 >0）', () async {
    final normal = await _render(family: 'S5StyleMatrix');
    final italic = await _render(family: 'S5StyleMatrix', italic: true);
    final diff = await _diffPixels(normal, italic);
    if (!fontsLoaded) {
      // ignore: avoid_print
      print('SKIP 本地字体缺失');
      return;
    }
    expect(diff, greaterThan(100), reason: 'italic 未触发合成倾斜，(weight,italic) 二元组可能被丢弃');
  });

  test('italic 之下权重维度仍选面：700-italic 与 400-italic 有差异', () async {
    if (!fontsLoaded) {
      // ignore: avoid_print
      print('SKIP 本地字体缺失');
      return;
    }
    final regularItalic = await _render(family: 'S5StyleMatrix', italic: true);
    final boldItalic = await _render(
      family: 'S5StyleMatrix',
      weight: 700,
      italic: true,
    );
    final diff = await _diffPixels(regularItalic, boldItalic);
    expect(diff, greaterThan(100), reason: 'italic 开启后 bold 字面未被选中');
  });

  test('bold-italic 组合同时生效：与 400-normal 双向都有差异', () async {
    if (!fontsLoaded) {
      // ignore: avoid_print
      print('SKIP 本地字体缺失');
      return;
    }
    final plain = await _render(family: 'S5StyleMatrix');
    final boldItalic = await _render(
      family: 'S5StyleMatrix',
      weight: 700,
      italic: true,
    );
    final diff = await _diffPixels(plain, boldItalic);
    expect(diff, greaterThan(100), reason: '粗斜组合渲染与常规体无差异');
  });
}
