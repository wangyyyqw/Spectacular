import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';

import 'support/css_chapter_book.dart';

/// W20 生成内容：`content` 的字符串/attr()/counter()/open-quote 组合。
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

  test('counter()/counters() 自动编号', () async {
    final out = await texts(
      '<ol class="c"><li>第一</li><li>第二</li></ol>',
      '.c { counter-reset: item; } '
      '.c > li::before { counter-increment: item; content: counter(item) ". "; }',
    );
    expect(out.any((t) => t.contains('1. 第一')), isTrue, reason: '$out');
    expect(out.any((t) => t.contains('2. 第二')), isTrue, reason: '$out');
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
}
