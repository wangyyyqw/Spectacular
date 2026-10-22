import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

/// 生成指定尺寸的 PNG 字节，用于解码实验。
Future<Uint8List> _makePng(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF336699),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  if (data == null) {
    throw StateError('PNG 编码失败');
  }
  return data.buffer.asUint8List();
}

Future<ui.Image> _decode(Uint8List bytes, {int? targetWidth}) async {
  final codec = await ui.instantiateImageCodec(bytes, targetWidth: targetWidth);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  codec.dispose();
  return image;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('S7 原始图 1000×500 的基准尺寸', () async {
    final bytes = await _makePng(1000, 500);
    final image = await _decode(bytes);
    // ignore: avoid_print
    print('S7 original width=${image.width} height=${image.height}');
    expect(image.width, 1000);
    expect(image.height, 500);
    image.dispose();
  });

  test('S7 targetWidth=500 时按比例降采样', () async {
    final bytes = await _makePng(1000, 500);
    final image = await _decode(bytes, targetWidth: 500);
    // ignore: avoid_print
    print('S7 target500 width=${image.width} height=${image.height}');
    expect(image.width, 500);
    expect(image.height, 250);
    image.dispose();
  });

  test('S7 targetWidth=200 时按比例降采样', () async {
    final bytes = await _makePng(1000, 500);
    final image = await _decode(bytes, targetWidth: 200);
    // ignore: avoid_print
    print('S7 target200 width=${image.width} height=${image.height}');
    expect(image.width, 200);
    expect(image.height, 100);
    image.dispose();
  });

  test('S7 理论解码内存随 targetWidth 平方下降', () async {
    const originalBytes = 1000 * 500 * 4;
    const targetBytes = 500 * 250 * 4;
    // ignore: avoid_print
    print(
      'S7 memory original=${originalBytes}B target=${targetBytes}B '
      'ratio=${(targetBytes / originalBytes * 100).toStringAsFixed(1)}%',
    );
    expect(targetBytes * 4, originalBytes);
  });
}
