import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/position/cfi.dart';
import 'package:reader_core/position/location_anchor.dart';

import 'support/css_chapter_book.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('正文索引与实际绘制文本和CFI一致，保留作者空白及补充平面字符', () async {
    final source = await openCssChapter(
      body:
          '<p>普通 a  b<span>𠮷😀</span>尾部</p>'
          '<p class="preserve">保留 a  b\nc  d</p><pre>预格式 a  b\nc</pre>'
          '<p class="hidden">隐藏内容</p>'
          '<p>可见<span style="display:none">不出现</span>尾句</p>',
      css: '.preserve { white-space: pre-wrap; } .hidden { display:none; }',
    );
    addTearDown(source.close);
    final chapter = source.anchorChapter(0);
    final book = AnchorBook(revision: 'test', chapters: [chapter]);
    final blocks = (await source.loadChapter(0))
        .expand((page) => page.slices)
        .map((slice) => slice.block)
        .where((block) => block.startCfi != null);
    for (final block in blocks) {
      final indexed = chapter.blocks.where(
        (candidate) => cfiBase(candidate.cfi) == cfiBase(block.startCfi!),
      );
      expect(indexed, isNotEmpty, reason: block.layout.text);
      expect(indexed.first.text, block.layout.text);
      final text = block.layout.text;
      if (text.isEmpty) continue;
      final start = cfiWithCharOffset(block.startCfi!, 0);
      final end = cfiWithCharOffset(block.startCfi!, text.length);
      expect(book.capture(start, endCfi: end)?.quote, text);
    }
    expect(chapter.text, contains('保留 a  b\nc  d'));
    expect(chapter.text, contains('𠮷😀'));
    expect(chapter.text, isNot(contains('隐藏内容')));
    expect(chapter.text, isNot(contains('不出现')));
  });

  test('表格单元格索引使用实际绘制文本', () async {
    final source = await openCssChapter(
      body:
          '<table><caption>标题</caption>'
          '<tr><td><p>第一段 文字</p><p>第二段𠮷😀</p></td><td>另一格</td></tr></table>',
    );
    addTearDown(source.close);
    final chapter = source.anchorChapter(0);
    final cells = (await source.loadChapter(0))
        .expand((page) => page.slices)
        .where((slice) => slice.block.table != null)
        .expand((slice) => slice.block.table!.cells)
        .toList();
    expect(cells, isNotEmpty);
    for (final cell in cells) {
      expect(
        chapter.blocks.map((block) => block.text),
        contains(cell.layout.text),
      );
    }
    expect(chapter.text, contains('第一段 文字\n第二段𠮷😀'));
  });
}
