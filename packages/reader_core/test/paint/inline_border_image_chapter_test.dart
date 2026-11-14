import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/hit_test.dart';
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
const _imageUrl = 'images/wave.png';
const _borderStyle =
    '.wave {text-decoration-style:wavy; -moz-text-decoration-style:wavy;'
    'border-bottom:4px solid transparent;'
    'border-image:url(images/wave.png)10 7 7 7 round;'
    'text-decoration:duokan-wavyline; duokan-text-decoration-width:1px;'
    'duokan-text-decoration-color:#333; padding-bottom:1px;}'
    '.solid {border-bottom:1px solid #333; padding-bottom:1px;}';

Future<Uint8List> _borderImageBytes() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(const Color(0xffff0000), BlendMode.src);
  // 10/7/7/7 切片中的底边为绿色，其余源区域红色，便于核对实际取样。
  canvas.drawRect(
    const Rect.fromLTWH(0, 17, 40, 7),
    Paint()..color = const Color(0xff008800),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(40, 24);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
        .asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Uint8List _epub(String css, String body, Uint8List image) => auditZip({
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml':
      '<container><rootfiles><rootfile full-path="book.opf"/>'
      '</rootfiles></container>',
  'book.opf':
      '<package version="3.0" unique-identifier="id" '
      'xmlns="http://www.idpf.org/2007/opf"><metadata '
      'xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="id">inline-border-image</dc:identifier>'
      '<dc:title>行内图片边框正式入口回归</dc:title></metadata><manifest>'
      '<item id="c" href="text/c.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="s" href="styles.css" media-type="text/css"/>'
      '<item id="i" href="$_imageUrl" media-type="image/png"/>'
      '</manifest><spine><itemref idref="c"/></spine></package>',
  'styles.css':
      'body {margin:0; padding:0; font-size:21px; font-family:Ahem; color:black;}'
      'p {margin:0; padding:0; text-indent:0; text-align:left;}'
      '$_borderStyle$css',
  'text/c.xhtml':
      '<html xmlns="http://www.w3.org/1999/xhtml"><head>'
      '<link rel="stylesheet" href="../styles.css"/></head>'
      '<body>$body</body></html>',
  _imageUrl: image,
});

Future<EpubChapterSource> _open(String css, String body) async {
  final source = await const EpubFormatOpener().openBytes(
    _epub(css, body, await _borderImageBytes()),
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

Future<ui.Image> _readImage(EpubChapterSource source) async {
  final bytes = await source.readImageBytes(_imageUrl);
  expect(bytes, isNotNull, reason: '外链 CSS 的图片 URL 必须经正式资源路径可读');
  final codec = await ui.instantiateImageCodec(bytes!);
  try {
    final image = (await codec.getNextFrame()).image;
    addTearDown(image.dispose);
    return image;
  } finally {
    codec.dispose();
  }
}

Future<ByteData> _paint(PageContent page, ui.Image? border) async {
  final recorder = ui.PictureRecorder();
  PagePainter(
    background: const Color(0xffffffff),
    imageLookup: (url) => url == _imageUrl ? border : null,
  ).paint(Canvas(recorder), page, pageSize: _pageSize, pageInsets: _insets);
  final picture = recorder.endRecording();
  final image = await picture.toImage(384, 854);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Rect _greenBounds(ByteData pixels, {Rect? within}) {
  final area = within ?? const Rect.fromLTWH(0, 0, 384, 854);
  var left = 384, top = 854, right = -1, bottom = -1;
  for (
    var y = area.top.floor().clamp(0, 853);
    y < area.bottom.ceil().clamp(0, 854);
    y++
  ) {
    for (
      var x = area.left.floor().clamp(0, 383);
      x < area.right.ceil().clamp(0, 384);
      x++
    ) {
      final i = (y * 384 + x) * 4;
      if (pixels.getUint8(i) < 30 &&
          pixels.getUint8(i + 1) > 110 &&
          pixels.getUint8(i + 2) < 30) {
        if (x < left) left = x;
        if (x > right) right = x;
        if (y < top) top = y;
        if (y > bottom) bottom = y;
      }
    }
  }
  expect(right, greaterThanOrEqualTo(left), reason: '每个实际行片段必须绘制图片底边');
  return Rect.fromLTRB(
    left.toDouble(),
    top.toDouble(),
    right + 1.0,
    bottom + 1.0,
  );
}

int _greenPixels(ByteData pixels) {
  var count = 0;
  for (var i = 0; i < pixels.lengthInBytes; i += 4) {
    if (pixels.getUint8(i) < 30 &&
        pixels.getUint8(i + 1) > 110 &&
        pixels.getUint8(i + 2) < 30) {
      count++;
    }
  }
  return count;
}

Rect _selectionOnPage(PageLineBox box, int start, int end) {
  final rect = TextHitTester.selectionRects(box, start, end).single;
  return rect.shift(
    Offset(_insets.left + box.rect.left, _insets.top + box.rect.top),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('行内仅底边的 border-image 实际绘制，图片缺失时保持透明且原文坐标不变', () async {
    final source = await _open(
      '',
      '<p><span class="solid">前文</span><span class="wave">甲乙</span>后文</p>',
    );
    final original = await source.loadAnchorChapter(0);
    final cfi = original.cfiAt(3)!;
    final page = (await source.loadChapter(0)).single;
    final block = page.slices.single.block;
    final run = block.layout.runs.singleWhere(
      (run) => run.style.borderImage != null,
    );
    expect(run.style.borders.top.width, 0);
    expect(run.style.borders.left.width, 0);
    expect(run.style.borders.right.width, 0);
    expect(run.style.borders.bottom.width, 4);
    expect(run.style.borderImage!.url, _imageUrl);
    final image = await _readImage(source);
    final painted = await _paint(page, image);
    final missing = await _paint(page, null);
    expect(_greenPixels(missing), 0);
    final border = _greenBounds(painted);
    final selection = _selectionOnPage(
      TextHitTester.lineBoxes(page).single,
      2,
      4,
    );
    expect(border.left, closeTo(selection.left, 1));
    expect(border.right, closeTo(selection.right, 1));
    expect(border.height, closeTo(4, 1));
    expect(border.top, greaterThan(selection.top));
    final after = await source.loadAnchorChapter(0);
    expect(after.text, original.text);
    expect(after.cfiAt(3), cfi);
    expect(after.offsetFor(cfi), 3);
  });

  test('跨行行内图片底边逐片段绘制，首尾位置跟随实际换行与选区', () async {
    final text = List.filled(4, '甲乙丙丁戊己').join();
    final source = await _open(
      'p {width:100px;}',
      '<p>前<span class="wave">$text</span>后</p>',
    );
    final page = (await source.loadChapter(0)).single;
    final block = page.slices.single.block;
    expect(block.layout.lineCount, greaterThan(2));
    final pixels = await _paint(page, await _readImage(source));
    final run = block.layout.runs.singleWhere(
      (run) => run.style.borderImage != null,
    );
    final boxes = TextHitTester.lineBoxes(page);
    for (final box in boxes) {
      final line = block.layout.lines[box.lineIndex];
      final start = math.max(run.start, line.start) - line.start;
      final end = math.min(run.end, line.end) - line.start;
      if (end <= start) continue;
      final selection = _selectionOnPage(box, start, end);
      final border = _greenBounds(
        pixels,
        within: Rect.fromLTRB(
          0,
          _insets.top + box.rect.top,
          384,
          _insets.top + box.rect.bottom + 6,
        ),
      );
      expect(border.left, closeTo(selection.left, 1));
      expect(border.right, closeTo(selection.right, 1));
      expect(border.height, closeTo(4, 1));
    }
  });
}
