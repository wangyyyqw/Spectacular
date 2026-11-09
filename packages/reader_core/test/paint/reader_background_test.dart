import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/page_background.dart';
import 'package:reader_core/paint/page_renderer.dart';

Future<ui.Image> _image() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 300, 100),
    Paint()..color = const Color(0xFFFF0000),
  );
  canvas.drawRect(
    const Rect.fromLTWH(100, 0, 100, 100),
    Paint()..color = const Color(0xFF00FF00),
  );
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(300, 100);
  } finally {
    picture.dispose();
  }
}

Future<int> _pixel(
  ui.Image image, {
  required bool cover,
  required double opacity,
  Color background = const Color(0xFF000000),
}) async {
  final recorder = ui.PictureRecorder();
  final page = PageContent(
    spineIndex: 0,
    pageIndex: 0,
    slices: const [],
    usedHeight: 0,
    pageHeight: 100,
    topPadding: 0,
  );
  PagePainter(
    background: background,
    pageBackgroundImage: image,
    pageBackgroundImageCover: cover,
    pageBackgroundImageOpacity: opacity,
  ).paint(Canvas(recorder), page, pageSize: const Size(100, 100));
  final picture = recorder.endRecording();
  final result = await picture.toImage(100, 100);
  try {
    final data = await result.toByteData(format: ui.ImageByteFormat.rawRgba);
    return data!.getUint32((50 * 100 + 50) * 4);
  } finally {
    result.dispose();
    picture.dispose();
  }
}

Future<ui.Image> _paperBackground(
  PagePainter painter,
  PageContent page, {
  required bool backgroundOnly,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const size = Size(100, 100);
  const insets = EdgeInsets.fromLTRB(7, 11, 13, 17);
  if (backgroundOnly) {
    painter.paintBackground(canvas, pageSize: size, pageInsets: insets);
  } else {
    painter.paint(canvas, page, pageSize: size, pageInsets: insets);
  }
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(100, 100);
  } finally {
    picture.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('图片居中裁切铺满，内置纹理保留平铺', () async {
    final image = await _image();
    addTearDown(image.dispose);
    expect(await _pixel(image, cover: true, opacity: 1), 0x00FF00FF);
    expect(await _pixel(image, cover: false, opacity: 1), 0xFF0000FF);
  });
  test('暗色主题淡化纹理，图片强度基于原始颜色', () async {
    final image = await _image();
    addTearDown(image.dispose);
    final pixel = await _pixel(image, cover: true, opacity: 0.18);
    expect((pixel >> 16) & 255, closeTo(46, 1));
    expect(pixel & 255, 255);
    expect(await _pixel(image, cover: true, opacity: 0), 0x000000FF);
  });

  for (final cover in [false, true]) {
    test('卷页纸底与完整纸面的主题背景一致，覆盖=$cover', () async {
      final image = await _image();
      addTearDown(image.dispose);
      final painter = PagePainter(
        background: const Color(0xFFEEE8D5),
        pageBackgroundImage: image,
        pageBackgroundImageCover: cover,
        pageBackgroundImageTint: const Color(0xFFDDDDEE),
        pageBackgroundImageOpacity: 0.18,
      );
      final page = PageContent(
        spineIndex: 0,
        pageIndex: 0,
        slices: const [],
        usedHeight: 0,
        pageHeight: 100,
        topPadding: 0,
      );
      final full = await _paperBackground(painter, page, backgroundOnly: false);
      final back = await _paperBackground(painter, page, backgroundOnly: true);
      addTearDown(full.dispose);
      addTearDown(back.dispose);
      final fullBytes = (await full.toByteData())!.buffer.asUint8List();
      final backBytes = (await back.toByteData())!.buffer.asUint8List();
      expect(backBytes, fullBytes, reason: '页边距、染色、透明度与平铺起点需共用');
    });
  }

  test('卷页纸底不混入书籍的整页内容背景', () async {
    final image = await _image();
    addTearDown(image.dispose);
    final painter = PagePainter(
      background: const Color(0xFF0000FF),
      imageLookup: (_) => image,
    );
    final page = PageContent(
      spineIndex: 0,
      pageIndex: 0,
      slices: const [],
      usedHeight: 0,
      pageHeight: 100,
      topPadding: 0,
      background: const PageBackground(imageUrl: '书籍底图'),
    );
    final full = await _paperBackground(painter, page, backgroundOnly: false);
    final back = await _paperBackground(painter, page, backgroundOnly: true);
    addTearDown(full.dispose);
    addTearDown(back.dispose);
    final offset = (50 * 100 + 50) * 4;
    expect((await full.toByteData())!.getUint32(offset), 0xFF0000FF);
    expect((await back.toByteData())!.getUint32(offset), 0x0000FFFF);
  });
}
