import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:convert';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/hit_test.dart';
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
const _height = 773.1694444444443;
const _panel =
    '<div class="panel"><h1>INFO</h1><p>FIRST</p>'
    '<p>SECOND</p><hr/><p><span class="js_readerFooterNote" '
    'data-wr-footernote="测试注释">N</span></p></div>';

Future<PageContent> _page({String css = '', String body = _panel}) async {
  final source = await const EpubFormatOpener().openBytes(
    auditZip({
      'mimetype': 'application/epub+zip',
      'META-INF/container.xml': '<container><rootfiles><rootfile full-path="book.opf"/></rootfiles></container>',
      'book.opf':
          '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">'
          '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">absolute-container</dc:identifier>'
          '<dc:title>绝对定位容器回归</dc:title></metadata><manifest>'
          '<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>'
          '<item id="i" href="pixel.png" media-type="image/png"/>'
          '</manifest><spine><itemref idref="c"/></spine></package>',
      'c.xhtml':
          '<html xmlns="http://www.w3.org/1999/xhtml"><head><style>'
          'body {margin:0;height:100vh;display:flex;justify-content:center;align-items:center;'
          'font-family:Ahem;color:white;text-align:center;}'
          '.panel {position:absolute;top:50%;left:50%;transform:translate(-50%,-50%);'
          'width:90%;margin:auto;padding:20px;border:1px solid transparent;'
          'border-radius:15px;background:rgba(128,128,128,.6);box-sizing:border-box;}'
          'h1 {font-size:1.5em;line-height:1.2;margin:0 0 .9em;}'
          'p {font-size:.9em;line-height:1.6;margin:10px 0;text-indent:0;}'
          'hr {border:0;height:1px;background:repeating-linear-gradient(to right,'
          '#999 0px,#999 4px,transparent 4px,transparent 8px);}'
          '$css</style></head><body>$body</body></html>',
      'pixel.png': base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ'
        'AAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==',
      ),
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
  const PagePainter(background: Color(0xFF004488))
      .paint(Canvas(recorder), page, pageSize: _size, pageInsets: _insets);
  final picture = recorder.endRecording();
  final image = await picture.toImage(384, 854);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  } finally {
    image.dispose();
    picture.dispose();
  }
}

List<int> _pixel(ByteData data, double x, double y) => [
  for (var i = 0; i < 4; i++)
    data.getUint8((y.floor() * 384 + x.floor()) * 4 + i),
];

Rect _bounds(PageContent page, PageContainer container) {
  final members = page.slices
      .where(
        (slice) => slice.block.containers.any(
          (fragment) => identical(fragment.container, container),
        ),
      )
      .toList();
  final first = members.first;
  final last = members.last;
  final start = first.block.containers.firstWhere(
    (fragment) => identical(fragment.container, container),
  );
  final end = last.block.containers.firstWhere(
    (fragment) => identical(fragment.container, container),
  );
  return Rect.fromLTRB(
    container.left,
    first.absoluteTop! + first.leadingExtent - start.topInset,
    container.left + container.width,
    last.absoluteTop! + last.height - last.trailingExtent + end.bottomInset,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('绝对定位多段面板保留完整圆角背景、透明边框和整体居中，注释坐标同步', () async {
    final page = await _page();
    expect(page.slices, hasLength(5));
    expect(page.slices.every((slice) => slice.overlay), isTrue);
    final panel = page.slices.first.block.containers.single.container;
    final bounds = _bounds(page, panel);
    expect(bounds.width, closeTo(_width * .9, .01));
    expect(bounds.center.dx, closeTo(_width / 2, .01));
    expect(bounds.center.dy, closeTo(_height / 2, .01));
    expect(page.usedHeight, 0);
    expect(panel.style.borders.top.color.a, 0);
    expect(
      page.slices.every((slice) => slice.block.style!.backgroundColor.a == 0),
      isTrue,
    );
    expect(
      page.slices
          .where((slice) => slice.block.layout.text.isNotEmpty)
          .every((slice) => slice.block.startCfi != null),
      isTrue,
    );
    final pixels = await _paint(page);
    final box = bounds.shift(Offset(_insets.left, _insets.top));
    for (var y = box.top + 17; y < box.bottom - 17; y += 3) {
      final pixel = _pixel(pixels, box.left + 8, y);
      expect(pixel[0], closeTo(77, 1));
      expect(pixel[1], closeTo(104, 1));
      expect(pixel[2], closeTo(131, 1));
    }
    expect(_pixel(pixels, box.left, box.top), [0, 68, 136, 255]);
    expect(_pixel(pixels, box.center.dx, box.top + 1)[0], closeTo(77, 1));
    expect(_pixel(pixels, box.center.dx, box.bottom + 2), [0, 68, 136, 255]);
    final lines = TextHitTester.lineBoxes(page);
    for (final line in lines.where((line) => line.text.isNotEmpty)) {
      expect(bounds.contains(line.rect.center), isTrue);
      expect(line.rect.center.dx, closeTo(bounds.center.dx, .01));
      expect(
        _pixel(
          pixels,
          line.rect.center.dx + _insets.left,
          line.rect.center.dy + _insets.top,
        ),
        everyElement(greaterThan(240)),
        reason: '绘制和命中使用同一文字位置',
      );
    }
    final noteLine = lines.singleWhere((line) => line.text == 'N');
    expect(TextHitTester.footnoteAt(page, noteLine.rect.center)?.text, '测试注释');
  });

  test('面板按最近定位祖先的 padding-box 定位，不撑高正文或丢失子块装饰', () async {
    final page = await _page(
      css:
          'body {display:block;} .outer {position:relative;width:260px;margin:20px 30px;'
          'padding:12px 18px;border:3px solid green;} .flow {height:300px;margin:0;}'
          '.panel {width:80%;} .panel p {background:#123456;}',
      body:
          '<p style="height:60px;margin:0;">BEFORE</p><div class="outer">'
          '<p class="flow">FLOW</p><div>$_panel</div></div>'
          '<p style="margin:0;">AFTER</p>',
    );
    final panel = page.slices
        .singleWhere((slice) => slice.block.layout.text == 'INFO')
        .block
        .containers
        .last
        .container;
    final box = _bounds(page, panel);
    expect(box.width, closeTo((260 + 36) * .8, .01));
    expect(box.center.dx, closeTo(30 + 3 + (260 + 36) / 2, .01));
    expect(box.center.dy, closeTo(60 + 20 + 3 + (300 + 24) / 2, .01));
    expect(
      page.slices
          .where((slice) => !slice.overlay)
          .map((slice) => slice.block.layout.text),
      ['BEFORE', 'FLOW', 'AFTER'],
    );
    final first = page.slices.singleWhere(
      (slice) => slice.block.layout.text == 'FIRST',
    );
    expect(first.block.style!.backgroundColor, const Color(0xFF123456));
  });

  test('面板保留块级图片、注音和内部定位标签，浮动分页路径使用同一定位', () async {
    final page = await _page(
      css:
          'body {display:block;} .panel {width:80%;} '
          '.badge {position:absolute;left:0;top:0;margin:0;} '
          '.outside {float:left;width:30px;height:30px;} '
          'img {display:block;width:40px;height:30px;}',
      body:
          '<div class="outside">X</div><div class="panel">'
          '<h1>INFO</h1><img src="pixel.png"/>'
          '<p><ruby>AB<rt>ab</rt></ruby> CD</p><p class="badge">TAG</p></div>',
    );
    final first = page.slices.singleWhere(
      (slice) => slice.block.layout.text == 'INFO',
    );
    final panel = first.block.containers.last.container;
    final flow = page.slices
        .where((slice) => slice.block.layout.text.contains('AB'))
        .single;
    final fragment = flow.block.containers.last;
    final top =
        first.absoluteTop! +
        first.leadingExtent -
        first.block.containers.last.topInset;
    final bottom =
        flow.absoluteTop! +
        flow.height -
        flow.trailingExtent +
        fragment.bottomInset;
    expect((top + bottom) / 2, closeTo(_height / 2, .01));
    expect(panel.width, closeTo(_width * .8, .01));
    expect(flow.block.rubies, hasLength(1));
    final image = page.slices.singleWhere((slice) => slice.block.isReplaced);
    expect(image.block.style!.width!.resolve(_width), 40);
    expect(image.block.height, 30);
    expect(image.block.style!.backgroundImage, 'pixel.png');
    final badge = page.slices.singleWhere(
      (slice) => slice.block.layout.text == 'TAG',
    );
    expect(badge.absoluteTop, closeTo(top + 1, .01));
    expect(badge.leftInset, closeTo(panel.left + 1, .01));
  });
}
