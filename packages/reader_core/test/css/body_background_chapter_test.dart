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
const _bands = [
  Color(0xFFFF0000),
  Color(0xFF00FF00),
  Color(0xFF0000FF),
  Color(0xFFFFFF00),
];

Future<ui.Image> _coverImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  for (var index = 0; index < _bands.length; index++) {
    canvas.drawRect(
      Rect.fromLTWH(0, index * 600, 1080, 600),
      Paint()..color = _bands[index],
    );
  }
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(1080, 2400);
  } finally {
    picture.dispose();
  }
}

Uint8List _bookBytes(
  Uint8List imageBytes,
  String body,
  String css,
) => auditZip({
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml':
      '<container><rootfiles><rootfile full-path="book.opf"/>'
      '</rootfiles></container>',
  'book.opf':
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
      'unique-identifier="id"><metadata '
      'xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="id">body-background</dc:identifier>'
      '<dc:title>空正文全屏背景回归</dc:title></metadata><manifest>'
      '<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="css" href="common.css" media-type="text/css"/>'
      '<item id="pic" href="cover.png" media-type="image/png"/>'
      '</manifest><spine><itemref idref="c"/></spine></package>',
  'c.xhtml':
      '<html xmlns="http://www.w3.org/1999/xhtml"><head>'
      '<link rel="stylesheet" href="common.css"/></head>'
      '<body style="background-image:url(cover.png);'
      'background-repeat:no-repeat;background-size:cover">$body</body></html>',
  'common.css':
      'html, body { height:100%; margin:0; padding:0; } '
      'p { line-height:130%; margin-left:1%; margin-right:1%; '
      'text-indent:2em; } $css',
  'cover.png': imageBytes,
});

Future<PageContent> _page(
  ui.Image cover,
  String body, {
  String css = '',
}) async {
  final imageBytes = (await cover.toByteData(format: ui.ImageByteFormat.png))!
      .buffer
      .asUint8List();
  final source = await const EpubFormatOpener().openBytes(
    _bookBytes(imageBytes, body, css),
    options: ReaderOpenOptions(
      contentWidth: _pageSize.width - _pageInsets.horizontal,
      contentHeight: _pageSize.height - _pageInsets.vertical,
    ),
  );
  addTearDown(source.close);
  await source.applyOverrides(
    const ReaderOverrides(fontSize: 21, lineHeight: 1.6, paragraphSpacing: 10),
  );
  return (await source.loadChapter(0)).single;
}

Future<ByteData> _render(PageContent page, ui.Image cover) async {
  final recorder = ui.PictureRecorder();
  PagePainter(
    imageLookup: (url) => url == 'cover.png' ? cover : null,
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

void _expectFullScreenCover(ByteData pixels) {
  for (var index = 0; index < _bands.length; index++) {
    final y = _pageSize.height * index / 4 + 12;
    for (final x in [4.0, 24.0, 192.0, 380.0]) {
      expect(
        _pixel(pixels, x, y),
        _bands[index],
        reason: '第 ${index + 1} 条色带在页边和正文区必须连续，不能重复缩放',
      );
    }
  }
  for (final x in [4.0, 380.0]) {
    expect(_pixel(pixels, x, 840), _bands.last, reason: '封面必须铺满屏幕底部');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final body in ['', '<p>&#160;</p>']) {
    test('空正文 "$body" 的 cover 背景铺满全屏，正文区没有接缝', () async {
      final cover = await _coverImage();
      addTearDown(cover.dispose);
      final page = await _page(cover, body);
      _expectFullScreenCover(await _render(page, cover));
    });
  }

  test('全屏背景传播后，普通空子盒的背景与边框仍正常绘制', () async {
    final cover = await _coverImage();
    addTearDown(cover.dispose);
    final page = await _page(
      cover,
      '<div class="panel"></div>',
      css:
          '.panel { width:120px; height:80px; background:#ff00ff; '
          'border:4px solid #000000; }',
    );
    final pixels = await _render(page, cover);
    expect(_pixel(pixels, 24, 72), const Color(0xFFFF00FF));
    expect(_pixel(pixels, 24, 58), const Color(0xFF000000));
    expect(_pixel(pixels, 24, 240), _bands[1]);
    expect(_pixel(pixels, 380, 840), _bands.last);
  });
}
