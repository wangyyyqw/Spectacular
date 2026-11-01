import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/paint/line_spans.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_core/paint/paragraph_cache.dart';

import 'support/css_chapter_book.dart';

const _caption = '白金常规形态&海浪使用形态';
const _width = 344.0;
const _height = 240.0;
const _scale = 3;

Future<PageContent> _page({
  double size = 17,
  String align = 'center',
  String captionBox = '',
}) async {
  final source = await openCssChapter(
    body:
        '<p class="caption"><span>$_caption</span></p>'
        '<div class="float">浮动</div>',
    css:
        'body { margin: 0; font-family: align_song; font-size: ${size}px; } '
        '.caption { margin: 10px; line-height: 1.6; text-indent: 0; '
        'text-align: $align; color: #008000; $captionBox } '
        '.caption span { font-size: .72em; font-family: align_caption; } '
        '.float { float: right; width: 20px; height: 15px; color: transparent; }',
    contentWidth: _width,
    contentHeight: _height,
  );
  return (await source.loadChapter(0)).single;
}

TextPainter _painter(PageLineBox box) {
  final block = box.slice.block;
  final line = block.layout.lines[box.lineIndex];
  return TextPainter(
    text: buildLineSpan(
      layout: block.layout,
      line: line,
      baseStyle: TextLayoutEngine.textStyleFor(block.style!),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
}

void _expectAligned(PageLineBox box, String align) {
  final painter = _painter(box);
  final line = box.slice.block.layout.lines[box.lineIndex];
  expect(line.width, closeTo(painter.width, .01), reason: '测量与绘制必须使用同一组行内样式');
  expect(box.rect.width, closeTo(painter.width, .01));
  final target = switch (align) {
    'left' => 10.0,
    'right' => _width - 10 - painter.width,
    _ => (_width - painter.width) / 2,
  };
  expect(box.rect.left, closeTo(target, .01));
  final selection = TextHitTester.selectionRects(
    box,
    0,
    box.text.length,
  ).reduce((left, right) => left.expandToInclude(right));
  expect(selection.left, closeTo(0, .01));
  expect(selection.right, closeTo(painter.width, .01));
  painter.dispose();
}

void _expectHitBounds(PageContent page, PageLineBox box) {
  final left = TextHitTester.hitTest(
    page,
    Offset(box.rect.left - 1, box.rect.center.dy),
  )!;
  final right = TextHitTester.hitTest(
    page,
    Offset(box.rect.right + 1, box.rect.center.dy),
  )!;
  expect(left.atLineStart, isTrue);
  expect(left.charOffset, 0);
  expect(right.atLineEnd, isTrue);
  expect(right.charOffset, box.text.length);
}

Future<Uint8List> _paint(PageContent page, ParagraphCache? cache) async {
  final recorder = ui.PictureRecorder();
  PagePainter(paragraphCache: cache).paint(
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
  final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return pixels!.buffer.asUint8List();
}

Future<void> _expectCenteredInk(PageContent page) async {
  final pixels = await _paint(page, null);
  var left = (_width * _scale).round();
  var right = -1;
  for (var i = 0; i < pixels.length; i += 4) {
    if (pixels[i] != 0 ||
        pixels[i + 1] != 128 ||
        pixels[i + 2] != 0 ||
        pixels[i + 3] != 255) {
      continue;
    }
    final x = i ~/ 4 % (_width * _scale).round();
    if (x < left) left = x;
    if (x > right) right = x;
  }
  expect(right, greaterThan(left), reason: '图注必须实际绘制');
  expect((left + right + 1) / (2 * _scale), closeTo(_width / 2, 1));
  final cache = ParagraphCache();
  addTearDown(cache.dispose);
  for (var pass = 0; pass < 2; pass++) {
    expect(await _paint(page, cache), orderedEquals(pixels));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final family in ['align_song', 'align_caption']) {
      await (FontLoader(family)..addFont(
            rootBundle.load('assets/fonts/SourceHanSerifCN-Regular.otf'),
          ))
          .load();
    }
  });

  for (final size in [17.0, 22.0]) {
    for (final align in ['left', 'center', 'right']) {
      test('${size}px $align：浮动章节图注按真实行内字号和字体对齐', () async {
        final page = await _page(size: size, align: align);
        final box = TextHitTester.lineBoxes(page)
            .singleWhere((box) => box.text == _caption);
        expect(box.slice.block.layout.runs.single.style.fontSize, size * .72);
        expect(box.slice.block.layout.runs.single.style.fontFamilies, [
          'align_caption',
        ]);
        _expectAligned(box, align);
        _expectHitBounds(page, box);
        if (align == 'center') await _expectCenteredInk(page);
      });
    }
  }

  test('声明盒高的图注重测仍保留行内字号、字体及选区', () async {
    final page = await _page(captionBox: 'height: 50px;');
    final box = TextHitTester.lineBoxes(page)
        .singleWhere((box) => box.text == _caption);
    expect(box.slice.block.layout.runs.single.style.fontSize, 17 * .72);
    _expectAligned(box, 'center');
    _expectHitBounds(page, box);
    await _expectCenteredInk(page);
  });

  test('跨页重测裁切并平移行内样式，原文字和命中偏移不变', () async {
    final text = _caption * 18;
    final source = await openCssChapter(
      body: '<p>前<span>$text</span>后</p><div class="float">浮动</div>',
      css:
          'body { margin: 0; font-family: align_song; font-size: 17px; } '
          'p { margin: 10px; text-indent: 0; text-align: center; line-height: 1.6; } '
          'span { font-size: .72em; font-family: align_caption; } '
          '.float { float: right; width: 20px; height: 15px; }',
      contentWidth: _width,
      contentHeight: 100,
    );
    final pages = await source.loadChapter(0);
    expect(pages.length, greaterThan(1));
    final lines = [
      for (final page in pages)
        ...TextHitTester.lineBoxes(page).where((box) => box.text != '浮动'),
    ];
    expect(lines.map((box) => box.text).join(), '前$text后');
    for (final box in lines) {
      _expectAligned(box, 'center');
    }
    for (final page in pages) {
      for (final box in TextHitTester.lineBoxes(page)) {
        if (box.text != '浮动') _expectHitBounds(page, box);
      }
    }
  });
}
