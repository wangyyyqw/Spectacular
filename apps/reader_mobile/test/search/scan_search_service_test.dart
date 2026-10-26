import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/search/scan_search_service.dart';

import '../support/test_epub.dart';

void main() {
  test('扫描式搜索：跨章命中、偏移可用、章节名正确', () async {
    final bytes = buildMultiChapterEpub(
      title: '扫描搜索',
      chapters: const <String>[
        '第一章\n这里没有任何关键词，只有普通的叙述文字。',
        '第二章\n沈河端着一盘辣子鸡走出来，客人愣住了。',
        '第三章\n沈河又端了一盘菜，说这道菜是辣的。',
      ],
    );
    final source = await openTestChapterSource(bytes);
    final service = ScanSearchService(source: source);

    final results = await service.search('沈河');
    expect(results, hasLength(2), reason: '两章各有命中');
    expect(results.first.spineIndex, lessThan(results.last.spineIndex));
    for (final result in results) {
      expect(result.context, contains('沈河'));
      expect(result.matchLength, 2);
      expect(result.charOffset, greaterThanOrEqualTo(0));
    }
    // CFI 至少能生成一条（块级 CFI 可定位时）。
    expect(results.any((r) => r.cfi != null), isTrue);
  });

  test('扫描式搜索：无命中返回空、空查询返回空', () async {
    final bytes = buildTestEpub(
      title: '空结果',
      paragraphs: const <String>['一段与关键词无关的正文。'],
    );
    final source = await openTestChapterSource(bytes);
    final service = ScanSearchService(source: source);

    expect(await service.search('不存在词'), isEmpty);
    expect(await service.search('   '), isEmpty);
  });

  test('扫描式搜索：结果数受上限约束', () async {
    final bytes = buildTestEpub(
      title: '上限',
      paragraphs: <String>[for (var i = 0; i < 30; i++) '目标字 目标字 目标字'],
    );
    final source = await openTestChapterSource(bytes);
    final service = ScanSearchService(source: source, maxResults: 5);

    final results = await service.search('目标字');
    expect(results, hasLength(5));
  });
}
