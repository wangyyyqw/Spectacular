import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/api.dart' show ReaderTextOverlay;
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/position/cfi.dart';

import 'support/css_chapter_book.dart';

PageBlock _firstTextBlock(List<PageContent> pages) => pages
    .expand((page) => page.slices)
    .firstWhere((slice) => slice.block.layout.text.isNotEmpty)
    .block;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('选区字号进入作者 run 并重排，颜色变化复用同一布局', () async {
    final text = '甲乙丙丁戊己庚辛壬癸' * 20;
    final source = await openCssChapter(
      body: '<p>$text</p>',
      css: 'body { margin: 0; font-size: 16px; } p { margin: 0; line-height: 1.5; }',
      contentWidth: 160,
      contentHeight: 130,
    );
    final originalPages = await source.loadChapter(0);
    final original = _firstTextBlock(originalPages);
    final start = cfiWithCharOffset(original.startCfi!, 10);
    final end = cfiWithCharOffset(original.startCfi!, 170);
    expect(
      await source.applyTextOverlays([
        ReaderTextOverlay(startCfi: start, endCfi: end, color: 0xffff0000),
      ]),
      isFalse,
    );
    expect(
      _firstTextBlock(await source.loadChapter(0)).layout,
      same(original.layout),
    );
    expect(
      await source.applyTextOverlays([
        ReaderTextOverlay(
          startCfi: start,
          endCfi: end,
          fontSizeScale: 2,
          fontWeight: 700,
          italic: true,
          letterSpacingEm: 0.1,
        ),
      ]),
      isTrue,
    );
    final enlargedPages = await source.loadChapter(0);
    final enlarged = _firstTextBlock(enlargedPages);
    final decorated = enlarged.layout.runs.firstWhere((run) => run.start == 10);
    expect(decorated.end, 170);
    expect(decorated.style.fontSize, 32);
    expect(decorated.style.fontWeight, 700);
    expect(decorated.style.italic, isTrue);
    expect(decorated.style.letterSpacing, closeTo(3.2, 0.001));
    expect(enlarged.layout.text, original.layout.text);
    expect(enlargedPages.length, greaterThan(originalPages.length));
    expect(
      await source.applyTextOverlays([
        ReaderTextOverlay(
          startCfi: start,
          endCfi: end,
          fontSizeScale: 2,
          fontWeight: 700,
          italic: true,
          letterSpacingEm: 0.1,
          color: 0xff0000ff,
        ),
      ]),
      isFalse,
    );
    expect(
      _firstTextBlock(await source.loadChapter(0)).layout,
      same(enlarged.layout),
    );
    expect(await source.applyTextOverlays(const []), isTrue);
    final restored = _firstTextBlock(await source.loadChapter(0)).layout;
    expect(
      restored.lines,
      same(original.layout.lines),
      reason: '缓存复用几何，当前样式区间重新绑定',
    );
    expect(restored.runs.first.style.fontSize, 16);
    expect(
      restored.runs.first.style.color,
      original.layout.runs.first.style.color,
    );
  });

  test('选区字体覆盖保留作者行内背景与边框', () async {
    final source = await openCssChapter(
      body: '<p>甲<span style="background-color:#ffeecc;border:1px dashed #008000;padding:2px">乙丙</span>丁</p>',
      css: 'body { margin:0; font-size:16px; } p { margin:0; }',
    );
    final original = _firstTextBlock(await source.loadChapter(0));
    final author = original.layout.runs.firstWhere((run) => run.start == 1);
    await source.applyTextOverlays([
      ReaderTextOverlay(
        startCfi: cfiWithCharOffset(original.startCfi!, 1),
        endCfi: cfiWithCharOffset(original.startCfi!, 3),
        fontSizeScale: 1.5,
        fontFamily: '测试字体',
      ),
    ]);
    final result = _firstTextBlock(await source.loadChapter(0)).layout.runs
        .firstWhere((run) => run.start == 1);
    expect(result.style.fontFamily, '测试字体');
    expect(result.style.fontSize, 24);
    expect(result.style.backgroundColor, author.style.backgroundColor);
    expect(result.style.borders.top.width, author.style.borders.top.width);
    expect(result.style.borders.top.color, author.style.borders.top.color);
    expect(result.style.padding.top, author.style.padding.top);
  });

  test('正文和标题可匹配，页眉页脚标记不可匹配，脚注定义已过滤', () async {
    final source = await openCssChapter(
      body: '<header><p>页眉内容</p></header><h1>章节标题</h1><p>正文内容</p><footer><p>页脚内容</p></footer><aside role="doc-footnote">脚注正文</aside>',
      css: 'body { margin:0; } p,h1 { margin:0; }',
    );
    final blocks = (await source.loadChapter(0))
        .expand((page) => page.slices)
        .map((slice) => slice.block)
        .toSet();
    PageBlock containing(String text) =>
        blocks.firstWhere((block) => block.layout.text.contains(text));
    expect(containing('页眉内容').textRuleEligible, isFalse);
    expect(containing('页脚内容').textRuleEligible, isFalse);
    expect(containing('章节标题').textRuleEligible, isTrue);
    expect(containing('正文内容').textRuleEligible, isTrue);
    expect(blocks.any((block) => block.layout.text.contains('脚注正文')), isFalse);
  });
}
