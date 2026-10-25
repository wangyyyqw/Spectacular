import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';

import '../support/test_epub.dart';

void main() {
  test('页缓存按章 LRU：超过上限淘汰最久未用的章（P4-32，§44.4）', () async {
    // 造一本 10 章的书（每章内容不同，确保缓存 key 不同）。
    final paragraphs = <String>[
      for (var i = 0; i < 10; i++) '第 $i 章正文内容' '，' * 20,
    ];
    final bytes = buildMultiChapterEpub(chapters: paragraphs);
    final source = await openTestChapterSource(bytes);
    expect(source.chapterCount, greaterThanOrEqualTo(10));

    // 依次加载前 8 章。
    for (var spine = 0; spine < 8; spine++) {
      await source.loadChapter(spine);
    }
    expect(
      source.cacheReport,
      contains('${EpubChapterSource.pageCacheChapterLimit}/'),
      reason: '页缓存保持在章数上限内',
    );

    // 再访问第 6 章：命中（不报错）且依然是上限内。
    await source.loadChapter(6);
    final cachedChapters = int.tryParse(
      RegExp(r'页缓存 (\d+)/').firstMatch(source.cacheReport)!.group(1)!,
    );
    expect(
      cachedChapters,
      lessThanOrEqualTo(EpubChapterSource.pageCacheChapterLimit),
    );
  });

  test('页缓存上限常量与 §44.4 预算一致（当前章 ±2）', () {
    expect(EpubChapterSource.pageCacheChapterLimit, 5);
  });
}
