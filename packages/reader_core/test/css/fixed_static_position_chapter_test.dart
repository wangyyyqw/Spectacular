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
const _header = '<div class="header"><img src="header.png"/></div>';
late Uint8List _imageBytes;

Future<void> _prepareImage() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(const Color(0xFF112233), BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(1080, 600);
  _imageBytes = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
      .asUint8List();
  image.dispose();
  picture.dispose();
}

Future<PageContent> _page({
  String preceding = _header,
  String extraCss = '',
}) async {
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
          '<dc:identifier id="id">fixed-static-position</dc:identifier>'
          '<dc:title>固定容器静态位置回归</dc:title></metadata><manifest>'
          '<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>'
          '<item id="i" href="header.png" media-type="image/png"/>'
          '</manifest><spine><itemref idref="c"/></spine></package>',
      'c.xhtml':
          '<html xmlns="http://www.w3.org/1999/xhtml"><head><style>'
          'body,div,p {margin:0;padding:0;font-family:Ahem;}'
          '.header {text-align:center;duokan-bleed:lefttopright;}'
          '.header img {width:100%;}'
          '.panel {position:fixed;display:inline-block;left:20px;right:20px;'
          'padding:10px 15px;border:2px solid #0c3483;'
          'background:#ffffff;border-radius:10px;box-sizing:border-box;}'
          '.panel p {margin:12px 0;text-indent:0;}'
          '$extraCss</style></head><body>$preceding'
          '<x-panel class="panel"><p>FIRST</p><p>SECOND</p></x-panel>'
          '<p>AFTER</p></body></html>',
      'header.png': _imageBytes,
    }),
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

Rect _bounds(PageContent page) {
  final members = page.slices.where((slice) => slice.overlay).toList();
  final first = members.first;
  final last = members.last;
  final start = first.block.containers.single;
  final end = last.block.containers.single;
  expect(end.container, same(start.container));
  return Rect.fromLTRB(
    start.container.left + _insets.left,
    first.absoluteTop! + first.leadingExtent - start.topInset + _insets.top,
    start.container.left + start.container.width + _insets.left,
    last.absoluteTop! +
        last.height -
        last.trailingExtent +
        end.bottomInset +
        _insets.top,
  );
}

Future<ByteData> _paint(PageContent page) async {
  final recorder = ui.PictureRecorder();
  const PagePainter(background: Color(0xFF000000))
      .paint(Canvas(recorder), page, pageSize: _size, pageInsets: _insets);
  final picture = recorder.endRecording();
  final image = await picture.toImage(384, 854);
  final pixels = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  image.dispose();
  picture.dispose();
  return pixels;
}

int _pixel(ByteData pixels, Offset position) =>
    pixels.getUint32((position.dy.floor() * 384 + position.dx.floor()) * 4);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_prepareImage);

  test('未声明上下偏移的固定父框位于出血头图之后，四侧边框同步移动', () async {
    final page = await _page();
    final bounds = _bounds(page);
    expect(bounds.left, closeTo(20, .01));
    expect(bounds.right, closeTo(364, .01));
    expect(bounds.top, closeTo(_size.width * 600 / 1080, .01));
    expect(page.topPadding, -_insets.top);
    expect(
      page.slices
          .where((slice) => !slice.overlay)
          .map((slice) => slice.block.layout.text),
      ['', 'AFTER'],
    );
    final pixels = await _paint(page);
    for (final position in [
      Offset(bounds.center.dx, bounds.top + 1),
      Offset(bounds.left + 1, bounds.top + 30),
      Offset(bounds.right - 1, bounds.top + 30),
      Offset(bounds.center.dx, bounds.bottom - 1),
    ]) {
      expect(_pixel(pixels, position), 0x0C3483FF);
    }
    expect(
      _pixel(pixels, Offset(bounds.center.dx, bounds.top - 3)),
      0x000000FF,
    );
    expect(
      page.slices
          .where((slice) => slice.overlay)
          .every((slice) => slice.block.startCfi != null),
      isTrue,
    );
  });

  test('无出血的头图后固定父框保留阅读顶部内缩', () async {
    final page = await _page(extraCss: '.header {duokan-bleed:none;}');
    expect(
      _bounds(page).top,
      closeTo(
        _insets.top + (_size.width - _insets.horizontal) * 600 / 1080,
        .01,
      ),
    );
  });

  test('出血头图自身上边距推动后方固定父框，不吞掉图片留白', () async {
    final page = await _page(extraCss: '.header img {margin-top:2em;}');
    expect(_bounds(page).top, closeTo(32 + _size.width * 600 / 1080, .01));
  });

  test('章首固定父框没有上下偏移时从正文起点开始', () async {
    final page = await _page(preceding: '');
    expect(_bounds(page).top, closeTo(_insets.top, .01));
    expect(
      page.slices.where((slice) => !slice.overlay).single.block.layout.text,
      'AFTER',
    );
  });

  test('显式顶部偏移继续以整页为基准，不跟随前方头图', () async {
    final page = await _page(extraCss: '.panel {top:50px;}');
    expect(_bounds(page).top, closeTo(50, .01));
  });

  test('普通流多块折叠边距后的静态位置不计入固定内容高度', () async {
    final page = await _page(
      preceding: '<div class="lead">BEFORE</div><div class="lead">NEXT</div>',
      extraCss: '.lead {height:70px;margin:15px 0 20px;}',
    );
    final flow = page.slices.where((slice) => !slice.overlay).toList();
    expect(flow.map((slice) => slice.block.layout.text), [
      'BEFORE',
      'NEXT',
      'AFTER',
    ]);
    expect(
      _bounds(page).top,
      closeTo(_insets.top + 15 + 70 + 20 + 70 + 20, .01),
    );
  });
}
