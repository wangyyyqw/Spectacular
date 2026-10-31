import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';

import 'support/css_chapter_book.dart';
import '../support/test_epub.dart';

void main() {
  test('页缓存按章 LRU：超过上限淘汰最久未用的章（P4-32，§44.4）', () async {
    // 造一本 10 章的书（每章内容不同，确保缓存 key 不同）。
    final paragraphs = <String>[
      for (var i = 0; i < 10; i++)
        '第 $i 章正文内容'
                '，' *
            20,
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
    expect(
      source.cacheReport,
      contains('块缓存 ${EpubChapterSource.blockCacheChapterLimit}/'),
      reason: 'styles 层块缓存与页缓存同上限',
    );
    expect(
      source.cacheReport,
      contains('文档缓存 ${EpubChapterSource.documentCacheChapterLimit}/'),
      reason: 'document 层聚合树/选择器视图不随长书无界增长',
    );
    expect(
      source.cacheReport,
      contains('样式章索引 ${EpubChapterSource.chapterIndexCacheLimit}/'),
      reason: '章节样式来源索引同样受章节窗口约束',
    );
    expect(
      source.cacheReport,
      contains('满屏索引 ${EpubChapterSource.chapterIndexCacheLimit}/'),
      reason: '满屏分析结果不随长书无界增长',
    );
    final whiteSpaceCached = int.parse(
      RegExp(r'空白索引 (\d+)/').firstMatch(source.cacheReport)!.group(1)!,
    );
    expect(
      whiteSpaceCached,
      lessThanOrEqualTo(EpubChapterSource.chapterIndexCacheLimit),
      reason: 'white-space 判定不随长书无界增长',
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

  test('整页背景与块缓存同生命周期，清页缓存后重放仍保留', () async {
    final source = await openCssChapter(
      body: '<p>带背景的正文</p>',
      css:
          'body { background-image: url("../Images/bg.png"); '
          'background-repeat: no-repeat; background-size: cover; }',
    );

    final first = await source.loadChapter(0);
    expect(first.first.background, isNotNull);

    source.clearPaginationCache();
    final replayed = await source.loadChapter(0);
    expect(replayed.first.background, isNotNull);

    final pageCached = await source.loadChapter(0);
    expect(pageCached.first.background, isNotNull);
  });
}
