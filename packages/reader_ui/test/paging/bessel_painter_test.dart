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

Future<ui.Image> _paperImage(
  bool markedPaper, {
  Color color = const Color(0xFFFFFFFF),
}) async {
  final paperRecorder = ui.PictureRecorder();
  final paperCanvas = Canvas(paperRecorder)
    ..drawColor(color, BlendMode.src);
  if (markedPaper) {
    for (final left in <double>[142, 190]) {
      paperCanvas.drawRect(
        Rect.fromLTWH(left, 0, 8, 300),
        Paint()..color = const Color(0xFF000000),
      );
    }
  }
  final paperPicture = paperRecorder.endRecording();
  final image = await paperPicture.toImage(200, 300);
  paperPicture.dispose();
  return image;
}

Future<ByteData> _render({
  bool top = false,
  bool horizontal = false,
  double touchX = 120,
  bool markedPaper = false,
  Color paperColor = const Color(0xFFFFFFFF),
  Color pageColor = const Color(0xFFFFFFFF),
  Color bottomColor = const Color(0xFFFFFFFF),
}) async {
  final paper = await _paperImage(markedPaper, color: pageColor);
  final bottom = await _solidImage(bottomColor);
  final recorder = ui.PictureRecorder();
  BesselPainter(paperColor: paperColor).paint(
    Canvas(recorder),
    BesselGeometry.resolve(
      _size,
      Offset(touchX, horizontal ? 150 : (top ? 100 : 200)),
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

  test('角部纸背显示镜像页面内容，且不透出底页', () async {
    for (final top in [false, true]) {
      final data = await _render(
        top: top,
        markedPaper: true,
        bottomColor: const Color(0xFFFF0000),
      );
      final g = BesselGeometry.resolve(
        _size,
        Offset(120, top ? 100 : 200),
        top: top,
      )!;
      final back = g.backPath(g.frontPath());
      var ink = 0;
      for (var y = 2; y < 298; y += 2) {
        for (var x = 2; x < 198; x += 2) {
          if (!back.contains(Offset(x + 0.5, y + 0.5))) continue;
          if (_brightness(data, Offset(x.toDouble(), y.toDouble())) < 210) {
            ink++;
          }
        }
      }
      expect(ink, greaterThan(0), reason: '${top ? '上' : '下'}角纸背应显示镜像正文');
    }
  });

  test('纸背内容变浅发白，正面颜色不受影响', () async {
    final data = await _render(
      pageColor: const Color(0xFF000000),
      paperColor: const Color(0xFFFFFFFF),
    );
    final back = crease + normal * 30;
    final backBrightness = _brightness(data, back);

    expect(backBrightness, inInclusiveRange(130, 200));
    expect(_brightness(data, const Offset(20, 150)), lessThan(60));
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

  test('中心卷面全高等宽，纸背折痕和底页投影连续渐变', () async {
    final data = await _render(horizontal: true);
    final geometry = BesselGeometry.resolve(
      _size,
      const Offset(120, 150),
      horizontal: true,
    )!;
    final crease = geometry.d.dx.floor();
    for (final sampleY in <double>[2, 75, 150, 225, 297]) {
      expect(_brightness(data, Offset(123, sampleY)), greaterThan(250));
      expect(_brightness(data, Offset(crease - 1.0, sampleY)), lessThan(205));
      expect(_brightness(data, Offset(crease + 2.0, sampleY)), lessThan(225));
      expect(_brightness(data, Offset(crease + 30.0, sampleY)), 255);
    }
    for (var sampleX = 115; sampleX < 180; sampleX++) {
      for (final sampleY in [2, 297]) {
        final actual = _rgba(data, sampleX, sampleY);
        final center = _rgba(data, sampleX, 150);
        for (var channel = 0; channel < 4; channel++) {
          expect(actual[channel], closeTo(center[channel], 2));
        }
      }
    }
  });

  test('中心纸背保留镜像图案且靠近圆柱折痕逐渐压缩', () async {
    final data = await _render(horizontal: true, touchX: 80, markedPaper: true);
    final flatInk = <int>[];
    final curvedInk = <int>[];
    for (var sampleX = 80; sampleX < 125; sampleX++) {
      if (_brightness(data, Offset(sampleX.toDouble(), 150)) >= 190) continue;
      (sampleX < 100 ? flatInk : curvedInk).add(sampleX);
    }

    expect(flatInk.length, inInclusiveRange(7, 9));
    expect(curvedInk, isNotEmpty);
    expect(curvedInk.length, lessThan(flatInk.length / 2));
    expect(curvedInk.first, greaterThan(flatInk.last));
  });

  test('深色图片页正面折痕不露出固定纸色亮边', () async {
    for (final mode in [
      (top: false, horizontal: false),
      (top: true, horizontal: false),
      (top: false, horizontal: true),
    ]) {
      final data = await _render(
        top: mode.top,
        horizontal: mode.horizontal,
        paperColor: const Color(0xFFF4EEDF),
        pageColor: const Color(0xFF18171D),
      );
      final g = BesselGeometry.resolve(
        _size,
        Offset(120, mode.horizontal ? 150 : (mode.top ? 100 : 200)),
        top: mode.top,
        horizontal: mode.horizontal,
      )!;
      final front = g.frontPath();

      for (var y = 1; y < 299; y++) {
        for (var x = 1; x < 199; x++) {
          if (!front.contains(Offset(x + 0.5, y + 0.5))) continue;
          expect(
            _brightness(data, Offset(x.toDouble(), y.toDouble())),
            lessThan(200),
            reason: '深色页面 (${x.toString()}, $y) 不应露出纸色亮边',
          );
        }
      }
    }
  });

  test('页脚角部翻出屏幕时侧边阴影随纸背淡出', () async {
    final data = await _render(
      touchX: -195,
      bottomColor: const Color(0xFF0000FF),
    );

    for (final point in const [
      Offset(0, 150),
      Offset(1, 150),
      Offset(1, 299),
    ]) {
      final pixel = _rgba(data, point.dx.toInt(), point.dy.toInt());
      expect(pixel[0], 0, reason: '侧边不应残留灰色纸背');
      expect(pixel[1], 0, reason: '侧边不应残留灰色纸背');
      expect(pixel[2], greaterThan(245), reason: '阴影应随纸背淡出，不压暗目标页');
    }
  });
}
