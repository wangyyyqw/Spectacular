import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/paint/image_cache.dart';
import 'package:reader_core/paint/image_paint.dart';

Future<Uint8List> _pngBytes(int width, int height, int colorValue) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = Color(colorValue),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

Future<ByteData> _renderRect(Rect rect, void Function(Canvas) draw) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  draw(canvas);
  final image = await recorder.endRecording().toImage(
        rect.width.round(),
        rect.height.round(),
      );
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('未解码：画占位并触发解码，200ms 预算内可替换', () async {
    final bytes = await _pngBytes(40, 30, 0xFF00FF00);
    final cache = DecodedImageCache(loadBytes: (url) async => bytes);
    final metrics = ImagePaintMetrics();
    const rect = Rect.fromLTWH(0, 0, 100, 60);

    var hit = false;
    final frame = await _renderRect(rect, (canvas) {
      hit = ImageBlockPainter.paint(
        canvas,
        rect,
        url: 'pic',
        cache: cache,
        metrics: metrics,
        nowMs: 1000,
      );
    });
    expect(hit, isFalse, reason: '未解码先画占位');
    expect(metrics.placeholderCount, 1);
    // 占位底色 E8E8E8 出现在画布中心（RGBA 按 Android 平台序校验绿色通道）。
    final centerBytes = frame.buffer.asUint8List();
    final center = (50 * 100 + 30) * 4;
    expect(centerBytes[center], 0xE8, reason: '占位底色 R 通道');
    expect(centerBytes[center + 1], 0xE8, reason: '占位底色 G 通道');

    // 解码完成后（fire-and-forget 已触发）下一帧命中成图。
    await cache.load('pic', displayWidth: rect.width);
    expect(cache.revision, greaterThan(0), reason: '宿主按 revision 触发重绘');
    final replaced = await _renderRect(rect, (canvas) {
      hit = ImageBlockPainter.paint(
        canvas,
        rect,
        url: 'pic',
        cache: cache,
        metrics: metrics,
        nowMs: 1050,
      );
    });
    expect(hit, isTrue);
    expect(metrics.drawnCount, 1);
    metrics.recordDrawn(nowMs: 1080);
    final centerBytes2 = replaced.buffer.asUint8List();
    final center2 = (50 * 100 + 30) * 4;
    // 40×30 源图 contain 到 100×60：高受限 → 100×75 裁剪内绘制，中心为绿。
    expect(centerBytes2[center2 + 1], 0xFF, reason: '替换后中心为图片绿色通道');
  });

  test('字节缺失：占位长期保留，不抛异常', () async {
    final cache = DecodedImageCache(loadBytes: (url) async => null);
    const rect = Rect.fromLTWH(0, 0, 80, 40);
    final frame = await _renderRect(rect, (canvas) {
      ImageBlockPainter.paint(canvas, rect, url: 'gone', cache: cache);
    });
    final bytes = frame.buffer.asUint8List();
    final probe = (20 * 100 + 10) * 4;
    expect(bytes[probe], 0xE8, reason: '缺失时占位保留');
  });

  test('ImagePageDetector：单图无正文满屏，双图/有正文普通路径', () {
    expect(
      ImagePageDetector.isFullBleedPage(imageCount: 1, hasText: false),
      isTrue,
    );
    expect(
      ImagePageDetector.isFullBleedPage(imageCount: 1, hasText: true),
      isFalse,
    );
    expect(
      ImagePageDetector.isFullBleedPage(imageCount: 2, hasText: false),
      isFalse,
    );
  });

  test('ImageFit.contain 等比居中', () async {
    final image = await _createImage(200, 100, 0xFF0000FF);
    final target = ImageFit.contain(
      const Rect.fromLTWH(0, 0, 100, 100),
      image,
    );
    expect(target.width, 100);
    expect(target.height, 50);
    expect(target.top, 25);
    image.dispose();
  });
}

Future<ui.Image> _createImage(int width, int height, int colorValue) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = Color(colorValue),
  );
  return recorder.endRecording().toImage(width, height);
}
