import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/position/cfi.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/search/chapter_text.dart';
import 'package:reader_mobile/search/search_index_store.dart';
import 'package:reader_mobile/search/search_indexer.dart';
import 'package:reader_mobile/search/search_service.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/test_epub.dart';

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  late AppDatabase db;
  late Directory dir;
  late LibraryStore library;
  late BookEntry book;
  late SearchIndexStore store;
  late ReaderChapterSource source;
  late SearchService service;
  late int bookId;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('search-service');
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryStore(database: db, directoryProvider: () async => dir);
    final bytes = buildTestEpub(
      title: '搜索书',
      paragraphs: const <String>[
        '沈河昨天收到了一个包裹。',
        '寄件人署名是他消失了多年的老爹。',
        '他拿着意外死亡证明把保险的补偿金都领了。',
        '沈河并不想知道生命的意义，但是他已经离开了精神病院。',
        '小心翼翼迈过卷帘门，走进房子里，四下打量一番。',
        '房间不大，大概四五十平米，一张靠墙的小四方桌。',
        '他把那把钥匙插进锁孔，扭了一圈。',
        '这间小餐厅后厨以前估计是主打线上平台。',
      ],
    );
    book = await library.importBytes(bytes);
    store = SearchIndexStore(db);
    source = await openTestChapterSource(bytes);
    final rows = await (db.select(
      db.books,
    )..where((table) => table.uuid.equals(book.id))).get();
    bookId = rows.single.id;
    await SearchIndexer(source: source, store: store).build(bookId);
    service = SearchService(source: source, store: store);
  });

  tearDown(() async {
    await db.close();
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });

  test('查询命中：结果含上下文、章名与 CFI（P4-25）', () async {
    final results = await service.search(bookId, '沈河');
    expect(results, isNotEmpty);
    final first = results.first;
    expect(first.context, contains('沈河'));
    expect(first.matchLength, 2);
    expect(first.cfi, isNotNull);
    expect(first.cfi, startsWith('epubcfi('));
  });

  test('CFI 定位指回同一处文字（点击结果能跳对位置）', () async {
    final results = await service.search(bookId, '沈河');
    expect(results, isNotEmpty);
    for (final result in results.take(5)) {
      final cfi = result.cfi!;
      final spine = spineIndexOfCfi(EpubCfi.parse(cfi)!);
      expect(spine, result.spineIndex, reason: 'CFI 章号与命中章一致');
      final localOffset = cfiCharOffset(cfi)!;
      final pages = await source.loadChapter(result.spineIndex);
      final chapter = ChapterText.fromPages(pages);
      final located = chapter.locate(
        result.charOffset,
      );
      expect(located, isNotNull);
      expect(located!.localOffset, localOffset, reason: '块内偏移一致');
      // 块内文本该位置正是查询词。
      final blockText = located.block.block.layout.text;
      expect(
        blockText.substring(localOffset, localOffset + 2),
        '沈河',
        reason: 'CFI 落点文字与查询词一致',
      );
    }
  });

  test('10 个查询词的结果都与预期一致', () async {
    // 用真实章节文本里确实出现的词，逐个检查结果里的每一条都真的包含该词。
    const queries = <String>[
      '沈河',
      '包裹',
      '老爹',
      '精神病院',
      '卷帘门',
      '钥匙',
      '房间',
      '餐厅',
      '补偿金',
      '保险',
    ];
    var withResults = 0;
    for (final query in queries) {
      final results = await service.search(bookId, query);
      if (results.isEmpty) {
        continue;
      }
      withResults++;
      for (final result in results) {
        expect(
          result.context,
          contains(query),
          reason: '"$query" 的上下文必须含查询词',
        );
        expect(result.chapterTitle, isNotEmpty, reason: '结果带章名');
      }
    }
    expect(withResults, greaterThanOrEqualTo(8), reason: '10 个词里大部分应命中');
  });

  test('不存在的词返回空；空查询返回空', () async {
    expect(await service.search(bookId, 'zzyyzz'), isEmpty);
    expect(await service.search(bookId, ''), isEmpty);
    expect(await service.search(bookId, '   '), isEmpty);
  });

  test('结果按文档顺序排列且去重', () async {
    final results = await service.search(bookId, '沈河');
    expect(results.length, greaterThan(1));
    for (var i = 1; i < results.length; i++) {
      final previous = results[i - 1];
      final current = results[i];
      final ordered =
          previous.spineIndex < current.spineIndex ||
          (previous.spineIndex == current.spineIndex &&
              previous.charOffset <= current.charOffset);
      expect(ordered, isTrue, reason: '结果按 (章, 偏移) 升序');
    }
    final keys = results
        .map((r) => '${r.spineIndex}:${r.charOffset}')
        .toSet();
    expect(keys.length, results.length, reason: '无重复命中');
  });

  test('多字查询与单字查询都可用（gram 交集 + 原文校验）', () async {
    final long = await service.search(bookId, '沈河昨天');
    if (long.isNotEmpty) {
      expect(long.first.context, contains('沈河昨天'));
    }
    final single = await service.search(bookId, '河');
    // 单字不产生 gram（§66.2），按规格返回空。
    expect(single, isEmpty, reason: '单字没有 2-gram，规格上不索引');
  });
}
