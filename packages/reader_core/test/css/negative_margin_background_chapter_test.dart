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

const _size = Size(384, 853.3333333333334);
const _insets = EdgeInsets.fromLTRB(
  8.8,
  56.075,
  8.53333333333336,
  24.08888888888893,
);
const _width = 366.6666666666667;
const _height = 773.1694444444445;
const _blue = 0x4875B9FF;

Future<PageContent> _page({String extraCss = '', bool clipped = false}) async {
  final source = await const EpubFormatOpener().openBytes(
    auditZip({
      'mimetype': 'application/epub+zip',
      'META-INF/container.xml': '<container><rootfiles><rootfile full-path="book.opf"/></rootfiles></container>',
      'book.opf':
          '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">'
          '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">negative-background</dc:identifier>'
          '<dc:title>负外边距背景裁剪回归</dc:title></metadata><manifest>'
          '<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>'
          '</manifest><spine><itemref idref="c"/></spine></package>',
      'c.xhtml':
          '<html xmlns="http://www.w3.org/1999/xhtml"><head><style>'
          'body {font-size:1em; margin:0 5pt; padding:0; font-family:Ahem;}'
          'h1 {background:#4875b9; color:black; display:block; font-family:Ahem; font-size:2em;'
          'font-weight:normal; line-height:1.2; padding-bottom:1em; padding-top:3em;'
          'text-align:center; margin:-2em -2em 1.5em;}'
          '.clip {overflow:hidden; margin:0 20px; padding:0;}'
          '$extraCss</style></head><body>${clipped ? '<div class="clip">' : ''}'
          '<h1>TEXT</h1>${clipped ? '</div>' : ''}<p>BODY TEXT</p></body></html>',
    }),
    options: const ReaderOpenOptions(
      contentWidth: _width,
      contentHeight: _height,
    ),
  );
  addTearDown(source.close);
  await source.applyOverrides(
    const ReaderOverrides(fontSize: 18, lineHeight: 1.6, paragraphSpacing: 10),
  );
  await source.applyContentSize(
    width: _width,
    height: _height,
    topInset: _insets.top,
    sideInsets: (left: _insets.left, right: _insets.right),
  );
  return (await source.loadChapter(0)).single;
}

Future<ByteData> _paint(PageContent page) async {
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
    return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  } finally {
    image.dispose();
    picture.dispose();
  }
}

int _pixel(ByteData pixels, int x, int y) =>
    pixels.getUint32((y * 384 + x) * 4);

Rect _blueBounds(ByteData pixels) {
  var left = 384, top = 854, right = -1, bottom = -1;
  for (var y = 0; y < 854; y++) {
    for (var x = 0; x < 384; x++) {
      if (_pixel(pixels, x, y) != _blue) continue;
      if (x < left) left = x;
      if (x > right) right = x;
      if (y < top) top = y;
      if (y > bottom) bottom = y;
    }
  }
  expect(right, greaterThanOrEqualTo(left), reason: '背景必须实际绘制');
  return Rect.fromLTRB(
    left.toDouble(),
    top.toDouble(),
    right + 1.0,
    bottom + 1.0,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('负左右外边距标题背景铺到页边，保留作者高度、文字和正文位置', () async {
    final page = await _page();
    final block = page.slices.first.block;
    expect(block.layout.text, 'TEXT');
    expect(block.style!.fontSize, 36);
    expect(block.style!.padding.top, 96, reason: '作者盒模型按原书字号计算');
    expect(block.style!.padding.bottom, 32);
    expect(block.style!.margin.top, -72);
    final pixels = await _paint(page);
    final bounds = _blueBounds(pixels);
    expect(bounds.left, 0);
    expect(bounds.right, 384);
    expect(bounds.top, 0);
    expect(bounds.bottom, closeTo(_insets.top - 72 + 96 + 43.2 + 32, 1));
    expect(_pixel(pixels, 0, 80), _blue);
    expect(_pixel(pixels, 383, 80), _blue);
    expect(_pixel(pixels, 0, 160), 0xFFFFFFFF, reason: '不能把段后距涂蓝');
    expect(page.slices.last.block.layout.text, 'BODY TEXT');
    expect(page.slices.first.height, closeTo(-72 + 96 + 43.2 + 32, .01));
  });

  test('单侧负外边距只扩展对应侧，正外边距仍保留留白', () async {
    final pixels = await _paint(
      await _page(extraCss: 'h1 {margin-left:-2em;margin-right:18px;}'),
    );
    final bounds = _blueBounds(pixels);
    expect(bounds.left, 0);
    expect(
      bounds.right,
      closeTo(_size.width - _insets.right - 5 * 4 / 3 - 18, 1),
    );
    expect(_pixel(pixels, 383, 80), 0xFFFFFFFF);
  });

  test('负外边距背景继续受作者 overflow:hidden 父盒裁剪', () async {
    final pixels = await _paint(await _page(clipped: true));
    final bounds = _blueBounds(pixels);
    expect(bounds.left, closeTo(_insets.left + 5 * 4 / 3 + 20, 1));
    expect(
      bounds.right,
      closeTo(_size.width - _insets.right - 5 * 4 / 3 - 20, 1),
    );
    expect(_pixel(pixels, 0, 80), 0xFFFFFFFF);
    expect(_pixel(pixels, 383, 80), 0xFFFFFFFF);
  });
}
