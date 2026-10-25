import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';

/// 临时诊断：真机（MEIZU 20, 1080x2400@2.8125）正文水平偏移复现。
///
/// 断言目标：正文本应左右对称内缩（padding 20dp），当前实现右侧被裁切。
void main() {
  test('真机复现：正文水平内缩', () async {
    final file = File('/tmp/reader_diag/book_zhushen.epub');
    if (!file.existsSync()) {
      markTestSkipped('缺少诊断书籍');
      return;
    }
    final bytes = Uint8List.fromList(await file.readAsBytes());
    // 真机几何（dp）：窗口 384 x 853.33；正文 padding 20/16；底部手势区 ~24。
    const windowWidth = 1080 / 2.8125;
    const windowHeight = 2400 / 2.8125;
    const padX = 20.0;
    const padY = 16.0;
    const bottomInset = 24.0;
    final contentWidth = windowWidth - padX * 2;
    final contentHeight = windowHeight - padY * 2 - bottomInset;

    final source = await EpubChapterSource.open(bytes);
    await source.applyContentSize(width: contentWidth, height: contentHeight);
    final pages = await source.loadChapter(46);
    print('pages=${pages.length} content=${contentWidth}x$contentHeight');
    final page = pages.first;

    for (var i = 0; i < page.slices.length && i < 12; i++) {
      final slice = page.slices[i];
      final style = slice.block.style;
      print(
        'slice#$i overlay=${slice.overlay} '
        'leftInset=${slice.leftInset.toStringAsFixed(2)} '
        'marginL=${style?.margin.left.toStringAsFixed(2)} '
        'marginR=${style?.margin.right.toStringAsFixed(2)} '
        'padL=${style?.padding.left.toStringAsFixed(2)} '
        'padR=${style?.padding.right.toStringAsFixed(2)} '
        'layoutW=${slice.block.layout.width.toStringAsFixed(2)} '
        'maxW=${slice.block.layout.maxWidth.toStringAsFixed(2)} '
        'lines=${slice.endLine - slice.startLine} '
        'text="${slice.block.layout.text.characters.take(12)}"',
      );
    }

    // 按阅读页当前写法绘制：canvas 已按 padding 平移，pageSize 传整窗尺寸。
    final margin = await _inkMargins(
      page: page,
      pageSize: Size(windowWidth, windowHeight),
      windowWidth: windowWidth,
      windowHeight: windowHeight,
      padX: padX,
      padY: padY,
    );
    print(
      '当前实现 墨迹: left=${margin.$1.toStringAsFixed(2)}dp '
      'right=${margin.$2.toStringAsFixed(2)}dp',
    );

    final marginFixed = await _inkMargins(
      page: page,
      pageSize: Size(contentWidth, contentHeight),
      windowWidth: windowWidth,
      windowHeight: windowHeight,
      padX: padX,
      padY: padY,
    );
    print(
      '仅修 pageSize 墨迹: left=${marginFixed.$1.toStringAsFixed(2)}dp '
      'right=${marginFixed.$2.toStringAsFixed(2)}dp',
    );
  });
}

/// 记录一页并按整窗尺寸取墨迹左右边距（dp）。
Future<(double, double)> _inkMargins({
  required PageContent page,
  required Size pageSize,
  required double windowWidth,
  required double windowHeight,
  required double padX,
  required double padY,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, windowWidth, windowHeight),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  canvas.save();
  canvas.translate(padX, padY);
  canvas.clipRect(
    Rect.fromLTWH(0, 0, windowWidth - padX * 2, windowHeight - padY * 2),
  );
  const PagePainter().paint(canvas, page, pageSize: pageSize);
  canvas.restore();
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    windowWidth.round(),
    windowHeight.round(),
  );
  final data = await image.toByteData();
  final pixels = data!.buffer.asUint8List();
  final width = image.width;
  final height = image.height;
  var minX = width;
  var maxX = -1;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final offset = (y * width + x) * 4;
      final a = pixels[offset + 3];
      if (a < 8) {
        continue;
      }
      final r = pixels[offset];
      if (r > 200) {
        continue;
      }
      if (x < minX) {
        minX = x;
      }
      if (x > maxX) {
        maxX = x;
      }
    }
  }
  return (minX.toDouble(), windowWidth - 1 - maxX);
}
