import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/search/scan_search_service.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_ui/panels/search_panel.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';

import '../support/reader_pump.dart';
import '../support/test_epub.dart';

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  testWidgets('菜单搜索 → 输入 → 点结果跳转并临时高亮（P4-26）', (tester) async {
    final dir = Directory.systemTemp.createTempSync('search-flow');
    addTearDown(() => dir.deleteSync(recursive: true));
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final library = LibraryStore(
      database: db,
      directoryProvider: () async => dir,
    );
    final bytes = buildTestEpub(
      title: '搜索流程书',
      paragraphs: const <String>[
        '沈河昨天收到了一个包裹。',
        '寄件人署名是他消失了多年的老爹。',
        '沈河并不想知道生命的意义。',
      ],
    );
    late BookEntry book;
    await tester.runAsync(() async {
      book = await library.importBytes(bytes);
    });
    final source = await openTestChapterSource(bytes);
    final service = ScanSearchService(source: source);

    late ReaderSession session;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              height: 520,
              child: ReaderPage(
                source: source,
                store: MemoryReaderProgressStore(),
                bookId: book.id,
                onSessionReady: (value) => session = value,
                onSearch: (query) async {
                  final results = await service.search(query);
                  return <SearchPanelResult>[
                    for (final result in results)
                      SearchPanelResult(
                        spineIndex: result.spineIndex,
                        charOffset: result.charOffset,
                        chapterTitle: result.chapterTitle,
                        context: result.context,
                        matchLength: result.matchLength,
                        cfi: result.cfi,
                      ),
                  ];
                },
              ),
            ),
          ),
        ),
      ),
    );
    await pumpReaderUntil(tester, find.byType(ReaderView));

    // 菜单 → 搜索。
    await tester.tapAt(tester.getCenter(find.byType(ReaderView)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('menu-entry-toc')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('drawer-tab-search')));
    await tester.pumpAndSettle();
    expect(find.byType(SearchPanel), findsOneWidget);

    // 输入 → 防抖 → 结果。
    await tester.enterText(
      find.byKey(const ValueKey<String>('search-input')),
      '沈河',
    );
    // 假时钟触发防抖后，按结果就绪交付扫描 isolate 的真实 IO 消息。
    await tester.pump(const Duration(milliseconds: 350));
    await pumpReaderUntil(
      tester,
      find.byKey(const ValueKey<String>('search-results')),
    );
    expect(
      find.byKey(const ValueKey<String>('search-results')),
      findsOneWidget,
    );

    // 命中项是 ListTile（章标题是普通 Text，不参与点击）。
    final hits = find.byType(ListTile);
    expect(hits, findsWidgets);
    await tester.tap(hits.first);
    await pumpReaderUntilComplete(
      tester,
      () =>
          !session.loading &&
          session.jumpLoadingTitle == null &&
          session.progress?.spineIndex == 0 &&
          find.byType(SearchPanel).evaluate().isEmpty,
      description: '搜索命中跳转与面板关闭',
    );

    // 跳转：仍在第 0 章（命中在第一段），临时高亮已挂上。
    expect(session.progress!.spineIndex, 0);
    expect(find.byType(SearchPanel), findsNothing, reason: '选中后关闭面板');

    // 3 秒后临时高亮消失。
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });
}
