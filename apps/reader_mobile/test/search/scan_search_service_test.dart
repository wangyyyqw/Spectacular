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
    // 搜索阶段不算 CFI（避免为 200 条命中各排版一次），点开时才解析。
    expect(results.every((r) => r.cfi == null), isTrue);
    final cfi = await service.resolveCfi(results.first);
    expect(cfi, isNotNull, reason: '点开某条命中时才排版算 CFI');
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

  group('recenterOffset', () {
    test('偏移超出排版文本长度时不抛 RangeError', () {
      final text = '甲' * 2703;
      // 扫描偏移来自更长的纯文本，远超排版文本长度（真机 2918 vs 2703）。
      expect(() => recenterOffset(text, '关键词', 2918), returnsNormally);
      expect(recenterOffset(text, '关键词', 2918), -1);
    });

    test('偏移在范围内时校正到真实位置', () {
      final text = '${'甲' * 100}关键词${'乙' * 100}';
      expect(recenterOffset(text, '关键词', 90), 100);
    });

    test('偏移差超过窗口时退回全章查找', () {
      final text = '开头关键词${'乙' * 900}';
      // 扫描偏移比真实位置大 500 字，两侧各 200 的窗口覆盖不到。
      expect(recenterOffset(text, '关键词', 502), 2);
    });
  });

  test('流式搜索：逐章推送，搜到就出结果', () async {
    final bytes = buildMultiChapterEpub(
      title: '流式',
      chapters: const <String>[
        '第一章\n没有关键词。',
        '第二章\n沈河出现了。',
        '第三章\n沈河又出现了。',
      ],
    );
    final source = await openTestChapterSource(bytes);
    final service = ScanSearchService(source: source);

    final batches = <ScanProgress>[];
    await for (final progress in service.searchStream('沈河')) {
      batches.add(progress);
    }
    expect(batches.length, greaterThanOrEqualTo(2), reason: '至少推送两次（两章命中）');
    expect(batches.first.results, hasLength(1), reason: '第一批只有第二章的命中');
    expect(batches.last.results, hasLength(2), reason: '最后一批累积两条');
    expect(batches.last.scanned, greaterThan(batches.first.scanned));
  });
}
