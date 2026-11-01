import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_core/paint/paragraph_cache.dart';

import 'support/css_chapter_book.dart';

const _width = 344.0;
const _height = 260.0;
const _scale = 3;
const _title = '神明遗物';
late Uint8List _leftBytes;
late Uint8List _rightBytes;
late ui.Image _leftImage;
late ui.Image _rightImage;

Future<Uint8List> _imageBytes(Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder)
      .drawRect(const Rect.fromLTWH(0, 0, 60, 20), Paint()..color = color);
  final picture = recorder.endRecording();
  final image = await picture.toImage(60, 20);
  picture.dispose();
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

Future<ui.Image> _decode(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final image = (await codec.getNextFrame()).image;
  codec.dispose();
  return image;
}

Future<PageContent> _titlePage({
  double size = 17,
  double width = _width,
  String align = 'baseline',
  String dimensions = 'height: .8em; width: auto;',
  bool withFloat = false,
}) async {
  final source = await openCssChapter(
    body:
        '<p><img class="icon" src="../Images/left.png"/>$_title'
        '<img class="icon" src="../Images/right.png"/></p>'
        '${withFloat ? '<div style="float: right; width: 30px; height: 20px;">浮动</div>' : ''}',
    css:
        'body { margin: 0; font-family: relic_song; font-size: ${size}px; } '
        'p { margin: 20px 0; text-indent: 0; text-align: center; '
        'line-height: 1.6; color: #008000; } '
        '.icon { margin: 0 10px; vertical-align: $align; $dimensions }',
    binaryFiles: {
      'OEBPS/Images/left.png': _leftBytes,
      'OEBPS/Images/right.png': _rightBytes,
    },
    contentWidth: width,
    contentHeight: _height,
  );
  return (await source.loadChapter(0)).single;
}

Future<Uint8List> _paint(PageContent page, ParagraphCache? cache) async {
  final recorder = ui.PictureRecorder();
  PagePainter(
    paragraphCache: cache,
    imageLookup: (url) => url.endsWith('left.png') ? _leftImage : _rightImage,
  ).paint(
    Canvas(recorder)..scale(_scale.toDouble()),
    page,
    pageSize: const Size(_width, _height),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    (_width * _scale).round(),
    (_height * _scale).round(),
  );
  picture.dispose();
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

Rect _inkBounds(Uint8List pixels, int rgb) {
  var left = (_width * _scale).round();
  var right = -1;
  var top = (_height * _scale).round();
  var bottom = -1;
  for (var index = 0; index < pixels.length; index += 4) {
    final color =
        pixels[index] << 16 | pixels[index + 1] << 8 | pixels[index + 2];
    if (color != rgb || pixels[index + 3] != 255) continue;
    final x = index ~/ 4 % (_width * _scale).round();
    final y = index ~/ 4 ~/ (_width * _scale).round();
    if (x < left) left = x;
    if (x > right) right = x;
    if (y < top) top = y;
    if (y > bottom) bottom = y;
  }
  expect(right, greaterThanOrEqualTo(left), reason: '目标图片或文字必须实际绘制');
  return Rect.fromLTRB(
    left / _scale,
    top / _scale,
    (right + 1) / _scale,
    (bottom + 1) / _scale,
  );
}

Future<void> _expectSeparatedInk(PageContent page) async {
  final pixels = await _paint(page, null);
  final left = _inkBounds(pixels, 0xff0000);
  final text = _inkBounds(pixels, 0x008000);
  final right = _inkBounds(pixels, 0x0000ff);
  expect(text.left - left.right, greaterThanOrEqualTo(9), reason: '左装饰不能压住标题');
  expect(right.left - text.right, greaterThanOrEqualTo(9), reason: '右装饰不能压住标题');
  expect(left.top, closeTo(right.top, .34));
  expect(left.width, closeTo(right.width, .34));
  final cache = ParagraphCache();
  addTearDown(cache.dispose);
  for (var pass = 0; pass < 2; pass++) {
    expect(await _paint(page, cache), orderedEquals(pixels));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('relic_song')..addFont(
          rootBundle.load('assets/fonts/SourceHanSerifCN-Regular.otf'),
        ))
        .load();
    _leftBytes = await _imageBytes(const Color(0xffff0000));
    _rightBytes = await _imageBytes(const Color(0xff0000ff));
    _leftImage = await _decode(_leftBytes);
    _rightImage = await _decode(_rightBytes);
  });
  tearDownAll(() {
    _leftImage.dispose();
    _rightImage.dispose();
  });

  for (final size in [17.0, 22.0]) {
    for (final align in ['baseline', 'middle']) {
      test('${size}px $align：装饰按实际宽高及左右边距占位，标题不重叠', () async {
        final page = await _titlePage(size: size, align: align);
        final layout = page.slices.single.block.layout;
        expect(layout.text, '\uFFFC$_title\uFFFC', reason: '保留原文偏移');
        final line = layout.lines.single;
        expect(line.inlineBoxes, hasLength(2));
        for (final box in line.inlineBoxes) {
          expect(box.width, closeTo(size * .8 * 3, .01));
          expect(box.height, closeTo(size * .8, .01));
          expect(box.spec.marginLeft, 10);
          expect(box.spec.marginRight, 10);
        }
        expect(line.width, closeTo(size * (4 + .8 * 6) + 40, .02));
        expect(line.offsetX, closeTo((_width - line.width) / 2, .01));
        await _expectSeparatedInk(page);
      });
    }
  }

  for (final dimensions in {
    '声明宽': ('width: 45px; height: auto;', 45.0, 15.0),
    '声明双边': ('width: 35px; height: 24px;', 35.0, 24.0),
    '声明宽高比': ('height: 16px; width: auto; aspect-ratio: 2;', 32.0, 16.0),
  }.entries) {
    test('${dimensions.key}：测量尺寸与绘制尺寸一致', () async {
      final page = await _titlePage(dimensions: dimensions.value.$1);
      final boxes = page.slices.single.block.layout.lines.single.inlineBoxes;
      expect(boxes, hasLength(2));
      for (final box in boxes) {
        expect(box.width, closeTo(dimensions.value.$2, .01));
        expect(box.height, closeTo(dimensions.value.$3, .01));
      }
      await _expectSeparatedInk(page);
    });
  }

  test('窄屏装饰整体换行，原文及图片偏移保持稳定', () async {
    final page = await _titlePage(width: 100);
    final layout = page.slices.single.block.layout;
    expect(layout.lines.length, greaterThan(1));
    expect(layout.lines.expand((line) => line.inlineBoxes), hasLength(2));
    expect(
      TextHitTester.lineBoxes(page).map((line) => line.text).join(),
      '\uFFFC$_title\uFFFC',
    );
    expect(layout.lines.every((line) => line.width <= 100), isTrue);
  });

  test('实际像素：左右装饰与标题间均保留原书边距', () async {
    await _expectSeparatedInk(await _titlePage());
  });

  test('章节包含浮动图时，重测和分页不丢装饰的占宽与载荷', () async {
    final page = await _titlePage(withFloat: true);
    expect(
      page.slices.first.block.layout.lines.single.inlineBoxes,
      hasLength(2),
    );
    await _expectSeparatedInk(page);
  });

  test('阅读器覆盖正文大小时，图片 em 仍按作者父标题样式解算', () async {
    final source = await openCssChapter(
      body:
          '<p><img src="../Images/left.png"/>$_title'
          '<img src="../Images/right.png"/></p>',
      css:
          'body { margin: 0; font-size: 17px; font-family: relic_song; } '
          'p { font-size: 1.1em; text-indent: 0; text-align: center; color: #008000; } '
          'img { height: .8em; width: auto; margin: 0 10px; }',
      overrides: const ReaderOverrides(fontSize: 22),
      binaryFiles: {
        'OEBPS/Images/left.png': _leftBytes,
        'OEBPS/Images/right.png': _rightBytes,
      },
      contentWidth: _width,
      contentHeight: _height,
    );
    final page = (await source.loadChapter(0)).single;
    final block = page.slices.single.block;
    expect(block.style!.fontSize, 22);
    for (final box in block.layout.lines.single.inlineBoxes) {
      expect(box.height, closeTo(17 * 1.1 * .8, .01));
      expect(box.width, closeTo(17 * 1.1 * .8 * 3, .01));
    }
    await _expectSeparatedInk(page);
  });
}
