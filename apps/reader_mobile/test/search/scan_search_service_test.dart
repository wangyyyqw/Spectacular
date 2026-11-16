import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/position/cfi.dart';
import 'package:reader_core/parser/document_parser.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_mobile/search/chapter_text.dart';
import 'package:reader_mobile/search/scan_search_service.dart';
import 'package:reader_ui/reader_session.dart';

import '../reader/support/css_chapter_book.dart';
import '../support/test_epub.dart';

Future<void> _verifyTableSearch(EpubChapterSource source, String query) async {
  final service = ScanSearchService(source: source);
  addTearDown(service.dispose);
  final session = ReaderSession(
    source: source,
    store: MemoryReaderProgressStore(),
    bookId: 'table-search-$query',
  );
  addTearDown(session.dispose);
  await session.open();
  final hits = await service.search(query);
  expect(hits, hasLength(9));
  final pages = await source.loadChapter(0);
  final chapter = ChapterText.fromPages(pages);
  expect(RegExp(query).allMatches(chapter.text), hasLength(9));
  final parsed = source.document.parseDocument(0);
  final destinations = <int>{};
  for (var i = 0; i < hits.length; i++) {
    final cfi = await service.resolveCfi(hits[i]);
    expect(cfi, isNotNull);
    destinations.add(
      await _verifyTableDestination(session, pages, parsed, cfi!, 'rank$i'),
    );
  }
  expect(destinations.length, greaterThan(2));
}

Future<int> _verifyTableDestination(
  ReaderSession session,
  List<PageContent> pages,
  ParsedDocument parsed,
  String cfi,
  String id,
) async {
  final node = parsed.nodeAtCfi(EpubCfi.parse(cfi)!);
  expect(node, isA<ParsedElement>());
  expect((node! as ParsedElement).id, id);
  expect(cfiCharOffset(cfi), isNull, reason: '元素页锚点不能伪造文本节点字符偏移');
  final expected = pages.singleWhere(
    (page) => page.slices.any(
      (slice) =>
          slice.block.table?.cells.any(
            (cell) => cfiBase(cell.startCfi!) == cfiBase(cfi),
          ) ??
          false,
    ),
  );
  await session.jumpToCfi(cfi);
  expect(session.page!.pageIndex, expected.pageIndex);
  return expected.pageIndex;
}

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

  group('mapSearchOffset', () {
    test('扫描偏移越界或排版中无词时返回未命中', () {
      expect(mapSearchOffset('正文', '关键词', '关键词', 2918), -1);
      expect(mapSearchOffset('正文', '关键词', '关键词', 0), -1);
      expect(mapSearchOffset('关键词', '正文', '关键词', 0), -1);
      expect(mapSearchOffset('正文', '正文', '', 0), -1);
    });

    test('块间换行不同也保留同上下文重复命中序号', () {
      const rendered = '标题\n相同关键词相同\n相同关键词相同';
      const scanned = '标题\n\n相同关键词相同\n\n相同关键词相同';
      expect(
        mapSearchOffset(rendered, scanned, '关键词', scanned.indexOf('关键词')),
        rendered.indexOf('关键词'),
      );
      expect(
        mapSearchOffset(rendered, scanned, '关键词', scanned.lastIndexOf('关键词')),
        rendered.lastIndexOf('关键词'),
      );
    });

    test('隐藏命中消失或生成命中增加时按原文上下文定位', () {
      const scanned = '隐藏关键词。\n\n甲段关键词甲尾\n\n乙段关键词乙尾';
      const rendered = '生成关键词。\n甲段关键词甲尾\n乙段关键词乙尾';
      expect(
        mapSearchOffset(rendered, scanned, '关键词', scanned.indexOf('关键词甲尾')),
        rendered.indexOf('关键词甲尾'),
      );
      expect(
        mapSearchOffset(rendered, scanned, '关键词', scanned.indexOf('关键词乙尾')),
        rendered.indexOf('关键词乙尾'),
      );
    });

    test('上下文得分为零或只有一个字时拒绝跳到同词其他位置', () {
      expect(mapSearchOffset('丙关键词丁', '甲关键词乙', '关键词', 1), -1);
      expect(mapSearchOffset('丙关键词。', '甲关键词。', '关键词', 1), -1);
    });

    test('全章只有命中词或只差空白时保留可靠定位', () {
      expect(mapSearchOffset('关键词', '关键词', '关键词', 0), 0);
      expect(mapSearchOffset('关键词', '\n\n关键词\n', '关键词', 2), 0);
      expect(mapSearchOffset('词\n词', '词\n\n词', '词', 3), 2);
    });
  });

  test('已有直接CFI不依赖上下文，但必须属于命中章节', () async {
    final source = await openTestChapterSource(buildTestEpub());
    addTearDown(source.close);
    final service = ScanSearchService(source: source);
    addTearDown(service.dispose);
    final cfi = source.document.parseDocument(0).textNodes.first.cfi.toString();
    SearchResult result(String direct, {int spine = 0}) => SearchResult(
      spineIndex: spine,
      charOffset: -1,
      chapterTitle: '',
      context: '',
      matchLength: 0,
      cfi: direct,
    );
    expect(await service.resolveCfi(result(cfi)), cfi);
    expect(await service.resolveCfi(result(cfi, spine: 1)), isNull);
    expect(await service.resolveCfi(result('无效位置')), isNull);
  });

  test('隐藏命中的弱上下文不能重新定位到另一处同词', () async {
    final source = await openCssChapter(
      body: '<p class="hidden">甲关键词。</p><p>乙关键词。</p>',
      css: '.hidden {display:none;}',
    );
    addTearDown(source.close);
    final service = ScanSearchService(source: source);
    addTearDown(service.dispose);
    final hits = await service.search('关键词');
    expect(hits, hasLength(2));
    expect(await service.resolveCfi(hits.first), isNull);
    expect(await service.resolveCfi(hits.last), isNotNull);
  });

  test('正式搜索命中映射到段内元素及其后的 /5 字符块', () async {
    final source = await openCssChapter(
      body: '<p id="p">lead<b id="b">A</b><i id="i">B</i>tail</p>',
    );
    addTearDown(source.close);
    final service = ScanSearchService(source: source);
    addTearDown(service.dispose);
    final chapter = ChapterText.fromPages(await source.loadChapter(0));
    final parsed = source.document.parseDocument(0);
    for (final (query, expected) in [
      ('tail', 'epubcfi(/6/2!/4/2[p]/5:0)'),
      ('A', 'epubcfi(/6/2!/4/2[p]/2[b]/1:0)'),
    ]) {
      final hit = (await service.search(query)).single;
      final cfi = (await service.resolveCfi(hit))!;
      expect(cfi, expected);
      final point = EpubCfi.parse(cfi)!;
      expect((parsed.nodeAtCfi(point) as ParsedText).text, query);
      expect(source.document.resolveCfi(0, point).exact, isTrue);
      final block = chapter.blocks.single.block;
      final offset = block.offsetForCfi(cfi)!;
      expect(block.layout.text.substring(offset), startsWith(query));
    }
  });

  test('多列后方搜索命中保留切片前的来源字符偏移', () async {
    final prefix = 'text ' * 80;
    final source = await openCssChapter(
      body: '<p id="p">lead<b>A</b><i>B</i>${prefix}needle</p>',
      css:
          'body,p{margin:0;padding:0;}p{column-count:2;column-gap:16px;'
          'font-family:Ahem;font-size:16px;line-height:1.5;}',
      contentWidth: 200,
      contentHeight: 120,
    );
    addTearDown(source.close);
    final service = ScanSearchService(source: source);
    addTearDown(service.dispose);
    final hit = (await service.search('needle')).single;
    final cfi = (await service.resolveCfi(hit))!;
    expect(cfi, 'epubcfi(/6/2!/4/2[p]/5:${prefix.length})');
    final pages = await source.loadChapter(0);
    expect(pages.length, greaterThan(1));
    final block = ChapterText.fromPages(pages).blocks.last.block;
    final offset = block.offsetForCfi(cfi)!;
    expect(block.layout.text.substring(offset), startsWith('needle'));
    final point = EpubCfi.parse(cfi)!;
    expect(source.document.resolveCfi(0, point).exact, isTrue);
    expect(
      (source.document.parseDocument(0).nodeAtCfi(point) as ParsedText).text,
      '${prefix}needle',
    );
  });

  test('搜索诊断只记录查询长度和扫描统计', () async {
    const query = '私密检索意图';
    final source = await openTestChapterSource(
      buildTestEpub(title: '私密书名', paragraphs: const ['$query 出现一次']),
    );
    addTearDown(source.close);
    final records = <Map<String, Object?>>[];
    final service = ScanSearchService(
      source: source,
      onLog: (_, fields) => records.add(fields),
    );
    addTearDown(service.dispose);
    expect(await service.search(query), hasLength(1));
    expect(records.single['query_length'], query.length);
    expect(records.single['hits'], 1);
    expect(records.single.toString(), isNot(contains(query)));
    expect(records.single.toString(), isNot(contains('私密书名')));
    expect(records.single, isNot(contains('query')));
  });

  test('多段落重复命中的CFI分别落在真实命中文字', () async {
    final source = await openTestChapterSource(
      buildTestEpub(paragraphs: const ['甲段重复词甲尾', '乙段重复词乙尾', '丙段重复词丙尾']),
    );
    addTearDown(source.close);
    final service = ScanSearchService(source: source);
    addTearDown(service.dispose);
    final results = await service.search('重复词');
    final chapter = ChapterText.fromPages(await source.loadChapter(0));
    final cfis = <String>[];
    for (final result in results) {
      final cfi = await service.resolveCfi(result);
      expect(cfi, isNotNull);
      cfis.add(cfi!);
      final block = chapter.blocks.singleWhere(
        (block) => cfiBase(block.block.startCfi!) == cfiBase(cfi),
      );
      final local = block.block.offsetForCfi(cfi)!;
      expect(block.block.layout.text.substring(local, local + 3), '重复词');
    }
    expect(results, hasLength(3));
    expect(cfis.toSet(), hasLength(3), reason: '不能把所有重复命中都跳到第一段');
  });

  test('隐藏与生成正文改变坐标时仍跳到可见段落的命中', () async {
    final source = await openCssChapter(
      body:
          '<h1>标题</h1><p class="hidden">隐藏重复词。</p>'
          '<p class="visible">甲段重复词甲尾</p><p>乙段重复词乙尾</p>',
      css: '.hidden {display: none;} .visible::before {content: "生成重复词。";}',
    );
    addTearDown(source.close);
    final service = ScanSearchService(source: source);
    addTearDown(service.dispose);
    final results = await service.search('重复词');
    final chapter = ChapterText.fromPages(await source.loadChapter(0));
    final cfis = <String>[];
    for (final result in results.skip(1)) {
      final cfi = (await service.resolveCfi(result))!;
      cfis.add(cfi);
      final block = chapter.blocks.singleWhere(
        (block) => cfiBase(block.block.startCfi!) == cfiBase(cfi),
      );
      final local = block.block.offsetForCfi(cfi)!;
      expect(block.block.layout.text.substring(local, local + 3), '重复词');
      expect(
        block.block.layout.text.substring(local + 3),
        startsWith(cfis.length == 1 ? '甲尾' : '乙尾'),
      );
    }
    expect(results, hasLength(3));
    expect(cfis.toSet(), hasLength(2));
  });

  for (final (transform, text, query, expected) in [
    ('uppercase', 'hello world', 'hello', 'HELLO'),
    ('lowercase', 'HELLO WORLD', 'HELLO', 'hello'),
    ('capitalize', 'hello world', 'world', 'World'),
    ('uppercase', 'straße ziel', 'ziel', 'ZIEL'),
    ('uppercase', 'straße ziel', 'straße', 'STRAßE'),
  ]) {
    test('CSS $transform 后搜索仍定位真实显示偏移：$query', () async {
      final source = await openCssChapter(
        body: '<p class="t">$text</p>',
        css: '.t {text-transform: $transform;}',
      );
      addTearDown(source.close);
      final service = ScanSearchService(source: source);
      addTearDown(service.dispose);
      final hits = await service.search(query);
      expect(hits, hasLength(1));
      final chapter = ChapterText.fromPages(await source.loadChapter(0));
      final cfi = await service.resolveCfi(hits.single);
      expect(cfi, isNotNull);
      final block = chapter.blocks.singleWhere(
        (item) => cfiBase(item.block.startCfi!) == cfiBase(cfi!),
      );
      expect(
        block.block.layout.text.substring(block.block.offsetForCfi(cfi!)!),
        startsWith(expected),
      );
    });
  }

  test('同词在不同大小写样式的段落中重复时按全章序号定位', () async {
    final source = await openCssChapter(
      body: '<p class="upper">hello</p><p>hello</p><p class="upper">hello</p>',
      css: '.upper {text-transform: uppercase;}',
    );
    addTearDown(source.close);
    final service = ScanSearchService(source: source);
    addTearDown(service.dispose);
    final hits = await service.search('hello');
    expect(hits, hasLength(3));
    final chapter = ChapterText.fromPages(await source.loadChapter(0));
    final cfis = <String>[];
    for (var i = 0; i < hits.length; i++) {
      final cfi = await service.resolveCfi(hits[i]);
      expect(cfi, isNotNull);
      cfis.add(cfi!);
      expect(cfiBase(cfi), cfiBase(chapter.blocks[i].block.startCfi!));
    }
    expect(cfis.toSet(), hasLength(3));
  });

  test('分页表格的重复命中使用真实单元格锚点跳到所在页', () async {
    final source = await openCssChapter(
      body:
          '<p>表格前正文</p><table>${[for (var i = 0; i < 9; i++) '<tr><td>名称$i</td><td id="rank$i">'
                '<span class="rank">RANK: SSS 条目$i</span></td></tr>'].join()}</table><p>表格后正文</p>',
      css:
          'table {width:100%;} td {height:54px;} .rank {display:inline-block;}',
      contentHeight: 150,
    );
    addTearDown(source.close);
    await _verifyTableSearch(source, 'RANK');
    await _verifyTableSearch(source, 'SSS');
  });

  test('Flex 单元格搜索不重复计入外层文本并保留大小写变换', () async {
    final source = await openCssChapter(
      body:
          '<div class="flex"><p class="upper">hello 甲尾</p>'
          '<p>hello 乙尾</p></div>',
      css: '.flex {display:flex;} .upper {text-transform:uppercase;}',
    );
    addTearDown(source.close);
    final service = ScanSearchService(source: source);
    addTearDown(service.dispose);
    final hits = await service.search('hello');
    expect(hits, hasLength(2));
    final chapter = ChapterText.fromPages(await source.loadChapter(0));
    expect(chapter.text, 'HELLO 甲尾\nhello 乙尾');
    final cfis = <String>{};
    for (final hit in hits) {
      final cfi = await service.resolveCfi(hit);
      expect(cfi, isNotNull);
      cfis.add(cfi!);
    }
    expect(cfis, hasLength(2));
  });

  test('流式搜索：逐章推送，搜到就出结果', () async {
    final bytes = buildMultiChapterEpub(
      title: '流式',
      chapters: const <String>['第一章\n没有关键词。', '第二章\n沈河出现了。', '第三章\n沈河又出现了。'],
    );
    final source = await openTestChapterSource(bytes);
    final service = ScanSearchService(source: source);

    final batches = <ScanProgress>[];
    await for (final progress in service.searchStream('沈河')) {
      batches.add(progress);
    }
    expect(batches.length, greaterThanOrEqualTo(2), reason: '至少推送两次（两章命中）');
    expect(batches.first.results, isEmpty, reason: '未命中章节也上报扫描进度');
    expect(batches[1].results, hasLength(1), reason: '第二章首次命中');
    expect(batches.last.results, hasLength(2), reason: '最后一批累积两条');
    expect(batches.last.scanned, greaterThan(batches.first.scanned));
  });

  test('退出搜索服务后停止扫描，但不关闭正文共用来源', () async {
    final source = await openTestChapterSource(
      buildMultiChapterEpub(chapters: const ['目标在第一章', '目标在第二章', '目标在第三章']),
    );
    addTearDown(source.close);
    final service = ScanSearchService(source: source);
    final iterator = StreamIterator(service.searchStream('目标'));
    expect(await iterator.moveNext(), isTrue);
    final first = iterator.current.results.single;
    service.dispose();
    expect(await iterator.moveNext(), isFalse);
    expect(await service.search('目标'), isEmpty);
    expect(await service.resolveCfi(first), isNull);
    expect(source.isClosed, isFalse);
    expect(await source.loadChapter(0), isNotEmpty);
    await iterator.cancel();
  });

  test('新查询取消旧流，不再输出过期结果', () async {
    final source = await openTestChapterSource(
      buildMultiChapterEpub(chapters: const ['第一章甲乙', '第二章甲乙']),
    );
    addTearDown(source.close);
    final service = ScanSearchService(source: source);
    addTearDown(service.dispose);
    final old = StreamIterator(service.searchStream('甲'));
    expect(await old.moveNext(), isTrue);
    final latest = await service.search('乙');
    expect(latest, hasLength(2));
    expect(await old.moveNext(), isFalse);
    await old.cancel();
  });

  test('新查询取消一次性查询，已产出的旧批次也不返回', () async {
    final source = await openTestChapterSource(
      buildMultiChapterEpub(chapters: const ['第一章甲乙', '第二章甲乙']),
    );
    addTearDown(source.close);
    final service = ScanSearchService(source: source);
    addTearDown(service.dispose);
    final previous = service.search('甲');
    await Future<void>.delayed(Duration.zero);
    expect(await service.search('乙'), hasLength(2));
    expect(await previous, isEmpty);
  });

  test('退出时丢弃在途命中定位，不关闭正文来源', () async {
    final source = await openTestChapterSource(buildTestEpub());
    addTearDown(source.close);
    final service = ScanSearchService(source: source);
    final hit = (await service.search('段落')).single;
    final resolving = service.resolveCfi(hit);
    service.dispose();
    expect(await resolving, isNull);
    expect(source.isClosed, isFalse);
  });

  test('关闭正文来源后搜索不再读取或恢复全文缓存', () async {
    final source = await openTestChapterSource(buildTestEpub());
    final service = ScanSearchService(source: source);
    expect(await service.search('段落'), isNotEmpty);
    source.close();
    expect(await service.search('段落'), isEmpty);
    expect(source.chapterPlainText(0), isEmpty);
    expect(source.cacheReport, contains('纯文本缓存 0/'));
  });

  test('全书扫描超限后仅保留定量纯文本，淘汰章回访仍可定位', () async {
    final count = EpubChapterSource.chapterIndexCacheLimit + 4;
    final source = await openTestChapterSource(
      buildMultiChapterEpub(
        chapters: [for (var i = 0; i < count; i++) '第$i章目标字正文'],
      ),
    );
    addTearDown(source.close);
    final service = ScanSearchService(source: source);
    addTearDown(service.dispose);
    final original = source.chapterPlainText(0);
    final results = await service.search('目标字');
    expect(results, hasLength(count));
    expect(
      source.cacheReport,
      contains(
        '纯文本缓存 '
        '${EpubChapterSource.chapterIndexCacheLimit}/'
        '${EpubChapterSource.chapterIndexCacheLimit} 章',
      ),
    );
    expect(source.chapterPlainText(0), original);
    expect(await service.resolveCfi(results.first), isNotNull);
    source.close();
    expect(source.cacheReport, contains('纯文本缓存 0/'));
  });
}
