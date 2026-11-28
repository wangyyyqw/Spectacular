import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_ui/selection/selection.dart';

/// 性能对照保留优化前的三倍合成选区图，只供真实 OCR 回归使用。
Future<Uint8List> captureLegacySelection(
  PageContent page,
  ReaderSelection selection,
) async {
  final regions = [
    for (final entry in SelectionOps.coveredLines(page, selection))
      for (final rect in SelectionOps.lineRectsFor(
        entry.box,
        entry.start,
        entry.end,
      ))
        if (!rect.isEmpty) (box: entry.box, rect: rect),
  ];
  final rects = regions.map((region) => region.rect).toList();
  if (rects.isEmpty) throw const FormatException('所选区域没有可识别文字');
  final imageWidth =
      rects.fold(0.0, (w, rect) => w > rect.width ? w : rect.width) + 24;
  final height = rects.fold(12.0, (h, rect) => h + rect.height + 12);
  const scale = 3.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..scale(scale)
    ..drawColor(const Color(0xffffffff), BlendMode.src);
  var top = 12.0;
  for (final region in regions) {
    final rect = region.rect;
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(12, top, rect.width, rect.height));
    canvas.translate(12 - rect.left, top - rect.top);
    PagePainter.paintRecognitionLine(canvas, region.box);
    canvas.restore();
    top += rect.height + 12;
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    (imageWidth * scale).ceil(),
    (height * scale).ceil(),
  );
  picture.dispose();
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}
