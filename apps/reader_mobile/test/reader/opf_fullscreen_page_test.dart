import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const coverBody = '<img src="../Images/cover.png"/>';

  Future<List<int>> coverPng() => _pngBytes(120, 90);

  test('duokan-page-fullscreen：整页 cover 铺满，正文样式不裁剪封面', () async {
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
      reason: '全屏页 cover 铺满',
    );
    expect(block.bleedLeft, isTrue);
    expect(block.bleedRight, isTrue);
    // 整页尺寸 = 原始页（300×500），不被 body padding 或 img 尺寸压小。
    expect(block.layout.width, closeTo(300, 0.01));
    expect(block.layout.height, closeTo(500, 0.01));
    expect(pages.single.usedHeight, closeTo(500, 0.01));
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

  test('duokan-page-fullscreen-spread-left/right 也按全屏处理并记录左右页', () async {
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
      // 标准 page-spread-* 同样识别为跨页标记。
      itemrefAttributes: ' properties="page-spread-right"',
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
      expect(
        source.chapterPageFlags(0).fullScreen,
        isTrue,
        reason: '$name 封面章带 duokan-page-fullscreen',
      );
      final pages = await source.loadChapter(0);
      final block = pages.single.slices.single.block;
      expect(block.bleedLeft, isTrue);
      expect(block.bleedRight, isTrue);
      expect(
        block.style!.backgroundSize.mode,
        CssBackgroundSizeMode.cover,
        reason: '$name 封面按 cover 铺满整页',
      );
      // 整页尺寸 = 页宽/页高（不被正文样式或页边距裁小）。
      expect(block.layout.width, closeTo(320, 0.01));
      expect(block.layout.height, closeTo(480, 0.01));
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
