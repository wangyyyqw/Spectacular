import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/image_gallery.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/paint/page_renderer.dart';

PageGalleryFrame _frame(
  int index,
  String color, {
  ComputedStyle? parent,
  double opacity = 1,
}) {
  final style = ComputedStyle({
    'width': '80px',
    'margin-left': '10px',
    'background-color': color,
    'opacity': '$opacity',
  }, parent: parent);
  return PageGalleryFrame(
    cfi: 'epubcfi(/6/2!/4/2/${index * 2 + 2})',
    content: Paginator(pageHeight: 60)
        .measureChapter(blocks: [_block(style, 60)])
        .pages
        .single,
  );
}

PageContent _page({
  double scale = 1,
  double opacity = 1,
  double frameOpacity = 1,
}) {
  final height = 60 * scale + 24;
  final style = ComputedStyle({
    'width': '80px',
    'margin-left': '10px',
    'opacity': '$opacity',
  });
  final gallery = PageGallery(
    cfi: 'epubcfi(/6/2!/4/2)',
    frames: [
      _frame(0, '#ff0000', parent: style, opacity: frameOpacity),
      _frame(1, '#00ff00', parent: style, opacity: frameOpacity),
    ],
    left: 10,
    width: 80,
    height: height,
    scale: scale,
    indicatorExtent: 24,
  );
  return Paginator(pageHeight: 100)
      .measureChapter(blocks: [_block(style, height, gallery: gallery)])
      .pages
      .single;
}

PageBlock _block(ComputedStyle style, double height, {PageGallery? gallery}) =>
    PageBlock.styled(
      layout: TextLayoutResult(
        text: '',
        lines: [
          LineBox(
            start: 0,
            end: 0,
            top: 0,
            height: height,
            baseline: height,
            width: 80,
          ),
        ],
        width: 80,
        height: height,
        maxWidth: 80,
      ),
      style: style,
      containingWidth: 100,
      gallery: gallery,
    );

Future<ByteData> _render(PageContent page, {int? index}) async {
  final recorder = ui.PictureRecorder();
  PagePainter(galleryFrameOf: index == null ? null : (_) => index)
      .paint(ui.Canvas(recorder), page, pageSize: const Size(100, 100));
  final picture = recorder.endRecording();
  final image = picture.toImageSync(100, 100);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  } finally {
    image.dispose();
    picture.dispose();
  }
}

List<int> _pixel(ByteData bytes, int x, int y) =>
    bytes.buffer.asUint8List((y * 100 + x) * 4, 4).toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('默认只画第一帧，切帧后相同位置显示新画面，区域外保持页底色', () async {
    final page = _page();
    final first = await _render(page);
    final second = await _render(page, index: 1);
    expect(_pixel(first, 40, 20), [255, 0, 0, 255]);
    expect(_pixel(second, 40, 20), [0, 255, 0, 255]);
    expect(_pixel(second, 5, 20), [255, 255, 255, 255]);
    expect(_pixel(second, 40, 70), [255, 255, 255, 255]);
  });

  test('整组缩放保留比例与水平居中，越界帧序号钳到有效范围', () async {
    final pixels = await _render(_page(scale: 0.5), index: 99);
    expect(_pixel(pixels, 40, 20), [0, 255, 0, 255]);
    expect(_pixel(pixels, 15, 20), [255, 255, 255, 255]);
    expect(_pixel(pixels, 40, 40), [255, 255, 255, 255]);
  });

  test('画廊与分帧透明度各合成一次，避免重复变淡', () async {
    final pixels = await _render(_page(opacity: 0.5, frameOpacity: 0.4));
    expect(_pixel(pixels, 40, 20), [255, 204, 204, 255]);
  });
}
