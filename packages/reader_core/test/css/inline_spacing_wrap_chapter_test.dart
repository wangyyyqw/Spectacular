import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_core/source/format_opener.dart';

import '../audit/audit_epub_fixture.dart';

const _pageWidth = 366.6666666666667;
const _pageHeight = 806.9333333333333;

Future<PageContent> _page(String css, {String text = '甲乙丙丁'}) async {
  final bytes = auditZip({
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml':
        '<container><rootfiles><rootfile '
        'full-path="book.opf"/></rootfiles></container>',
    'book.opf':
        '<package version="3.0" unique-identifier="id" '
        'xmlns="http://www.idpf.org/2007/opf"><metadata '
        'xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '<dc:identifier id="id">inline-wrap</dc:identifier>'
        '<dc:title>行内盒换行回归</dc:title></metadata><manifest>'
        '<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>'
        '</manifest><spine><itemref idref="c"/></spine></package>',
    'c.xhtml':
        '<html xmlns="http://www.w3.org/1999/xhtml"><head><style>'
        'body{margin:0} h2{font:20px/1.5 Ahem;margin:0;width:65px;'
        'text-indent:0;text-align:left} $css'
        '</style></head><body><h2><span>$text</span></h2></body></html>',
  });
  final source = await const EpubFormatOpener().openBytes(
    bytes,
    options: const ReaderOpenOptions(
      contentWidth: _pageWidth,
      contentHeight: _pageHeight,
    ),
  );
  addTearDown(source.close);
  return (await source.loadChapter(0)).first;
}

Future<ByteData> _pixels(PageContent page) async {
  final recorder = ui.PictureRecorder();
  const PagePainter().paint(
    Canvas(recorder),
    page,
    pageSize: const Size(_pageWidth, _pageHeight),
  );
  final image = await recorder.endRecording().toImage(367, 807);
  final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return pixels!;
}

int _blue(ByteData pixels, int left, int right, int top, int bottom) {
  var count = 0;
  for (var y = top; y < bottom; y++) {
    for (var x = left; x < right; x++) {
      final offset = (y * 367 + x) * 4;
      if (pixels.getUint8(offset) < 10 &&
          pixels.getUint8(offset + 2) > 240 &&
          pixels.getUint8(offset + 3) > 240) {
        count++;
      }
    }
  }
  return count;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('跨行内边距和透明侧边仅在元素首尾占宽，原文位置不变', () async {
    final page = await _page(
      'span{padding:0 10px;'
      'border-left:3px solid transparent;border-right:3px solid transparent}',
    );
    final lines = TextHitTester.lineBoxes(page);
    expect(lines.map((line) => line.text), ['甲乙', '丙丁']);
    final first = TextHitTester.selectionRects(lines.first, 0, 1).first;
    final last = TextHitTester.selectionRects(lines.last, 0, 1).first;
    expect(first.left, closeTo(13, .01));
    expect(last.left, closeTo(0, .01));
    final layout = lines.first.slice.block.layout;
    expect(
      layout.lines.map((line) => line.width),
      everyElement(closeTo(53, .01)),
    );
    expect(layout.text, '甲乙丙丁');
  });

  test('跨行背景与边框跟随文字，只绘制首片左边和末片右边', () async {
    final page = await _page(
      'span{padding:0 10px;color:transparent;'
      'background:red;border-left:3px solid blue;border-right:3px solid blue}',
    );
    final pixels = await _pixels(page);
    expect(_blue(pixels, 0, 3, 0, 30), greaterThan(0));
    expect(_blue(pixels, 50, 53, 0, 30), 0);
    expect(_blue(pixels, 0, 3, 30, 60), 0);
    expect(_blue(pixels, 50, 53, 30, 60), greaterThan(0));
  });

  test('行内内边距保留软连字符的断词和原文偏移', () async {
    final page = await _page(
      'h2{width:85px;hyphens:manual}'
      'span{padding:0 5px}',
      text: 'ab&#173;cd',
    );
    final layout = page.slices.first.block.layout;
    expect(layout.text, 'ab\u00adcd');
    expect(layout.lines.length, 2);
    expect(layout.lines.first.hyphenated, isTrue);
    expect(layout.lines.last.end, layout.text.length);
  });
}
