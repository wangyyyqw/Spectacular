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

const _pageSize = Size(384, 853.3333333333334);
const _insets = EdgeInsets.fromLTRB(
  8.8,
  56.075,
  8.53333333333336,
  24.08888888888893,
);

const _headingCss = '''
body { margin:0; padding:0; font-family:Ahem; }
.header {
  display:block; font-size:1.15em; margin:0.8em 0 1.8em;
  padding:90px 27% 10px 0; border-bottom:2px solid #000;
  background-image:url(../Images/header.png);
  background-repeat:no-repeat; background-size:30% auto;
}
.chapter-row { display:block; font-size:0.605em; margin:0; }
.title-row { display:block; font-size:0.766em; margin:0; }
h2 { margin:0; padding:0; font-size:1em; text-align:left; }
.chapter {
  font-weight:800; padding:0 0.2em 1px;
  background-image:linear-gradient(180deg,
    #00000000 0%, #00000000 53%, #FFD7A958 53%, #FFD7A958 100%);
}
''';

Uint8List _bookBytes(String body, String css, Uint8List? image) => auditZip({
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml':
      '<container><rootfiles><rootfile full-path="OEBPS/book.opf"/>'
      '</rootfiles></container>',
  'OEBPS/book.opf':
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
      'unique-identifier="id"><metadata '
      'xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="id">title-background</dc:identifier>'
      '<dc:title>标题背景回归</dc:title></metadata><manifest>'
      '<item id="c" href="Text/c.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="css" href="Styles/main.css" media-type="text/css"/>'
      '${image == null ? '' : '<item id="image" href="Images/header.png" media-type="image/png"/>'}'
      '</manifest><spine><itemref idref="c"/></spine></package>',
  'OEBPS/Text/c.xhtml':
      '<html xmlns="http://www.w3.org/1999/xhtml"><head>'
      '<link rel="stylesheet" href="../Styles/main.css"/>'
      '</head><body>$body</body></html>',
  'OEBPS/Styles/main.css': '$_headingCss $css',
  'OEBPS/Images/header.png': ?image,
});

Future<PageContent> _page(String body, String css, {Uint8List? image}) async {
  final source = await const EpubFormatOpener().openBytes(
    _bookBytes(body, css, image),
    options: ReaderOpenOptions(
      contentWidth: _pageSize.width - _insets.horizontal,
      contentHeight: _pageSize.height - _insets.vertical,
    ),
  );
  addTearDown(source.close);
  await source.applyOverrides(
    const ReaderOverrides(fontSize: 18, lineHeight: 1.6, paragraphSpacing: 10),
  );
  await source.applyContentSize(
    width: _pageSize.width - _insets.horizontal,
    height: _pageSize.height - _insets.vertical,
    topInset: _insets.top,
    sideInsets: (left: _insets.left, right: _insets.right),
  );
  return (await source.loadChapter(0)).single;
}

Future<ByteData> _paint(PageContent page, {ui.Image? image}) async {
  final recorder = ui.PictureRecorder();
  PagePainter(imageLookup: image == null ? null : (_) => image)
      .paint(Canvas(recorder), page, pageSize: _pageSize, pageInsets: _insets);
  final picture = recorder.endRecording();
  final rendered = await picture.toImage(384, 854);
  try {
    return (await rendered.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  } finally {
    rendered.dispose();
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('标题头图的三值边缘偏移保留右侧20px空隙，不覆盖左侧标题区', () async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(const Color(0xffff0000), BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(1024, 1536);
    picture.dispose();
    addTearDown(image.dispose);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
    for (final position in ['right 20px center', 'center right 20px']) {
      final page = await _page(
        '<div class="header"><div class="chapter-row">'
            '<h2>Chapter 1</h2></div><div class="title-row">'
            '<h2>A title</h2></div></div><p>Body</p>',
        '.header { background-position:$position; }',
        image: bytes,
      );
      final pixels = await _paint(page, image: image);
      expect(_pixel(pixels, 300, 100), const Color(0xffff0000));
      expect(_pixel(pixels, 40, 100), const Color(0xffffffff));
      expect(_pixel(pixels, 354, 100), const Color(0xffff0000));
      expect(_pixel(pixels, 358, 100), const Color(0xffffffff));
    }
  });

  test('只有背景图的普通行内章号绘制下半部浅色渐变，周围保持透明', () async {
    final page = await _page(
      '<div class="chapter-row"><h2><span class="chapter">ABC</span>'
          '</h2></div>',
      '.chapter { color:transparent; }',
    );
    expect(
      page.slices.single.block.layout.runs.single.style.backgroundLayers,
      hasLength(1),
    );
    final pixels = await _paint(page);
    final tintedRows = [
      for (var y = 40; y < 100; y++)
        if (_pixel(pixels, 16, y).b < 0.95) y,
    ];
    expect(tintedRows.length, greaterThan(3), reason: '纯行内渐变不能被漏画');
    expect(_pixel(pixels, 16, tintedRows.first - 4), const Color(0xffffffff));
    expect(_pixel(pixels, 160, tintedRows.last), const Color(0xffffffff));
    final expected = Color.alphaBlend(
      const Color(0x58ffd7a9),
      const Color(0xffffffff),
    );
    final actual = _pixel(pixels, 16, tintedRows.last - 1);
    expect(actual.r, closeTo(expected.r, 1 / 255));
    expect(actual.g, closeTo(expected.g, 1 / 255));
    expect(actual.b, closeTo(expected.b, 1 / 255));
  });
}
