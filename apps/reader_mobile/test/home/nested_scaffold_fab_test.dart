import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/bookshelf_page.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_ui/reader_session.dart';

/// 复现真机结构：外层 Scaffold（HomeShell 的 body + NavigationBar）里再放
/// 一个自带 Scaffold 的书架页，检查书架导入按钮是否还能点到。
void main() {
  testWidgets('真机 MediaQuery（刘海 + 手势条 + DPR）下导入按钮仍可点击（P1）', (tester) async {
    var pickCalls = 0;
    final dir = Directory.systemTemp.createTempSync('nested-fab');
    addTearDown(() => dir.deleteSync(recursive: true));
    final library = LibraryStore(
      database: AppDatabase(NativeDatabase.memory()),
      directoryProvider: () async => dir,
    );

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.8125;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(384, 853),
            devicePixelRatio: 2.8125,
            padding: EdgeInsets.only(top: 32, bottom: 24),
            viewPadding: EdgeInsets.only(top: 32, bottom: 24),
          ),
          child: Scaffold(
            body: IndexedStack(
              index: 0,
              children: <Widget>[
                BookshelfPage(
                  library: library,
                  progressStore: MemoryReaderProgressStore(),
                  pickEpubFiles: () async {
                    pickCalls++;
                    return <String>[];
                  },
                ),
              ],
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: 0,
              onDestinationSelected: (_) {},
              destinations: const <Widget>[
                NavigationDestination(
                  icon: Icon(Icons.library_books_outlined),
                  label: '书架',
                ),
                NavigationDestination(
                  icon: Icon(Icons.bar_chart_outlined),
                  label: '统计',
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 导入按钮存在且可被命中（若被外层布局遮挡，tap 会命中别的 widget）。
    final importButton = find.byTooltip('导入 EPUB');
    expect(importButton, findsOneWidget);
    await tester.tap(importButton, warnIfMissed: true);
    await tester.pumpAndSettle();
    expect(pickCalls, 1, reason: '点导入按钮应触发选文件');
  });
}
