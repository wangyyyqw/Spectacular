import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/paging/curl3d_geometry.dart';
import 'package:reader_ui/paging/curl3d_painter.dart';

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
  Offset grab = const Offset(400, 600),
  Offset touch = const Offset(300, 480),
  Offset slide = Offset.zero,
  bool mirror = false,
}) async {
  final recorder = ui.PictureRecorder();
  Curl3dPainter(paperColor: _paper).paint(
    Canvas(recorder),
    _size,
    origin,
    target,
    geometry: Curl3dGeometry(
      size: _size,
      grab: grab,
      touch: touch,
      slide: slide,
    ),
    mirror: mirror,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(400, 600);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  return data!;
}

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
    expect(_isRed(_pixel(data, 200, 300)), isTrue);
    origin.dispose();
    target.dispose();
  });

  test('纸背铺纸色且不透明', () async {
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

  test('收尾位移把纸张推出画面，只留下下一页', () async {
    final origin = await _solid(_red);
    final target = await _solid(_blue);
    final data = await _render(
      origin,
      target,
      touch: const Offset(-240, 480),
      slide: const Offset(-400, 0),
    );
    for (var x = 4; x < 400; x += 40) {
      expect(_isBlue(_pixel(data, x, 300)), isTrue, reason: 'x=$x 应只剩下一页');
    }
    origin.dispose();
    target.dispose();
  });
}
