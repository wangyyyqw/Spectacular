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

Future<List<PageContent>> _pages(
  String body,
  String css, {
  Map<String, Uint8List> images = const {},
}) async {
  final bytes = auditZip({
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml':
        '<container><rootfiles><rootfile full-path="OEBPS/book.opf"/>'
        '</rootfiles></container>',
    'OEBPS/book.opf':
        '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
        'unique-identifier="id"><metadata '
        'xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '<dc:identifier id="id">table-row-background</dc:identifier>'
        '<dc:title>表格行背景回归</dc:title></metadata><manifest>'
        '<item id="c" href="Text/c.xhtml" media-type="application/xhtml+xml"/>'
        '${images.keys.indexed.map((entry) => '<item id="image${entry.$1}" '
            'href="${entry.$2.substring(6)}" media-type="image/png"/>').join()}'
        '</manifest><spine><itemref idref="c"/></spine></package>',
    'OEBPS/Text/c.xhtml':
        '<html xmlns="http://www.w3.org/1999/xhtml"><head><style>'
        'body{margin:0;padding:0;font-family:Ahem;}'
        'table{width:100%;margin:0;border-spacing:0;}'
        'td{height:48px;padding:12px;border:0;}'
        '$css</style></head><body>$body</body></html>',
    ...images,
  });
  final source = await const EpubFormatOpener().openBytes(
    bytes,
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
  return source.loadChapter(0);
}

Future<ByteData> _paint(
  PageContent page, {
  Map<String, ui.Image> images = const {},
}) async {
  final recorder = ui.PictureRecorder();
  PagePainter(imageLookup: (url) => images[url])
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

void _expectPixel(ByteData pixels, Offset point, Color expected) {
  final offset = (point.dy.round() * 384 + point.dx.round()) * 4;
  final channels = [expected.r, expected.g, expected.b, expected.a];
  for (var channel = 0; channel < 4; channel++) {
    expect(
      pixels.getUint8(offset + channel),
      closeTo(channels[channel] * 255, 1),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('行的半透明底色铺在透明单元格下方，单元格自有背景保持在上层', () async {
    final page = (await _pages(
      '<table><tr><td>A</td><td style="background:#0000ff">B</td></tr>'
          '<tr><td colspan="2">C</td></tr></table>',
      'table{background:#7a9eb4;border-collapse:collapse;}'
          'tr{background:rgba(26,28,37,.7);}',
    )).single;
    final slice = page.slices.singleWhere((slice) => slice.block.table != null);
    final cells = slice.block.table!.cells;
    final pixels = await _paint(page);
    final base = Offset(_insets.left + slice.leftInset, _insets.top);
    final blended = Color.alphaBlend(
      const Color.fromRGBO(26, 28, 37, .7),
      const Color(0xff7a9eb4),
    );
    _expectPixel(
      pixels,
      base + cells.first.rect.topLeft + const Offset(4, 4),
      blended,
    );
    _expectPixel(
      pixels,
      base + cells[1].rect.topLeft + const Offset(4, 4),
      const Color(0xff0000ff),
    );
    _expectPixel(
      pixels,
      base + cells.last.rect.topLeft + const Offset(4, 4),
      blended,
    );
  });

  test('跨行格延续起始行底色，格间距和隐藏空格透出表格背景', () async {
    final page = (await _pages(
      '<table><tr class="red"><td rowspan="3">A</td><td>B</td></tr>'
          '<tr class="blue"><td style="empty-cells:hide;background:yellow"></td></tr>'
          '<tr class="green"><td>C</td></tr></table>',
      'table{background:#7a9eb4;border-spacing:8px 6px;}'
          '.red{background:red;}.blue{background:blue;}.green{background:green;}',
    )).single;
    final slice = page.slices.singleWhere((slice) => slice.block.table != null);
    final cells = slice.block.table!.cells;
    final empty = cells.singleWhere((cell) => cell.layout.text.isEmpty);
    final last = cells.singleWhere((cell) => cell.layout.text == 'C');
    final pixels = await _paint(page);
    final base = Offset(_insets.left + slice.leftInset, _insets.top);
    _expectPixel(
      pixels,
      base + Offset(cells.first.rect.left + 4, empty.rect.top + 4),
      const Color(0xffff0000),
    );
    _expectPixel(
      pixels,
      base + empty.rect.topLeft + const Offset(4, 4),
      const Color(0xff7a9eb4),
    );
    _expectPixel(
      pixels,
      base + last.rect.topLeft + const Offset(4, 4),
      const Color(0xff008000),
    );
    _expectPixel(
      pixels,
      base + Offset(cells.first.rect.right + 4, cells.first.rect.top + 4),
      const Color(0xff7a9eb4),
    );
  });

  test('连续行底色在小数像素的列界和行界保持一致，不产生浅色接缝', () async {
    final page = (await _pages(
      '<table><tr><td>A</td><td>B</td></tr>'
          '<tr><td>C</td><td>D</td></tr></table>',
      'table{background:#7a9eb4;border-collapse:collapse;}'
          'tr{background:rgba(26,28,37,.7);}',
    )).single;
    final slice = page.slices.singleWhere((slice) => slice.block.table != null);
    final cells = slice.block.table!.cells;
    final pixels = await _paint(page);
    final base = Offset(_insets.left + slice.leftInset, _insets.top);
    final blended = Color.alphaBlend(
      const Color.fromRGBO(26, 28, 37, .7),
      const Color(0xff7a9eb4),
    );
    _expectPixel(pixels, base + Offset(cells.first.rect.right, 4), blended);
    _expectPixel(pixels, base + Offset(4, cells[2].rect.top), blended);
  });

  test('分页保留跨行格的起始行底色，续页不会改成当前行底色', () async {
    final pages = await _pages(
      '<table><tr style="background:red"><td rowspan="2" style="height:1000px">A</td><td>B</td></tr>'
          '<tr style="background:blue"><td>C</td></tr></table>',
      'table{border-collapse:collapse;}',
    );
    expect(pages, hasLength(2));
    for (final page in pages) {
      final slice = page.slices.singleWhere(
        (slice) => slice.block.table != null,
      );
      final cells = slice.block.table!.cells;
      final span = cells.singleWhere((cell) => cell.layout.text == 'A');
      final pixels = await _paint(page);
      final base = Offset(_insets.left + slice.leftInset, _insets.top);
      _expectPixel(
        pixels,
        base + span.rect.topLeft + const Offset(4, 4),
        const Color(0xffff0000),
      );
      if (page == pages.last) {
        final other = cells.singleWhere((cell) => cell.layout.text == 'C');
        _expectPixel(
          pixels,
          base + other.rect.topLeft + const Offset(4, 4),
          const Color(0xff0000ff),
        );
      }
    }
  });

  test('跨页重复表头及正文各行背景按原顺序保留', () async {
    final rows = List.generate(
      12,
      (index) =>
          '<tr style="background:${index.isEven ? 'red' : 'blue'}">'
          '<td style="height:90px">$index</td></tr>',
    ).join();
    final pages = await _pages(
      '<table><thead><tr style="background:yellow"><td>H</td></tr></thead>'
          '<tbody>$rows</tbody></table>',
      'table{border-collapse:collapse;}',
    );
    expect(pages.length, greaterThan(1));
    final numbers = <int>[];
    for (final page in pages) {
      final slice = page.slices.singleWhere(
        (slice) => slice.block.table != null,
      );
      final cells = slice.block.table!.cells;
      expect(cells.first.layout.text, 'H');
      final pixels = await _paint(page);
      final base = Offset(_insets.left + slice.leftInset, _insets.top);
      for (final cell in cells) {
        final number = int.tryParse(cell.layout.text);
        if (number != null) numbers.add(number);
        final color = number == null
            ? const Color(0xffffff00)
            : number.isEven
            ? const Color(0xffff0000)
            : const Color(0xff0000ff);
        _expectPixel(
          pixels,
          base + cell.rect.topLeft + const Offset(4, 4),
          color,
        );
      }
    }
    expect(numbers, List.generate(12, (index) => index));
  });

  test('行背景图片按完整行定位，穿过列界时不会从每个单元格重新开始', () async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 320, 80),
      Paint()..color = const Color(0xffff0000),
    );
    canvas.drawRect(
      const Rect.fromLTWH(320, 0, 320, 80),
      Paint()..color = const Color(0xff0000ff),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(640, 80);
    addTearDown(image.dispose);
    picture.dispose();
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
    final page = (await _pages(
      '<table><tr><td>A</td><td>B</td></tr></table>',
      'table{table-layout:fixed;border-collapse:collapse;}'
          'tr{background:url(../Images/row.png) center/100% 100% no-repeat;}',
      images: {'OEBPS/Images/row.png': bytes},
    )).single;
    final slice = page.slices.singleWhere((slice) => slice.block.table != null);
    final cells = slice.block.table!.cells;
    final pixels = await _paint(page, images: {'OEBPS/Images/row.png': image});
    final base = Offset(_insets.left + slice.leftInset, _insets.top);
    _expectPixel(
      pixels,
      base + cells.first.rect.topLeft + const Offset(4, 4),
      const Color(0xffff0000),
    );
    _expectPixel(
      pixels,
      base + cells.last.rect.topLeft + const Offset(4, 4),
      const Color(0xff0000ff),
    );
  });
}
