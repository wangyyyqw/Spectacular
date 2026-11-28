import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/page_renderer.dart';
import 'package:reader_core/paint/paragraph_cache.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_ui/panels/settings_panel.dart';

import 'support/css_chapter_book.dart';

const _width = 360;
const _height = 260;
// 提高采样倍率，避免亚像素位置的 1px 边框没有完整着色像素。
const _scale = 3;

Future<Uint8List> _paint(PageContent page, ParagraphCache? cache) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(_scale.toDouble());
  PagePainter(paragraphCache: cache)
      .paint(canvas, page, pageSize: const Size(360, 260));
  final picture = recorder.endRecording();
  final image = await picture.toImage(_width * _scale, _height * _scale);
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!.buffer.asUint8List();
}

Rect _colorBounds(Uint8List pixels, int rgb) {
  var left = _width * _scale;
  var right = -1;
  var top = _height * _scale;
  var bottom = -1;
  for (var index = 0; index < pixels.length; index += 4) {
    final color =
        pixels[index] << 16 | pixels[index + 1] << 8 | pixels[index + 2];
    if (color != rgb || pixels[index + 3] != 255) continue;
    final x = index ~/ 4 % (_width * _scale);
    final y = index ~/ 4 ~/ (_width * _scale);
    if (x < left) left = x;
    if (x > right) right = x;
    if (y < top) top = y;
    if (y > bottom) bottom = y;
  }
  expect(right, greaterThanOrEqualTo(left), reason: '目标颜色必须完整绘制');
  return Rect.fromLTRB(
    left / _scale,
    top / _scale,
    (right + 1) / _scale,
    (bottom + 1) / _scale,
  );
}

Future<PageContent> _tagPage(String container, String align) async {
  const tags =
      '<span class="tag first">A</span>'
      '<span class="tag second">B</span>';
  final body = switch (container) {
    '表格' => '<table><tr><td>$tags</td></tr></table>',
    '嵌套' => '<p><span class="outer">$tags</span></p>',
    _ => '<p>$tags</p>',
  };
  final source = await openCssChapter(
    body: body,
    css:
        'body { margin: 0; font-family: Ahem; font-size: 20px; line-height: 2; } '
        'p { margin: 0; } td { padding: 0; border: none; } '
        '.outer { display: inline-block; padding: 5px; } '
        '.tag { display: inline-block; font-size: 16px; line-height: 2; '
        'padding: 2px; border: 1px solid #00ff00; vertical-align: $align; } '
        '.first { margin: 9px 4px 9px 0; color: #ff0000; } '
        '.second { margin: 2px 0 2px; color: #0000ff; }',
    contentWidth: _width.toDouble(),
    contentHeight: _height.toDouble(),
  );
  return (await source.loadChapter(0)).single;
}

Future<void> _expectAlignedInk(PageContent page) async {
  final pixels = await _paint(page, null);
  final first = _colorBounds(pixels, 0xff0000);
  final second = _colorBounds(pixels, 0x0000ff);
  expect(first.top, second.top, reason: '上外边距不同不能使文字错开');
  expect(first.bottom, second.bottom);
  final cache = ParagraphCache();
  addTearDown(cache.dispose);
  for (var pass = 0; pass < 2; pass++) {
    expect(await _paint(page, cache), orderedEquals(pixels));
  }
}

Future<void> _expectServantTags(EpubChapterSource source, double size) async {
  await source.applyOverrides(
    ReaderSettingsDefaults.overrides.copyWith(fontSize: size),
  );
  await source.applyContentSize(width: 344, height: 772);
  final blocks = <PageBlock>{
    for (final page in await source.loadChapter(37))
      for (final slice in page.slices) slice.block,
  };
  for (final path in ['腐朽', '污堕']) {
    final text = '沉沦命途·【$path】令使';
    final block = blocks.firstWhere(
      (block) => block.layout.lines
          .expand((line) => line.inlineBoxes)
          .map((tag) => tag.spec.payload)
          .whereType<PageBlock>()
          .any((block) => block.layout.text == text),
    );
    await _expectServantRow(block, size, text);
  }
}

Future<void> _expectServantRow(
  PageBlock block,
  double size,
  String text,
) async {
  final tags = block.layout.lines
      .expand((line) => line.inlineBoxes)
      .where((box) => box.spec.payload is PageBlock)
      .toList();
  expect(tags, hasLength(2));
  if (size == 17) {
    expect(block.layout.lines, hasLength(1), reason: '默认字号复现手机同排标签');
  }
  final page = Paginator(pageHeight: _height.toDouble())
      .measureChapter(
        blocks: [PageBlock(layout: block.layout, style: block.style)],
      )
      .pages
      .single;
  final pixels = await _paint(page, null);
  for (var index = 0; index < 2; index++) {
    final tag = tags[index];
    final line = block.layout.lines.firstWhere(
      (line) => line.inlineBoxes.contains(tag),
    );
    final payload = tag.spec.payload! as PageBlock;
    expect(payload.layout.text, index == 0 ? text : '生命命途·【繁荣】前令使');
    expect(payload.layout.lineCount, 1);
    expect(
      payload.style!.fontSize,
      closeTo(size * (index == 0 ? .65 : .7), .01),
    );
    expect(tag.spec.marginTop, closeTo(index == 0 ? size * .65 * .5 : 2, .01));
    final border = _colorBounds(pixels, index == 0 ? 0x4a3860 : 0x7e3b41);
    final expectedTop = line.baseline - tag.spec.contentBaseline!;
    expect(
      border.top,
      closeTo(expectedTop, 1),
      reason: '边框原点须从 margin 盒移到 border 盒',
    );
    expect(border.bottom, closeTo(expectedTop + tag.height, 1));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final container in ['段落', '表格', '嵌套']) {
    for (final align in ['baseline', 'middle']) {
      test('$container：$align 对齐的不同外边距标签文字不发生竖直偏移', () async {
        await _expectAlignedInk(await _tagPage(container, align));
      });
    }
  }

  test('负上外边距仍以内容基线绘制，而不是当作额外文字位移', () async {
    final source = await openCssChapter(
      body: '<p><span class="first">A</span><span class="second">B</span></p>',
      css:
          'p { margin: 0; font-family: Ahem; font-size: 20px; line-height: 3; } '
          'span { display: inline-block; font-size: 16px; line-height: 2; } '
          '.first { margin-top: 5px; color: #ff0000; } '
          '.second { margin-top: -3px; color: #0000ff; }',
    );
    await _expectAlignedInk((await source.loadChapter(0)).single);
  });

  final book = File('../../test_corpus/real/zhushen-yuxi.epub');
  for (final size in [17.0, 22.0]) {
    test('诸神愚戏从神：${size}px 下现任与前任令使标签按实际内容基线绘制', () async {
      final source = await EpubChapterSource.open(
        book.readAsBytesSync(),
        contentWidth: 344,
        contentHeight: 772,
        verifyCrc: false,
      );
      await _expectServantTags(source, size);
    }, skip: !book.existsSync());
  }
}
