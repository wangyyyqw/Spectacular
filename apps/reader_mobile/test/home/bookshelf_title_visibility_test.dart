import 'package:flutter/material.dart';
import 'package:reader_ui/theme/reader_switch.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/bookshelf_page.dart';
import 'package:reader_mobile/home/bookshelf_sort.dart';
import 'package:reader_mobile/home/home_shell.dart';
import 'package:reader_mobile/library/library_store.dart';

import '../support/test_epub.dart';

import 'package:reader_ui/reader_session.dart';

Future<void> _settle(WidgetTester tester, {int frames = 12}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('我的页关闭“显示书名”后书架隐藏书名，重启保持', (tester) async {
    final library = LibraryStore.memory();
    final ids = <String>[];
    await tester.runAsync(() async {
      for (final title in <String>['A书', 'B书']) {
        ids.add((await library.importBytes(buildTestEpub(title: title))).id);
      }
    });

    await tester.pumpWidget(
      MaterialApp(
        home: HomeShell(
          library: library,
          progressStore: MemoryReaderProgressStore(),
        ),
      ),
    );
    await _settle(tester);

    Finder cardTitle(String id) =>
        find.byKey(ValueKey<String>('book-card-title-$id'));
    Finder rowTitle(String id) =>
        find.byKey(ValueKey<String>('book-row-title-$id'));
    for (final id in ids) {
      expect(cardTitle(id), findsOneWidget);
    }

    await tester.tap(find.text('我的'));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('profile-settings-entry')));
    await _settle(tester);
    final switchTile = find.byKey(
      const ValueKey<String>('bookshelf-title-setting'),
    );
    expect(tester.widget<ReaderSwitchListTile>(switchTile).value, isTrue);
    await tester.tap(switchTile);
    await _settle(tester);
    expect(tester.widget<ReaderSwitchListTile>(switchTile).value, isFalse);
    expect(await library.getSetting(bookshelfShowTitlesKey), 'false');

    await tester.pageBack();
    await _settle(tester);
    await tester.tap(find.text('书架'));
    await _settle(tester);
    for (final id in ids) {
      expect(cardTitle(id), findsNothing);
    }

    await tester.tap(find.byTooltip('列表视图'));
    await _settle(tester);
    for (final id in ids) {
      expect(rowTitle(id), findsNothing);
    }

    // 重新构建页面（≈ 重启）仍保持隐藏。
    await tester.pumpWidget(
      MaterialApp(
        home: BookshelfPage(
          library: library,
          progressStore: MemoryReaderProgressStore(),
        ),
      ),
    );
    await _settle(tester);
    for (final id in ids) {
      expect(rowTitle(id), findsNothing);
    }
  });
}
