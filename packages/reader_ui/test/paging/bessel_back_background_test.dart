import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/paging/bessel_geometry.dart';
import 'package:reader_ui/paging/bessel_painter.dart';

const _size = Size(200, 300);
const _colors = [
  Color(0xFFFF0000),
  Color(0xFF0000FF),
  Color(0xFF00FF00),
  Color(0xFFFF00FF),
];

Future<ui.Image> _image(int ratio, void Function(Canvas) draw) async {
  final recorder = ui.PictureRecorder();
  draw(Canvas(recorder)..scale(ratio.toDouble()));
  final picture = recorder.endRecording();
  final image = await picture.toImage(200 * ratio, 300 * ratio);
  picture.dispose();
  return image;
}

Future<ByteData> _render(
  BesselGeometry geometry,
  bool rtl,
  int ratio,
  bool translucentEdge,
) async {
  final paper = await _image(ratio, (canvas) {
    for (var index = 0; index < _colors.length; index++) {
      canvas.drawRect(
        Rect.fromLTWH((index % 2) * 100, (index ~/ 2) * 150, 100, 150),
        Paint()..color = _colors[index],
      );
    }
    if (translucentEdge) _fadeSnapshotEdge(canvas, ratio);
  });
  final bottom = await _image(
    ratio,
    (canvas) => canvas.drawColor(const Color(0xFF000000), BlendMode.src),
  );
  final output = await _image(
    ratio,
    (canvas) =>
        BesselPainter(paperColor: const Color(0xFFFFFFFF))
            .paint(canvas, geometry, bottom, paper, rtl: rtl),
  );
  final data = await output.toByteData(format: ui.ImageByteFormat.rawRgba);
  output.dispose();
  paper.dispose();
  bottom.dispose();
  return data!;
}

void _fadeSnapshotEdge(Canvas canvas, int ratio) {
  final width = 1 / ratio;
  final paint = Paint()
    ..color = const Color(0x40000000)
    ..blendMode = BlendMode.dstIn;
  for (final rect in [
    Rect.fromLTWH(0, 0, width, 300),
    Rect.fromLTWH(200 - width, 0, width, 300),
    Rect.fromLTWH(0, 0, 200, width),
    Rect.fromLTWH(0, 300 - width, 200, width),
  ]) {
    canvas.drawRect(rect, paint);
  }
}

Offset _source(BesselGeometry geometry, Offset point, bool rtl) {
  final matrix = geometry.reflection();
  final x = matrix[0] * point.dx + matrix[4] * point.dy + matrix[12];
  final y = matrix[1] * point.dx + matrix[5] * point.dy + matrix[13];
  return Offset(rtl ? _size.width - x : x, y);
}

bool _inside(Path path, Offset point) =>
    path.contains(point) &&
    path.contains(point + const Offset(1, 0)) &&
    path.contains(point - const Offset(1, 0)) &&
    path.contains(point + const Offset(0, 1)) &&
    path.contains(point - const Offset(0, 1));

void _expectTexture(ByteData data, Offset point, Offset source, int ratio) {
  final index =
      ((point.dy * ratio).floor() * 200 * ratio + (point.dx * ratio).floor()) *
      4;
  final actual = List.generate(3, (channel) => data.getUint8(index + channel));
  final color = _colors[(source.dy < 150 ? 0 : 2) + (source.dx < 100 ? 0 : 1)];
  final channels = [color.r, color.g, color.b];
  final brightest = actual.reduce((a, b) => a > b ? a : b);
  for (var channel = 0; channel < 3; channel++) {
    // 阴影等比压暗各通道；保留 22% 的原图色差，不能只覆盖纸色。
    expect(
      actual[channel],
      closeTo(brightest * (0.78 + channels[channel] * 0.22), 3),
      reason: '纸背 $point 对应原图 $source，应延展原图纹理并连续淡化',
    );
  }
  expect(data.getUint8(index + 3), 255);
}

Future<(int, int)> _checkCoverage(
  BesselGeometry geometry,
  bool rtl,
  int ratio,
  bool translucentEdge,
) async {
  final back = geometry.backPath(geometry.frontPath());
  final data = await _render(geometry, rtl, ratio, translucentEdge);
  var horizontalExtension = 0;
  var verticalExtension = 0;
  for (var y = 1.5; y < 299; y++) {
    for (var x = 1.5; x < 199; x++) {
      final point = Offset(x, y);
      if (!_inside(back, point)) continue;
      final source = _source(geometry, point, rtl);
      if ((source.dx - 100).abs() < 2 || (source.dy - 150).abs() < 2) continue;
      if (source.dx < -1 || source.dx > 201) horizontalExtension++;
      if (source.dy < -1 || source.dy > 301) verticalExtension++;
      _expectTexture(
        data,
        rtl ? Offset(_size.width - x, y) : point,
        source,
        ratio,
      );
    }
  }
  return (horizontalExtension, verticalExtension);
}

Future<void> _checkStages(
  bool top,
  bool rtl,
  int ratio,
  bool translucentEdge,
) async {
  var horizontalExtension = 0;
  var verticalExtension = 0;
  for (final touch in const [
    Offset(160, 250),
    Offset(120, 200),
    Offset(40, 190),
    Offset(-100, 220),
  ]) {
    final geometry = BesselGeometry.resolve(
      _size,
      Offset(touch.dx, top ? _size.height - touch.dy : touch.dy),
      top: top,
    )!;
    final counts = await _checkCoverage(geometry, rtl, ratio, translucentEdge);
    horizontalExtension += counts.$1;
    verticalExtension += counts.$2;
  }
  expect(horizontalExtension, greaterThan(10), reason: '覆盖侧边弯折延展区域');
  expect(verticalExtension, greaterThan(10), reason: '覆盖页角弯折延展区域');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final top in [false, true]) {
    for (final rtl in [false, true]) {
      for (final ratio in [1, 3]) {
        for (final translucentEdge in [false, true]) {
          test(
            '${top ? '上' : '下'}角 ${rtl ? '左' : '右'}侧 $ratio 倍'
            '${translucentEdge ? '半透明边缘快照' : '完整位图'}纹理填满整个纸背弯折区域',
            () => _checkStages(top, rtl, ratio, translucentEdge),
          );
        }
      }
    }
  }
}
