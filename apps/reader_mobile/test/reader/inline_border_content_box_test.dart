import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/page_renderer.dart';

import 'support/css_chapter_book.dart';

const _size = Size(320, 240);
const _titleCss = '''
html, body { margin: 0; font: 20px/130% builtin_song; }
h1 { font-size: 1.4em; text-align: center; margin: 25% 0 1em; }
h1 span {
  color: black; border-style: solid; border-color: red;
  border-width: .15em 0; padding: .1em .1em 0;
}
''';

Future<PageContent> _page(
  String title,
  String css, {
  String after = '',
  ReaderOverrides overrides = const ReaderOverrides(),
  double? contentHeight,
}) async {
  final source = await openCssChapter(
    body: '<h1><span>$title</span></h1>$after',
    css: css,
    contentWidth: _size.width,
    contentHeight: contentHeight ?? _size.height,
    overrides: overrides,
  );
  addTearDown(source.close);
  return (await source.loadChapter(0)).single;
}

Future<ByteData> _paint(PageContent page, {Size pageSize = _size}) async {
  final recorder = ui.PictureRecorder();
  const PagePainter().paint(Canvas(recorder), page, pageSize: pageSize);
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    _size.width.toInt(),
    _size.height.toInt(),
  );
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  } finally {
    image.dispose();
    picture.dispose();
  }
}

bool _red(int pixel) =>
    pixel >> 24 > 200 && (pixel >> 16 & 255) < 80 && (pixel >> 8 & 255) < 80;

bool _black(int pixel) =>
    pixel >> 24 < 80 && (pixel >> 16 & 255) < 80 && (pixel >> 8 & 255) < 80;

int _pixel(ByteData data, int x, int y) =>
    data.getUint32((y * _size.width.toInt() + x) * 4);

Rect _bounds(ByteData data, bool Function(int) matches) {
  var left = _size.width.toInt(), top = _size.height.toInt();
  var right = -1, bottom = -1;
  for (var y = 0; y < _size.height; y++) {
    for (var x = 0; x < _size.width; x++) {
      if (!matches(_pixel(data, x, y))) continue;
      if (x < left) left = x;
      if (x > right) right = x;
      if (y < top) top = y;
      if (y > bottom) bottom = y;
    }
  }
  expect(right, greaterThanOrEqualTo(left), reason: '应绘出指定颜色的像素');
  return Rect.fromLTRB(
    left.toDouble(),
    top.toDouble(),
    right + 1.0,
    bottom + 1.0,
  );
}

List<({int start, int end})> _borderBands(ByteData data, int x) {
  final bands = <({int start, int end})>[];
  int? start;
  for (var y = 0; y <= _size.height; y++) {
    final red = y < _size.height && _red(_pixel(data, x, y));
    if (red && start == null) start = y;
    if (!red && start != null) {
      bands.add((start: start, end: y));
      start = null;
    }
  }
  return bands;
}

void _expectSameLines(PageContent bordered, PageContent plain) {
  final actual = bordered.slices.first.block.layout;
  final expected = plain.slices.first.block.layout;
  expect(actual.lineCount, expected.lineCount);
  expect(actual.height, expected.height, reason: '行内上下边框不撑高行盒');
  expect(actual.lines.single.baseline, expected.lines.single.baseline);
}

Future<void> _expectFontBox(double lineHeight) async {
  final css =
      '''
html, body { margin: 0; }
h1 { margin: 60px 0; font: 40px/$lineHeight Ahem; text-align: center; }
span { color: transparent; border: 6px solid red;
  border-width: 6px 0; padding: 4px 4px 0; }
''';
  final page = await _page('AAAA', css);
  final plain = await _page('AAAA', '$css span { border: none; }');
  _expectSameLines(page, plain);
  final bands = _borderBands(await _paint(page), _size.width ~/ 2);
  expect(bands, hasLength(2));
  for (final band in bands) {
    expect(band.end - band.start, closeTo(6, 1), reason: '上下边框各占 6px');
  }
  expect(
    bands.last.start - bands.first.end,
    closeTo(44, 1),
    reason: '边框内沿之间为 40px 字体盒 + 4px 顶部内边距，不受行高影响',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('builtin_song')
          ..addFont(rootBundle.load('assets/fonts/MoyuSerif-Regular.otf'))
          ..addFont(rootBundle.load('assets/fonts/MoyuSerif-Bold.otf')))
        .load();
  });

  for (final height in [.8, 1.3, 2.0]) {
    test('行高 $height 时上下边框位于字体盒和内边距之外', () => _expectFontBox(height));
  }

  test('内容简介标题底部内边距为零时，上下边框仍不压住汉字', () async {
    final page = await _page('【内容简介】', _titleCss);
    final plain = await _page('【内容简介】', '$_titleCss h1 span { border: none; }');
    _expectSameLines(page, plain);
    final pixels = await _paint(page);
    final text = _bounds(await _paint(plain), _black);
    expect(_bounds(pixels, _black), text, reason: '修正边框不能移动或裁掉文字');
    final border = _bounds(pixels, _red);
    final bands = _borderBands(pixels, border.left.toInt() + 1);
    expect(bands, hasLength(2));
    expect(bands.first.end, lessThanOrEqualTo(text.top));
    expect(bands.last.start, greaterThanOrEqualTo(text.bottom));
  });

  test('真机阅读设置下，标题后紧接简介正文时仍绘出完整上下边框', () async {
    const settings = ReaderOverrides(
      fontSize: 17,
      lineHeight: 1.6,
      paragraphSpacing: 10,
    );
    const after = '<p>这是两个年轻人拯救世界的俗套故事。</p>';
    final css = '$_titleCss p { color: blue; }';
    final page = await _page('【内容简介】', css, after: after, overrides: settings);
    final plain = await _page(
      '【内容简介】',
      '$css h1 span { border: none; }',
      after: after,
      overrides: settings,
    );
    _expectSameLines(page, plain);
    expect(page.usedHeight, plain.usedHeight, reason: '边框溢出不改变正文占位');
    final pixels = await _paint(page);
    final border = _bounds(pixels, _red);
    final bands = _borderBands(pixels, border.left.toInt() + 1);
    expect(bands, hasLength(2), reason: '不能按标题行盒裁掉下边框');
    final borderWidth =
        page.slices.first.block.layout.runs.first.style.borders.top.width;
    for (final band in bands) {
      expect(band.end - band.start, closeTo(borderWidth, 1), reason: '边框厚度完整');
    }
    final text = _bounds(await _paint(plain), _black);
    expect(bands.first.end, lessThanOrEqualTo(text.top));
    expect(bands.last.start, greaterThanOrEqualTo(text.bottom));
  });

  test('行内边框的裁剪扩展不越出本页内容区', () async {
    const height = 140.0;
    final page = await _page('AAAA', '''
html, body { margin: 0; }
h1 { margin: 100px 0 0; font: 40px/.8 Ahem; text-align: center; }
span { color: transparent; border: 12px solid red; border-width: 12px 0; }
''', contentHeight: height);
    final pixels = await _paint(page, pageSize: Size(_size.width, height));
    final border = _bounds(pixels, _red);
    expect(border.bottom, lessThanOrEqualTo(height), reason: '页外仍必须裁剪边框');
    final bands = _borderBands(pixels, _size.width ~/ 2);
    expect(bands, hasLength(2));
    expect(bands.last.end, height, reason: '只绘制下边框落在本页的部分');
  });

  test('行内边框扩展仍遵守作者 overflow: hidden', () async {
    const css = '''
html, body { margin: 0; }
h1 { margin: 60px 0; font: 40px/.8 Ahem; text-align: center; }
span { color: transparent; border: 6px solid red; border-width: 6px 0; }
''';
    final visible = await _page('AAAA', css);
    final hidden = await _page('AAAA', '$css h1 { overflow: hidden; }');
    expect(_borderBands(await _paint(visible), _size.width ~/ 2), hasLength(2));
    expect(_borderBands(await _paint(hidden), _size.width ~/ 2), isEmpty);
  });
}
