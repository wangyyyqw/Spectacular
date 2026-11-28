import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/image_cache.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_core/source/format_opener.dart';

import '../audit/audit_epub_fixture.dart';

const _pageSize = Size(384, 853.3333333333333);
const _insets = EdgeInsets.fromLTRB(
  8.8,
  56.075,
  8.53333333333336,
  24.08888888888893,
);
const _imagePath = 'R (1).png';
const _imageHref = '../../R%20%281%29.png';
const _imageColor = Color(0xff008800);

Future<Uint8List> _imageBytes() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(_imageColor, BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(768, 1024);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
        .asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Uint8List _epub(Uint8List image, String body, String css) => auditZip({
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml':
      '<container><rootfiles><rootfile full-path="OEBPS/book.opf"/>'
      '</rootfiles></container>',
  'OEBPS/book.opf':
      '<package version="3.0" unique-identifier="id" '
      'xmlns="http://www.idpf.org/2007/opf"><metadata '
      'xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="id">image-resource-url</dc:identifier>'
      '<dc:title>图片资源路径回归</dc:title></metadata><manifest>'
      '<item id="c" href="Text/info.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="s" href="Styles/style.css" media-type="text/css"/>'
      '<item id="i" href="../R%20%281%29.png" media-type="image/png"/>'
      '</manifest><spine><itemref idref="c"/></spine></package>',
  'OEBPS/Text/info.xhtml':
      '<html xmlns="http://www.w3.org/1999/xhtml"><head>'
      '<link rel="stylesheet" href="../Styles/style.css"/>'
      '</head><body>$body</body></html>',
  'OEBPS/Styles/style.css': 'body {margin:0;} $css',
  _imagePath: image,
});

Future<EpubChapterSource> _open(
  Uint8List image,
  String body,
  String css,
) async {
  final width = _pageSize.width - _insets.horizontal;
  final height = _pageSize.height - _insets.vertical;
  final source = await const EpubFormatOpener().openBytes(
    _epub(image, body, css),
    options: ReaderOpenOptions(contentWidth: width, contentHeight: height),
  );
  addTearDown(source.close);
  await source.applyOverrides(
    const ReaderOverrides(fontSize: 21, lineHeight: 1.6, paragraphSpacing: 10),
  );
  await source.applyContentSize(
    width: width,
    height: height,
    topInset: _insets.top,
    sideInsets: (left: _insets.left, right: _insets.right),
  );
  return source;
}

Iterable<ComputedStyle> _imageStyles(PageBlock block) sync* {
  if (block.style?.backgroundImage != null) yield block.style!;
  for (final box in block.layout.lines.expand((line) => line.inlineBoxes)) {
    if (box.spec.payload case final PageBlock payload) {
      yield* _imageStyles(payload);
    }
  }
}

Future<ByteData> _paint(PageContent page, DecodedImageCache cache) async {
  final recorder = ui.PictureRecorder();
  PagePainter(imageLookup: cache.lookup)
      .paint(Canvas(recorder), page, pageSize: _pageSize, pageInsets: _insets);
  final picture = recorder.endRecording();
  final image = await picture.toImage(384, 854);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Rect _imageBounds(ByteData pixels) {
  var left = 384;
  var top = 854;
  var right = -1;
  var bottom = -1;
  for (var y = 0; y < 854; y++) {
    for (var x = 0; x < 384; x++) {
      final offset = (y * 384 + x) * 4;
      if (pixels.getUint8(offset) != 0 ||
          pixels.getUint8(offset + 1) != 136 ||
          pixels.getUint8(offset + 2) != 0) {
        continue;
      }
      if (x < left) left = x;
      if (x > right) right = x;
      if (y < top) top = y;
      if (y > bottom) bottom = y;
    }
  }
  expect(right, greaterThanOrEqualTo(left), reason: '必须从正式资源加载器取得图片并实际绘制');
  return Rect.fromLTRB(
    left.toDouble(),
    top.toDouble(),
    right + 1.0,
    bottom + 1.0,
  );
}

Future<Rect> _checkImage(
  Uint8List image,
  String body, {
  String css = '',
}) async {
  final source = await _open(image, body, css);
  final page = (await source.loadChapter(0)).single;
  final styles = page.slices.expand((slice) => _imageStyles(slice.block));
  final style = styles.single;
  expect(style.backgroundImage, _imagePath, reason: '图片转为背景载荷后，路径不能在括号处截断');
  final cache = DecodedImageCache(loadBytes: source.readImageBytes);
  addTearDown(cache.clear);
  expect(
    await cache.load(
      style.backgroundImage!,
      displayWidth: _pageSize.width - _insets.horizontal,
      devicePixelRatio: 2.8125,
    ),
    isNotNull,
  );
  return _imageBounds(await _paint(page, cache));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Uint8List image;
  setUpAll(() async => image = await _imageBytes());

  test('块级缩略图加载含空格括号的路径，保留百分比宽度和居中样式', () async {
    final bounds = await _checkImage(
      image,
      '<div class="info"><div class="cover"><img src="$_imageHref"/></div>'
      '<p>书名</p><p>作者</p></div>',
      css:
          '.info {margin:0 auto; padding:16px;}'
          '.cover img {width:30%; max-width:300px; height:auto;'
          'margin:0 auto 24px; display:block; border-radius:4px;'
          'box-shadow:0 6px 18px rgba(80,80,80,.52);}',
    );
    final width = (_pageSize.width - _insets.horizontal - 32) * .3;
    expect(bounds.width, closeTo(width, 2));
    expect(bounds.height, closeTo(width * 4 / 3, 2));
    expect(
      bounds.center.dx,
      closeTo(_insets.left + (_pageSize.width - _insets.horizontal) / 2, 1),
    );
  });

  test('整页单图加载含空格括号的资源并完整绘制', () async {
    final bounds = await _checkImage(
      image,
      '<div><img src="$_imageHref"/></div>',
    );
    expect(bounds.width, closeTo(_pageSize.width, 2));
    expect(bounds.height, closeTo(bounds.width * 4 / 3, 2));
  });

  test('正文行内图片的背景载荷保留含空格括号的路径', () async {
    final bounds = await _checkImage(
      image,
      '<p>甲<img src="$_imageHref" style="width:36px;height:48px"/>乙</p>',
    );
    expect(bounds.width, closeTo(36, 2));
    expect(bounds.height, closeTo(48, 2));
  });

  test('从正文提取的浮动图片加载完整资源路径', () async {
    final bounds = await _checkImage(
      image,
      '<p>甲<img src="$_imageHref" '
      'style="float:left;width:36px;height:48px"/>乙</p><p>丙</p>',
    );
    expect(bounds.width, closeTo(36, 2));
    expect(bounds.height, closeTo(48, 2));
  });
}
