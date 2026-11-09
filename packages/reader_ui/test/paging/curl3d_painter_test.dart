import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/paging/curl3d_geometry.dart';
import 'package:reader_ui/paging/curl3d_painter.dart';
import 'package:reader_ui/paging/duokan_curl_shader.dart';

const _size = Size(400, 600);
const _red = Color(0xFFFF0000);
const _blue = Color(0xFF0000FF);
const _paper = Color(0xFFFFFDF4);

Future<ui.Image> _solid(Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(color, BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(400, 600);
  picture.dispose();
  return image;
}

/// 左上白、右侧竖线标记，用来检查内容有没有被拉伸。
Future<ui.Image> _marked() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 400, 600), Paint()..color = _paper);
  canvas.drawRect(
    const Rect.fromLTWH(100, 0, 6, 600),
    Paint()..color = const Color(0xFF000000),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(400, 600);
  picture.dispose();
  return image;
}

Future<ByteData> _render(
  ui.Image origin,
  ui.Image target, {
  Curl3dGeometry? geometry,
  bool mirror = false,
}) async {
  await DuokanCurlShader.load();
  final recorder = ui.PictureRecorder();
  Curl3dPainter(paperColor: _paper).paint(
    Canvas(recorder),
    origin,
    target,
    geometry: geometry ?? _geometry(),
    mirror: mirror,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(400, 600);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  return data!;
}

Curl3dGeometry _geometry({
  Offset grab = const Offset(400, 600),
  Offset touch = const Offset(300, 480),
}) => Curl3dGeometry(size: _size, grab: grab, touch: touch);

List<int> _pixel(ByteData data, int x, int y) {
  final offset = (y * 400 + x) * 4;
  return List<int>.generate(4, (index) => data.getUint8(offset + index));
}

bool _isRed(List<int> pixel) =>
    pixel[0] > 180 && pixel[1] < 60 && pixel[2] < 60;

bool _isBlue(List<int> pixel) =>
    pixel[2] > 180 && pixel[0] < 60 && pixel[1] < 60;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('掀起的页角露出下一页，其余位置保留原页', () async {
    final origin = await _solid(_red);
    final target = await _solid(_blue);
    final data = await _render(origin, target);
    expect(_isBlue(_pixel(data, 392, 594)), isTrue, reason: '页角处应露出下一页');
    expect(_isRed(_pixel(data, 20, 40)), isTrue, reason: '未翻起的部分保持原页');
    expect(_pixel(data, 20, 40), [255, 0, 0, 255], reason: '平面正面不额外压暗');
    expect(_isRed(_pixel(data, 200, 300)), isTrue);
    origin.dispose();
    target.dispose();
  });

  test('静态底页和卷纸正面均还原原 GLES 的 RGB565 采样', () async {
    final origin = await _solid(const Color(0xFF808080));
    final target = await _solid(const Color(0xFF123456));
    addTearDown(origin.dispose);
    addTearDown(target.dispose);
    final data = await _render(origin, target);
    expect(_pixel(data, 20, 40), [132, 129, 132, 255]);
    expect(_pixel(data, 392, 594), [16, 53, 82, 255]);
  });

  test('纸背带正面透印且不透明', () async {
    final origin = await _solid(_red);
    final target = await _solid(_blue);
    final data = await _render(origin, target);
    var paper = 0;
    for (var y = 470; y < 360 + 200; y++) {
      for (var x = 290; x < 350; x++) {
        final pixel = _pixel(data, x, y);
        expect(pixel[3], 255, reason: '不能出现透明缺口');
        if (!_isRed(pixel) && !_isBlue(pixel)) paper++;
      }
    }
    expect(paper, greaterThan(200), reason: '折叠区域应能看到纸背');
    origin.dispose();
    target.dispose();
  });

  test('镜像后折角出现在左侧', () async {
    final origin = await _solid(_red);
    final target = await _solid(_blue);
    final data = await _render(origin, target, mirror: true);
    expect(_isBlue(_pixel(data, 8, 594)), isTrue);
    expect(_isRed(_pixel(data, 380, 40)), isTrue);
    origin.dispose();
    target.dispose();
  });

  for (final mirror in [false, true]) {
    test('${mirror ? '左侧' : '右侧'}近水平拖动时上下角纸面与两类阴影对称', () async {
      final origin = await _solid(_red);
      final target = await _solid(_blue);
      addTearDown(origin.dispose);
      addTearDown(target.dispose);
      final upper = await _render(
        origin,
        target,
        geometry: _geometry(
          grab: const Offset(400, 0),
          touch: const Offset(200, 12),
        ),
        mirror: mirror,
      );
      final lower = await _render(
        origin,
        target,
        geometry: _geometry(touch: const Offset(200, 588)),
        mirror: mirror,
      );
      var error = 0;
      for (var y = 0; y < 600; y++) {
        for (var x = 0; x < 400; x++) {
          final a = _pixel(upper, x, 599 - y);
          final b = _pixel(lower, x, y);
          for (var channel = 0; channel < 4; channel++) {
            error += (a[channel] - b[channel]).abs();
          }
          expect(b.last, 255, reason: '阴影与纸背合成不能留下透明裂隙');
        }
      }
      expect(error / upper.lengthInBytes, lessThan(0.25), reason: '只容忍亚像素纸边误差');
    });
  }

  test('正面标记位置不被折角采样移动', () async {
    final origin = await _marked();
    final target = await _solid(_blue);
    final data = await _render(origin, target);
    final line = <int>[];
    for (var x = 80; x < 140; x++) {
      final pixel = _pixel(data, x, 60);
      if (pixel[0] < 60 && pixel[1] < 60 && pixel[2] < 60) line.add(x);
    }
    expect(line.first, inInclusiveRange(99, 101));
    expect(line.last, inInclusiveRange(104, 106));
    origin.dispose();
    target.dispose();
  });

  test('完成时卷页自然移出视口，底页完整显露', () async {
    final origin = await _solid(_red);
    final target = await _solid(_blue);
    final data = await _render(
      origin,
      target,
      geometry: _geometry(touch: const Offset(-400, 600)),
    );
    for (var x = 4; x < 400; x += 40) {
      expect(_isBlue(_pixel(data, x, 300)), isTrue, reason: 'x=$x 应只剩下一页');
    }
    origin.dispose();
    target.dispose();
  });
}
