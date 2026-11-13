import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/image_cache.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_core/source/format_opener.dart';

import '../audit/audit_epub_fixture.dart';

const _pageSize = Size(384, 853.3333333333334);
const _insets = EdgeInsets.fromLTRB(
  8.8,
  56.07500000000001,
  8.53333333333336,
  24.08888888888893,
);
const _ratio = 2.8125;
const _width = 1080;
const _height = 2400;
const _blue = 0x0e27e8ff;
const _background = 0xd422eeff;
const _css = '''
body { margin:0 .5%; padding:0; background:#d422ee; font-family:Ahem; }
h1 { margin:0; padding:0; font-size:100%; duokan-bleed:lefttopright; }
img { width:100%; margin:0; padding:0; }
.number { background:#0e27e8; margin:5% auto 0; padding:5px 10px;
  width:1em; text-align:center; border:4px solid white;
  font-size:1.3em; line-height:130%; color:white; }
.name { margin:1.5em auto 0; padding:5px; text-align:center;
  font-size:1.5em; line-height:130%; }
.name span { padding:5px; border:solid white; border-width:4px 0;
  color:white; }
''';

Future<Uint8List> _banner() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(const Color(0xff00aa00), BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(16, 9);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
        .asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Future<Uint8List> _epub(String extraCss) async => auditZip({
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml':
      '<container><rootfiles><rootfile full-path="book.opf"/>'
      '</rootfiles></container>',
  'book.opf':
      '<package version="3.0" unique-identifier="id" '
      'xmlns="http://www.idpf.org/2007/opf"><metadata '
      'xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="id">ancestor-bleed</dc:identifier>'
      '<dc:title>祖先出血回归</dc:title></metadata><manifest>'
      '<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="i" href="banner.png" media-type="image/png"/>'
      '</manifest><spine><itemref idref="c"/></spine></package>',
  'c.xhtml':
      '<html xmlns="http://www.w3.org/1999/xhtml"><head>'
      '<style>$_css $extraCss</style></head><body><h1>'
      '<img src="banner.png"/><div class="number">ABC</div>'
      '<div class="name"><span>DEFG</span></div></h1></body></html>',
  'banner.png': await _banner(),
});

Future<({PageContent page, ByteData pixels})> _render({
  String extraCss = '',
}) async {
  final source = await const EpubFormatOpener().openBytes(
    await _epub(extraCss),
    options: ReaderOpenOptions(
      contentWidth: _pageSize.width - _insets.horizontal,
      contentHeight: _pageSize.height - _insets.vertical,
    ),
  );
  addTearDown(source.close);
  await source.applyOverrides(
    const ReaderOverrides(fontSize: 21, lineHeight: 1.6, paragraphSpacing: 10),
  );
  await source.applyContentSize(
    width: _pageSize.width - _insets.horizontal,
    height: _pageSize.height - _insets.vertical,
    topInset: _insets.top,
    sideInsets: (left: _insets.left, right: _insets.right),
  );
  final page = (await source.loadChapter(0)).single;
  final cache = DecodedImageCache(loadBytes: source.readImageBytes);
  addTearDown(cache.clear);
  await cache.load('banner.png', displayWidth: _pageSize.width);
  return (page: page, pixels: await _paint(page, cache));
}

Future<ByteData> _paint(PageContent page, DecodedImageCache cache) async {
  final recorder = ui.PictureRecorder();
  PagePainter(imageLookup: cache.lookup).paint(
    Canvas(recorder)..scale(_ratio),
    page,
    pageSize: _pageSize,
    pageInsets: _insets,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(_width, _height);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  } finally {
    image.dispose();
    picture.dispose();
  }
}

int _pixel(ByteData pixels, int x, int y) =>
    pixels.getUint32((y * _width + x) * 4);

Rect _blueBounds(ByteData pixels) {
  var left = _width, top = _height, right = -1, bottom = -1;
  for (var y = 0; y < _height; y++) {
    for (var x = 0; x < _width; x++) {
      if (_pixel(pixels, x, y) != _blue) continue;
      if (x < left) left = x;
      if (y < top) top = y;
      if (x > right) right = x;
      if (y > bottom) bottom = y;
    }
  }
  expect(right, greaterThanOrEqualTo(left), reason: '作者背景必须实际绘制');
  return Rect.fromLTRB(
    left.toDouble(),
    top.toDouble(),
    right + 1.0,
    bottom + 1.0,
  );
}

PageBlock _number(PageContent page) =>
    page.slices.singleWhere((slice) => slice.block.layout.text == 'ABC').block;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('祖先横幅出血不扩大后代窄标题的背景和白框', () async {
    final result = await _render();
    final number = _number(result.page);
    expect(number.bleedLeft, isFalse);
    expect(number.bleedRight, isFalse);
    expect(number.bleedTop, isFalse);
    expect(number.style!.borders.left.isVisible, isTrue);
    final bounds = _blueBounds(result.pixels);
    expect(bounds.width / _ratio, lessThan(60));
    expect(bounds.center.dx / _ratio, closeTo(_pageSize.width / 2, 1));
    expect(_pixel(result.pixels, 5, bounds.center.dy.round()), _background);
    expect(
      _pixel(result.pixels, bounds.left.round() - 5, bounds.center.dy.round()),
      0xffffffff,
      reason: '作者声明的白框仍紧贴标题盒',
    );
  });

  test('祖先出血仍传给横幅图片，图片铺到页顶及两侧', () async {
    final result = await _render();
    final image = result.page.slices.first.block;
    expect(image.bleedLeft, isTrue);
    expect(image.bleedRight, isTrue);
    expect(image.bleedTop, isTrue);
    expect(_pixel(result.pixels, 1, 1), 0x00aa00ff);
    expect(_pixel(result.pixels, _width - 2, 1), 0x00aa00ff);
  });

  test('标题自身声明出血时仍扩展背景及白框', () async {
    final result = await _render(extraCss: '.number {duokan-bleed:leftright;}');
    final number = _number(result.page);
    expect(number.bleedLeft, isTrue);
    expect(number.bleedRight, isTrue);
    expect(number.bleedTop, isFalse);
    expect(_blueBounds(result.pixels).width / _ratio, greaterThan(375));
  });
}
