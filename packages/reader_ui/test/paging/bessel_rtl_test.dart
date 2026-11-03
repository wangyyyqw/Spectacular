import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/paging/bessel_geometry.dart';
import 'package:reader_ui/paging/bessel_painter.dart';

const Size _size = Size(200, 300);

Future<ui.Image> _splitImage(Color left, Color right) {
  const width = 200;
  const height = 300;
  final pixels = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final color = x < width / 2 ? left : right;
      final offset = (y * width + x) * 4;
      pixels[offset] = (color.r * 255).round();
      pixels[offset + 1] = (color.g * 255).round();
      pixels[offset + 2] = (color.b * 255).round();
      pixels[offset + 3] = 255;
    }
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

Future<ByteData> _render({required bool rtl}) async {
  final bottom = await _splitImage(
    const Color(0xFFFF0000),
    const Color(0xFF0000FF),
  );
  final paper = await _splitImage(
    const Color(0xFFFFFF00),
    const Color(0xFF00FF00),
  );
  final geometry = BesselGeometry.resolve(
    _size,
    const Offset(130, 180),
  )!;
  final recorder = ui.PictureRecorder();
  BesselPainter(paperColor: const Color(0xFFFFFFFF)).paint(
    Canvas(recorder),
    geometry,
    bottom,
    paper,
    rtl: rtl,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    _size.width.toInt(),
    _size.height.toInt(),
  );
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  bottom.dispose();
  paper.dispose();
  return data!;
}

List<int> _pixel(ByteData data, int x, int y) {
  final offset = (y * _size.width.toInt() + x) * 4;
  return List<int>.generate(4, (index) => data.getUint8(offset + index));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('RTL 只镜像几何，底页和活动纸方向保持正向', () async {
    final ltr = await _render(rtl: false);
    final rtl = await _render(rtl: true);

    expect(
      _pixel(ltr, 10, 280),
      <int>[255, 255, 0, 255],
      reason: 'LTR 左下被活动纸覆盖',
    );
    expect(
      _pixel(rtl, 10, 280),
      <int>[255, 0, 0, 255],
      reason: 'RTL 镜像后底页左侧仍使用图片左侧',
    );
    expect(
      _pixel(rtl, 150, 280),
      <int>[0, 255, 0, 255],
      reason: 'RTL 活动纸右侧仍使用图片右侧',
    );
  });
}
