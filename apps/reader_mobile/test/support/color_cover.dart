import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 生成有真实像素的双色封面，不依赖外部图片或联网。
Future<File> createColorCover(
  Directory directory,
  String name,
  Color mainColor, {
  Color accent = Colors.white,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 48, 72),
    Paint()..color = mainColor,
  );
  canvas.drawRect(const Rect.fromLTWH(40, 0, 8, 72), Paint()..color = accent);
  final picture = recorder.endRecording();
  final image = picture.toImageSync(48, 72);
  try {
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    return await File('${directory.path}/$name.png')
        .writeAsBytes(bytes.buffer.asUint8List());
  } finally {
    image.dispose();
    picture.dispose();
  }
}
