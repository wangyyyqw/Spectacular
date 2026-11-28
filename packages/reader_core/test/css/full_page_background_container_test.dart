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
const _insets = EdgeInsets.fromLTRB(
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
const _css = '''
body { margin:0; padding:0; font-family:Ahem; }
.surface { background-image:url(images/page.png); background-size:cover;
  background-position:center; background-repeat:no-repeat; margin:0;
  height:100vh; display:flex; justify-content:center; align-items:center;
  color:white; text-align:center; }
h1 { margin:0; }
''';

Future<ui.Image> _background() async {
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

Future<List<PageContent>> _pages(
  ui.Image image, {
  String extraCss = '',
  String body = '<div class="surface"><h1>TEXT</h1></div>',
}) async {
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
      .asUint8List();
  final source = await const EpubFormatOpener().openBytes(
    auditZip({
      'mimetype': 'application/epub+zip',
      'META-INF/container.xml':
          '<container><rootfiles><rootfile full-path="book.opf"/>'
          '</rootfiles></container>',
      'book.opf':
          '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
          'unique-identifier="id"><metadata '
          'xmlns:dc="http://purl.org/dc/elements/1.1/">'
          '<dc:identifier id="id">background-container</dc:identifier>'
          '<dc:title>独立背景容器回归</dc:title></metadata><manifest>'
          '<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>'
          '<item id="css" href="page.css" media-type="text/css"/>'
          '<item id="img" href="images/page.png" media-type="image/png"/>'
          '</manifest><spine><itemref idref="c"/></spine></package>',
      'c.xhtml':
          '<html xmlns="http://www.w3.org/1999/xhtml"><head>'
          '<link rel="stylesheet" href="page.css"/></head>'
          '<body>$body</body></html>',
      'page.css': '$_css $extraCss',
      'images/page.png': bytes,
    }),
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
  return source.loadChapter(0);
}

Future<ByteData> _paint(PageContent page, ui.Image background) async {
  final recorder = ui.PictureRecorder();
  PagePainter(
    imageLookup: (url) => url == 'images/page.png' ? background : null,
  ).paint(Canvas(recorder), page, pageSize: _pageSize, pageInsets: _insets);
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('独立整页背景容器铺满四边，保留作者文字、CFI 与命中位置', () async {
    final background = await _background();
    addTearDown(background.dispose);
    final page = (await _pages(background)).single;
    final block = page.slices.single.block;
    expect(block.layout.text, 'TEXT');
    expect(block.startCfi, 'epubcfi(/6/2!/4/2/2/1:0)');
    expect(block.offsetForCfi(block.startCfi!), 0);
    final cell = block.table!.cells.single;
    expect(cell.layout.text, 'TEXT');
    expect(cell.startCfi, block.startCfi);
    expect(cell.style.color, const Color(0xFFFFFFFF));
    expect(page.hitTest(cell.rect.center)?.slice.block, same(block));
    final pixels = await _paint(page, background);
    for (var index = 0; index < _bands.length; index++) {
      final y = (_pageSize.height * (index + 0.5) / 4).round();
      for (final x in [4, 24, 192, 380]) {
        expect(
          _pixel(pixels, x, y),
          _bands[index],
          reason: '第 ${index + 1} 条色带在 ($x, $y) 应连续覆盖整页，背景只能缩放一次',
        );
      }
    }
    for (final x in [4, 380]) {
      expect(_pixel(pixels, x, 12), _bands.first);
      expect(_pixel(pixels, x, 840), _bands.last);
    }
    final line = cell.layout.lines.single;
    expect(
      _pixel(
        pixels,
        (cell.textOrigin.dx + _insets.left + line.advanceWidth / 2).round(),
        (cell.textOrigin.dy + _insets.top + line.height / 2).round(),
      ),
      const Color(0xFFFFFFFF),
      reason: '作者文字必须继续实际绘制',
    );
  });

  for (final css in [
    '.surface {height:120px;}',
    '.surface {width:80%;}',
    '.surface {height:calc(100vh - 20px); margin:10px 0;}',
    '.surface {border-radius:20px;}',
  ]) {
    test('普通背景卡片保留原盒范围：$css', () async {
      final background = await _background();
      addTearDown(background.dispose);
      final page = (await _pages(background, extraCss: css)).single;
      final pixels = await _paint(page, background);
      expect(_pixel(pixels, 4, 12), const Color(0xFFFFFFFF));
      expect(_pixel(pixels, 380, 840), const Color(0xFFFFFFFF));
    });
  }

  test('正文中的背景容器与跨页容器不被扩大成整页封面', () async {
    final background = await _background();
    addTearDown(background.dispose);
    final pages = await _pages(
      background,
      body: '<div class="surface"><h1>TEXT</h1></div><p>BODY</p>',
    );
    for (final page in pages) {
      expect(
        _pixel(await _paint(page, background), 4, 12),
        const Color(0xFFFFFFFF),
      );
    }
    final tall = await _pages(background, extraCss: '.surface {height:200vh;}');
    for (final page in tall) {
      expect(
        _pixel(await _paint(page, background), 4, 12),
        const Color(0xFFFFFFFF),
      );
    }
  });
}
