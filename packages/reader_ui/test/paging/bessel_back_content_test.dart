import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/paging/bessel_geometry.dart';
import 'package:reader_ui/paging/bessel_painter.dart';

const _size = Size(200, 300);

Future<ui.Image> _image(int ratio, void Function(Canvas) draw) async {
  final recorder = ui.PictureRecorder();
  draw(Canvas(recorder)..scale(ratio.toDouble()));
  final picture = recorder.endRecording();
  final image = await picture.toImage(200 * ratio, 300 * ratio);
  picture.dispose();
  return image;
}

Offset _mirror(Offset point, bool rtl) =>
    rtl ? Offset(_size.width - point.dx, point.dy) : point;

Offset _source(BesselGeometry geometry, Offset point) {
  final matrix = geometry.reflection();
  return Offset(
    matrix[0] * point.dx + matrix[4] * point.dy + matrix[12],
    matrix[1] * point.dx + matrix[5] * point.dy + matrix[13],
  );
}

Future<ui.Image> _paper(
  BesselGeometry geometry,
  int ratio,
  bool rtl,
  Color paperColor, {
  Rect? mark,
}) {
  return _image(ratio, (canvas) {
    canvas.drawColor(paperColor, BlendMode.src);
    if (mark == null) return;
    final center = _mirror(_source(geometry, mark.center), rtl);
    final normal = geometry.a - geometry.f;
    canvas.translate(center.dx, center.dy);
    canvas.rotate(math.atan2(normal.dy, rtl ? -normal.dx : normal.dx));
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset.zero,
        width: mark.width,
        height: mark.height,
      ),
      Paint()
        ..color = paperColor.r < 0.5
            ? const Color(0xFFFFFFFF)
            : const Color(0xFF000000),
    );
  });
}

Future<ByteData> _render(
  BesselGeometry geometry,
  int ratio,
  bool rtl,
  Color paperColor, {
  Rect? mark,
}) async {
  final paper = await _paper(geometry, ratio, rtl, paperColor, mark: mark);
  final bottom = await _image(
    ratio,
    (canvas) => canvas.drawColor(const Color(0xFFFF0000), BlendMode.src),
  );
  final output = await _image(
    ratio,
    (canvas) =>
        BesselPainter(paperColor: paperColor)
            .paint(canvas, geometry, bottom, paper, rtl: rtl),
  );
  final data = await output.toByteData(format: ui.ImageByteFormat.rawRgba);
  output.dispose();
  paper.dispose();
  bottom.dispose();
  return data!;
}

int _red(ByteData data, Offset point, int ratio) => data.getUint8(
  ((point.dy * ratio).floor() * 200 * ratio + (point.dx * ratio).floor()) * 4,
);

double _markWidth(
  (ByteData, ByteData) images,
  Offset center,
  Offset direction,
  int ratio,
) {
  var samples = 0;
  for (var step = -64; step <= 64; step++) {
    final point = center + direction * (step / 4);
    if ((_red(images.$1, point, ratio) - _red(images.$2, point, ratio)).abs() >
        25) {
      samples++;
    }
  }
  return samples / 4;
}

void _expectMarkSize(
  (ByteData, ByteData) images,
  Offset center,
  Offset normal,
  int ratio,
) {
  expect(_markWidth(images, center, normal, ratio), closeTo(12, 1.5));
  expect(
    _markWidth(images, center, Offset(-normal.dy, normal.dx), ratio),
    closeTo(10, 1.5),
  );
  for (final sign in [-1.0, 1.0]) {
    final outside = center + normal * (8 * sign);
    expect(
      (_red(images.$1, outside, ratio) - _red(images.$2, outside, ratio)).abs(),
      lessThan(8),
      reason: '镜像标记不能偏移或扩大到原尺寸以外',
    );
  }
  expect(_red(images.$2, center, ratio), inInclusiveRange(190, 210));
}

Future<void> _checkCorner(bool top, bool rtl, int ratio) async {
  final geometry = BesselGeometry.resolve(
    _size,
    Offset(120, top ? 100 : 200),
    top: top,
  )!;
  final normal = (geometry.a - geometry.f) / (geometry.a - geometry.f).distance;
  final center = (geometry.d + geometry.i) / 2 + normal * 28;
  final blank = await _render(geometry, ratio, rtl, const Color(0xFFFFFFFF));
  final marked = await _render(
    geometry,
    ratio,
    rtl,
    const Color(0xFFFFFFFF),
    mark: Rect.fromCenter(center: center, width: 12, height: 10),
  );
  _expectMarkSize(
    (blank, marked),
    _mirror(center, rtl),
    Offset(rtl ? -normal.dx : normal.dx, normal.dy),
    ratio,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final top in [false, true]) {
    for (final rtl in [false, true]) {
      for (final ratio in [1, 3]) {
        test(
          '${top ? '上' : '下'}角纸背 ${rtl ? '左' : '右'}侧 $ratio 倍位图保持内容尺寸与位置且明显淡化',
          () => _checkCorner(top, rtl, ratio),
        );
      }
    }
  }

  for (final paperColor in [const Color(0xFFF4EEDF), const Color(0xFF202020)]) {
    test('纸背在纸色 $paperColor 下减少油墨反差，保持不透明', () async {
      final geometry = BesselGeometry.resolve(_size, const Offset(120, 200))!;
      final normal =
          (geometry.a - geometry.f) / (geometry.a - geometry.f).distance;
      final center = (geometry.d + geometry.i) / 2 + normal * 28;
      final data = await _render(
        geometry,
        1,
        false,
        paperColor,
        mark: Rect.fromCenter(center: center, width: 12, height: 10),
      );
      final expected =
          paperColor.r * 255 * 0.78 + (paperColor.r < 0.5 ? 255 : 0) * 0.22;
      expect(_red(data, center, 1), closeTo(expected, 3));
      final alphaIndex = (center.dy.floor() * 200 + center.dx.floor()) * 4 + 3;
      expect(data.getUint8(alphaIndex), 255);
    });
  }
}
