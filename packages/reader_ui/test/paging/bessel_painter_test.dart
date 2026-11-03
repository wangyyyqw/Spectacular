import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/paging/bessel_geometry.dart';
import 'package:reader_ui/paging/bessel_painter.dart';

const _size = Size(200, 300);

Future<ui.Image> _solidImage(Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(color, BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(200, 300);
  picture.dispose();
  return image;
}

Future<ByteData> _render({
  bool top = false,
  bool horizontal = false,
  Color bottomColor = const Color(0xFFFFFFFF),
}) async {
  final paperRecorder = ui.PictureRecorder();
  Canvas(paperRecorder).drawColor(const Color(0xFFFFFFFF), BlendMode.src);
  final paperPicture = paperRecorder.endRecording();
  final paper = await paperPicture.toImage(200, 300);
  paperPicture.dispose();
  final bottom = await _solidImage(bottomColor);
  final recorder = ui.PictureRecorder();
  BesselPainter(paperColor: const Color(0xFFFFFFFF)).paint(
    Canvas(recorder),
    BesselGeometry.resolve(
      _size,
      Offset(120, horizontal ? 150 : (top ? 100 : 200)),
      top: top,
      horizontal: horizontal,
    )!,
    bottom,
    paper,
    rtl: false,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(200, 300);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  paper.dispose();
  bottom.dispose();
  return data!;
}

int _brightness(ByteData data, Offset point, {bool mirrored = false}) {
  final x = point.dx.floor();
  final y = mirrored ? 299 - point.dy.floor() : point.dy.floor();
  return data.getUint8((y * 200 + x) * 4);
}

List<int> _rgba(ByteData data, int x, int y) {
  final offset = (y * 200 + x) * 4;
  return List<int>.generate(4, (index) => data.getUint8(offset + index));
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

  test('纸背背景完整覆盖弯曲区域，不露出底页', () async {
    for (final mode in [
      (top: false, horizontal: false),
      (top: true, horizontal: false),
      (top: false, horizontal: true),
    ]) {
      final redBottom = await _render(
        top: mode.top,
        horizontal: mode.horizontal,
        bottomColor: const Color(0xFFFF0000),
      );
      final blueBottom = await _render(
        top: mode.top,
        horizontal: mode.horizontal,
        bottomColor: const Color(0xFF0000FF),
      );
      final g = BesselGeometry.resolve(
        _size,
        Offset(120, mode.horizontal ? 150 : (mode.top ? 100 : 200)),
        top: mode.top,
        horizontal: mode.horizontal,
      )!;
      final back = g.backPath(g.frontPath());

      for (var y = 3; y < 297; y += 3) {
        for (var x = 3; x < 197; x += 3) {
          final point = Offset(x + 0.5, y + 0.5);
          // 折痕与纸背外轮廓有 1 像素抗锯齿过渡，只验证其内部。
          if (!back.contains(point) ||
              !back.contains(point + const Offset(2, 0)) ||
              !back.contains(point - const Offset(2, 0)) ||
              !back.contains(point + const Offset(0, 2)) ||
              !back.contains(point - const Offset(0, 2))) {
            continue;
          }
          expect(
            _rgba(redBottom, x, y),
            _rgba(blueBottom, x, y),
            reason: '弯曲区域 ($x, $y) 不应透出底页颜色',
          );
        }
      }
    }
  });

  test('中心起卷上下对称且整条侧边都有纸背', () async {
    final data = await _render(
      horizontal: true,
      bottomColor: const Color(0xFFFF0000),
    );
    for (final y in [10, 75, 149]) {
      final upper = _rgba(data, 145, y);
      final lower = _rgba(data, 145, 299 - y);

      expect(upper[0], upper[1], reason: '纸背内部不能漏出红色底页');
      expect(upper[1], upper[2]);
      expect(lower[0], closeTo(upper[0], 2));
    }
  });
}
