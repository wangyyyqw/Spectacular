import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/footnote.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';

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

  test('QQ/微信读书图片注号从 alt 生成弹窗数据', () async {
    final source = await openCssChapter(
      body: '''
<p class="icon"><img class="qqreader-footnote" alt="QQ 阅读图片注正文"
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
    expect(footnotes.single.text, 'QQ 阅读图片注正文');
  });

  test('综合注释测试书隐藏定义并生成各渠道弹窗数据', () async {
    final file = File('../../test_corpus/footnote-formats.epub');
    final source = await EpubChapterSource.open(
      file.readAsBytesSync(),
      contentWidth: 300,
      contentHeight: 900,
      verifyCrc: false,
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
    expect(pageText, contains('01 EPUB3 noteref 脚注'));
    expect(pageText, isNot(contains('EPUB3 标准脚注第一段')));
    expect(pageText, isNot(contains('多看文字注第一段')));
    expect(pageText, isNot(contains('Reeden 与多看双类名组合注文')));
    expect(footnotes, hasLength(22));
    expect(
      footnotes.map((note) => note.text).whereType<String>(),
      containsAll(<String>[
        'EPUB2 上标数字链接命中的普通段落注释。',
        'DPUB-ARIA 脚注正文。',
        '这是写在 title 属性里的旧式弹注正文。',
        '这是多看图片注，注文放在 alt 属性中。',
        '这是 QQ 阅读或微信读书图片注，注文放在 alt 属性中。',
        '这是掌阅通用弹注法，正文来自 zy-footnote 属性。',
        'WR 直接文本兼容结构。',
        '这是 js_readerFooterNote 直接文本兼容写法。',
        '这是 data-reeden-footnote-body 直接注文。',
      ]),
    );
    expect(
      footnotes
          .expand((note) => note.imageUrls)
          .where((url) => url.endsWith('note-card.png')),
      isNotEmpty,
    );
  });

  test('跨文档注释定义页只显示说明，不显示任何注文定义', () async {
    final file = File('../../test_corpus/footnote-formats.epub');
    final source = await EpubChapterSource.open(
      file.readAsBytesSync(),
      contentWidth: 300,
      contentHeight: 900,
      verifyCrc: false,
    );
    addTearDown(source.close);

    final pages = await source.loadChapter(1);
    final pageText = pages
        .expand((page) => page.slices)
        .map((slice) => slice.block.layout.text)
        .join('\n');
    expect(pageText, contains('正常阅读只应看到本说明'));
    expect(pageText, isNot(contains('跨 XHTML 标准尾注正文')));
    expect(pageText, isNot(contains('EPUB3 rearnote 尾注正文')));
    expect(pageText, isNot(contains('掌阅 zy-footnote 的真实定义目标')));
    expect(pageText, isNot(contains('21 回链兜底注文')));
  });
}
