import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/epub/extension.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';

import 'support/css_chapter_book.dart';

const _width = 200;
const _height = 500;
const _imagePath = 'OEBPS/Images/cover.png';
const _body =
    '<h2 title="封面"></h2><div>'
    '<img alt="cover" style="width:100%" src="../Images/cover.png"/>'
    '</div>';
late ui.Image _image;
late Uint8List _png;

Future<void> _prepareImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  const colors = [0xffff0000, 0xff00ff00, 0xff0000ff];
  for (var column = 0; column < colors.length; column++) {
    canvas.drawRect(
      ui.Rect.fromLTWH(column * 200.0, 0, 200, 500),
      ui.Paint()..color = ui.Color(colors[column]),
    );
  }
  final picture = recorder.endRecording();
  _image = await picture.toImage(600, 500);
  picture.dispose();
  _png = (await _image.toByteData(format: ui.ImageByteFormat.png))!.buffer
      .asUint8List();
}

Future<EpubChapterSource> _open(
  String properties, {
  String layout = 'reflow',
  String body = _body,
}) async {
  final source = await openCssChapter(
    body: body,
    itemrefAttributes: ' properties="$properties"',
    contentWidth: _width.toDouble(),
    contentHeight: _height.toDouble(),
    binaryFiles: {
      _imagePath: _png,
      if (layout != 'reflow')
        DuokanExtensionParser.path: utf8.encode(
          '<duokan-extension version="1.0"><display-options>'
          '<layout>$layout</layout>'
          '</display-options></duokan-extension>',
        ),
    },
  );
  addTearDown(source.close);
  return source;
}

Future<ByteData> _paint(PageContent page) async {
  final recorder = ui.PictureRecorder();
  PagePainter(imageLookup: (_) => _image).paint(
    ui.Canvas(recorder),
    page,
    pageSize: ui.Size(_width.toDouble(), _height.toDouble()),
  );
  final picture = recorder.endRecording();
  final output = await picture.toImage(_width, _height);
  picture.dispose();
  final pixels = await output.toByteData(format: ui.ImageByteFormat.rawRgba);
  output.dispose();
  return pixels!;
}

void _expectSolidCrop(ByteData pixels, int color) {
  for (final (x, y) in [(10, 20), (100, 250), (190, 480)]) {
    expect(
      pixels.getUint32((y * _width + x) * 4),
      color,
      reason: '实际绘制像素 ($x, $y) 必须来自指定侧，不能居中或拉伸整图',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_prepareImage);
  tearDownAll(() => _image.dispose());

  for (final layout in ['reflow', 'fixed-page']) {
    for (final (side, color) in [('left', 0xff0000ff), ('right', 0x0000ffff)]) {
      test('$layout 全屏跨页图按 $side 裁切，保留整页与原图比例', () async {
        final source = await _open(
          'duokan-page-fullscreen-spread-$side',
          layout: layout,
        );
        final pages = await source.loadChapter(0);
        expect(pages, hasLength(1));
        expect(pages.single.slices, hasLength(1));
        final block = pages.single.slices.single.block;
        expect(block.style!.backgroundSize.mode, CssBackgroundSizeMode.cover);
        expect(block.bleedLeft && block.bleedRight, isTrue);
        expect(block.bleedTop && block.bleedBottom, isTrue);
        expect(block.startCfi, isNotNull);
        _expectSolidCrop(await _paint(pages.single), color);
      });
    }

    test('$layout 普通全屏图保持居中裁切', () async {
      final source = await _open('duokan-page-fullscreen', layout: layout);
      final page = (await source.loadChapter(0)).single;
      _expectSolidCrop(await _paint(page), 0x00ff00ff);
    });

    test('$layout fitwindow 优先于左右跨页裁切，完整图片居中显示', () async {
      for (final side in ['left', 'right']) {
        final source = await _open(
          'duokan-page-fullscreen-spread-$side duokan-page-fitwindow',
          layout: layout,
        );
        final page = (await source.loadChapter(0)).single;
        expect(
          page.slices.single.block.style!.backgroundSize.mode,
          CssBackgroundSizeMode.contain,
        );
        final pixels = await _paint(page);
        for (final (x, color) in [
          (25, 0xff0000ff),
          (100, 0x00ff00ff),
          (175, 0x0000ffff),
        ]) {
          expect(pixels.getUint32((250 * _width + x) * 4), color);
        }
        expect(pixels.getUint32((10 * _width + 100) * 4), 0xffffffff);
        expect(pixels.getUint32((490 * _width + 100) * 4), 0xffffffff);
      }
    });
  }

  for (final side in ['left', 'right']) {
    test('标准 page-spread-$side 保留页面位置属性，不触发整页图', () async {
      final source = await _open(
        'page-spread-$side',
        body:
            '<p>正文保留</p>'
            '<img src="../Images/cover.png" width="90" height="60"/>',
      );
      expect(
        source.document.spine.single.properties,
        contains('page-spread-$side'),
      );
      expect(source.chapterPageFlags(0).isFullPage, isFalse);
      final pages = await source.loadChapter(0);
      expect(
        pages
            .expand((page) => page.slices)
            .map((slice) => slice.block.layout.text),
        contains('正文保留'),
      );
    });

    test('标准 page-spread-$side 与普通全屏组合时不改变图片裁切方向', () async {
      final source = await _open('duokan-page-fullscreen page-spread-$side');
      final page = (await source.loadChapter(0)).single;
      _expectSolidCrop(await _paint(page), 0x00ff00ff);
    });
  }

  test('左右跨页标记冲突时居中裁切', () async {
    final source = await _open(
      'duokan-page-fullscreen-spread-left duokan-page-fullscreen-spread-right',
    );
    final page = (await source.loadChapter(0)).single;
    _expectSolidCrop(await _paint(page), 0x00ff00ff);
  });
}
