import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/bookshelf_page.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';
import 'package:reader_ui/panels/search_panel.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';

import '../support/test_epub.dart';
import '../support/reader_pump.dart';

Future<SearchPanel> _searchPanel(WidgetTester tester) async {
  await tester.tapAt(tester.getCenter(find.byType(ReaderView)));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const ValueKey('menu-entry-toc')));
  await tester.tap(find.byKey(const ValueKey('menu-entry-toc')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('drawer-tab-search')));
  await tester.pumpAndSettle();
  return tester.widget<SearchPanel>(find.byType(SearchPanel));
}

Future<List<SearchPanelResult>> _search(
  WidgetTester tester,
  SearchPanel panel,
  String query,
) async {
  var results = <SearchPanelResult>[];
  await tester.runAsync(() async {
    results = await panel.onSearch(query);
  });
  return results;
}

void main() {
  testWidgets('换书搜索只返回当前书，退出关闭同一正文来源与搜索任务', (tester) async {
    final library = LibraryStore.memory();
    await library.importBytes(
      buildTestEpub(
        title: '搜索书甲',
        identifier: 'search-a',
        paragraphs: const ['ONLY_IN_BOOK_A'],
      ),
    );
    await library.importBytes(
      buildTestEpub(
        title: '搜索书乙',
        identifier: 'search-b',
        paragraphs: const ['ONLY_IN_BOOK_B'],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: BookshelfPage(
          library: library,
          progressStore: MemoryReaderProgressStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('搜索书甲').first);
    await pumpReaderUntil(tester, find.byType(ReaderView));
    await pumpReaderUntilComplete(
      tester,
      () => find.byKey(const ValueKey('book-opening-view')).evaluate().isEmpty,
    );
    final firstReader = tester.widget<ReaderPage>(find.byType(ReaderPage));
    final firstSource = firstReader.source as EpubChapterSource;
    final firstPanel = await _searchPanel(tester);
    final firstResults = await _search(tester, firstPanel, 'ONLY_IN_BOOK_A');
    expect(firstResults, hasLength(1));
    final firstPages = await pumpReaderTask(tester, firstSource.loadChapter(0));
    expect(
      await pumpReaderTask(
        tester,
        firstReader.onResolveSearchCfi!(firstResults.single),
      ),
      isNotNull,
    );
    expect(
      await pumpReaderTask(tester, firstSource.loadChapter(0)),
      same(firstPages),
      reason: '搜索解析命中复用正文已分页的同一来源与几何',
    );
    Navigator.of(tester.element(find.byType(ReaderPage))).pop();
    await pumpReaderUntilComplete(tester, () => firstSource.isClosed);
    await tester.pumpAndSettle();
    expect(firstSource.isClosed, isTrue);
    expect(await _search(tester, firstPanel, 'ONLY_IN_BOOK_A'), isEmpty);

    await tester.tap(find.text('搜索书乙').first);
    await pumpReaderUntil(tester, find.byType(ReaderView));
    await pumpReaderUntilComplete(
      tester,
      () => find.byKey(const ValueKey('book-opening-view')).evaluate().isEmpty,
    );
    final secondSource =
        tester.widget<ReaderPage>(find.byType(ReaderPage)).source
            as EpubChapterSource;
    expect(secondSource, isNot(same(firstSource)));
    final secondPanel = await _searchPanel(tester);
    expect(await _search(tester, secondPanel, 'ONLY_IN_BOOK_A'), isEmpty);
    expect(await _search(tester, secondPanel, 'ONLY_IN_BOOK_B'), hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpReaderUntilComplete(tester, () => secondSource.isClosed);
    expect(secondSource.isClosed, isTrue);
  });
}
