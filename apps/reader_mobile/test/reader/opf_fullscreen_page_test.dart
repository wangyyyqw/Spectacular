import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';

import 'support/css_chapter_book.dart';

/// OPF 全屏页（多看 `duokan-page-*`）：`itemref` 属性决定整页图铺法，
/// 且封面不被正文样式裁剪。
Future<List<int>> _pngBytes(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF3F51B5),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

Future<ui.Image> _decodeImage(List<int> png) async {
  final codec = await ui.instantiateImageCodec(Uint8List.fromList(png));
  final frame = await codec.getNextFrame();
  return frame.image;
}

/// 渲染整页并统计：图片色（0xFF3F51B5）出现的行区间与四边留白。
Future<({int top, int bottom, bool leftEdge, bool rightEdge, int width, int height})>
_renderCoverBand({
  required EpubChapterSource source,
  required List<int> png,
  required Size pageSize,
}) async {
  final image = await _decodeImage(png);
  final pages = await source.loadChapter(0);
  final recorder = ui.PictureRecorder();
  PagePainter(
    background: const Color(0xFFFFFFFF),
    imageLookup: (url) => image,
  ).paint(Canvas(recorder), pages.single, pageSize: pageSize);
  final shot = await recorder.endRecording().toImage(
    pageSize.width.toInt(),
    pageSize.height.toInt(),
  );
  final bytes = (await shot.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  shot.dispose();
  image.dispose();
  final w = pageSize.width.toInt();
  final h = pageSize.height.toInt();
  const cover = Color(0xFF3F51B5);
  Color pixel(int x, int y) {
    final offset = (y * w + x) * 4;
    return Color.fromARGB(
      bytes.getUint8(offset + 3),
      bytes.getUint8(offset),
      bytes.getUint8(offset + 1),
      bytes.getUint8(offset + 2),
    );
  }

  var top = -1;
  var bottom = -1;
  for (var y = 0; y < h; y++) {
    if (pixel(w ~/ 2, y) == cover) {
      top = top < 0 ? y : top;
      bottom = y;
    }
  }
  return (
    top: top,
    bottom: bottom,
    leftEdge: top >= 0 && pixel(0, (top + bottom) ~/ 2) == cover,
    rightEdge: top >= 0 && pixel(w - 1, (top + bottom) ~/ 2) == cover,
    width: w,
    height: h,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const coverBody = '<img src="../Images/cover.png"/>';

  Future<List<int>> coverPng() => _pngBytes(120, 90);

  test('duokan-page-fullscreen：没有 slim 变体时 cover 铺满，正文样式不裁剪', () async {
    final source = await openCssChapter(
      body: coverBody,
      // 正文样式故意写得很“贵”：padding/字号/行高都不应影响全屏页。
      css: 'body { margin: 0; padding: 40px; font-size: 30px; '
          'line-height: 3; } img { width: 100px; height: 50px; }',
      binaryFiles: <String, List<int>>{
        'OEBPS/Images/cover.png': await coverPng(),
      },
      itemrefAttributes: ' properties="duokan-page-fullscreen"',
      contentWidth: 300,
      contentHeight: 500,
    );

    expect(source.chapterPageFlags(0).fullScreen, isTrue);
    final pages = await source.loadChapter(0);
    expect(pages, hasLength(1));
    final slice = pages.single.slices.single;
    final block = slice.block;
    expect(block.style!.backgroundImage, 'OEBPS/Images/cover.png');
    expect(
      block.style!.backgroundSize.mode,
      CssBackgroundSizeMode.cover,
      reason: '全屏页必须铺满查看区域',
    );
    expect(block.bleedLeft, isTrue);
    expect(block.bleedRight, isTrue);
    // 整页尺寸 = 原始页（300×500），不被 body padding 或 img 尺寸压小。
    expect(block.layout.width, closeTo(300, 0.01));
    expect(block.layout.height, closeTo(500, 0.01));
    expect(pages.single.usedHeight, closeTo(500, 0.01));
  });

  test('SVG 封面页：全屏标记优先于 SVG meet，按 cover 铺满页面', () async {
    // 页面 320x480（比例 0.667），图片 660x880（比例 0.75）。
    // 即使 SVG 自身写 meet，OPF 全屏页仍应覆盖整页。
    final png = await _pngBytes(660, 880);
    final source = await openCssChapter(
      body: '<svg xmlns="http://www.w3.org/2000/svg" '
          'xmlns:xlink="http://www.w3.org/1999/xlink" '
          'viewBox="0 0 660 880" preserveAspectRatio="xMidYMid meet">'
          '<image xlink:href="../Images/cover.png" x="0" y="0" '
          'width="660" height="880"/></svg>',
      binaryFiles: <String, List<int>>{'OEBPS/Images/cover.png': png},
      itemrefAttributes: ' properties="duokan-page-fullscreen"',
      contentWidth: 320,
      contentHeight: 480,
    );
    final pages = await source.loadChapter(0);
    final block = pages.single.slices.single.block;
    expect(
      block.style!.backgroundSize.mode,
      CssBackgroundSizeMode.cover,
      reason: 'OPF fullscreen 页面按 cover 铺满',
    );
    const pageSize = Size(320, 480);
    final band = await _renderCoverBand(
      source: source,
      png: png,
      pageSize: pageSize,
    );
    expect(band.top, lessThanOrEqualTo(1), reason: 'cover 页面顶部无白边');
    expect(band.bottom, greaterThanOrEqualTo(478), reason: 'cover 页面底部无白边');
    expect(band.leftEdge, isTrue, reason: '宽度撑满版心（无左右留白）');
    expect(band.rightEdge, isTrue);
    final drawnHeight = band.bottom - band.top + 1;
    expect(drawnHeight, closeTo(480, 1), reason: '图片铺满整个页面高度');
  });

  test('同时提供 ~slim 变体时，按页面比例选择更接近的一张', () async {
    final original = await _pngBytes(120, 90);
    final slim = await _pngBytes(60, 100);
    final source = await openCssChapter(
      body: coverBody,
      binaryFiles: <String, List<int>>{
        'OEBPS/Images/cover.png': original,
        'OEBPS/Images/cover~slim.png': slim,
      },
      itemrefAttributes: ' properties="duokan-page-fullscreen"',
      contentWidth: 300,
      contentHeight: 500,
    );
    final block = (await source.loadChapter(0)).single.slices.single.block;
    expect(
      block.style!.backgroundImage,
      'OEBPS/Images/cover~slim.png',
      reason: '页面比例 0.6，slim 图比例 0.6 比原图 1.33 更接近',
    );
    expect(block.style!.backgroundSize.mode, CssBackgroundSizeMode.cover);
  });

  test('图片宽高比与页面几乎一致（<2%）→ cover 铺满不留白', () async {
    final png = await _pngBytes(320, 480);
    final source = await openCssChapter(
      body: coverBody,
      binaryFiles: <String, List<int>>{'OEBPS/Images/cover.png': png},
      itemrefAttributes: ' properties="duokan-page-fullscreen"',
      contentWidth: 320,
      contentHeight: 480,
    );
    final block = (await source.loadChapter(0)).single.slices.single.block;
    expect(
      block.style!.backgroundSize.mode,
      CssBackgroundSizeMode.cover,
      reason: '宽高比几乎一致时 cover 无损铺满',
    );
    final band = await _renderCoverBand(
      source: source,
      png: png,
      pageSize: const Size(320, 480),
    );
    expect(band.top, lessThanOrEqualTo(1), reason: 'cover 顶部无留白');
    expect(band.bottom, greaterThanOrEqualTo(478), reason: 'cover 底部无留白');
  });

  test('duokan-page-fitwindow：contain 适配并在页内居中', () async {
    final source = await openCssChapter(
      body: coverBody,
      binaryFiles: <String, List<int>>{
        'OEBPS/Images/cover.png': await coverPng(),
      },
      itemrefAttributes: ' properties="duokan-page-fitwindow"',
      contentWidth: 300,
      contentHeight: 500,
    );
    expect(source.chapterPageFlags(0).fitWindow, isTrue);
    expect(source.chapterPageFlags(0).fullScreen, isFalse);
    final pages = await source.loadChapter(0);
    final block = pages.single.slices.single.block;
    expect(
      block.style!.backgroundSize.mode,
      CssBackgroundSizeMode.contain,
      reason: 'fitwindow 用 contain 不裁切',
    );
    expect(block.style!.backgroundPosition.y, isNotNull);
    expect(block.layout.height, closeTo(500, 0.01));
  });

  test('duokan-page-fullscreen-spread-left/right 按全屏处理并保留裁切方向', () async {
    final left = await openCssChapter(
      body: coverBody,
      binaryFiles: <String, List<int>>{
        'OEBPS/Images/cover.png': await coverPng(),
      },
      itemrefAttributes: ' properties="duokan-page-fullscreen-spread-left"',
    );
    expect(left.chapterPageFlags(0).fullScreen, isTrue);
    expect(left.chapterPageFlags(0).spreadLeft, isTrue);
    expect((await left.loadChapter(0)).single.slices.single.block.bleedLeft, isTrue);

    final right = await openCssChapter(
      body: coverBody,
      binaryFiles: <String, List<int>>{
        'OEBPS/Images/cover.png': await coverPng(),
      },
      itemrefAttributes: ' properties="duokan-page-fullscreen-spread-right"',
    );
    expect(right.chapterPageFlags(0).spreadRight, isTrue);
    expect(right.chapterPageFlags(0).fullScreen, isTrue);
  });

  test('无 page 属性时按普通章节排版（不回退整页图）', () async {
    final source = await openCssChapter(
      body: '<p>普通正文</p>',
      css: 'p { margin: 0; }',
    );
    expect(source.chapterPageFlags(0).isFullPage, isFalse);
    final pages = await source.loadChapter(0);
    expect(pages.single.slices.first.block.style!.backgroundImage, isNull);
  });

  test('真书取证：mj-003 / zhushen-yuxi 的封面章按全屏铺满', () async {
    // 语料：两本多看书的 OPF 都把封面章标成
    // `<itemref idref="cover.xhtml" properties="duokan-page-fullscreen"/>`。
    for (final name in <String>['mj-003.epub', 'zhushen-yuxi.epub']) {
      final file = File('../../test_corpus/real/$name');
      if (!file.existsSync()) {
        continue;
      }
      final source = await EpubChapterSource.open(
        file.readAsBytesSync(),
        verifyCrc: false,
      );
      await source.applyContentSize(width: 320, height: 711);
      expect(
        source.chapterPageFlags(0).fullScreen,
        isTrue,
        reason: '$name 封面章带 duokan-page-fullscreen',
      );
      final pages = await source.loadChapter(0);
      final block = pages.single.slices.single.block;
      expect(block.bleedLeft, isTrue);
      expect(block.bleedRight, isTrue);
      // 真书同时提供 ~slim 变体；全屏页按 cover 铺满，且优先匹配
      // 当前屏幕比例，避免为了铺满而大幅裁切主封面。
      expect(
        block.style!.backgroundSize.mode,
        CssBackgroundSizeMode.cover,
        reason: '$name 全屏封面按 cover 铺满',
      );
      expect(
        block.style!.backgroundImage,
        endsWith('~slim.jpg'),
        reason: '$name 应优先选择与屏幕比例更接近的 slim 封面',
      );
      // 整页尺寸 = 页宽/页高（不被正文样式或页边距裁小）。
      expect(block.layout.width, closeTo(320, 0.01));
      expect(block.layout.height, closeTo(711, 0.01));
    }
  });

  test('全屏标记但章内没有图片：退回普通排版，不丢正文', () async {
    final source = await openCssChapter(
      body: '<p>只有文字的一章</p>',
      css: 'p { margin: 0; }',
      itemrefAttributes: ' properties="duokan-page-fullscreen"',
    );
    expect(source.chapterPageFlags(0).fullScreen, isTrue);
    final pages = await source.loadChapter(0);
    final text = pages
        .expand((page) => page.slices)
        .map((slice) => slice.block.layout.text)
        .join();
    expect(text, contains('只有文字'));
  });
}
