import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';

import 'support/css_chapter_book.dart';

Future<List<PageBlock>> _blocks(EpubChapterSource source) async =>
    (await source.loadChapter(0))
        .expand((page) => page.slices)
        .map((slice) => slice.block)
        .toSet()
        .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('同形段落按源树匹配结构选择器，重排不改变 CFI', () async {
    final source = await openCssChapter(
      body: '<h2>标题</h2><p>第一段</p><p>第二段</p><p>第三段</p>',
      css:
          'h2,p { margin: 0; font-size: 16px; line-height: 28px; }'
          'p:nth-of-type(even) { font-size: 24px; padding-left: 18px; }'
          'p:nth-last-of-type(1) { padding-right: 10px; }',
    );
    final before = await _blocks(source);
    expect(before.map((block) => block.style!.fontSize), [16, 16, 24, 16]);
    expect(before[2].style!.padding.left, 18);
    expect(before[3].style!.padding.right, 10);
    final cfis = before.map((block) => block.startCfi).toList();
    expect(cfis, everyElement(isNotNull));
    source.clearPaginationCache();
    final replayed = await _blocks(source);
    expect(replayed.map((block) => block.style!.fontSize), [16, 16, 24, 16]);
    expect(replayed.map((block) => block.startCfi), cfis);
    await source.applyContentSize(width: 280, height: 450);
    final after = await _blocks(source);
    expect(after.map((block) => block.style!.fontSize), [16, 16, 24, 16]);
    expect(after.map((block) => block.startCfi), cfis);
  });

  test('结构选择器隐藏元素后，兄弟索引仍按原始 DOM 计数', () async {
    final source = await openCssChapter(
      body: '<p>第一段</p><p>隐藏段</p><p>第三段</p>',
      css:
          'p { margin: 0; font-size: 16px; }'
          'p:nth-child(2) { display: none; }'
          'p:nth-child(3) { font-size: 23px; }'
          'p + p { padding-left: 8px; }',
    );
    final blocks = await _blocks(source);
    expect(blocks.map((block) => block.layout.text), ['第一段', '第三段']);
    expect(blocks.last.style!.fontSize, 23);
    expect(blocks.last.style!.padding.left, 8);
  });

  test('否定选择器的属性匹配与 ID、类型特异性进入最终排版', () async {
    final source = await openCssChapter(
      body:
          '<p class="a b">第一段</p><p class="c d">第二段</p>'
          '<p class="e">第三段</p><p class="e" hidden="hidden">隐藏段</p>',
      css:
          'p { margin: 0; font-size: 16px; }'
          '.a:not(#excluded) { font-size: 24px; } .a.b { font-size: 12px; }'
          '.c.d { font-size: 20px; } .c:not(span) { font-size: 12px; }'
          '.e:not([hidden]) { padding-left: 10px; }',
    );
    final blocks = await _blocks(source);
    expect(blocks.map((block) => block.style!.fontSize), [24, 20, 16]);
    expect(blocks.last.style!.padding.left, 10);
  });

  test('否定参数或祖先依赖兄弟位置时，同形后代不能共享样式', () async {
    final source = await openCssChapter(
      body:
          '<section><p>第一段</p></section>'
          '<section><p>第二段</p></section>'
          '<section><p>第三段</p></section>',
      css:
          'p { margin: 0; font-size: 16px; }'
          'section:not(:nth-child(2)) p { font-size: 22px; }'
          'section + section p { padding-left: 8px; }',
    );
    for (var i = 0; i < 2; i++) {
      final blocks = await _blocks(source);
      expect(blocks.map((block) => block.style!.fontSize), [22, 16, 22]);
      expect(blocks.map((block) => block.style!.padding.left), [0, 8, 8]);
      source.clearPaginationCache();
    }
  });
}
