import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_core/paint/paragraph_cache.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_ui/panels/settings_panel.dart';

import 'support/css_chapter_book.dart';

Future<Uint8List> _paint(PageContent page, ParagraphCache? cache) async {
  final recorder = ui.PictureRecorder();
  PagePainter(paragraphCache: cache)
      .paint(Canvas(recorder), page, pageSize: const Size(300, 160));
  final picture = recorder.endRecording();
  final image = await picture.toImage(300, 160);
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!.buffer.asUint8List();
}

void _expectInkInside(Uint8List pixels) {
  final border = <int>[];
  final ink = <int>[];
  for (var index = 0; index < pixels.length; index += 4) {
    final x = index ~/ 4 % 300;
    final red = pixels[index];
    final green = pixels[index + 1];
    final blue = pixels[index + 2];
    if (green > 80 && green > red + 20 && green > blue + 20) {
      border.add(x);
    }
    if (blue > 80 && blue > red + 20 && blue > green + 20) {
      ink.add(x);
    }
  }
  expect(border, isNotEmpty);
  expect(ink, isNotEmpty, reason: '文字须完整绘制，不能靠裁剪掩盖越界');
  border.sort();
  ink.sort();
  expect(ink.first, greaterThanOrEqualTo(border.first + 7));
  expect(ink.last, lessThanOrEqualTo(border.last - 7));
}

Future<PageContent> _shortGradePage(String align, String whiteSpace) async {
  final source = await openCssChapter(
    body: '<table><tr><td><span class="tag">SSS</span></td></tr></table>',
    css:
        'body { margin: 0; font-family: builtin_song; font-size: 20px; } '
        'table { width: 100%; table-layout: fixed; border-collapse: collapse; } '
        'td { padding: 0; border: none; text-align: $align; '
        'text-align-last: $align; white-space: $whiteSpace; } '
        '.tag { display: inline-block; font-size: .7em; padding: 1px 6px; '
        'border: 1px solid #00ff00; background: #ff0000; color: #0000ff; }',
    contentWidth: 300,
    contentHeight: 160,
  );
  return (await source.loadChapter(0)).single;
}

PageBlock _expectContentFits(InlineBoxPlacement tag) {
  final payload = tag.spec.payload! as PageBlock;
  final style = payload.style!;
  final contentWidth =
      tag.width -
      style.padding.horizontal -
      style.borders.left.width -
      style.borders.right.width;
  expect(payload.layout.maxWidth, closeTo(contentWidth, .01));
  for (final line in payload.layout.lines) {
    expect(line.offsetX, greaterThanOrEqualTo(-.01));
    expect(line.offsetX + line.width, lessThanOrEqualTo(contentWidth + .01));
  }
  return payload;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await (FontLoader('builtin_song')..addFont(
          rootBundle.load('assets/fonts/SourceHanSerifCN-Regular.otf'),
        ))
        .load();
  });

  for (final align in ['left', 'center', 'right']) {
    for (final whiteSpace in ['normal', 'nowrap']) {
      test('短评级行内块：$align / $whiteSpace 的文字与边框共用内容宽', () async {
        final page = await _shortGradePage(align, whiteSpace);
        final cell = page.slices.single.block.table!.cells.single;
        final tag = cell.layout.lines.single.inlineBoxes.single;
        final payload = _expectContentFits(tag);
        expect(payload.layout.text, 'SSS');
        final cache = ParagraphCache();
        addTearDown(cache.dispose);
        final pixels = await _paint(page, null);
        _expectInkInside(pixels);
        for (var pass = 0; pass < 2; pass++) {
          expect(await _paint(page, cache), orderedEquals(pixels));
        }
      });
    }
  }

  final book = File('../../test_corpus/real/zhushen-yuxi.epub');
  for (final size in [17.0, 22.0]) {
    test('诸神愚戏道具：${size}px 下 SSS 评级完整留在标签内容区', () async {
      final source = await EpubChapterSource.open(
        book.readAsBytesSync(),
        contentWidth: 344,
        contentHeight: 772,
        verifyCrc: false,
      );
      await source.applyOverrides(
        ReaderSettingsDefaults.overrides.copyWith(fontSize: size),
      );
      final blocks = <PageBlock>{
        for (final page in await source.loadChapter(32))
          for (final slice in page.slices) slice.block,
      };
      var grades = 0;
      for (final block in blocks.where((block) => block.table != null)) {
        for (final cell in block.table!.cells) {
          for (final tag in cell.layout.lines.expand(
            (line) => line.inlineBoxes,
          )) {
            final payload = _expectContentFits(tag);
            if (payload.layout.text != 'SSS') continue;
            expect(payload.style!.padding.right, 6);
            grades++;
          }
        }
      }
      expect(grades, greaterThanOrEqualTo(3));
    }, skip: !book.existsSync());
  }
}
