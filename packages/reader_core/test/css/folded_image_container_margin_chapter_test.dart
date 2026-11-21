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

const _pageSize = Size(384, 853.3333333333333);
const _insets = EdgeInsets.fromLTRB(9, 56, 9, 30);
const _green = Color(0xFF008800);
late ui.Image _image;
late Uint8List _imageBytes;

Future<void> _prepareImage() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(_green, BlendMode.src);
  final picture = recorder.endRecording();
  _image = await picture.toImage(40, 20);
  picture.dispose();
  _imageBytes = (await _image.toByteData(format: ui.ImageByteFormat.png))!
      .buffer
      .asUint8List();
}

Uint8List _book(String body, String css) => auditZip({
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml':
      '<container><rootfiles><rootfile full-path="book.opf"/>'
      '</rootfiles></container>',
  'book.opf':
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
      'unique-identifier="id"><metadata '
      'xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="id">folded-image-margin</dc:identifier>'
      '<dc:title>折叠图片容器边距回归</dc:title></metadata><manifest>'
      '<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="pic" href="picture.png" media-type="image/png"/>'
      '</manifest><spine><itemref idref="c"/></spine></package>',
  'c.xhtml':
      '<html xmlns="http://www.w3.org/1999/xhtml"><head><style>'
      'body { margin:0; font-family:Ahem; } '
      'p { margin:0; } img { width:40px; height:20px; } '
      '.picture { margin:6px 0 8px; text-align:center; } '
      '.marker { width:1px; height:20px; display:block; } '
      '$css</style></head><body>$body</body></html>',
  'picture.png': _imageBytes,
});

Future<PageContent> _page(
  String body,
  String css, {
  double? fontSize = 18,
}) async {
  final source = await const EpubFormatOpener().openBytes(
    _book(body, css),
    options: ReaderOpenOptions(
      contentWidth: _pageSize.width - _insets.horizontal,
      contentHeight: _pageSize.height - _insets.vertical,
    ),
  );
  addTearDown(source.close);
  await source.applyOverrides(
    ReaderOverrides(fontSize: fontSize, lineHeight: 1.6, paragraphSpacing: 10),
  );
  await source.applyContentSize(
    width: _pageSize.width - _insets.horizontal,
    height: _pageSize.height - _insets.vertical,
    topInset: _insets.top,
    sideInsets: (left: _insets.left, right: _insets.right),
  );
  return (await source.loadChapter(0)).single;
}

List<double> _tops(PageContent page) {
  var y = _insets.top + page.topPadding;
  return [
    for (final slice in page.slices)
      (() {
        final top = y + slice.leadingExtent;
        y += slice.height;
        return top;
      })(),
  ];
}

Future<ByteData> _paint(PageContent page) async {
  final recorder = ui.PictureRecorder();
  PagePainter(imageLookup: (_) => _image)
      .paint(Canvas(recorder), page, pageSize: _pageSize, pageInsets: _insets);
  final picture = recorder.endRecording();
  final rendered = await picture.toImage(384, 854);
  try {
    return (await rendered.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  } finally {
    rendered.dispose();
    picture.dispose();
  }
}

void _expectContainerShift(
  PageContent baseline,
  PageContent changed,
  double top,
  double bottom,
) {
  final before = _tops(baseline);
  final after = _tops(changed);
  expect(after, hasLength(before.length));
  expect(after.first, closeTo(before.first, .001));
  for (var index = 1; index < after.length - 1; index++) {
    expect(
      after[index] - before[index],
      closeTo(top, .001),
      reason: '外层上边距只移动整个容器，内部图片与文字应同步移动',
    );
  }
  expect(after.last - before.last, closeTo(top + bottom, .001));
}

const _marker = '<img class="marker" src="picture.png"/>';
const _picture = '<div class="picture"><img src="picture.png"/></div>';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_prepareImage);
  tearDownAll(() => _image.dispose());

  for (final (margin, expectedTop) in [
    ('2em', 36.0),
    ('12px', 12.0),
    ('0', 0.0),
    ('-8px', -8.0),
  ]) {
    test('章首出血容器保留图片自身 $margin 上边距，绘制与正文流同步', () async {
      final page = await _page(
        '$_picture<h2 class="heading">标题</h2><p>相邻正文</p>',
        '''
body { font-size:16px; }
.picture { margin:0; text-align:left; duokan-bleed:lefttopright; }
.picture img { width:85%; height:auto; margin:$margin 1.55em 0 1.5em; }
.heading { margin:1em 0 2.7em; font-size:1em; }
''',
      );
      final image = page.slices.first.block;
      final tops = _tops(page);
      expect(tops.first, closeTo(expectedTop, .001));
      expect(image.layout.height, closeTo(_pageSize.width * .85 / 2, .001));
      expect(
        tops[1],
        closeTo(expectedTop + image.layout.height + 18, .001),
        reason: '图片、标题和相邻正文共享同一正式分页位置',
      );
      final pixels = await _paint(page);
      final rows = [
        for (var y = 0; y < 854; y++)
          if (pixels.getUint32((y * 384 + 192) * 4) == 0x008800ff) y,
      ];
      expect(rows.first, closeTo(expectedTop < 0 ? 0 : expectedTop, 1));
      expect(rows.last + 1, closeTo(expectedTop + image.layout.height, 1));
      final hit = page.hitTest(
        Offset(192 - _insets.left, rows[rows.length ~/ 2] - _insets.top),
      );
      expect(hit?.slice.block, same(image), reason: '恢复留白后仍命中头图');
    });
  }

  for (final (fontSize, width, left) in [
    (18.0, 326.4, 27.0),
    (50 / 2.8125, 326.4, 75 / 2.8125),
    (56 / 2.8125, (1080 - 56 * 3.05) / 2.8125, 84 / 2.8125),
    (24.0, 310.8, 36.0),
    (null, 326.4, 24.0),
  ]) {
    test('阅读字号$fontSize传到出血头图em边距，超宽时等比缩小', () async {
      final page = await _page('$_picture<h2>标题</h2><p>相邻正文</p>', '''
body { margin:0 1%; }
.picture { margin:0; text-align:left; duokan-bleed:lefttopright; }
.picture img { width:85%; height:auto; margin:2em 1.55em 0 1.5em; }
h2 { margin:1em 0; font-size:1em; }
''', fontSize: fontSize);
      final image = page.slices.first.block;
      expect(image.style!.width!.value, closeTo(width, .001));
      expect(image.layout.height, closeTo(width / 2, .001));
      expect(image.style!.margin.left, closeTo(left, .001));
      expect(_tops(page).first, closeTo(2 * (fontSize ?? 16), .001));
      final pixels = await _paint(page);
      final y = (_tops(page).first + image.layout.height / 2).round();
      final columns = [
        for (var x = 0; x < 384; x++)
          if (pixels.getUint32((y * 384 + x) * 4) == 0x008800ff) x,
      ];
      expect(columns.first, closeTo(left, 1));
      expect(columns.last + 1, closeTo(left + width, 1));
      final hit = page.hitTest(Offset(left + width / 2 - 9, y - 56.0));
      expect(hit?.slice.block, same(image));
      expect(image.startCfi, isNotNull);
      expect(page.slices.last.block.layout.text, '相邻正文');
    });
  }

  test('图片em、rem及calc各按对应字号求解，像素边距和父盒尺寸不变', () async {
    final page = await _page(
      '<div class="picture"><img src="picture.png"/><p>图注</p></div>'
          '<p>相邻正文</p>',
      '''
.picture { width:200px; padding:4px; margin:0; font-size:.5em; }
.picture img { margin:calc(1em + 3px) 10px 1rem 2em; }
''',
      fontSize: 24,
    );
    final image = page.slices.first.block;
    expect(image.style!.fontSize, 12);
    expect(image.style!.margin.top, 15);
    expect(image.style!.margin.bottom, 24);
    expect(image.style!.width!.value, 40);
    expect(image.layout.height, 20);
    expect(image.containers.single.container.contentWidth, 200);
  });

  for (final (top, bottom) in [(32, 24), (-32, -24), (0, 32)]) {
    test('保留容器边距 $top/$bottom 只移动整体，不在内部图片重复消费', () async {
      const body =
          '$_marker<div class="panel"><p>容器开头</p>'
          '$_picture<p>容器末尾</p></div>$_marker';
      const css = '.panel { padding:12px; }';
      final baseline = await _page(body, css);
      final changed = await _page(
        body,
        '$css .panel { margin:${top}px 0 ${bottom}px; }',
      );
      _expectContainerShift(
        baseline,
        changed,
        top.toDouble(),
        bottom.toDouble(),
      );
      final pixels = await _paint(changed);
      final y = _tops(changed)[2].ceil() + 2;
      expect(pixels.getUint32((y * 384 + 192) * 4), 0x008800ff);
    });
  }

  test('首末纯图后代保留自身边距，外层边距不在两张图片上重复消费', () async {
    const body =
        '$_marker<div class="panel">$_picture'
        '<p>两张图片之间的说明</p>$_picture</div>$_marker';
    const css = '.panel { padding:12px; }';
    final baseline = await _page(body, css);
    final changed = await _page(body, '$css .panel { margin:32px 0 24px; }');
    _expectContainerShift(baseline, changed, 32, 24);
  });

  test('两层保留容器的边距只各消费一次，折叠图片仍在内层文字之后', () async {
    const body =
        '$_marker<div class="outer"><div class="panel">'
        '<p>容器开头</p>$_picture<p>容器末尾</p></div></div>$_marker';
    const css = '.outer, .panel { padding:12px; }';
    final baseline = await _page(body, css);
    final changed = await _page(
      body,
      '$css .outer { margin:48px 0 16px; } '
      '.panel { margin:32px 0 24px; }',
    );
    _expectContainerShift(baseline, changed, 80, 40);
  });

  test('纯图兄弟的负边距继续按声明叠放，不混入保留容器的上边距', () async {
    const body =
        '<div class="frame"><div class="support">'
        '<img src="picture.png"/></div><div class="portrait">'
        '<a href="c.xhtml"><img src="picture.png"/></a></div>'
        '<p>封面后的书名</p></div>';
    final page = await _page(body, '''
body { margin:0 10px; font-size:97%; }
.frame { padding:.5em 15px 15px; margin:1em 5px .3em; }
.support { margin:20% 0; text-align:center; }
.support img { width:65%; height:60px; }
.portrait { margin:-68% auto 10%; text-align:center; }
.portrait img { width:30.5%; height:120px; }
''');
    final parentWidth = _pageSize.width - _insets.horizontal - 20 - 10 - 30;
    final tops = _tops(page);
    final supportTop = _insets.top + 16 * .97 * 1.5 + parentWidth * .2;
    expect(tops.first, closeTo(supportTop, .001));
    expect(
      tops[1],
      closeTo(supportTop + 60 + parentWidth * (.2 - .68), .001),
      reason: '封面与书架只消费各自折叠后的正负边距',
    );
    expect(page.slices[1].block.layout.height, 120);
  });
}
