import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/bookshelf_sort.dart';
import 'package:reader_mobile/home/home_shell.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/file_progress_store.dart';

import '../support/test_epub.dart';

Future<void> _settle(WidgetTester tester, {int frames = 12}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

List<String> _listTitles(WidgetTester tester) => <String>[
  for (final tile in tester.widgetList<ListTile>(
    find.descendant(
      of: find.byKey(const ValueKey<String>('bookshelf-list')),
      matching: find.byType(ListTile),
    ),
  ))
    ((tile.title as Text).data) ?? '',
];

void main() {
  testWidgets('在“我的”设置书架排序，返回书架后按书名排序', (tester) async {
    final library = LibraryStore.memory();
    await tester.runAsync(() async {
      for (final title in <String>['B书', 'A书', 'C书']) {
        await library.importBytes(buildTestEpub(title: title));
      }
    });

    await tester.pumpWidget(
      MaterialApp(
        home: HomeShell(
          library: library,
          progressStore: FileReaderProgressStore.memory(),
        ),
      ),
    );
    await _settle(tester);

    await tester.tap(find.text('我的'));
    await _settle(tester);
    expect(find.text('书架排序'), findsOneWidget);
    ListTile sortTile() => tester.widget<ListTile>(
      find.byKey(const ValueKey<String>('bookshelf-sort-setting')),
    );
    expect((sortTile().subtitle! as Text).data, '最近阅读');

    await tester.tap(
      find.byKey(const ValueKey<String>('bookshelf-sort-setting')),
    );
    await _settle(tester, frames: 4);
    await tester.tap(
      find.byKey(const ValueKey<String>('bookshelf-sort-title')),
    );
    await _settle(tester);
    expect(await library.getSetting(bookshelfSortKey), 'title');
    expect((sortTile().subtitle! as Text).data, '书名');

    await tester.tap(find.text('书架'));
    await _settle(tester);
    await tester.tap(find.byTooltip('列表视图'));
    await _settle(tester);
    expect(_listTitles(tester), <String>['A书', 'B书', 'C书']);
  });
}
