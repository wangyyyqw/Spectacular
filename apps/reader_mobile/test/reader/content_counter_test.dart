import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';

import 'support/css_chapter_book.dart';

/// W20 生成内容：`content` 的字符串/attr()/counter()/open-quote/url() 组合。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<List<String>> texts(String body, String css) async {
    final source = await EpubChapterSource.open(
      buildCssChapterBook(body: body, css: css),
      verifyCrc: false,
    );
    final pages = await source.loadChapter(0);
    return pages
        .expand((page) => page.slices)
        .map((slice) => slice.block.layout.text)
        .where((text) => text.isNotEmpty)
        .toList();
  }

  test('::before content 字符串与 attr()', () async {
    final out = await texts(
      '<p class="t" data-x="标签">正文</p>',
      '.t::before { content: "【" attr(data-x) "】"; }',
    );
    expect(out.any((t) => t.contains('【标签】正文')), isTrue, reason: '$out');
  });

  test('::before/::after content 使用伪元素自身样式', () async {
    final source = await EpubChapterSource.open(
      buildCssChapterBook(
        body: '<p class="t">正文</p>',
        css:
            '.t::before { content: "前言"; color: #cc0000; } '
            '.t::after { content: "后记"; color: #0066cc; font-weight: bold; }',
      ),
      verifyCrc: false,
    );
    final page = (await source.loadChapter(0)).single;
    final layout = page.slices.single.block.layout;

    expect(layout.text, '前言正文后记');
    final prefix = layout.runs.singleWhere((run) => run.start == 0);
    final suffix = layout.runs.singleWhere(
      (run) => run.start == layout.text.length - 2,
    );
    expect(prefix.end, 2);
    expect(prefix.style.color, const Color(0xFFCC0000));
    expect(suffix.end, layout.text.length);
    expect(suffix.style.color, const Color(0xFF0066CC));
    expect(suffix.style.fontWeight, 700);
  });

  test('counter()/counters() 自动编号', () async {
    final out = await texts(
      '<ol class="c"><li>第一</li><li>第二</li></ol>',
      '.c { counter-reset: item; } '
          '.c > li::before { counter-increment: item; content: counter(item) ". "; }',
    );
    expect(out.any((t) => t.contains('1. 第一')), isTrue, reason: '$out');
    expect(out.any((t) => t.contains('2. 第二')), isTrue, reason: '$out');
  });

  test('同一伪元素的多条规则按级联覆盖 content 和 counter-*', () async {
    final out = await texts(
      '<div class="scope"><p class="item">第一章</p>'
          '<p class="item">第二章</p>'
          '<p class="item sub">小节</p>'
          '<p class="item">第三章</p></div>',
      '.scope { counter-reset: item; } '
          '.item::before { counter-increment: item; '
          'content: counter(item) ". "; } '
          '.sub::before { counter-increment: step; '
          'content: "[" counter(step) "] "; }',
    );
    expect(out.any((t) => t.contains('1. 第一章')), isTrue, reason: '$out');
    expect(out.any((t) => t.contains('2. 第二章')), isTrue, reason: '$out');
    expect(out.any((t) => t.contains('[1] 小节')), isTrue, reason: '$out');
    expect(out.any((t) => t.contains('3. 第三章')), isTrue, reason: '$out');
  });

  test('open-quote/close-quote 按 quotes 生成引号', () async {
    final out = await texts(
      '<p class="q">引用</p>',
      '.q { quotes: "«" "»"; } '
          '.q::before { content: open-quote; } '
          '.q::after { content: close-quote; }',
    );
    expect(out.any((t) => t.contains('«引用»')), isTrue, reason: '$out');
  });

  test('content: url() 生成行内图片占位并使用相对资源路径', () async {
    final source = await EpubChapterSource.open(
      buildCssChapterBook(
        body: '<p class="t">正文</p>',
        css:
            '.t::before { content: "【" url("../Images/icon.png") "】"; } '
            '.t::after { content: url("../Images/tail.png"); '
            'width: 12px; height: 18px; }',
        binaryFiles: const <String, List<int>>{
          'OEBPS/Images/icon.png': <int>[137, 80, 78, 71],
          'OEBPS/Images/tail.png': <int>[137, 80, 78, 71],
        },
      ),
      verifyCrc: false,
    );
    final block = (await source.loadChapter(0))
        .expand((page) => page.slices.map((slice) => slice.block))
        .first;

    expect(block.layout.text, '【\uFFFC】正文\uFFFC');
    expect(block.inlineImages.map((image) => image.url), <String>[
      'OEBPS/Images/icon.png',
      'OEBPS/Images/tail.png',
    ]);
    expect(block.inlineImages.map((image) => image.offset), <int>[
      1,
      block.layout.text.length - 1,
    ]);
    expect(block.inlineImages.last.width, 12);
    expect(block.inlineImages.last.height, 18);
  });
}
