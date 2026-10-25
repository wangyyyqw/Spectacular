import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/text/search.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/search/search_index_store.dart';
import 'package:reader_mobile/search/search_indexer.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/test_epub.dart';

/// 可计数、可截断的章节源（模拟中断续建）。
class _FakeSource implements ReaderChapterSource {
  _FakeSource(this.chapters, {this.failAfter = -1});

  final List<String> chapters;

  /// 第 N 次 loadChapter 后抛错（-1 表示不抛）。
  final int failAfter;
  int calls = 0;

  @override
  int get chapterCount => chapters.length;

  @override
  Future<List<PageContent>> loadChapter(int spineIndex) async {
    if (failAfter >= 0 && calls >= failAfter) {
      throw StateError('模拟中断');
    }
    calls++;
    final style = ComputedStyle(const <String, String>{
      'font-size': '16px',
      'line-height': '1.5',
    });
    final layout = TextLayoutEngine.layout(
      text: chapters[spineIndex],
      style: style,
      maxWidth: 320,
    );
    final block = PageBlock(layout: layout, style: style);
    return <PageContent>[
      PageContent(
        spineIndex: spineIndex,
        pageIndex: 0,
        slices: <PageBlockSlice>[
          PageBlockSlice(
            block: block,
            startLine: 0,
            endLine: layout.lineCount,
            height: layout.height,
          ),
        ],
        usedHeight: layout.height,
        pageHeight: 800,
        topPadding: 0,
      ),
    ];
  }
}

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  late AppDatabase db;
  late Directory dir;
  late LibraryStore library;
  late BookEntry book;
  late SearchIndexStore store;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('search-index');
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryStore(database: db, directoryProvider: () async => dir);
    book = await library.importBytes(buildTestEpub(title: '索引书'));
    store = SearchIndexStore(db);
  });

  tearDown(() async {
    await db.close();
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });

  Future<int> bookId() async {
    final rows = await (db.select(
      db.books,
    )..where((table) => table.uuid.equals(book.id))).get();
    return rows.single.id;
  }

  test('建索引：逐章写入原文与 gram（P4-24）', () async {
    final id = await bookId();
    final source = _FakeSource(<String>['你好世界', '第二章节内容']);
    final indexer = SearchIndexer(source: source, store: store);
    final built = await indexer.build(id);
    expect(built, 2);
    expect(await store.indexedChapterCount(id), 2);
    expect(await store.lastIndexedSpine(id), 1);
    expect(await store.chapterText(id, 0), '你好世界');

    final hits = await store.lookup(id, '世界');
    expect(hits, hasLength(1));
    expect(hits.single.spineIndex, 0);
    expect(hits.single.charOffset, 2);
  });

  test('中断后从断点续建，不重复也不漏（P4-24）', () async {
    final id = await bookId();
    final chapters = <String>['第一章甲', '第二章乙', '第三章丙', '第四章丁'];
    final first = SearchIndexer(
      source: _FakeSource(chapters, failAfter: 2),
      store: store,
    );
    await expectLater(first.build(id), throwsA(isA<StateError>()));
    expect(await store.indexedChapterCount(id), 2);
    expect(await store.lastIndexedSpine(id), 1);

    final second = SearchIndexer(
      source: _FakeSource(chapters),
      store: store,
    );
    final built = await second.build(id);
    expect(built, 2, reason: '只补未索引的两章');
    expect(await store.indexedChapterCount(id), 4);
    expect(await store.lastIndexedSpine(id), 3);
    final hits = await store.lookup(id, '第二');
    expect(hits, hasLength(1));
  });

  test('已全部索引时再调用不做事', () async {
    final id = await bookId();
    final indexer = SearchIndexer(
      source: _FakeSource(<String>['只有一章']),
      store: store,
    );
    expect(await indexer.build(id), 1);
    expect(await indexer.build(id), 0);
  });

  test('30 万字切分与写入在 10s 内（P4-24 验收）', () async {
    final id = await bookId();
    final chapters = <String>[
      for (var i = 0; i < 30; i++)
        List<String>.generate(
          10000,
          (index) => '甲乙丙丁戊己庚辛壬癸'[index % 10],
        ).join(),
    ];
    final totalChars = chapters.fold<int>(0, (sum, text) => sum + text.length);
    expect(totalChars, 300000);

    final watch = Stopwatch()..start();
    final indexer = SearchIndexer(
      source: _FakeSource(chapters),
      store: store,
    );
    final built = await indexer.build(id);
    watch.stop();

    expect(built, 30);
    expect(
      watch.elapsed,
      lessThan(const Duration(seconds: 10)),
      reason: '30 万字索引耗时 ${watch.elapsedMilliseconds}ms',
    );
    final grams = await store.lookup(id, '甲乙');
    expect(grams, isNotEmpty);
  });

  test('切分规则与查询 gram 一致（同套规则）', () {
    expect(SearchTokenizer.queryGrams('你好世界'), contains('你好'));
    expect(SearchTokenizer.queryGrams('2026'), <String>['2026']);
  });
}
