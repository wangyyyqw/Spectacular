import 'package:flutter_test/flutter_test.dart';

import 'support/css_chapter_book.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('共享主体候选仍按属性、祖先和分组选项匹配', () async {
    final source = await openCssChapter(
      body:
          '<section class="card">'
          '<p class="note" data-tone="cold">第一</p>'
          '<p class="note" data-tone="warm">第二</p></section>'
          '<p class="note" data-tone="warm"><span id="special">第三</span></p>',
      css:
          'p { color: black; } .missing, p.note { font-size: 18px; } '
          'p.note[data-tone="cold"] { color: blue; } '
          'p.note[data-tone="warm"] { color: red; } '
          '.card > p.note[data-tone="warm"] { font-weight: bold; } '
          '.missing, #special { font-style: italic; }',
    );
    for (var pass = 0; pass < 2; pass++) {
      final blocks = (await source.loadChapter(0))
          .expand((page) => page.slices)
          .map((slice) => slice.block)
          .toList();
      expect(blocks, hasLength(3));
      expect(blocks.map((block) => block.style!.fontSize), everyElement(18));
      expect(blocks.first.style!.color.toARGB32(), 0xff0000ff);
      expect(blocks[1].style!.color.toARGB32(), 0xffff0000);
      expect(blocks[1].style!.fontWeight, 700);
      expect(blocks.last.style!.fontWeight, 400);
      expect(blocks.last.layout.runs.single.style.italic, isTrue);
      source.clearPaginationCache();
    }
  });

  test('辅助规则复用保留计数器内联覆盖与前后生成内容', () async {
    final source = await openCssChapter(
      body:
          '<p class="item" data-tail="！" style="counter-increment: item 2">正文一</p>'
          '<p class="item" data-tail="？">正文二</p>',
      css:
          'p.item { counter-increment: item; color: red; } '
          '.missing::before, p.item::before { content: counter(item) ". "; } '
          'p.item::after { content: attr(data-tail); }',
    );
    final texts = (await source.loadChapter(0))
        .expand((page) => page.slices)
        .map((slice) => slice.block.layout.text);
    expect(texts, ['2. 正文一！', '3. 正文二？']);
  });
}
