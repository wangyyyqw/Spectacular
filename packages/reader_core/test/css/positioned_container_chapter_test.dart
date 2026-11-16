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

const _pageSize = Size(384, 853.3333333333334);
const _insets = EdgeInsets.fromLTRB(
  8.8,
  56.075,
  8.53333333333336,
  24.08888888888893,
);
const _width = 366.6666666666667;
const _height = 773.1694444444445;

Future<ui.Image> _image() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(const Color(0xFF004488), BlendMode.src);
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(1200, 1000);
  } finally {
    picture.dispose();
  }
}

Future<List<PageContent>> _pages(
  ui.Image image, {
  String extraCss = '',
  String leading = '',
  bool nested = false,
  String innerContent = '',
}) async {
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
      .asUint8List();
  final source = await const EpubFormatOpener().openBytes(
    auditZip({
      'mimetype': 'application/epub+zip',
      'META-INF/container.xml': '<container><rootfiles><rootfile full-path="book.opf"/></rootfiles></container>',
      'book.opf':
          '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">'
          '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">positioned-title</dc:identifier>'
          '<dc:title>定位标题回归</dc:title></metadata><manifest>'
          '<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>'
          '<item id="i" href="banner.png" media-type="image/png"/>'
          '</manifest><spine><itemref idref="c"/></spine></package>',
      'c.xhtml':
          '<html xmlns="http://www.w3.org/1999/xhtml"><head><style>'
          'body {margin:0; font-family:Ahem;} div {margin:0;}'
          '.banner {position:relative; text-align:center; text-indent:0; duokan-bleed:lefttopright;}'
          '.banner img {width:70%;}'
          '.caption {position:absolute; left:50%; top:50%; transform:translate(-50%,-50%);'
          'color:white; pointer-events:none; z-index:1; text-align:center; font-size:1.3em; line-height:1.4; text-indent:0;}'
          '$extraCss</style></head><body>$leading<div class="banner"><img src="banner.png"/>'
          '${nested ? '<div class="inner">$innerContent' : ''}<div class="caption">TITLE</div>${nested ? '</div>' : ''}'
          '</div><p>BODY TEXT</p></body></html>',
      'banner.png': bytes,
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
  return source.loadChapter(0);
}

Future<ByteData> _paint(PageContent page, ui.Image image) async {
  final recorder = ui.PictureRecorder();
  PagePainter(imageLookup: (_) => image)
      .paint(Canvas(recorder), page, pageSize: _pageSize, pageInsets: _insets);
  final picture = recorder.endRecording();
  final output = await picture.toImage(384, 854);
  try {
    return (await output.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  } finally {
    output.dispose();
    picture.dispose();
  }
}

Rect _titleInk(ByteData data, Rect imageBounds) {
  var left = 384, top = 854, right = -1, bottom = -1;
  for (
    var y = imageBounds.top.ceil() + 2;
    y < imageBounds.bottom.floor() - 2;
    y++
  ) {
    for (
      var x = imageBounds.left.ceil() + 2;
      x < imageBounds.right.floor() - 2;
      x++
    ) {
      if (data.getUint32((y * 384 + x) * 4) != 0xFFFFFFFF) continue;
      if (x < left) left = x;
      if (x > right) right = x;
      if (y < top) top = y;
      if (y > bottom) bottom = y;
    }
  }
  expect(right, greaterThanOrEqualTo(left), reason: '白色标题必须实际画在图片上');
  return Rect.fromLTRB(
    left.toDouble(),
    top.toDouble(),
    right + 1.0,
    bottom + 1.0,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('绝对定位标题以相对定位图片容器为基准，百分比平移使用标题自身宽度', () async {
    final image = await _image();
    addTearDown(image.dispose);
    final page = (await _pages(image)).single;
    final picture = page.slices.first.block;
    final title = page.slices.singleWhere((slice) => slice.overlay);
    expect(title.block.layout.text, 'TITLE');
    expect(title.absoluteTop, closeTo(picture.height / 2, .01));
    expect(title.leftInset, closeTo(_width / 2, .01));
    expect(title.block.layout.maxWidth, closeTo(23.4 * 5, .01));
    expect(title.block.startCfi, isNotNull);
    final imageWidth = _width * .7;
    final bounds = Rect.fromLTWH(
      _insets.left + (_width - imageWidth) / 2,
      _insets.top,
      imageWidth,
      picture.height,
    );
    final ink = _titleInk(await _paint(page, image), bounds);
    expect(ink.center.dx, closeTo(bounds.center.dx, 1));
    expect(ink.center.dy, closeTo(bounds.center.dy, 2));
    expect(page.slices.last.block.layout.text, 'BODY TEXT');
  });

  test('前置正文和静态内层容器不改变最近定位祖先', () async {
    final image = await _image();
    addTearDown(image.dispose);
    final page = (await _pages(
      image,
      leading: '<p style="height:80px;margin:0;">BEFORE</p>',
      nested: true,
      extraCss: '.banner {duokan-bleed:none;}',
    )).single;
    final title = page.slices.singleWhere((slice) => slice.overlay);
    final picture = page.slices.singleWhere((slice) => slice.block.isReplaced);
    expect(title.absoluteTop, closeTo(80 + picture.block.height / 2, .01));
    expect(title.leftInset, closeTo(_width / 2, .01));
    expect(page.slices.last.block.layout.text, 'BODY TEXT');
  });

  test('定位包含块使用 padding-box，保留自身边距且后续正文不被覆盖层撑高', () async {
    final image = await _image();
    addTearDown(image.dispose);
    final page = (await _pages(
      image,
      extraCss:
          '.banner {width:220px; padding:12px 20px; margin:15px 30px; border:4px solid red;duokan-bleed:none;}'
          '.banner img {width:100%;display:block;}',
    )).single;
    final title = page.slices.singleWhere((slice) => slice.overlay);
    final picture = page.slices.singleWhere((slice) => slice.block.isReplaced);
    expect(
      title.absoluteTop,
      closeTo(15 + 4 + (picture.block.height + 24) / 2, .01),
    );
    expect(title.leftInset, closeTo(30 + 4 + (220 + 40) / 2, .01));
    expect(title.block.style!.margin.left, 0);
    expect(title.block.style!.margin.right, 0);
    expect(page.usedHeight, lessThan(350));
  });

  test('静态容器不接管页面绝对定位，固定定位仍按页面放置', () async {
    final image = await _image();
    addTearDown(image.dispose);
    final page = (await _pages(
      image,
      extraCss: '.banner {position:static;}',
    )).single;
    final title = page.slices.singleWhere((slice) => slice.overlay);
    expect(title.absoluteTop, closeTo(_height / 2, .01));
    expect(title.leftInset, closeTo(_width / 2, .01));
    final fixed = (await _pages(
      image,
      extraCss: '.caption {position:fixed;}',
    )).single;
    expect(
      fixed.slices.singleWhere((slice) => slice.overlay).absoluteTop,
      closeTo(_height / 2, .01),
    );
  });

  test('定位子容器优先于外层定位容器，并保留自身百分比尺寸', () async {
    final image = await _image();
    addTearDown(image.dispose);
    final page = (await _pages(
      image,
      nested: true,
      innerContent:
          '<p style="height:80px;margin:0;color:transparent;">ANCHOR</p>',
      extraCss:
          '.inner {position:relative;width:180px;margin-left:25px;}'
          '.caption {width:50%;height:20px;}',
    )).single;
    final title = page.slices.singleWhere((slice) => slice.overlay);
    final picture = page.slices.singleWhere((slice) => slice.block.isReplaced);
    expect(title.absoluteTop, closeTo(picture.block.height + 40, .01));
    expect(title.leftInset, closeTo(25 + 90, .01));
    expect(title.block.layout.maxWidth, closeTo(90, .01));
  });

  test('父容器裁剪和背景按在流图片收口，标题仍在裁剪盒中央绘制', () async {
    final image = await _image();
    addTearDown(image.dispose);
    final page = (await _pages(
      image,
      extraCss: '.banner {overflow:hidden;background:#00ff00;}',
    )).single;
    final picture = page.slices.first.block;
    final width = _width * .7;
    final bounds = Rect.fromLTWH(
      _insets.left + (_width - width) / 2,
      _insets.top,
      width,
      picture.height,
    );
    final pixels = await _paint(page, image);
    final ink = _titleInk(pixels, bounds);
    expect(ink.center.dx, closeTo(bounds.center.dx, 1));
    expect(ink.center.dy, closeTo(bounds.center.dy, 2));
    expect(
      pixels.getUint32(((bounds.bottom + 3).round() * 384 + 20) * 4),
      0xFFFFFFFF,
      reason: '绝对定位子块不应把父背景撑出图片的高度',
    );
  });
}
