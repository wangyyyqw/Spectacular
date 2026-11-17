import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_core/source/format_opener.dart';

import '../audit/audit_epub_fixture.dart';

const _size = Size(384, 853.3333333333334);
const _insets = EdgeInsets.fromLTRB(
  8.8,
  56.075,
  8.53333333333336,
  24.08888888888893,
);
const _ratio = 2.8125;
const _pixelWidth = 1080;
const _pixelHeight = 2400;

Uint8List _book(String css) => auditZip({
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml': '<container><rootfiles><rootfile full-path="book.opf"/></rootfiles></container>',
  'book.opf':
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">'
      '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="id">ruby-content-box</dc:identifier>'
      '<dc:title>多行注音内容盒回归</dc:title></metadata><manifest>'
      '<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>'
      '</manifest><spine><itemref idref="c"/></spine></package>',
  'c.xhtml':
      '<html xmlns="http://www.w3.org/1999/xhtml"><head><style>'
      'body {margin:0 1%; font-family:Ahem; font-size:16px;}'
      'p {line-height:130%;}'
      '.skills {font-size:.8em; font-weight:900; color:#808000; '
      'text-align:center; text-indent:0; margin:1.3em .9em;}'
      'ruby {ruby-align:center;} rt {font-family:Ahem; font-size:.5em; color:#000;}'
      '$css</style></head><body><div style="height:100px;"></div>'
      '<p class="skills"><ruby>AAAA<rt>aaa</rt></ruby> BBBB CCCC DDDD<br/>'
      'EEEE FFFF GGGG HHHH<br/>'
      'IIII<ruby>JJJJ<rt>j</rt></ruby> <ruby>KKKK<rt>k</rt></ruby> '
      '<ruby>LLLL<rt>l</rt></ruby><br/>'
      '<ruby>MMMM<rt>m</rt></ruby><ruby>NNNN<rt>n</rt></ruby> '
      '<ruby>OOOO<rt>o</rt></ruby> PPPP</p>'
      '<p style="color:red;">后续标题</p></body></html>',
});

Future<ByteData> _render(String css) async {
  final source = await const EpubFormatOpener().openBytes(
    _book(css),
    options: ReaderOpenOptions(
      contentWidth: _size.width - _insets.horizontal,
      contentHeight: _size.height - _insets.vertical,
    ),
  );
  addTearDown(source.close);
  await source.applyOverrides(
    const ReaderOverrides(fontSize: 18, lineHeight: 1.6, paragraphSpacing: 10),
  );
  await source.applyContentSize(
    width: _size.width - _insets.horizontal,
    height: _size.height - _insets.vertical,
    topInset: _insets.top,
    sideInsets: (left: _insets.left, right: _insets.right),
  );
  final page = (await source.loadChapter(0)).single;
  final block = page.slices.singleWhere((s) => s.block.rubies != null).block;
  expect(block.layout.lines, hasLength(4));
  expect(block.rubies, hasLength(7));
  expect(block.layout.text, isNot(contains('aaa')));
  expect(block.layout.text, endsWith('MMMMNNNN OOOO PPPP'));
  expect(block.style!.fontSize, closeTo(14.4, .01));
  expect(block.rubies!.first.style!.fontSize, closeTo(7.2, .01));
  final recorder = ui.PictureRecorder();
  const PagePainter().paint(
    Canvas(recorder)..scale(_ratio),
    page,
    pageSize: _size,
    pageInsets: _insets,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(_pixelWidth, _pixelHeight);
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  image.dispose();
  picture.dispose();
  return data;
}

List<Rect> _colorBands(ByteData pixels, int color) {
  final bands = <Rect>[];
  for (var y = 0; y < _pixelHeight; y++) {
    var left = _pixelWidth, right = -1;
    for (var x = 0; x < _pixelWidth; x++) {
      if (pixels.getUint32((y * _pixelWidth + x) * 4) != color) continue;
      if (x < left) left = x;
      if (x > right) right = x;
    }
    if (right < 0) continue;
    final row = Rect.fromLTRB(left.toDouble(), y.toDouble(), right + 1, y + 1);
    if (bands.isNotEmpty && bands.last.bottom == y) {
      bands[bands.length - 1] = bands.last.expandToInclude(row);
    } else {
      bands.add(row);
    }
  }
  return bands;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final position in ['over', 'under']) {
    for (final rtLineHeight in ['normal', '4']) {
      test('多行 $position 注音贴基字且不压相邻行，rt 行高 $rtLineHeight 不参与定位', () async {
        final pixels = await _render(
          'ruby {ruby-position:$position;} rt {line-height:$rtLineHeight;}',
        );
        final bases = _colorBands(pixels, 0x808000ff);
        final annotations = _colorBands(pixels, 0x000000ff);
        expect(bases, hasLength(4));
        expect(annotations, hasLength(3));
        for (final (i, row) in [0, 2, 3].indexed) {
          final base = bases[row];
          final annotation = annotations[i];
          final gap = position == 'over'
              ? base.top - annotation.bottom
              : annotation.top - base.bottom;
          expect(gap / _ratio, closeTo(0, 1));
          if (position == 'over' && row > 0) {
            expect(annotation.top, greaterThanOrEqualTo(bases[row - 1].bottom));
          }
          if (position == 'under' && row < 3) {
            expect(annotation.bottom, lessThanOrEqualTo(bases[row + 1].top));
          }
          expect(annotation.left, greaterThanOrEqualTo(base.left));
          expect(annotation.right, lessThanOrEqualTo(base.right));
        }
      });
    }
  }
}
