import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/table_layout.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_core/source/format_opener.dart';

import '../audit/audit_epub_fixture.dart';

const _pageSize = Size(384, 853.3333333333334);
const _insets = EdgeInsets.fromLTRB(
  8.8,
  56.07500000000001,
  8.53333333333336,
  24.08888888888893,
);
const _red = Color(0xffff0000);
const _green = Color(0xff008800);

Future<ui.Image> _image(Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(color, BlendMode.src);
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(64, 32);
    addTearDown(image.dispose);
    return image;
  } finally {
    picture.dispose();
  }
}

Future<Map<String, ui.Image>> _images() async => {
  'OEBPS/Images/red.png': await _image(_red),
  'OEBPS/Images/green.png': await _image(_green),
};

Future<Uint8List> _book(
  String body,
  String css,
  Map<String, ui.Image> images,
) async {
  final files = <String, Object>{
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml':
        '<container><rootfiles><rootfile '
        'full-path="OEBPS/book.opf"/></rootfiles></container>',
    'OEBPS/book.opf':
        '<package version="3.0" unique-identifier="id" '
        'xmlns="http://www.idpf.org/2007/opf"><metadata '
        'xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '<dc:identifier id="id">table-content-regression</dc:identifier>'
        '<dc:title>表格图文回归</dc:title></metadata><manifest>'
        '<item id="c" href="Text/c.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="r" href="Images/red.png" media-type="image/png"/>'
        '<item id="g" href="Images/green.png" media-type="image/png"/>'
        '</manifest><spine><itemref idref="c"/></spine></package>',
    'OEBPS/Text/c.xhtml':
        '<html xmlns="http://www.w3.org/1999/xhtml">'
        '<head><style>body{margin:0;padding:0;font-family:Ahem;}'
        'table{margin:0;border-spacing:0;}td{padding:0;border:0;}'
        'p{margin:0;text-indent:0;}$css</style></head><body>$body</body></html>',
  };
  for (final entry in images.entries) {
    files[entry.key] = (await entry.value.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
  }
  return auditZip(files);
}

Future<PageContent> _page(
  String body,
  String css,
  Map<String, ui.Image> images,
) async {
  final source = await const EpubFormatOpener().openBytes(
    await _book(body, css, images),
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
  return (await source.loadChapter(0)).single;
}

List<TableCellRender> _cells(PageContent page) => [
  for (final slice in page.slices)
    if (slice.block.table != null) ...slice.block.table!.cells,
];

Iterable<PageBlock> _boxes(TextLayoutResult layout) sync* {
  for (final line in layout.lines) {
    for (final box in line.inlineBoxes) {
      final payload = box.spec.payload;
      if (payload is! PageBlock) continue;
      yield payload;
      yield* _boxes(payload.layout);
    }
  }
}

List<PageBlock> _imageBoxes(TextLayoutResult layout) => _boxes(layout)
    .where(
      (box) =>
          box.style?.values['background-image']?.startsWith('url(') ?? false,
    )
    .toList();

Future<ByteData> _paint(PageContent page, Map<String, ui.Image> images) async {
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

Rect _colorBounds(ByteData data, int rgba) {
  var left = 384, top = 854, right = -1, bottom = -1;
  for (var y = 0; y < 854; y++) {
    for (var x = 0; x < 384; x++) {
      if (data.getUint32((y * 384 + x) * 4) != rgba) continue;
      if (x < left) left = x;
      if (x > right) right = x;
      if (y < top) top = y;
      if (y > bottom) bottom = y;
    }
  }
  expect(right, greaterThanOrEqualTo(left), reason: '图片必须通过正式画笔实际绘制');
  return Rect.fromLTRB(
    left.toDouble(),
    top.toDouble(),
    right + 1.0,
    bottom + 1.0,
  );
}

int _inkIn(ByteData pixels, Rect region) {
  var ink = 0;
  for (var y = region.top.ceil(); y < region.bottom.floor(); y++) {
    for (var x = region.left.ceil(); x < region.right.floor(); x++) {
      if (pixels.getUint32((y * 384 + x) * 4) == 0x000000ff) ink++;
    }
  }
  return ink;
}

void _expectCellBlockPaint(
  ByteData pixels,
  TableCellRender cell,
  ({String align, double left}) expected,
) {
  final bounds = _colorBounds(pixels, 0xff0000ff);
  final left = _insets.left + cell.textOrigin.dx + expected.left;
  expect(
    bounds.left,
    closeTo(left + 5 + (expected.align == 'right' ? 30 : 15), 1),
  );
  expect(bounds.width, closeTo(20, 1));
  expect(
    _inkIn(
      pixels,
      Rect.fromLTRB(
        left,
        bounds.bottom,
        left + 60,
        _insets.top + cell.rect.bottom,
      ),
    ),
    greaterThan(10),
    reason: '图注必须保留并绘制在真实块宽内',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('纯图单元格保留表格结构、作者尺寸、正式资源路径和跨列图注', () async {
    final images = await _images();
    final page = await _page(
      '<table><tbody><tr><td><img src="../Images/red.png" '
          'style="width:150px;height:150px"/></td><td><img '
          'src="../Images/green.png" style="width:150px;height:150px"/>'
          '</td></tr><tr><td colspan="2"><p>CAPTION</p></td></tr></tbody></table>',
      'td{text-align:center;}',
      images,
    );
    final cells = _cells(page);
    expect(cells, hasLength(3));
    expect(cells.last.layout.text, 'CAPTION');
    for (var i = 0; i < 2; i++) {
      final box = _imageBoxes(cells[i].layout).single;
      final path = i == 0 ? 'red' : 'green';
      expect(
        box.style!.values['background-image'],
        'url(OEBPS/Images/$path.png)',
      );
      expect(box.layout.width, closeTo(150, .01));
      expect(box.layout.height, closeTo(150, .01));
    }
    final pixels = await _paint(page, images);
    for (final color in [0xff0000ff, 0x008800ff]) {
      final bounds = _colorBounds(pixels, color);
      expect(bounds.width, closeTo(150, 1));
      expect(bounds.height, closeTo(150, 1));
    }
  });

  test('嵌套图片容器保留百分比尺寸、居中、自然比例和图注字体', () async {
    final images = await _images();
    final page = await _page(
      '<table><tr><td><div class="frame"><img src="../Images/red.png"/>'
          '<p class="caption">SMALL</p></div></td><td><div class="frame">'
          '<img src="../Images/green.png"/><p class="caption">BIG</p>'
          '</div></td></tr></table>',
      'table{width:300px;table-layout:fixed;}'
          '.frame{width:100%;box-sizing:border-box;padding:5px;text-align:center;}'
          '.frame img{width:50%;margin-bottom:5px;}'
          '.caption{font-size:10px;color:#0000ff;}',
      images,
    );
    final cells = _cells(page);
    expect(cells, hasLength(2));
    for (final cell in cells) {
      final box = _imageBoxes(cell.layout).single;
      expect(box.layout.width, closeTo(70, .01));
      expect(box.layout.height, closeTo(35, .01));
      final textLayouts = [
        cell.layout,
        ..._boxes(cell.layout).map((b) => b.layout),
      ];
      expect(
        textLayouts.any(
          (l) => l.text.contains(cell == cells.first ? 'SMALL' : 'BIG'),
        ),
        isTrue,
      );
      expect(
        textLayouts
            .expand((l) => l.runs)
            .any((r) => (r.style.fontSize - 10).abs() < .01),
        isTrue,
      );
    }
    final pixels = await _paint(page, images);
    final red = _colorBounds(pixels, 0xff0000ff);
    final green = _colorBounds(pixels, 0x008800ff);
    expect(red.center.dx, closeTo(_insets.left + cells[0].rect.center.dx, 1));
    expect(green.center.dx, closeTo(_insets.left + cells[1].rect.center.dx, 1));
    expect(red.width, closeTo(70, 1));
    expect(green.width, closeTo(70, 1));
  });

  test('纯图嵌套容器折叠后恢复盒样式并使用图片自然尺寸', () async {
    final images = await _images();
    // 保留相邻正文，让本例走表格流而非单图章节的整页图片入口。
    final page = await _page(
      '<table><thead><tr><th><div class="frame"><div class="inner">'
          '<img src="../Images/red.png"/></div></div></th></tr></thead></table>'
          '<p>AFTER</p>',
      'table{width:160px;table-layout:fixed;}'
          'th{padding:0;border:0;text-align:left;}'
          '.frame{width:100%;box-sizing:border-box;padding:5px;text-align:center;}'
          '.inner{width:100%;}',
      images,
    );
    expect(_cells(page), hasLength(1), reason: '纯图表头必须保留表格结构');
    final cell = _cells(page).single;
    final boxes = _boxes(cell.layout).toList();
    expect(boxes.any((box) => box.style?.padding.left == 5), isTrue);
    final image = _imageBoxes(cell.layout).single;
    expect(image.layout.width, 64);
    expect(image.layout.height, 32);
    final bounds = _colorBounds(await _paint(page, images), 0xff0000ff);
    expect(bounds.width, closeTo(64, 1));
    expect(bounds.height, closeTo(32, 1));
    expect(bounds.center.dx, closeTo(_insets.left + cell.rect.center.dx, 1));
  });

  test('混合图文与前置、嵌套行内盒共同保留图片和文本坐标', () async {
    final images = await _images();
    final page = await _page(
      '<table><tr><td>AA<span class="badge">TAG</span>BB'
          '<img src="../Images/red.png" style="width:30px;height:20px"/>'
          '<span class="box"><img src="../Images/green.png" '
          'style="width:20px;height:10px"/>CC</span>DD</td></tr></table>',
      'table{width:350px;table-layout:fixed;}'
          'td{font-size:13.6px;text-align:right;}'
          '.badge{display:inline-block;padding:2px;background:#dddddd;}'
          '.box{display:inline-block;width:80px;text-align:left;}',
      images,
    );
    final layout = _cells(page).single.layout;
    expect(layout.text, 'AABB\uFFFCDD');
    final boxes = _boxes(layout).toList();
    expect(boxes.any((box) => box.layout.text == 'TAG'), isTrue);
    expect(boxes.any((box) => box.layout.text == '\uFFFCCC'), isTrue);
    expect(_imageBoxes(layout), hasLength(2));
    final redPlacement = layout.lines
        .expand((line) => line.inlineBoxes)
        .singleWhere(
          (p) =>
              p.spec.payload is PageBlock &&
              (p.spec.payload as PageBlock).style?.values['background-image'] ==
                  'url(OEBPS/Images/red.png)',
        );
    expect(redPlacement.spec.offset, 4, reason: '摘掉前置标签后，图片占位同步重映射');
    final pixels = await _paint(page, images);
    expect(_colorBounds(pixels, 0xff0000ff).width, closeTo(30, 1));
    expect(_colorBounds(pixels, 0x008800ff).width, closeTo(20, 1));
  });

  test('含图块夹在正文之间时保留块换行和图注', () async {
    final images = await _images();
    final page = await _page(
      '<table><tr><td>BEFORE<div class="frame">'
          '<img src="../Images/red.png" style="width:20px;height:10px"/>'
          '<p>CC</p></div>AFTER</td></tr></table>',
      'table{width:200px;table-layout:fixed;}td{font-size:12px;text-align:right;}'
          '.frame{width:60px;text-align:center;}',
      images,
    );
    final layout = _cells(page).single.layout;
    expect(layout.lines, hasLength(3));
    expect(layout.lines.first.inlineBoxes, isEmpty);
    expect(layout.lines[1].inlineBoxes, hasLength(1));
    expect(layout.lines.last.inlineBoxes, isEmpty);
    for (final line in [layout.lines.first, layout.lines.last]) {
      expect(
        line.offsetX,
        closeTo(200 - line.width, .01),
        reason: '块前后的正文仍按单元格的文字对齐排版',
      );
    }
    expect(layout.lines[1].offsetX, closeTo(0, .01));
    expect(layout.lines[1].inlineBoxes.single.left, closeTo(0, .01));
    expect(_boxes(layout).any((box) => box.layout.text.contains('CC')), isTrue);
    final pixels = await _paint(page, images);
    expect(_colorBounds(pixels, 0xff0000ff).width, closeTo(20, 1));
  });

  for (final sample in const [
    (label: '继承右对齐', align: 'right', margin: '0', left: 0.0, rtl: false),
    (label: '继承居中', align: 'center', margin: '0', left: 0.0, rtl: false),
    (
      label: '双侧自动外边距',
      align: 'right',
      margin: '0 auto',
      left: 70.0,
      rtl: false,
    ),
    (
      label: '左侧自动外边距',
      align: 'center',
      margin: '0 0 0 auto',
      left: 140.0,
      rtl: false,
    ),
    (
      label: '右侧自动外边距',
      align: 'right',
      margin: '0 auto 0 7px',
      left: 7.0,
      rtl: false,
    ),
    (
      label: '作者固定外边距',
      align: 'center',
      margin: '0 11px 0 7px',
      left: 7.0,
      rtl: false,
    ),
    (label: '从右向左包含块', align: 'center', margin: '0', left: 140.0, rtl: true),
  ]) {
    test('固定宽度格内含图块按包含块定位：${sample.label}', () async {
      final images = await _images();
      final page = await _page(
        '<table><tr><td><div class="frame"><img src="../Images/red.png" '
            'style="width:20px;height:10px"/><p>CC</p></div></td></tr></table>',
        'table{width:200px;table-layout:fixed;}td{text-align:${sample.align};'
            'direction:${sample.rtl ? 'rtl' : 'ltr'};}'
            '.frame{width:60px;box-sizing:border-box;padding:4px;'
            'border:1px solid #0000ff;margin:${sample.margin};}'
            '.frame p{font-size:10px;}',
        images,
      );
      final cell = _cells(page).single;
      final line = cell.layout.lines.single;
      final placement = line.inlineBoxes.single;
      final frame = placement.spec.payload as PageBlock;
      expect(cell.rect.width, closeTo(200, .01));
      expect(placement.width, closeTo(60, .01));
      expect(frame.layout.maxWidth, closeTo(50, .01));
      expect(
        line.offsetX + placement.left,
        closeTo(sample.left, .01),
        reason: '单元格的文字对齐只作用于块内内容，块边框按作者外边距定位',
      );
      _expectCellBlockPaint(await _paint(page, images), cell, (
        align: sample.align,
        left: sample.left,
      ));
    });
  }

  test('窄格按真实内容宽测量居中及左右对齐，文字仍在格内可见', () async {
    final page = await _page(
      '<table><tr><td style="text-align:left">A</td>'
          '<td style="text-align:center">A</td>'
          '<td style="text-align:right">A</td></tr></table>',
      'table{width:96px;table-layout:fixed;}'
          'td{font-size:13.6px;padding:2px;border:1px solid #999999;}',
      const {},
    );
    final cells = _cells(page);
    expect(cells, hasLength(3));
    for (var i = 0; i < cells.length; i++) {
      final cell = cells[i];
      final width =
          cell.rect.width -
          cell.style.padding.horizontal -
          cell.style.borders.left.width -
          cell.style.borders.right.width;
      final line = cell.layout.lines.single;
      expect(cell.layout.maxWidth, closeTo(width, .01));
      expect(line.offsetX, closeTo((width - line.advanceWidth) * i / 2, .01));
      expect(line.offsetX + line.advanceWidth, lessThanOrEqualTo(width + .01));
    }
    final pixels = await _paint(page, const {});
    for (final cell in cells) {
      final region = cell.rect.shift(_insets.topLeft).deflate(3);
      expect(_inkIn(pixels, region), greaterThan(10), reason: '每个对齐方式都要保留格内字形');
    }
  });

  test('分离边框的大间距表格保持一字宽内容及四个格内字形', () async {
    final page = await _page(
      '<table><tbody><tr><td>A</td><td>B</td></tr>'
          '<tr><td>C</td><td>D</td></tr></tbody></table>',
      'table{font-size:13.6px;border-spacing:2em 1em;}'
          'td{padding:.25em;border:1px solid #777777;text-align:center;}',
      const {},
    );
    final cells = _cells(page);
    expect(cells, hasLength(4));
    final pixels = await _paint(page, const {});
    for (final cell in cells) {
      expect(cell.rect.width, closeTo(22.4, .01));
      expect(cell.layout.maxWidth, closeTo(13.6, .01));
      expect(cell.layout.lines.single.offsetX, closeTo(0, .01));
      final region = cell.rect.shift(_insets.topLeft).deflate(1);
      expect(_inkIn(pixels, region), greaterThan(10), reason: '表格间距不能把文字推入裁切区');
    }
  });
}
