import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/search/chapter_text.dart';

import '../reader/support/css_chapter_book.dart';

void main() {
  test('空章节没有可定位的文本块', () {
    final chapter = ChapterText.fromPages(const []);
    expect(chapter.text, isEmpty);
    for (final offset in [-1, 0, 1]) {
      expect(chapter.blockAt(offset), isNull);
      expect(chapter.locate(offset), isNull);
    }
  });

  test('按字符定位保留跨页去重、UTF-16 偏移和块间换行边界', () async {
    final last = '跨页正文' * 100;
    final texts = ['甲🙂乙', '丙丁', last];
    final source = await openCssChapter(
      body: '<p>${texts[0]}</p><p></p><p>${texts[1]}</p><p>$last</p>',
      css: 'body,p{margin:0;padding:0;}p{font-size:16px;line-height:1.5;}',
      contentWidth: 200,
      contentHeight: 100,
    );
    addTearDown(source.close);
    final pages = await source.loadChapter(0);
    expect(pages.length, greaterThan(1));
    final chapter = ChapterText.fromPages(pages);
    expect(chapter.text, texts.join('\n'));
    expect(chapter.blocks, hasLength(3), reason: '跨页块只进入索引一次');
    var start = 0;
    for (var i = 0; i < texts.length; i++) {
      final block = chapter.blocks[i];
      expect(block.start, start);
      for (var offset = 0; offset < texts[i].length; offset++) {
        expect(chapter.blockAt(start + offset), same(block));
        expect(chapter.locate(start + offset)?.localOffset, offset);
      }
      start += texts[i].length;
      expect(chapter.blockAt(start), isNull, reason: '换行和章末不归入前一块');
      start++;
    }
    expect(chapter.locate(-1), isNull);
    expect(chapter.locate(chapter.text.length + 1), isNull);
  });
}
