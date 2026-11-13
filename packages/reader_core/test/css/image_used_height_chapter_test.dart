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
const _coverSize = Size(988, 1388);
const _colors = [
  Color(0xFFFF0000),
  Color(0xFF00FF00),
  Color(0xFF0000FF),
  Color(0xFFFFFF00),
];
const _opf =
    '<package version="3.0" unique-identifier="id" '
    'xmlns="http://www.idpf.org/2007/opf"><metadata '
    'xmlns:dc="http://purl.org/dc/elements/1.1/">'
    '<dc:identifier id="id">image-used-height</dc:identifier>'
    '<dc:title>图片实际高度回归</dc:title></metadata><manifest>'
    '<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>'
    '<item id="pic" href="cover.png" media-type="image/png"/>'
    '</manifest><spine><itemref idref="c"/></spine></package>';

Future<ui.Image> _coverImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  for (var index = 0; index < _colors.length; index++) {
    canvas.drawRect(
      Rect.fromLTWH(
        index % 2 * _coverSize.width / 2,
        index ~/ 2 * _coverSize.height / 2,
        _coverSize.width / 2,
        _coverSize.height / 2,
      ),
      Paint()..color = _colors[index],
    );
  }
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(988, 1388);
  } finally {
    picture.dispose();
  }
}

Future<List<PageContent>> _pages(
  Uint8List imageBytes,
  String body, {
  String css = '',
}) async {
  final bytes = auditZip({
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml':
        '<container><rootfiles><rootfile full-path="book.opf"/>'
        '</rootfiles></container>',
    'book.opf': _opf,
    'c.xhtml':
        '<html xmlns="http://www.w3.org/1999/xhtml"><head><style>'
        '@page { padding:0pt; margin:0pt; } '
        'body { text-align:center; padding:0pt; margin:0pt; } $css'
        '</style></head><body>$body</body></html>',
    'cover.png': imageBytes,
  });
  final source = await const EpubFormatOpener().openBytes(
    bytes,
    options: ReaderOpenOptions(
      contentWidth: _pageSize.width - _pageInsets.horizontal,
      contentHeight: _pageSize.height - _pageInsets.vertical,
    ),
  );
  addTearDown(source.close);
  await source.applyOverrides(
    const ReaderOverrides(fontSize: 21, lineHeight: 1.6, paragraphSpacing: 10),
  );
  return source.loadChapter(0);
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

Color _pixel(ByteData pixels, int x, int y) {
  final offset = (y * 384 + x) * 4;
  return Color.fromARGB(
    pixels.getUint8(offset + 3),
    pixels.getUint8(offset),
    pixels.getUint8(offset + 1),
    pixels.getUint8(offset + 2),
  );
}

Future<void> _checkSvgCover(Uint8List imageBytes, ui.Image cover) async {
  final pages = await _pages(
    imageBytes,
    '<div><svg xmlns="http://www.w3.org/2000/svg" '
    'xmlns:xlink="http://www.w3.org/1999/xlink" version="1.1" '
    'width="100%" height="100%" viewBox="0 0 988 1388" '
    'preserveAspectRatio="none">'
    '<image width="988" height="1388" xlink:href="cover.png"/>'
    '</svg></div>',
  );
  final slice = pages.single.slices.single;
  final contentHeight = _pageSize.height - _pageInsets.vertical;
  expect(slice.block.layout.height, closeTo(contentHeight, 0.001));
  expect(slice.height, closeTo(contentHeight, 0.001));
  expect(pages.single.usedHeight, closeTo(contentHeight, 0.001));

  final width = _pageSize.width - _pageInsets.horizontal;
  final drawnHeight = width * _coverSize.height / _coverSize.width;
  final top = _pageInsets.top + (contentHeight - drawnHeight) / 2;
  final pixels = await _render(pages.single, cover);
  for (var index = 0; index < _colors.length; index++) {
    final x = _pageInsets.left + (index % 2 == 0 ? 2 : width - 2);
    final y = top + (index < 2 ? 2 : drawnHeight - 2);
    expect(_pixel(pixels, x.round(), y.round()), _colors[index]);
  }
}

Future<void> _checkMaxHeight(Uint8List imageBytes) async {
  final pages = await _pages(
    imageBytes,
    '<div><img src="cover.png"/></div><p>图片后正文</p>',
    css: 'img { width:120px; height:1388px; max-height:160px; }',
  );
  final image = pages.single.slices.first;
  expect(image.block.layout.height, 160);
  expect(image.height, 160);
  expect(pages.single.slices.last.block.layout.text, '图片后正文');
}

Future<void> _checkFloatingHeight(Uint8List imageBytes) async {
  final pages = await _pages(
    imageBytes,
    '<div><img src="cover.png"/></div><p>浮动图片旁正文</p>',
    css: 'img { float:left; width:240px; height:360px; }',
  );
  final block = pages.single.slices.first.block;
  final width = (_pageSize.width - _pageInsets.horizontal) * 0.45;
  final height = 360 * width / 240;
  expect(block.layout.height, closeTo(height, 0.001));
  expect(block.height, closeTo(height, 0.001));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ui.Image cover;
  late Uint8List imageBytes;
  setUpAll(() async {
    cover = await _coverImage();
    imageBytes = (await cover.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
  });
  tearDownAll(() => cover.dispose());

  test(
    'SVG 大尺寸封面使用缩放后的高度分页，四角完整留在页面内',
    () => _checkSvgCover(imageBytes, cover),
  );
  test('CSS 最大高度限制后的图片与后续正文共用同一页', () => _checkMaxHeight(imageBytes));
  test('浮动图片宽度收缩后，分页与绘制使用同比缩小的高度', () => _checkFloatingHeight(imageBytes));
}
