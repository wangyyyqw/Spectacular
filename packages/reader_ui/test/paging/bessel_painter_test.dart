import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/paging/bessel_geometry.dart';
import 'package:reader_ui/paging/bessel_painter.dart';

const _size = Size(200, 300);

Future<ByteData> _render({bool top = false}) async {
  final paperRecorder = ui.PictureRecorder();
  Canvas(paperRecorder).drawColor(const Color(0xFFFFFFFF), BlendMode.src);
  final paperPicture = paperRecorder.endRecording();
  final paper = await paperPicture.toImage(200, 300);
  paperPicture.dispose();
  final recorder = ui.PictureRecorder();
  BesselPainter(paperColor: const Color(0xFFFFFFFF)).paint(
    Canvas(recorder),
    BesselGeometry.resolve(_size, Offset(120, top ? 100 : 200), top: top)!,
    paper,
    paper,
    rtl: false,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(200, 300);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  paper.dispose();
  return data!;
}

int _brightness(ByteData data, Offset point, {bool mirrored = false}) {
  final x = point.dx.floor();
  final y = mirrored ? 299 - point.dy.floor() : point.dy.floor();
  return data.getUint8((y * 200 + x) * 4);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final geometry = BesselGeometry.resolve(_size, const Offset(120, 200))!;
  final crease = (geometry.d + geometry.i) / 2;
  final normal = (geometry.a - geometry.f) / (geometry.a - geometry.f).distance;

  test('下角纸背在折痕处变暗，向抓取点恢复纸色', () async {
    final data = await _render();
    final near = crease + normal * 4;
    final far = crease + normal * 25;
    final back = geometry.backPath(geometry.frontPath());

    expect(back.contains(near), isTrue);
    expect(back.contains(far), isTrue);
    expect(_brightness(data, near), lessThan(_brightness(data, far) - 15));
    expect(_brightness(data, far), 255);
  });

  test('底页投影紧贴折痕，远离折痕后恢复纸色', () async {
    final data = await _render();
    final near = crease - normal * 4;
    final far = crease - normal * 40;

    expect(_brightness(data, near), lessThan(225));
    expect(_brightness(data, far), 255);
  });

  test('上下角纸背渐变和底页投影相互镜像', () async {
    final bottom = await _render();
    final top = await _render(top: true);

    for (final distance in <double>[-25, -4, 4, 12, 25]) {
      final point = crease + normal * distance;
      expect(
        _brightness(top, point, mirrored: true),
        closeTo(_brightness(bottom, point), 2),
        reason: '距折痕 $distance 像素处的明暗应一致',
      );
    }
  });
}
