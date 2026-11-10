import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/page_renderer.dart';

import 'support/css_chapter_book.dart';

final _pixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a1ioAAAAASUVORK5CYII=',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('绝对定位图片作为覆盖层，不占正文段落空间', () async {
    final source = await openCssChapter(
      body: '<p>前段</p><img src="../Images/pixel.png"/><p>后段</p>',
      css:
          'p {margin:0;} img {display:block; position:absolute; '
          'width:80px; height:40px; top:50%; left:50%;}',
      binaryFiles: {'OEBPS/Images/pixel.png': _pixel},
    );
    addTearDown(source.close);
    final page = (await source.loadChapter(0)).single;
    final image = page.slices.singleWhere(
      (slice) => slice.block.layout.text.isEmpty,
    );
    expect(image.block.absolute, isTrue);
    expect(image.overlay, isTrue);
    expect(image.absoluteTop, closeTo(250, .01));
    expect(image.leftInset, closeTo(150, .01));
    final bodyHeight = page.slices
        .where((slice) => !slice.overlay)
        .fold(0.0, (sum, slice) => sum + slice.height);
    expect(page.usedHeight, closeTo(bodyHeight, .01));
  });

  test('Flex 中的绝对定位图片不挤占标题项且保留图片绘制载荷', () async {
    final source = await openCssChapter(
      body: '<h1>正文一</h1><img src="../Images/pixel.png"/>',
      css:
          'body {display:flex; height:100vh; align-items:center; '
          'justify-content:center;} h1 {margin:0; font-size:20px;} '
          'img {display:block; position:absolute; width:80%; height:40px; '
          'top:50%; left:50%; transform:translate(-50%,-50%);}',
      binaryFiles: {'OEBPS/Images/pixel.png': _pixel},
    );
    addTearDown(source.close);
    final page = (await source.loadChapter(0)).single;
    final overlays = page.slices.where((slice) => slice.overlay).toList();
    expect(overlays, hasLength(1));
    expect(
      overlays.single.block.style!.backgroundImage,
      'OEBPS/Images/pixel.png',
    );
    expect(overlays.single.block.style!.transforms, isNotEmpty);
    expect(overlays.single.absoluteTop, closeTo(250, .01));
    expect(overlays.single.block.layout.width, closeTo(240, .01));
    final flex = page.slices.singleWhere(
      (slice) => slice.block.table?.flex == true,
    );
    expect(flex.block.table!.cells, hasLength(1));
    expect(flex.block.table!.cells.single.layout.text, '正文一');
    expect(flex.block.table!.cells.single.rect.center.dx, closeTo(150, .01));
  });

  test('单张图片的 CSS 尺寸和定位不能被满屏快路覆盖', () async {
    final source = await openCssChapter(
      body: '<img src="../Images/pixel.png"/>',
      css:
          'img {display:block; position:absolute; width:80%; height:40px; object-fit:fill; '
          'top:50%; left:50%; transform:translate(-50%,-50%);}',
      binaryFiles: {'OEBPS/Images/pixel.png': _pixel},
    );
    addTearDown(source.close);
    final page = (await source.loadChapter(0)).single;
    final image = page.slices.single;
    expect(image.overlay, isTrue);
    expect(image.block.layout.width, closeTo(240, .01));
    expect(image.block.layout.height, closeTo(40, .01));
    expect(image.leftInset, closeTo(150, .01));
    expect(image.absoluteTop, closeTo(250, .01));
    final pixels = await _paintImagePage(page);
    List<int> pixel(int x, int y) =>
        pixels.sublist((y * 300 + x) * 4, (y * 300 + x) * 4 + 4);
    expect(pixel(150, 250), [255, 0, 0, 255]);
    expect(pixel(30, 230), [255, 0, 0, 255]);
    expect(pixel(29, 250), [255, 255, 255, 255]);
    expect(pixel(150, 229), [255, 255, 255, 255]);
  });

  test('静态容器的内边距不改变页面绝对定位图片的尺寸和原点', () async {
    final source = await openCssChapter(
      body: '<div><p>正文</p><img src="../Images/pixel.png"/></div>',
      css:
          'div {padding:20px;} img {display:block; position:absolute; '
          'width:80%; height:40px; top:50%; left:50%;}',
      binaryFiles: {'OEBPS/Images/pixel.png': _pixel},
    );
    addTearDown(source.close);
    final page = (await source.loadChapter(0)).single;
    final image = page.slices.singleWhere((slice) => slice.overlay);
    expect(image.block.layout.width, closeTo(240, .01));
    expect(image.block.style!.margin.left, 0);
    expect(image.leftInset, closeTo(150, .01));
  });

  test('原书图像载荷在负边距标题框背景之上绘制', () async {
    final source = await openCssChapter(
      body: '<img src="../Images/pixel.png"/><div><p>标题</p></div>',
      css:
          'img {display:block; width:100px; height:60px; object-fit:fill;}'
          'div {background:blue; width:120px; margin-top:-40px;}'
          'p {margin:0; font-size:16px; line-height:1; color:transparent;}',
      binaryFiles: {'OEBPS/Images/pixel.png': _pixel},
    );
    addTearDown(source.close);
    final page = (await source.loadChapter(0)).single;
    expect(page.slices.first.block.isReplaced, isTrue);
    final pixels = await _paintImagePage(page);
    List<int> pixel(int x, int y) =>
        pixels.sublist((y * 300 + x) * 4, (y * 300 + x) * 4 + 4);
    expect(pixel(80, 25), [255, 0, 0, 255]);
    expect(pixel(110, 25), [0, 0, 255, 255]);
  });
}

Future<Uint8List> _paintImagePage(PageContent page) async {
  final sourceRecorder = ui.PictureRecorder();
  ui.Canvas(sourceRecorder)
      .drawColor(const ui.Color(0xffff0000), ui.BlendMode.src);
  final sourcePicture = sourceRecorder.endRecording();
  final source = await sourcePicture.toImage(1, 1);
  final recorder = ui.PictureRecorder();
  PagePainter(
    background: const ui.Color(0xffffffff),
    imageLookup: (_) => source,
  ).paint(ui.Canvas(recorder), page, pageSize: const ui.Size(300, 500));
  final picture = recorder.endRecording();
  final image = await picture.toImage(300, 500);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer
        .asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
    source.dispose();
    sourcePicture.dispose();
  }
}
