import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_core/source/format_opener.dart';

import '../audit/audit_epub_fixture.dart';

const _pageSize = Size(384, 853.3333333333333);
const _pageInsets = EdgeInsets.fromLTRB(
  8.8,
  56.075,
  8.53333333333336,
  24.08888888888893,
);
const _imageColor = Color(0xFF008800);

Future<ui.Image> _bannerImage() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(_imageColor, BlendMode.src);
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(432, 150);
  } finally {
    picture.dispose();
  }
}

Uint8List _bookBytes(String position, Uint8List imageBytes) => auditZip({
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml':
      '<container><rootfiles><rootfile full-path="book.opf"/>'
      '</rootfiles></container>',
  'book.opf':
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
      'unique-identifier="id"><metadata '
      'xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="id">relative-container-margin</dc:identifier>'
      '<dc:title>相对定位容器边距回归</dc:title></metadata><manifest>'
      '<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="image" href="banner.png" media-type="image/png"/>'
      '</manifest><spine><itemref idref="c"/></spine></package>',
  'c.xhtml':
      '<html xmlns="http://www.w3.org/1999/xhtml"><head><style>'
      'body { margin:0; padding:0 10%; font-family:Ahem; } '
      'div { margin-top:80%; text-align:center; position:$position; } '
      'img { margin:0; width:100%; } '
      'p { margin:1em 0 0; font-size:1.2em; line-height:1.25em; '
      'text-indent:0; text-align:center; color:#000; } '
      '</style></head><body><h2 title="横幅"></h2><div>'
      '<img src="banner.png" alt="横幅"/><p>横幅说明</p>'
      '</div></body></html>',
  'banner.png': imageBytes,
});

Future<PageContent> _page(String position, ui.Image banner) async {
  final imageBytes = (await banner.toByteData(format: ui.ImageByteFormat.png))!
      .buffer
      .asUint8List();
  final source = await const EpubFormatOpener().openBytes(
    _bookBytes(position, imageBytes),
    options: ReaderOpenOptions(
      contentWidth: _pageSize.width - _pageInsets.horizontal,
      contentHeight: _pageSize.height - _pageInsets.vertical,
    ),
  );
  addTearDown(source.close);
  await source.applyOverrides(
    const ReaderOverrides(fontSize: 21, lineHeight: 1.6, paragraphSpacing: 10),
  );
  await source.applyContentSize(
    width: _pageSize.width - _pageInsets.horizontal,
    height: _pageSize.height - _pageInsets.vertical,
    topInset: _pageInsets.top,
    sideInsets: (left: _pageInsets.left, right: _pageInsets.right),
  );
  return (await source.loadChapter(0)).single;
}

Future<ByteData> _render(PageContent page, ui.Image banner) async {
  final recorder = ui.PictureRecorder();
  PagePainter(
    imageLookup: (_) => banner,
  ).paint(Canvas(recorder), page, pageSize: _pageSize, pageInsets: _pageInsets);
  final picture = recorder.endRecording();
  final image = await picture.toImage(384, 854);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Color _pixel(ByteData pixels, double x, double y) {
  final offset = (y.round() * 384 + x.round()) * 4;
  return Color.fromARGB(
    pixels.getUint8(offset + 3),
    pixels.getUint8(offset),
    pixels.getUint8(offset + 1),
    pixels.getUint8(offset + 2),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final position in ['static', 'relative']) {
    test('$position 容器按父内容宽保留百分比上距，横幅及说明同步下移', () async {
      final banner = await _bannerImage();
      addTearDown(banner.dispose);
      final page = await _page(position, banner);
      final image = page.slices.first;
      final caption = page.slices[1];
      final bodyWidth = (_pageSize.width - _pageInsets.horizontal) * .8;
      final topMargin = bodyWidth * .8;
      final imageHeight = bodyWidth * 150 / 432;
      expect(image.leadingExtent, closeTo(topMargin, .001));
      expect(
        image.block.style!.width!.resolve(bodyWidth),
        closeTo(bodyWidth, .001),
      );
      expect(image.block.layout.height, closeTo(imageHeight, .001));
      expect(caption.block.layout.text, '横幅说明');
      expect(caption.leadingExtent, closeTo(21 * 1.2, .001));
      expect(
        page.usedHeight,
        closeTo(topMargin + imageHeight + caption.height, .001),
        reason: '父容器外边距只消费一次，图片说明保留自身段距',
      );
      final pixels = await _render(page, banner);
      final top = _pageInsets.top + topMargin;
      expect(_pixel(pixels, 192, _pageInsets.top + 2), const Color(0xFFFFFFFF));
      expect(_pixel(pixels, 192, top - 2), const Color(0xFFFFFFFF));
      expect(_pixel(pixels, 192, top + 2), _imageColor);
      expect(_pixel(pixels, 192, top + imageHeight - 2), _imageColor);
      expect(
        _pixel(pixels, _pageInsets.left + 2, top + 2),
        const Color(0xFFFFFFFF),
      );
    });
  }
}
