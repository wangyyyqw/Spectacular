import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/page_renderer.dart';

import 'support/css_chapter_book.dart';

const _width = 300.0;
const _height = 500.0;
const _columnWidth = 147.0;
const _imageWidth = _columnWidth * .85;
const _color = 0x00cc44ff;
late ui.Image _image;
late Uint8List _png;

Future<PageContent> _page(
  String side, {
  bool image = true,
  bool caption = true,
  bool frame = false,
}) async {
  final source = await openCssChapter(
    body:
        '<div class="float"><div class="inner">'
        '${image ? '<img src="../Images/a.png" width="85%" height="80"/>' : ''}'
        '${caption ? '<p class="caption">人物图注</p>' : ''}'
        '</div></div><p class="flow">${'正文绕排。' * 70}</p>',
    css:
        'body {margin:0 1%; font-size:16px;} '
        '.float {float:$side; width:50%; margin:12px 6px 7px 8px; '
        '${frame ? 'padding:4px; border:2px solid #ff0000; background:#1122aa;' : ''}} '
        '.inner {text-align:center;} '
        '.caption {margin:10px 0; text-align:center; line-height:1;} '
        '.flow {margin:0; font-size:10px; line-height:1;}',
    binaryFiles: {'OEBPS/Images/a.png': _png},
    contentWidth: _width,
    contentHeight: _height,
  );
  addTearDown(source.close);
  return (await source.loadChapter(0)).first;
}

Future<void> _expectImagePixels(PageContent page, double left) async {
  const scale = 2;
  final recorder = ui.PictureRecorder();
  PagePainter(imageLookup: (_) => _image).paint(
    ui.Canvas(recorder)..scale(scale.toDouble()),
    page,
    pageSize: const ui.Size(_width, _height),
  );
  final picture = recorder.endRecording();
  final output = await picture.toImage(600, 1000);
  picture.dispose();
  final pixels = await output.toByteData(format: ui.ImageByteFormat.rawRgba);
  output.dispose();
  final row = page.slices.firstWhere((slice) => slice.block.isReplaced);
  final y = ((row.absoluteTop! + row.height / 2) * scale).floor();
  final colored = [
    for (var x = 0; x < 600; x++)
      if (pixels!.getUint32((y * 600 + x) * 4) == _color) x,
  ];
  expect(colored, isNotEmpty);
  expect(colored.first, closeTo(left * scale, 1));
  expect(colored.last + 1, closeTo((left + _imageWidth) * scale, 1));
}

Future<void> _expectFrame(PageContent page, double left) async {
  final recorder = ui.PictureRecorder();
  PagePainter(
    imageLookup: (_) => _image,
  ).paint(ui.Canvas(recorder), page, pageSize: const ui.Size(_width, _height));
  final picture = recorder.endRecording();
  final image = await picture.toImage(300, 500);
  picture.dispose();
  final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  int pixel(int x, int y) => pixels!.getUint32((y * 300 + x) * 4);
  expect(pixel(left.toInt(), 40), 0xff0000ff);
  expect(pixel((left + 159 - 1).toInt(), 40), 0xff0000ff);
  expect(pixel((left + 80).toInt(), 12), 0xff0000ff);
  expect(pixel((left + 80).toInt(), 139), 0xff0000ff);
  expect(pixel((left + 5).toInt(), 95), 0x1122aaff);
}

void _expectWrapping(PageContent page, String side) {
  final float = page.slices.firstWhere((slice) => slice.overlay);
  expect(float.block.floatBox!.container.width, closeTo(_columnWidth, .01));
  final paragraph = page.slices.firstWhere((slice) => !slice.overlay);
  final lines = paragraph.block.layout.lines;
  if (side == 'left') {
    expect(lines.first.offsetX, closeTo(_columnWidth + 14, .01));
  } else {
    expect(lines.first.offsetX, 0);
    expect(lines.first.width, lessThanOrEqualTo(294 - _columnWidth - 14));
  }
  expect(
    lines.where((line) => line.offsetX == 0 && line.width > 200),
    isNotEmpty,
    reason: '整组浮动结束后恢复包含块全宽',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const ui.Color(0xff00cc44), ui.BlendMode.src);
    final picture = recorder.endRecording();
    _image = await picture.toImage(250, 160);
    picture.dispose();
    _png = (await _image.toByteData(format: ui.ImageByteFormat.png))!.buffer
        .asUint8List();
  });
  tearDownAll(() => _image.dispose());

  for (final side in ['left', 'right']) {
    test('$side 浮动图片和图注保留整组背景、内边距与边框', () async {
      final page = await _page(side, frame: true);
      final image = page.slices.firstWhere((slice) => slice.block.isReplaced);
      expect(image.block.floatBox!.container.width, 159);
      expect(image.absoluteTop, 18);
      await _expectFrame(page, side == 'left' ? 11 : 132);
    });

    test('$side 半宽浮动中的 85% 图片居中，正文避让整个容器', () async {
      final page = await _page(side);
      final image = page.slices.firstWhere((slice) => slice.block.isReplaced);
      final caption = page.slices.singleWhere(
        (slice) => slice.block.layout.text == '人物图注',
      );
      final containerLeft = side == 'left' ? 11.0 : 144.0;
      final imageLeft = containerLeft + (_columnWidth - _imageWidth) / 2;
      expect(image.block.layout.maxWidth, closeTo(_imageWidth, .01));
      expect(
        image.leftInset + image.block.style!.margin.left,
        closeTo(imageLeft, .01),
      );
      expect(image.absoluteTop, 12);
      expect(
        caption.leftInset + caption.block.style!.margin.left,
        closeTo(containerLeft, .01),
      );
      expect(caption.block.floatBox, same(image.block.floatBox));
      _expectWrapping(page, side);
      await _expectImagePixels(page, imageLeft);
    });

    test('$side 浮动首块为图注时仍按作者整盒宽占位', () async {
      _expectWrapping(await _page(side, image: false), side);
    });

    test('$side 单图祖先折叠后保留内部居中和容器占位', () async {
      final page = await _page(side, caption: false);
      final containerLeft = side == 'left' ? 11.0 : 144.0;
      _expectWrapping(page, side);
      await _expectImagePixels(
        page,
        containerLeft + (_columnWidth - _imageWidth) / 2,
      );
    });

    test('图片自身 $side 浮动时不再叠加父 text-align:center', () async {
      final source = await openCssChapter(
        body:
            '<div class="center"><img src="../Images/a.png"/></div>'
            '<p>正文</p>',
        css:
            'body,p {margin:0;} .center {text-align:center;} '
            'img {float:$side; width:80px; height:80px;}',
        binaryFiles: {'OEBPS/Images/a.png': _png},
        contentWidth: _width,
        contentHeight: _height,
      );
      addTearDown(source.close);
      final image = (await source.loadChapter(0)).first.slices.first;
      expect(image.block.floatBox, isNull);
      expect(
        image.leftInset + image.block.style!.margin.left,
        closeTo(side == 'left' ? 0 : 220, .01),
      );
    });
  }
}
