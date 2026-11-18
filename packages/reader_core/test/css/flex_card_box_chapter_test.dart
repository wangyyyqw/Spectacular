import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/table_layout.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_core/source/format_opener.dart';

import '../audit/audit_epub_fixture.dart';

const _contentWidth = 366.6666666666667;
const _contentHeight = 773.1694444444443;
const _pageSize = Size(384, 853.3333333333333);
const _pageInsets = EdgeInsets.fromLTRB(
  8.8,
  56.075,
  8.53333333333336,
  24.08888888888893,
);
const _css = '''
body { margin:0; min-height:100vh; display:flex;
  justify-content:center; align-items:center; font-family:Ahem; }
.card { width:70%; padding:20px; border:1px solid #207f4c;
  border-radius:12px; background:#fffef8; text-align:center; }
h2 { font-size:24px; line-height:1.4; font-weight:normal; margin:0 0 20px; }
p { font-size:15px; line-height:1.6; margin:8px 0; text-indent:0; }
hr { border:none; height:1.5px; margin:20px 0;
  background:repeating-linear-gradient(to right,#207f4c 0 12px,
    transparent 12px 18px,#207f4c 18px 20px,transparent 20px 26px); }
.license { font-size:12px; line-height:1.3; margin:0; }
span.reader { position:relative; display:inline-block; width:19px; height:19px;
  vertical-align:sub; margin:0 3px; background-image:url("note.png");
  background-size:100%; background-repeat:no-repeat; }
''';
const _body =
    '<div class="card"><h2>ABCD</h2><p>ABCDE</p>'
    '<p>ABCDEFG</p><p>ABC</p><hr/><p class="license">ABCD</p>'
    '<p class="license">ABCDEFGH</p></div>';

Uint8List _book(String css, String body) => auditZip({
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml':
      '<container><rootfiles>'
      '<rootfile full-path="book.opf"/></rootfiles></container>',
  'book.opf':
      '<package version="3.0" unique-identifier="id" '
      'xmlns="http://www.idpf.org/2007/opf"><metadata '
      'xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="id">flex-card-box</dc:identifier>'
      '<dc:title>Flex 卡片盒模型回归</dc:title></metadata><manifest>'
      '<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="s" href="s.css" media-type="text/css"/>'
      '<item id="n" href="note.png" media-type="image/png"/>'
      '</manifest><spine><itemref idref="c"/></spine></package>',
  'c.xhtml':
      '<html xmlns="http://www.w3.org/1999/xhtml"><head>'
      '<link rel="stylesheet" href="s.css"/></head><body>$body</body></html>',
  's.css': '$_css $css',
  'note.png': base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ'
    'AAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==',
  ),
});

Future<List<PageContent>> _pages({
  String css = '',
  String body = _body,
  double contentHeight = _contentHeight,
}) async {
  final source = await const EpubFormatOpener().openBytes(
    _book(css, body),
    options: ReaderOpenOptions(
      contentWidth: _contentWidth,
      contentHeight: contentHeight,
    ),
  );
  addTearDown(source.close);
  await source.applyOverrides(
    const ReaderOverrides(fontSize: 21, lineHeight: 1.6, paragraphSpacing: 10),
  );
  return source.loadChapter(0);
}

Future<PageContent> _page({String css = '', String body = _body}) async =>
    (await _pages(css: css, body: body)).single;

List<TableCellRender> _cells(PageContent page) =>
    page.slices.single.block.table!.cells;

String _noteRow(String label, String note) =>
    '<p class="license">$label<span class="reader js_readerFooterNote" '
    'data-wr-footernote="$note"></span></p>';

Offset _iconCenter(TableCellRender cell, {bool bottom = false}) {
  final line = cell.layout.lines.single;
  final icon = line.inlineBoxes.single;
  final style = cell.style;
  final textTop = bottom
      ? cell.rect.bottom -
            style.padding.bottom -
            style.borders.bottom.width -
            cell.layout.height
      : cell.rect.top + style.padding.top + style.borders.top.width;
  return Offset(
    cell.rect.left +
        style.padding.left +
        style.borders.left.width +
        line.offsetX +
        icon.left +
        icon.width / 2,
    textTop + icon.topIn(line.baseline - line.top) + icon.height / 2,
  );
}

Future<ByteData> _render(PageContent page) async {
  final recorder = ui.PictureRecorder();
  const PagePainter().paint(
    Canvas(recorder),
    page,
    pageSize: _pageSize,
    pageInsets: _pageInsets,
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

int _pixel(ByteData data, int x, int y) => data.getUint32((y * 384 + x) * 4);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final borderBox in [false, true]) {
    test(
      'Flex 多块卡片保留 ${borderBox ? 'border-box' : 'content-box'} 尺寸和内部留白',
      () async {
        final page = await _page(
          css: borderBox ? '.card {box-sizing:border-box;}' : '',
        );
        final cells = _cells(page);
        final card = cells.first.rect;
        final expectedWidth = _contentWidth * .7 + (borderBox ? 0 : 42);
        expect(card.width, closeTo(expectedWidth, .01));
        expect(card.center.dx, closeTo(_contentWidth / 2, .01));
        expect(card.center.dy, closeTo(_contentHeight / 2, .01));
        expect(cells, hasLength(8));
        for (final cell in cells.skip(1)) {
          expect(cell.rect.left - card.left, closeTo(21, .01));
          expect(card.right - cell.rect.right, closeTo(21, .01));
          expect(cell.layout.maxWidth, closeTo(expectedWidth - 42, .01));
          if (cell.layout.text.isNotEmpty) expect(cell.startCfi, isNotNull);
        }
        expect(cells[1].rect.top - card.top, closeTo(21, .01));
        expect(card.bottom - cells.last.rect.bottom, closeTo(21, .01));
        expect(cells[5].rect.height, closeTo(1.5, .01), reason: '分隔线不吞上下留白');
      },
    );
  }

  test('Flex 卡片内相邻块的外边距折叠，标题底距和分隔线上下距保留', () async {
    final cells = _cells(await _page());
    final gaps = [
      for (var i = 2; i < cells.length; i++)
        cells[i].rect.top - cells[i - 1].rect.bottom,
    ];
    expect(gaps, orderedEquals([20, 8, 8, 20, 20, 0]));
    expect(cells[1].layout.height, closeTo(33.6, .01));
    expect(cells[2].layout.height, closeTo(24, .01));
    expect(cells.last.layout.height, closeTo(15.6, .01));
  });

  test('Flex 卡片后代保留自身外边距和内边距，文字不重复消费祖先内缩', () async {
    final cells = _cells(
      await _page(
        body: '<div class="card"><p>AB</p><p>CD</p></div>',
        css: 'p {margin:8px 10px; padding:3px; border:2px solid red;}',
      ),
    );
    final card = cells.first.rect;
    for (final cell in cells.skip(1)) {
      expect(cell.rect.left - card.left, closeTo(31, .01));
      expect(card.right - cell.rect.right, closeTo(31, .01));
      expect(cell.rect.height, closeTo(cell.layout.height + 10, .01));
      expect(cell.layout.maxWidth, closeTo(card.width - 72, .01));
    }
    expect(cells[1].rect.top - card.top, closeTo(29, .01));
    expect(card.bottom - cells.last.rect.bottom, closeTo(29, .01));
    expect(cells[2].rect.top - cells[1].rect.bottom, closeTo(8, .01));
  });

  test('未声明宽度的 Flex 卡片仍按自然内容宽收缩，再加自身装饰', () async {
    final cells = _cells(
      await _page(
        css: '.card {width:auto;}',
        body: '<div class="card"><p>ABCDE</p><p>ABCDEFG</p></div>',
      ),
    );
    expect(cells.first.rect.width, closeTo(147, .01));
    expect(cells.first.rect.center.dx, closeTo(_contentWidth / 2, .01));
    expect(cells.last.rect.width, closeTo(105, .01));
  });

  test('Flex 卡片内两个空 span 注号按各自的居中绘制坐标命中', () async {
    final notes = ['制作说明', '文本来源说明'];
    final page = await _page(
      body:
          '<div class="card"><h2>ABCD</h2>'
          '${_noteRow('ABC', notes[0])}${_noteRow('ABCDEFG', notes[1])}</div>',
    );
    final cells = _cells(page);
    final noteCells = cells
        .where(
          (cell) =>
              cell.layout.lines.any((line) => line.inlineBoxes.isNotEmpty),
        )
        .toList();
    expect(noteCells, hasLength(2));
    for (var i = 0; i < noteCells.length; i++) {
      final center = _iconCenter(noteCells[i]);
      expect(TextHitTester.footnoteAt(page, center)?.text, notes[i]);
      expect(
        TextHitTester.footnoteAt(
          page,
          Offset(cells.first.rect.left + 5, center.dy),
        ),
        isNull,
        reason: '卡片内边距不能成为注号点击区',
      );
    }
  });

  test('Flex 直接子块的注号命中包括自身装饰和底部对齐', () async {
    final page = await _page(
      body: _noteRow('ABCDE', '直接子项注释'),
      css:
          '.license {height:90px; padding:7px; border:2px solid green; '
          'vertical-align:bottom;}',
    );
    final cell = _cells(page).single;
    final center = _iconCenter(cell, bottom: true);
    expect(TextHitTester.footnoteAt(page, center)?.text, '直接子项注释');
    expect(
      TextHitTester.footnoteAt(page, Offset(center.dx, cell.rect.top + 10)),
      isNull,
      reason: '高度盒顶部留白不能命中底部注号',
    );
  });

  test('Flex 换行分页后保留注释数据并按当前切片坐标命中', () async {
    final pages = await _pages(
      body: [
        for (var i = 0; i < 3; i++)
          '<div class="card">${_noteRow('ABCDE', '分页注释$i')}</div>',
      ].join(),
      css:
          'body {min-height:0; flex-wrap:wrap; align-items:flex-start; '
          'align-content:flex-start;}',
      contentHeight: 120,
    );
    expect(pages, hasLength(3));
    for (var i = 0; i < pages.length; i++) {
      final page = pages[i];
      final cell = _cells(page).last;
      final slice = page.slices.single;
      final center = _iconCenter(cell).translate(
        slice.leftInset + (slice.block.style?.margin.left ?? 0),
        page.topPadding + slice.leadingExtent,
      );
      expect(TextHitTester.footnoteAt(page, center)?.text, '分页注释$i');
    }
  });

  test('Flex 卡片的圆角边框与阴影实际绘制，分隔线保持在内容盒内', () async {
    final page = await _page(
      css: '.card {box-shadow:0 8px 16px rgba(0,0,0,.3);}',
    );
    final cells = _cells(page);
    final card = cells.first.rect.shift(_pageInsets.topLeft);
    final pixels = await _render(page);
    final corner = _pixel(pixels, card.left.round(), card.top.round());
    expect((corner >> 24) & 0xff, greaterThan(245), reason: '圆角外不能仍有直线边框');
    final top = _pixel(pixels, card.center.dx.round(), card.top.round());
    expect(
      (top >> 16) & 0xff,
      greaterThan((top >> 24) & 0xff),
      reason: '上边中点仍画绿色边框',
    );
    final shadow = _pixel(
      pixels,
      card.center.dx.round(),
      card.bottom.round() + 6,
    );
    expect(shadow >> 24, lessThan(245), reason: '卡片底部的外阴影不能丢失');
    final line = cells[5].rect.shift(_pageInsets.topLeft);
    expect(
      _pixel(pixels, card.left.round() + 8, line.top.round()),
      0xfffef8ff,
      reason: '分隔线不进入卡片左内边距',
    );
  });

  test('Flex 卡片背景滤镜复用页背景，圆角外的背景保持锐利', () async {
    const background =
        'body {background:repeating-linear-gradient(to right,'
        '#000 0 2px,#fff 2px 4px);} .card {background:transparent;} '
        'h2,p {color:transparent;}';
    final plain = await _page(css: background);
    final blurred = await _page(
      css: '$background .card {backdrop-filter:blur(6px);}',
    );
    final card = _cells(blurred).first.rect.shift(_pageInsets.topLeft);
    final before = await _render(plain);
    final after = await _render(blurred);
    double contrast(ByteData data) {
      var total = 0.0;
      final y = card.top.round() + 30;
      for (var x = card.left.round() + 30; x < card.left.round() + 94; x++) {
        total += ((_pixel(data, x, y) >> 24) - (_pixel(data, x + 1, y) >> 24))
            .abs();
      }
      return total / 64;
    }

    expect(contrast(before), greaterThan(80));
    expect(contrast(after), lessThan(contrast(before) * .5));
    expect(
      _pixel(after, card.left.round(), card.top.round()),
      _pixel(before, card.left.round(), card.top.round()),
      reason: '背景滤镜不能漏出卡片圆角',
    );
  });
}
