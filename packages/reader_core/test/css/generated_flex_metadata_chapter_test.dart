import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/table_layout.dart';
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
const _width = 366.6666666666667;
const _height = 773.1694444444443;
const _entries = [
  ('书　名', '全员嫌疑人'),
  ('作　者', '[日] 大山诚一郎'),
  ('译　者', '曹逸冰'),
  ('制　作', '鹤别青山'),
];
const _css = '''
body {margin:0; padding:0; background:#0d0d0d; min-height:100vh;
  display:flex; align-items:center; justify-content:center; font-family:Ahem;}
.card {width:92%; max-width:420px; border-radius:4px;
  padding:48px 32px 40px; box-sizing:border-box; position:relative; overflow:hidden;}
.title {font-size:28px; font-weight:900; color:#f0f0f0; text-align:center;
  letter-spacing:.35em; margin:0 0 8px; line-height:1.3;}
.title::after {content:""; display:block; width:40px; height:1px;
  background:#c9a96e; margin:12px auto 0;}
.copyright {font-size:10px; font-weight:300; color:#666; text-align:center;
  letter-spacing:.5em; margin:0 0 28px;}
.row {display:flex; justify-content:space-between; align-items:baseline;
  margin:0; padding:10px 0; border-bottom:1px solid rgba(255,255,255,.06);
  font-size:13px; line-height:1.6; color:#d4d4d4;}
.row:last-child {border-bottom:none;}
.row::before {content:attr(data-label); color:#888; font-weight:400; letter-spacing:.08em;}
''';

Uint8List _epub(String css, String body, Uint8List? image) => auditZip({
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml':
      '<container><rootfiles><rootfile full-path="book.opf"/>'
      '</rootfiles></container>',
  'book.opf':
      '<package version="3.0" unique-identifier="id" '
      'xmlns="http://www.idpf.org/2007/opf"><metadata '
      'xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="id">generated-flex-metadata</dc:identifier>'
      '<dc:title>生成内容与嵌套 Flex 信息行回归</dc:title></metadata><manifest>'
      '<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="s" href="s.css" media-type="text/css"/>'
      '<item id="i" href="icon.png" media-type="image/png"/>'
      '</manifest><spine><itemref idref="c"/></spine></package>',
  'c.xhtml':
      '<html xmlns="http://www.w3.org/1999/xhtml"><head>'
      '<link rel="stylesheet" href="s.css"/></head><body>$body</body></html>',
  's.css': '$_css $css',
  'icon.png': ?image,
});

Future<EpubChapterSource> _open({
  String css = '',
  String? body,
  Uint8List? image,
}) async {
  final source = await const EpubFormatOpener().openBytes(
    _epub(
      css,
      body ??
          '<div class="card"><h1 class="title">制 作 信 息</h1>'
              '<p class="copyright">COPYRIGHT</p>'
              '${_entries.map((entry) => '<p class="row" data-label="${entry.$1}">${entry.$2}</p>').join()}'
              '</div>',
      image,
    ),
    options: ReaderOpenOptions(contentWidth: _width, contentHeight: _height),
  );
  addTearDown(source.close);
  await source.applyOverrides(
    const ReaderOverrides(fontSize: 21, lineHeight: 1.6, paragraphSpacing: 10),
  );
  await source.applyContentSize(
    width: _width,
    height: _height,
    topInset: _insets.top,
    sideInsets: (left: _insets.left, right: _insets.right),
  );
  return source;
}

TableCellRender _cell(List<TableCellRender> cells, String text) =>
    cells.singleWhere((cell) => cell.layout.text == text);

Future<ByteData> _paint(PageContent page, {ui.Image? icon}) async {
  final recorder = ui.PictureRecorder();
  PagePainter(imageLookup: (_) => icon)
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

Future<ui.Image> _icon() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(const Color(0xff008800), BlendMode.src);
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(12, 10);
  } finally {
    picture.dispose();
  }
}

void _expectRows(List<TableCellRender> cells) {
  final card = cells.first.rect;
  final rows = cells
      .where((cell) => cell.style.display == CssDisplay.flex)
      .toList();
  expect(card.width, closeTo(_width * .92, .01));
  expect(card.center.dx, closeTo(_width / 2, .01));
  expect(rows, hasLength(4));
  for (var i = 0; i < _entries.length; i++) {
    final label = _cell(cells, _entries[i].$1);
    final value = _cell(cells, _entries[i].$2);
    expect(label.rect.left, closeTo(card.left + 32, .01));
    expect(value.rect.right, closeTo(card.right - 32, .01));
    expect(label.rect.right, lessThan(value.rect.left));
    expect(label.style.color, const Color(0xff888888));
    expect(value.style.color, const Color(0xffd4d4d4));
    expect(label.style.fontSize, 13);
    expect(value.style.fontSize, 13);
    expect(label.layout.height, closeTo(20.8, .01));
    expect(value.layout.height, closeTo(20.8, .01));
    expect(label.textOrigin.dy, closeTo(rows[i].rect.top + 10, .01));
    expect(value.textOrigin.dy, closeTo(label.textOrigin.dy, .01));
    expect(rows[i].rect.left, closeTo(card.left + 32, .01));
    expect(rows[i].rect.right, closeTo(card.right - 32, .01));
    expect(rows[i].rect.height, closeTo(i == 3 ? 40.8 : 41.8, .01));
    if (i > 0) {
      expect(rows[i].rect.top, closeTo(rows[i - 1].rect.bottom, .01));
    }
    expect(label.startCfi, isNull, reason: '生成标签不能冒充原文锚点');
    expect(value.startCfi, isNotNull);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('制作信息行生成独立标签，嵌套 Flex 保留卡片内缩和作者字号行高', () async {
    final source = await _open();
    final original = await source.loadAnchorChapter(0);
    final page = (await source.loadChapter(0)).single;
    final cells = page.slices.single.block.table!.cells;
    _expectRows(cells);
    final after = await source.loadAnchorChapter(0);
    expect(after.text, original.text);
    for (final entry in _entries) {
      final offset = original.text.indexOf(entry.$2);
      final cfi = original.cfiAt(offset)!;
      expect(after.cfiAt(offset), cfi);
      expect(after.offsetFor(cfi), offset);
      expect(after.offsetFor(_cell(cells, entry.$2).startCfi!), offset);
    }
  });

  test('Flex 前后生成子项按文档顺序求值，计数器只推进一次且保留原文首锚点', () async {
    final source = await _open(
      css:
          '.card {counter-reset:row;} .row {counter-increment:row;}'
          '.row::before {content:counter(row) ":";}'
          '.row::after {content:attr(data-tail); color:red;}',
      body:
          '<div class="card"><p class="row" data-tail="后">甲</p>'
          '<p class="row" data-tail="后">乙</p></div>',
    );
    final original = await source.loadAnchorChapter(0);
    final block = (await source.loadChapter(0)).single.slices.single.block;
    final cells = block.table!.cells
        .where((cell) => cell.layout.text.isNotEmpty)
        .toList();
    expect(cells.map((cell) => cell.layout.text), [
      '1:',
      '甲',
      '后',
      '2:',
      '乙',
      '后',
    ]);
    expect(cells.where((cell) => cell.startCfi != null), hasLength(2));
    expect(original.offsetFor(block.startCfi!), 0);
    expect(original.offsetFor(_cell(cells, '乙').startCfi!), 1);
    expect(original.text, '甲乙');
    for (final index in [0, 3]) {
      expect(cells[index].rect.right, lessThan(cells[index + 1].rect.left));
      expect(cells[index + 1].rect.right, lessThan(cells[index + 2].rect.left));
      expect(cells[index + 2].style.color, const Color(0xffff0000));
    }
  });

  test('空内容块伪元素绘制标题短线，保留自身尺寸和上下留白', () async {
    final page = (await (await _open()).loadChapter(0)).single;
    final cells = page.slices.single.block.table!.cells;
    final title = _cell(cells, '制 作 信 息');
    final copyright = _cell(cells, 'COPYRIGHT');
    final line = cells.singleWhere(
      (cell) => cell.style.backgroundColor == const Color(0xffc9a96e),
    );
    expect(title.style.fontSize, 28);
    expect(title.layout.height, closeTo(36.4, .01));
    expect(line.rect.width, closeTo(40, .01));
    expect(line.rect.height, closeTo(1, .01));
    expect(line.rect.center.dx, closeTo(_width / 2, .01));
    expect(line.rect.top - title.rect.bottom, closeTo(12, .01));
    expect(copyright.rect.top - line.rect.bottom, closeTo(8, .01));
    final pixels = await _paint(page);
    final point = line.rect.center + _insets.topLeft;
    final offset = (point.dy.floor() * 384 + point.dx.floor()) * 4;
    // 1px 线落在小数坐标时会抗锯齿；按金色与页背景的实际混色核验。
    final coverage = (pixels.getUint8(offset) - 13) / (201 - 13);
    expect(coverage, greaterThan(.35));
    expect(pixels.getUint8(offset + 1), closeTo(13 + coverage * (169 - 13), 1));
    expect(pixels.getUint8(offset + 2), closeTo(13 + coverage * (110 - 13), 1));
  });

  test('Flex 生成图片保留外边距，图片自身不重复消费包含块内缩', () async {
    final icon = await _icon();
    addTearDown(icon.dispose);
    final png = (await icon.toByteData(format: ui.ImageByteFormat.png))!.buffer
        .asUint8List();
    final source = await _open(
      css:
          '.row::before {content:url(icon.png); width:12px; height:10px;'
          'margin:0 5px 0 3px;}',
      body: '<div class="card"><p class="row">甲</p></div>',
      image: png,
    );
    final page = (await source.loadChapter(0)).single;
    final cells = page.slices.single.block.table!.cells;
    final row = cells.singleWhere(
      (cell) => cell.style.display == CssDisplay.flex,
    );
    final image = cells.singleWhere(
      (cell) => cell.layout.lines.any((line) => line.inlineBoxes.isNotEmpty),
    );
    final box = image.layout.lines
        .expand((line) => line.inlineBoxes)
        .single
        .spec;
    expect(image.rect.left - row.rect.left, closeTo(3, .01));
    expect(image.rect.width, closeTo(12, .01));
    expect(box.width, closeTo(12, .01));
    expect(box.height, closeTo(10, .01));
    expect(box.outerWidth, closeTo(12, .01));
    final pixels = await _paint(page, icon: icon);
    final point = image.rect.center + _insets.topLeft;
    final offset = (point.dy.floor() * 384 + point.dx.floor()) * 4;
    expect(pixels.getUint8(offset), 0);
    expect(pixels.getUint8(offset + 1), 136);
    expect(pixels.getUint8(offset + 2), 0);
  });
}
