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
const _imageSize = Size(428, 571);
const _corners = [
  Color(0xFFFF0000),
  Color(0xFF00FF00),
  Color(0xFF0000FF),
  Color(0xFFFFFF00),
];

Future<ui.Image> _coverImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Offset.zero & _imageSize,
    Paint()..color = const Color(0xFF808080),
  );
  for (var index = 0; index < _corners.length; index++) {
    canvas.drawRect(
      Rect.fromLTWH(
        index % 2 == 0 ? 0 : _imageSize.width - 16,
        index < 2 ? 0 : _imageSize.height - 16,
        16,
        16,
      ),
      Paint()..color = _corners[index],
    );
  }
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(428, 571);
  } finally {
    picture.dispose();
  }
}

Uint8List _bookBytes(Uint8List imageBytes) => auditZip({
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml':
      '<container><rootfiles><rootfile full-path="book.opf"/>'
      '</rootfiles></container>',
  'book.opf':
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
      'unique-identifier="id"><metadata '
      'xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="id">single-image</dc:identifier>'
      '<dc:title>单图封面回归</dc:title></metadata><manifest>'
      '<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="css" href="common.css" media-type="text/css"/>'
      '<item id="pic" href="cover.png" media-type="image/png"/>'
      '</manifest><spine><itemref idref="c"/></spine></package>',
  'c.xhtml':
      '<html xmlns="http://www.w3.org/1999/xhtml"><head>'
      '<link rel="stylesheet" href="common.css"/></head><body><section>'
      '<div><div class="centered-image">'
      '<img src="cover.png" alt="封面"/>'
      '</div></div></section></body></html>',
  'common.css':
      'body { font-size:16px; line-height:1.8; } '
      '.centered-image { display:flex; justify-content:center; }',
  'cover.png': imageBytes,
});

Future<PageContent> _coverPage(Uint8List imageBytes) async {
  final source = await const EpubFormatOpener().openBytes(
    _bookBytes(imageBytes),
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
    imageLookup: (_) => cover,
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

void _expectCompleteCover(ByteData pixels) {
  final width = _pageSize.width - _pageInsets.horizontal;
  final contentHeight = _pageSize.height - _pageInsets.vertical;
  final height = width * _imageSize.height / _imageSize.width;
  final top = _pageInsets.top + (contentHeight - height) / 2;
  for (var index = 0; index < _corners.length; index++) {
    final x = _pageInsets.left + (index % 2 == 0 ? 4 : width - 4);
    final y = top + (index < 2 ? 4 : height - 4);
    expect(
      _pixel(pixels, x, y),
      _corners[index],
      reason: '原图第 ${index + 1} 个角的标记必须完整可见，不能铺满后裁切',
    );
  }
  expect(_pixel(pixels, _pageSize.width / 2, top - 4), const Color(0xFFFFFFFF));
  expect(
    _pixel(pixels, _pageSize.width / 2, top + height + 4),
    const Color(0xFFFFFFFF),
  );
  expect(_pixel(pixels, 4, top + height / 2), const Color(0xFFFFFFFF));
  expect(_pixel(pixels, 380, top + height / 2), const Color(0xFFFFFFFF));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('无裁切声明的居中单图在手机版心内完整等比显示，四角及页边距保留', () async {
    final cover = await _coverImage();
    addTearDown(cover.dispose);
    final imageBytes = (await cover.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
    final page = await _coverPage(imageBytes);
    final block = page.slices.single.block;
    expect(block.startCfi, isNotNull);
    expect(block.bleedLeft || block.bleedRight, isFalse);
    expect(block.bleedTop || block.bleedBottom, isFalse);
    expect(
      block.layout.height,
      closeTo(_pageSize.height - _pageInsets.vertical, 0.001),
    );
    _expectCompleteCover(await _render(page, cover));
  });
}
