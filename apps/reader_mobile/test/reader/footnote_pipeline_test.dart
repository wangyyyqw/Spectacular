import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/footnote.dart';

import 'support/css_chapter_book.dart';

void main() {
  test('注释定义不进入正文页面，注号映射为可点击数据', () async {
    final source = await openCssChapter(
      body: '''
<p>正文一<sup><a href="#fn1" role="doc-noteref">[1]</a></sup></p>
<p>正文二<a href="#en1" role="doc-noteref">[2]</a></p>
<aside id="fn1" role="doc-footnote">
  <p>脚注正文第一段</p><p>脚注正文第二段</p>
</aside>
<section role="doc-endnotes">
  <h2>尾注标题</h2>
  <ol><li id="en1" role="doc-endnote">尾注正文</li></ol>
</section>
''',
      contentHeight: 600,
    );
    addTearDown(source.close);

    final pages = await source.loadChapter(0);
    final blocks = pages
        .expand((page) => page.slices)
        .map((slice) => slice.block)
        .toList(growable: false);
    final pageText = blocks.map((block) => block.layout.text).join('\n');
    final footnotes = blocks
        .expand((block) => block.footnotes)
        .toList(growable: false);

    expect(pageText, contains('正文一'));
    expect(pageText, contains('正文二'));
    expect(pageText, isNot(contains('脚注正文')));
    expect(pageText, isNot(contains('尾注正文')));
    expect(pageText, isNot(contains('尾注标题')));
    expect(footnotes, hasLength(2));
    expect(footnotes[0].kind, NoteKind.footnote);
    expect(footnotes[0].text, '脚注正文第一段\n脚注正文第二段');
    expect(footnotes[1].kind, NoteKind.endnote);
    expect(footnotes[1].text, '尾注正文');
  });

  test('普通数字内链不生成注释点击区', () async {
    final source = await openCssChapter(
      body: '''
<p><a href="#chapter-1">1</a></p>
<section id="chapter-1"><p>第一章正文</p></section>
''',
    );
    addTearDown(source.close);

    final pages = await source.loadChapter(0);
    final blocks = pages
        .expand((page) => page.slices)
        .map((slice) => slice.block)
        .toList(growable: false);
    final footnotes = blocks.expand((block) => block.footnotes);
    expect(footnotes, isEmpty);
    expect(blocks.map((block) => block.layout.text), contains('第一章正文'));
  });

  test('目标 id 位于无 id 列表项时隐藏整条注释定义', () async {
    final source = await openCssChapter(
      body: '''
<p>正文<a epub:type="noteref" href="#fn-inner">[1]</a></p>
<ol><li><a id="fn-inner"></a>无 id 容器注释</li></ol>
''',
    );
    addTearDown(source.close);

    final pages = await source.loadChapter(0);
    final blocks = pages
        .expand((page) => page.slices)
        .map((slice) => slice.block)
        .toList(growable: false);
    expect(
      blocks.map((block) => block.layout.text),
      isNot(contains('无 id 容器注释')),
    );
    expect(
      blocks.expand((block) => block.footnotes).single.text,
      '无 id 容器注释',
    );
  });

  test('独立图片注号仍生成可点击注释区域', () async {
    final source = await openCssChapter(
      body: '''
<p class="icon"><img class="duokan-footnote" alt="图片注释"
  src="../Images/note.png" width="12" height="12"/></p>
''',
    );
    addTearDown(source.close);

    final pages = await source.loadChapter(0);
    final footnotes = pages
        .expand((page) => page.slices)
        .expand((slice) => slice.block.footnotes)
        .toList(growable: false);
    expect(footnotes, hasLength(1));
    expect(footnotes.single.text, '图片注释');
  });
}
