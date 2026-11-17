import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/layout/paginator.dart';
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
const _title = 'ABCDEFGHIJK';

Uint8List _book(String css, String text) => auditZip({
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml': '<container><rootfiles><rootfile full-path="book.opf"/></rootfiles></container>',
  'book.opf':
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">'
      '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">flex-text-indent</dc:identifier>'
      '<dc:title>Flex 首行缩进回归</dc:title></metadata><manifest>'
      '<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="a" href="first.css" media-type="text/css"/>'
      '<item id="b" href="second.css" media-type="text/css"/>'
      '</manifest><spine><itemref idref="c"/></spine></package>',
  'c.xhtml':
      '<html xmlns="http://www.w3.org/1999/xhtml"><head><style>'
      'body {display:flex;justify-content:center;align-items:center;min-height:100vh;margin:0;font-family:Ahem;}'
      '</style><link rel="stylesheet" href="first.css"/><link rel="stylesheet" href="second.css"/>'
      '</head><body><h2 class="caption">$text</h2></body></html>',
  'first.css': '.caption {margin:0;padding:0;text-indent:0;}',
  'second.css':
      '.caption {font-size:1em;text-indent:2em;text-align:justify;}$css',
});

Future<PageContent> _page({String css = '', String text = _title}) async {
  final source = await const EpubFormatOpener().openBytes(
    _book(css, text),
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
  return (await source.loadChapter(0)).single;
}

Future<Rect> _textBounds(PageContent page) async {
  final recorder = ui.PictureRecorder();
  const PagePainter().paint(
    Canvas(recorder),
    page,
    pageSize: _size,
    pageInsets: _insets,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(384, 854);
  try {
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    var left = 384, top = 854, right = -1, bottom = -1;
    for (var y = 0; y < 854; y++) {
      for (var x = 0; x < 384; x++) {
        final offset = (y * 384 + x) * 4;
        if (data.getUint8(offset) > 30 ||
            data.getUint8(offset + 1) > 30 ||
            data.getUint8(offset + 2) > 30) {
          continue;
        }
        left = math.min(left, x);
        top = math.min(top, y);
        right = math.max(right, x);
        bottom = math.max(bottom, y);
      }
    }
    return Rect.fromLTRB(
      left.toDouble(),
      top.toDouble(),
      right + 1.0,
      bottom + 1.0,
    );
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Future<void> _checkTitle(String align, double indent) async {
  final page = await _page(
    css: '.caption {text-align:$align;text-indent:${indent}px;}',
  );
  final cell = page.slices.single.block.table!.cells.single;
  final line = cell.layout.lines.single;
  expect(cell.style.fontSize, 18);
  expect(cell.style.textIndent, indent);
  expect(cell.style.textAlign.name, align);
  expect(cell.layout.text, _title);
  expect(
    cell.rect.width,
    closeTo(198 + indent, .01),
    reason: '自然宽须包含首行缩进，不包含原宽度下的对齐偏移',
  );
  expect(
    cell.rect.center.dx,
    closeTo((_size.width - _insets.horizontal) / 2, .01),
  );
  expect(
    cell.rect.center.dy,
    closeTo((_size.height - _insets.vertical) / 2, .01),
  );
  expect(line.indent, indent);
  expect(line.offsetX, closeTo(indent, .01));
  expect(
    line.indent + line.advanceWidth,
    lessThanOrEqualTo(cell.rect.width + .01),
  );
  expect(cell.startCfi, 'epubcfi(/6/2!/4/2/1:0)');
  final bounds = await _textBounds(page);
  expect(bounds.width, closeTo(198, 2), reason: '11 个字形必须全部绘制，不能因缩进裁掉末尾');
}

// 此入口只登记同一路径的独立回归，集中保留便于对照，不再拆分注册函数。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final align in ['justify', 'center', 'right']) {
    for (final indent in [0.0, 36.0]) {
      test(
        'Flex $align 标题保留 $indent 首行缩进，盒子居中且文字完整',
        () => _checkTitle(align, indent),
      );
    }
  }
  test('后加载样式覆盖零缩进，原书两字符缩进参与自然宽', () async {
    final cell = (await _page()).slices.single.block.table!.cells.single;
    expect(cell.style.textAlign, CssTextAlign.justify);
    expect(cell.style.textIndent, 36);
    expect(cell.rect.width, closeTo(234, .01));
  });
  test('首行缩进不加到更宽的后续硬换行上', () async {
    final cell = (await _page(text: 'ABC<br/>$_title'))
        .slices
        .single
        .block
        .table!
        .cells
        .single;
    expect(cell.layout.lines, hasLength(2));
    expect(cell.layout.lines.first.indent, 36);
    expect(cell.layout.lines.last.indent, 0);
    expect(cell.rect.width, closeTo(198, .01));
  });
  test('百分比缩进不扩大 Flex 内在自然宽', () async {
    final cell = (await _page(css: '.caption {text-indent:10%;}'))
        .slices
        .single
        .block
        .table!
        .cells
        .single;
    expect(
      cell.style.textIndent,
      closeTo((_size.width - _insets.horizontal) * .1, .01),
    );
    expect(cell.rect.width, closeTo(198, .01));
  });
}
