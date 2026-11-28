import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_core/paint/hit_test.dart';

import 'selection.dart';

/// 从正式分页按阅读顺序裁出白底黑字的行图，不改变用户阅读页面。
abstract final class SelectionImage {
  /// 排版已提供准确行框，逐行识别可省去全图文字检测和透视裁剪。
  /// 输入统一约 64 像素高，留出边距；不再随字号把整个选区放大三倍。
  static Stream<Uint8List> captureLines(
    PageContent page,
    ReaderSelection selection,
  ) async* {
    var found = false;
    for (final entry in SelectionOps.coveredLines(page, selection)) {
      for (final rect in SelectionOps.lineRectsFor(
        entry.box,
        entry.start,
        entry.end,
      )) {
        if (rect.isEmpty) continue;
        found = true;
        yield await _captureLine(entry.box, rect);
      }
    }
    if (!found) throw const FormatException('所选区域没有可识别文字');
  }

  static Future<Uint8List> _captureLine(PageLineBox box, Rect rect) async {
    if (box.isVertical) throw const FormatException('暂不支持竖排选区识别，请选择横排文字');
    final scale = 64 / rect.height;
    const padding = 4.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..drawColor(const Color(0xffffffff), BlendMode.src)
      ..translate(padding, padding)
      ..scale(scale)
      ..clipRect(Rect.fromLTWH(0, 0, rect.width, rect.height))
      ..translate(-rect.left, -rect.top);
    PagePainter.paintRecognitionLine(canvas, box);
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      (rect.width * scale + padding * 2).ceil(),
      72,
    );
    picture.dispose();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }
}
