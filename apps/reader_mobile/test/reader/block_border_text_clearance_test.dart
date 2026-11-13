import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/page_renderer.dart';

import 'support/css_chapter_book.dart';

const _size = Size(366.6666666666667, 773.1694444444445);
const _pixelWidth = 366;
const _pixelHeight = 773;
const _css = '''
html, body { margin: 0; font-family: builtin_song; }
h3 {
  color: #CC0000;
  line-height: 100%;
  text-align: right;
  border-style: solid none dotted solid;
  border-width: 0 0 2px 0;
  border-color: #CC0000;
  font-weight: bold;
  font-size: 1.3em;
  margin-top: 6em;
  margin-bottom: 1em;
  padding: 0.1em;
}
h3 span { font-size: 1.5em; font-weight: bolder; }
''';

Future<PageContent> _page({bool border = true, bool hideText = false}) async {
  final css = [
    border ? _css : '$_css h3 { border-bottom-width: 0; }',
    if (hideText) 'h3, h3 span { color: transparent; }',
  ].join('\n');
  final source = await openCssChapter(
    body: '<h3><span>版权信息</span></h3>',
    css: css,
    contentWidth: _size.width,
    contentHeight: _size.height,
    overrides: const ReaderOverrides(fontSize: 21, lineHeight: 1.6),
  );
  addTearDown(source.close);
  return (await source.loadChapter(0)).single;
}

Future<ByteData> _paint(PageContent page) async {
  final recorder = ui.PictureRecorder();
  const PagePainter().paint(Canvas(recorder), page, pageSize: _size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(_pixelWidth, _pixelHeight);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  } finally {
    image.dispose();
    picture.dispose();
  }
}

bool _notPaper(int pixel) => pixel != 0xffffffff;

int _pixel(ByteData data, int x, int y) =>
    data.getUint32((y * _pixelWidth + x) * 4);

Rect _bounds(ByteData data, bool Function(int) matches) {
  var left = _pixelWidth, top = _pixelHeight;
  var right = -1, bottom = -1;
  for (var y = 0; y < _pixelHeight; y++) {
    for (var x = 0; x < _pixelWidth; x++) {
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

Rect _bottomBorderBounds(ByteData data) {
  var top = _pixelHeight, bottom = -1;
  for (var y = 0; y < _pixelHeight; y++) {
    var paintedPixels = 0;
    for (var x = 0; x < _pixelWidth; x++) {
      if (_notPaper(_pixel(data, x, y))) paintedPixels++;
    }
    if (paintedPixels <= _pixelWidth ~/ 4) continue;
    if (y < top) top = y;
    if (y > bottom) bottom = y;
  }
  expect(bottom, greaterThanOrEqualTo(top), reason: '应绘出底部点线边框');
  return Rect.fromLTRB(0, top.toDouble(), _size.width, bottom + 1.0);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('builtin_song')
          ..addFont(
            rootBundle.load('assets/fonts/SourceHanSerifCN-Regular.otf'),
          )
          ..addFont(rootBundle.load('assets/fonts/SourceHanSerifCN-Bold.otf')))
        .load();
  });

  test('放大行内文字溢出短行盒时，底部边框移到字形之外', () async {
    final bordered = await _page();
    final plain = await _page(border: false);
    final borderedLayout = bordered.slices.single.block.layout;
    final plainLayout = plain.slices.single.block.layout;
    expect(borderedLayout.lineCount, plainLayout.lineCount);
    expect(
      borderedLayout.lines.single.baseline,
      plainLayout.lines.single.baseline,
    );

    final plainPixels = await _paint(plain);
    final text = _bounds(plainPixels, _notPaper);
    final border = _bottomBorderBounds(
      await _paint(await _page(hideText: true)),
    );
    expect(border.top, greaterThan(text.bottom), reason: '点线边框必须与放大后的标题字形留出空白');
  });
}
