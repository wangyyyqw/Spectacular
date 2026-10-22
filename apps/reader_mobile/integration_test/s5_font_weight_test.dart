import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

Future<Uint8List> _loadAsset(String name) async {
  final data = await rootBundle.load('assets/test_fonts/$name');
  return data.buffer.asUint8List();
}

Future<void> _loadFamily(String family, List<Uint8List> fonts) async {
  final loader = FontLoader(family);
  for (final bytes in fonts) {
    loader.addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

Future<Uint8List> _render(
  String family,
  FontWeight weight, {
  int width = 320,
  int height = 120,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  final painter = TextPainter(
    text: TextSpan(
      text: '粗体测试 ABC 123',
      style: TextStyle(
        fontFamily: family,
        fontSize: 48,
        fontWeight: weight,
        color: const ui.Color(0xFF000000),
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(canvas, const ui.Offset(8, 8));
  painter.dispose();

  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  if (data == null) {
    throw StateError('无法读取渲染像素');
  }
  return data.buffer.asUint8List();
}

int _diffPixels(Uint8List a, Uint8List b) {
  if (a.length != b.length) {
    throw StateError('尺寸不一致');
  }
  var diff = 0;
  for (var i = 0; i < a.length; i += 4) {
    if (a[i] != b[i] ||
        a[i + 1] != b[i + 1] ||
        a[i + 2] != b[i + 2] ||
        a[i + 3] != b[i + 3]) {
      diff++;
    }
  }
  return diff;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('S5 同 family 多字重在模拟器/桌面上按 fontWeight 选中 bold', (tester) async {
    final regular = await _loadAsset('SourceHanSerifSC-Regular.otf');
    final bold = await _loadAsset('SourceHanSerifSC-Bold.otf');

    await _loadFamily('S5Multi', <Uint8List>[regular, bold]);
    await _loadFamily('S5OnlyRegular', <Uint8List>[regular]);

    final multi400 = await _render('S5Multi', FontWeight.w400);
    final multi700 = await _render('S5Multi', FontWeight.w700);
    final only400 = await _render('S5OnlyRegular', FontWeight.w400);
    final only700 = await _render('S5OnlyRegular', FontWeight.w700);

    final regularControl = _diffPixels(multi400, only400);
    final boldFaceEffect = _diffPixels(multi700, only700);

    // ignore: avoid_print
    print(
      'S5 device=${defaultTargetPlatform.name} regular_control=$regularControl '
      'bold_face_effect=$boldFaceEffect',
    );

    expect(regularControl, 0, reason: '同一 regular 字体在不同 family 名下应渲染一致');
    expect(
      boldFaceEffect,
      greaterThan(0),
      reason: '加载 bold 后 700 渲染应不同于仅 regular',
    );
  });
}
