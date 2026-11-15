import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/layout/float_occupancy.dart';
import 'package:reader_core/layout/paginator.dart';
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
const _solidBoxes =
    '<div class="row"><div class="blue">&#160;</div>'
    '<div class="green">&#160;</div><div class="red">&#160;</div></div>'
    '<p class="clear">后续正文</p>';
const _headingCss = '''
body {margin:0 1%;}
.row {margin:10% auto 0 0;}
.badge {float:left; width:3em; height:.8em; font-size:.4em;
  margin:0 3px 0 0; padding:3px 5px; line-height:130%; background:blue;}
.titles {float:left; width:40%; margin:0; border-left:1px solid black;
  padding-right:3px;}
.chapter {font-size:.6em; line-height:100%; margin:0 auto 0 3px;}
.subtitle {font-size:.5em; line-height:100%; margin:4px auto 0 3px;}
''';
const _headingBody =
    '<div class="row"><p class="badge">书名</p>'
    '<div class="titles"><p class="chapter">第一章</p>'
    '<p class="subtitle">章序</p><div class="clear"></div></div>'
    '<div class="clear"></div></div><p>后续正文</p>';
const _headingTop = 35.93333333333334;

Uint8List _epub(String css, String body) => auditZip({
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml':
      '<container><rootfiles><rootfile full-path="book.opf"/>'
      '</rootfiles></container>',
  'book.opf':
      '<package version="3.0" unique-identifier="id" '
      'xmlns="http://www.idpf.org/2007/opf"><metadata '
      'xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="id">empty-float-boxes</dc:identifier>'
      '<dc:title>空浮动盒正式入口回归</dc:title></metadata><manifest>'
      '<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>'
      '</manifest><spine><itemref idref="c"/></spine></package>',
  'c.xhtml':
      '<html xmlns="http://www.w3.org/1999/xhtml"><head><style>'
      'body {margin:0; padding:0; font-size:21px; font-family:Ahem; color:black;}'
      'p {margin:0; padding:0; text-indent:0; text-align:left;}'
      '.row {margin:0; padding:0;}'
      '.blue,.green,.red {float:left; width:50px; height:50px; margin:0;}'
      '.blue {background:blue;} .green {background:green;} .red {background:red;}'
      '.clear {clear:both;}'
      '$css</style></head><body>$body</body></html>',
});

Future<EpubChapterSource> _open(String css, String body) async {
  final source = await const EpubFormatOpener().openBytes(
    _epub(css, body),
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
  return source;
}

Future<ByteData> _paint(PageContent page) async {
  final recorder = ui.PictureRecorder();
  const PagePainter(background: Color(0xffffffff))
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

Rect _bounds(ByteData pixels, bool Function(int, int, int) matches) {
  var left = 384, top = 854, right = -1, bottom = -1;
  for (var y = 0; y < 854; y++) {
    for (var x = 0; x < 384; x++) {
      final i = (y * 384 + x) * 4;
      if (matches(
        pixels.getUint8(i),
        pixels.getUint8(i + 1),
        pixels.getUint8(i + 2),
      )) {
        if (x < left) left = x;
        if (x > right) right = x;
        if (y < top) top = y;
        if (y > bottom) bottom = y;
      }
    }
  }
  expect(right, greaterThanOrEqualTo(left), reason: '指定浮动背景必须实际绘制');
  return Rect.fromLTRB(
    left.toDouble(),
    top.toDouble(),
    right + 1.0,
    bottom + 1.0,
  );
}

List<Rect> _solidBounds(ByteData pixels) => [
  _bounds(pixels, (r, g, b) => r < 20 && g < 20 && b > 230),
  _bounds(pixels, (r, g, b) => r < 20 && g > 110 && g < 145 && b < 20),
  _bounds(pixels, (r, g, b) => r > 230 && g < 20 && b < 20),
];

int _textPixels(ByteData pixels, Rect box, int maximum) {
  var count = 0;
  for (var y = box.top.ceil(); y < box.bottom.floor(); y++) {
    for (var x = box.left.ceil(); x < box.right.floor(); x++) {
      final i = (y * 384 + x) * 4;
      final r = pixels.getUint8(i);
      final g = pixels.getUint8(i + 1);
      final b = pixels.getUint8(i + 2);
      if (r < maximum && (r - g).abs() < 5 && (b - g).abs() < 5) count++;
    }
  }
  return count;
}

String _floatDetails(PageContent page) => page.slices
    .where((slice) => slice.overlay)
    .map((slice) {
      final block = slice.block;
      final box = block.floatBox;
      final margin = block.style?.margin;
      return '浮动盒 top=${slice.absoluteTop}, left=${slice.leftInset}, '
          '内容=${block.layout.maxWidth}×${block.layout.height}, '
          '声明高度=${block.declaredContentHeight}, '
          '边距=(${margin?.left},${margin?.top},'
          '${margin?.right},${margin?.bottom}), '
          '包含块 left=${box?.containingLeft ?? block.floatContainingLeft}, '
          'width=${box?.containingWidth ?? block.floatContainingWidth}, '
          '容器 width=${box?.container.width}, height=${box?.container.style.height}';
    })
    .join('\n');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('章首段落浮动与两行容器浮动共享父上边距，clear 不重复增加留白', () async {
    final source = await _open(_headingCss, _headingBody);
    final page = (await source.loadChapter(0)).single;
    final floats = page.slices.where((slice) => slice.overlay).toList();
    expect(floats.map((slice) => slice.block.layout.text), ['书名', '第一章', '章序']);
    expect(floats[0].absoluteTop, closeTo(_headingTop, .001));
    expect(floats[1].absoluteTop, closeTo(_headingTop, .001));
    expect(floats[2].absoluteTop, closeTo(_headingTop + 16.6, .001));
    final badge = _bounds(
      await _paint(page),
      (r, g, b) => r < 20 && g < 20 && b > 230,
    );
    expect(badge.top, closeTo(_insets.top + _headingTop, 1));
    final body = page.slices.singleWhere(
      (slice) => slice.block.layout.text == '后续正文',
    );
    final bodyTop = page.slices
        .takeWhile((slice) => !identical(slice, body))
        .where((slice) => !slice.overlay)
        .fold<double>(
          page.topPadding,
          (height, slice) => height + slice.height,
        );
    // 正文保留阅读设置中的 10px 段前距。
    expect(
      bodyTop + body.leadingExtent,
      closeTo(_headingTop + 27.1 + 10, .001),
    );
  });

  test('父上边距不折叠浮动自身上边距，前一段底距只消费一次', () async {
    final source = await _open(
      '$_headingCss .before {height:20px; margin:0 0 42px;}'
          '.badge {margin-top:9px;}',
      '<p class="before">前文</p>$_headingBody',
    );
    final page = (await source.loadChapter(0)).single;
    final floats = page.slices.where((slice) => slice.overlay).toList();
    expect(floats[0].absoluteTop, closeTo(20 + 42 + 9, .001));
    expect(floats[1].absoluteTop, closeTo(20 + 42, .001));
    expect(floats[2].absoluteTop, closeTo(20 + 42 + 16.6, .001));
  });

  test('无 clear 的首个在流子块与父上距折叠，嵌套外层边距不重复相加', () async {
    final source = await _open(
      '$_headingCss .outer {margin-top:60px;}'
          '.body {margin-top:50px; line-height:21px;}'
          '.blue {margin-top:9px;}',
      '<div class="outer"><div class="row"><div class="blue"></div>'
          '<div class="green"></div><p class="body">正文</p></div></div>',
    );
    final page = (await source.loadChapter(0)).single;
    final floats = page.slices.where((slice) => slice.overlay).toList();
    expect(floats[0].absoluteTop, closeTo(60 + 9, .001));
    expect(floats[1].absoluteTop, closeTo(60, .001));
    final body = page.slices.singleWhere(
      (slice) => slice.block.layout.text == '正文',
    );
    expect(body.leadingExtent, closeTo(60, .001));
  });

  test('带边框与内边距的浮动父盒只在开头消费一次父上距', () async {
    final source = await _open(
      '.row {margin-top:30px; padding-top:7px; border-top:2px solid black;}',
      _solidBoxes,
    );
    final page = (await source.loadChapter(0)).single;
    for (final slice in page.slices.where((slice) => slice.overlay)) {
      expect(slice.absoluteTop, closeTo(30 + 7 + 2, .001));
    }
    final boxes = _solidBounds(await _paint(page));
    for (final box in boxes) {
      expect(box.top, closeTo(_insets.top + 30 + 7 + 2, 1));
    }
  });

  test('只含浮动的父盒保留各自边距，后续 clear 在边距后的边框顶补足高度', () async {
    final source = await _open(
      '.row {margin:30px 0 20px;}'
          '.blue {margin-top:9px;}'
          '.clear {margin-top:10px; padding-top:4px;}',
      '<div class="row"><div class="blue"></div>'
          '<div class="green"></div></div><p class="clear">后续正文</p>',
    );
    final page = (await source.loadChapter(0)).single;
    final floats = page.slices.where((slice) => slice.overlay).toList();
    expect(floats[0].absoluteTop, closeTo(30 + 9, .001));
    expect(floats[1].absoluteTop, closeTo(30, .001));
    final body = page.slices.singleWhere(
      (slice) => slice.block.layout.text == '后续正文',
    );
    final bodyTop = page.slices
        .takeWhile((slice) => !identical(slice, body))
        .where((slice) => !slice.overlay)
        .fold<double>(
          page.topPadding,
          (height, slice) => height + slice.height,
        );
    expect(bodyTop + body.leadingExtent, closeTo(30 + 9 + 50 + 4, .001));
  });

  test('三个 50px 空浮动色块经正式入口同排，clear 后正文位于其下方', () async {
    final source = await _open('', _solidBoxes);
    final original = await source.loadAnchorChapter(0);
    final cfi = original.cfiAt(original.text.indexOf('后'))!;
    final page = (await source.loadChapter(0)).single;
    final floats = page.slices.where((slice) => slice.overlay).toList();
    expect(floats, hasLength(3));
    for (final slice in floats) {
      expect(slice.block.floatSide, FloatSide.left);
      expect(slice.block.layout.maxWidth, closeTo(50, .001));
      expect(slice.block.declaredContentHeight, closeTo(50, .001));
    }
    final boxes = _solidBounds(await _paint(page));
    for (var i = 0; i < boxes.length; i++) {
      expect(boxes[i].left, closeTo(_insets.left + 50 * i, 1));
      expect(boxes[i].top, closeTo(boxes.first.top, 1));
      expect(boxes[i].width, closeTo(50, 1));
      expect(boxes[i].height, closeTo(50, 1));
    }
    final body = page.slices.singleWhere(
      (slice) => slice.block.layout.text.contains('后续正文'),
    );
    final bodyTop = page.slices
        .takeWhile((slice) => !identical(slice, body))
        .where((slice) => !slice.overlay)
        .fold<double>(
          page.topPadding,
          (height, slice) => height + slice.height,
        );
    expect(bodyTop + body.leadingExtent, greaterThanOrEqualTo(50));
    final after = await source.loadAnchorChapter(0);
    expect(after.text, original.text);
    expect(after.cfiAt(original.text.indexOf('后')), cfi);
  });

  test('140px 容器中的第三个 50px 空浮动盒换到下一排', () async {
    final source = await _open('.row {width:140px;}', _solidBoxes);
    final page = (await source.loadChapter(0)).single;
    final boxes = _solidBounds(await _paint(page));
    final details = '像素盒：$boxes\n${_floatDetails(page)}';
    for (final slice in page.slices.where((slice) => slice.overlay)) {
      expect(slice.block.floatContainingWidth, closeTo(140, .001));
      expect(slice.block.style!.margin.right, 0);
    }
    expect(boxes[0].top, closeTo(boxes[1].top, 1), reason: details);
    expect(boxes[1].left - boxes[0].left, closeTo(50, 1));
    expect(boxes[2].top - boxes[0].top, closeTo(50, 1));
    expect(boxes[2].left, closeTo(boxes[0].left, 1));
  });

  test('偏移窄容器内的百分比空浮动按父宽解算，半透明背景只绘一次', () async {
    final source = await _open(
      '.row {width:140px; margin-left:17px;}'
          '.blue {width:50%; background:rgba(0,0,255,.5); opacity:.5;}',
      '<div class="row"><div class="blue">&#160;</div>'
          '<div class="blue">&#160;</div></div><p class="clear">后续正文</p>',
    );
    final page = (await source.loadChapter(0)).single;
    final floats = page.slices.where((slice) => slice.overlay).toList();
    expect(floats, hasLength(2));
    for (var i = 0; i < floats.length; i++) {
      final block = floats[i].block;
      expect(block.floatContainingLeft, closeTo(17, .001));
      expect(block.floatContainingWidth, closeTo(140, .001));
      expect(block.layout.maxWidth, closeTo(70, .001));
      expect(floats[i].leftInset, closeTo(17 + i * 70, .001));
    }
    final box = _bounds(
      await _paint(page),
      (r, g, b) => (r - 191).abs() < 3 && (g - 191).abs() < 3 && b > 250,
    );
    expect(box.left, closeTo(_insets.left + 17, 1));
    expect(box.width, closeTo(140, 1));
    expect(box.height, closeTo(50, 1));
  });

  test('完全无文本的空浮动盒也保留 140px 父包含块并正确换排', () async {
    final source = await _open(
      '.row {width:140px;}',
      _solidBoxes.replaceAll('&#160;', ''),
    );
    final page = (await source.loadChapter(0)).single;
    final boxes = _solidBounds(await _paint(page));
    final details = '像素盒：$boxes\n${_floatDetails(page)}';
    expect(boxes[0].top, closeTo(boxes[1].top, 1), reason: details);
    expect(boxes[1].left - boxes[0].left, closeTo(50, 1));
    expect(boxes[2].top - boxes[0].top, closeTo(50, 1), reason: details);
    expect(boxes[2].left, closeTo(boxes[0].left, 1));
  });

  test('相邻五个 20% 文字浮动盒同排，文字与背景一同按 opacity 渐淡', () async {
    const opacities = ['1', '0.8', '0.6', '0.4', '0.2'];
    final body = [
      for (final opacity in opacities)
        '<div class="fade" style="opacity:$opacity;">'
            '<p>透明度$opacity</p></div>',
      '<p class="clear">后续正文</p>',
    ].join();
    final source = await _open(
      '.fade {float:left; width:20%; height:4em; background-color:#ff00ff;}',
      body,
    );
    final page = (await source.loadChapter(0)).single;
    final floats = page.slices.where((slice) => slice.overlay).toList();
    expect(floats, hasLength(5));
    final pixels = await _paint(page);
    final width = (_pageSize.width - _insets.horizontal) / 5;
    final boxes = [
      for (var i = 0; i < 5; i++)
        _bounds(
          pixels,
          (r, g, b) => r > 250 && b > 250 && (g - i * 51).abs() < 3,
        ),
    ];
    final details = '像素盒：$boxes\n${_floatDetails(page)}';
    double? top;
    for (var i = 0; i < 5; i++) {
      final green = i * 51;
      final box = boxes[i];
      top ??= box.top;
      expect(box.left, closeTo(_insets.left + width * i, 2));
      expect(box.width, closeTo(width, 2));
      expect(box.top, closeTo(top, 1));
      expect(box.height, closeTo(84, 1), reason: details);
      expect(_textPixels(pixels, box, green + 12), greaterThan(0));
      expect(
        floats[i].block.effectiveOpacity,
        closeTo(double.parse(opacities[i]), .001),
      );
    }
  });
}
