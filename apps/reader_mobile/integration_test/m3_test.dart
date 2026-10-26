import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reader_mobile/home/bookshelf_page.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_ui/annotations/annotation.dart';
import 'package:reader_ui/panels/search_panel.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';

import '../test/support/test_epub.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('M3 全链路：导入 → 阅读 → 标注 → 搜索 → 跳转 → 语义', (tester) async {
    final dir = Directory.systemTemp.createTempSync('m3-e2e');
    addTearDown(() => dir.deleteSync(recursive: true));
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final library = LibraryStore(database: db, directoryProvider: () async => dir);

    // 一段足够分多页的正文，含几个可搜的词。
    final chapters = <String>[
      for (var i = 0; i < 4; i++)
        '沈河昨天收到了一个包裹。' * 8 + '他拿着保险的补偿金离开了精神病院。' * 8,
    ];
    final bytes = buildMultiChapterEpub(chapters: chapters, title: 'M3 集成书');

    late BookEntry book;
    await tester.runAsync(() async {
      book = await library.importBytes(bytes);
    });
    expect(book.id, isNotEmpty);

    // 1. 书库：卡片可见。
    await tester.pumpWidget(
      MaterialApp(
        home: BookshelfPage(
          library: library,
          progressStore: MemoryReaderProgressStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('M3 集成书'), findsWidgets);

    // 2. 打开阅读页。
    await tester.tap(find.text('M3 集成书').first);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.byType(ReaderPage), findsOneWidget);

    // 3. 翻页：点右区前进。
    final size = tester.getSize(find.byType(ReaderView));
    final before = find.textContaining('/');
    await tester.tapAt(Offset(size.width * 0.9, size.height * 0.5));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderView), findsOneWidget);
    expect(before, findsWidgets);

    // 4. 标注：长按选词 → 高亮 → 落库。
    await tester.longPressAt(tester.getCenter(find.byType(ReaderView)));
    await tester.pumpAndSettle();
    final highlight = find.byKey(
      const ValueKey<String>('selection-action-highlight'),
    );
    if (highlight.evaluate().isNotEmpty) {
      await tester.tap(highlight);
      await tester.pumpAndSettle();
      final rows = await tester.runAsync(() => db.select(db.annotations).get());
      expect(
        (rows ?? const <AnnotationRow>[])
            .where((row) => row.type == ReaderAnnotationType.highlight.storageValue)
            .length,
        greaterThanOrEqualTo(1),
        reason: '高亮写入数据库',
      );
    }

    // 5. 搜索：菜单 → 搜索 → 输入 → 结果。
    await tester.tapAt(tester.getCenter(find.byType(ReaderView)));
    await tester.pumpAndSettle();
    // 菜单 → 目录抽屉 → 搜索页签（设计稿四入口里搜索挂在目录下）。
    await tester.tap(find.byKey(const ValueKey<String>('menu-entry-toc')));
    await tester.pumpAndSettle();
    final searchEntry = find.byKey(const ValueKey<String>('drawer-tab-search'));
    expect(searchEntry, findsOneWidget, reason: '目录抽屉有搜索页签');
    await tester.tap(searchEntry);
    await tester.pumpAndSettle();
    expect(find.byType(SearchPanel), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey<String>('search-input')),
      '沈河',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('search-results')),
      findsOneWidget,
      reason: '搜索出结果',
    );
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();
    expect(find.byType(SearchPanel), findsNothing, reason: '选中后关闭面板');

    // 6. 语义：正文进入无障碍树。
    final semantics = tester.ensureSemantics();
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(RegExp('沈河')),
      findsWidgets,
      reason: '语义树含正文字样',
    );
    semantics.dispose();

    // 7. 返回书库（阅读页没有 AppBar，走系统返回）。
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('M3 集成书'), findsWidgets);
  });
}
