import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/bookshelf_sort.dart';
import 'package:reader_mobile/home/home_shell.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_ui/theme/reader_switch.dart';
import 'package:reader_ui/theme/reader_sheet_form.dart';

import '../support/test_epub.dart';

import 'package:reader_ui/reader_session.dart';

Future<void> _settle(WidgetTester tester, {int frames = 12}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

List<String> _listTitles(WidgetTester tester) => <String>[
  for (final text in tester.widgetList<Text>(
    find.descendant(
      of: find.byKey(const ValueKey<String>('bookshelf-list')),
      matching: find.byType(Text),
    ),
  ))
    if (text.key is ValueKey<String> &&
        (text.key! as ValueKey<String>).value.startsWith('book-row-title-'))
      text.data ?? '',
];

void main() {
  testWidgets('书架管理保存宫格书名、分割线和新书置顶设置', (tester) async {
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
          progressStore: MemoryReaderProgressStore(),
        ),
      ),
    );
    await _settle(tester);

    await tester.tap(find.text('我的'));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('profile-settings-entry')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('bookshelf-management-entry')));
    await _settle(tester, frames: 4);
    final gridTitles = find.byKey(
      const ValueKey('bookshelf-grid-title-setting'),
    );
    expect(tester.widget<ReaderSwitchListTile>(gridTitles).value, isTrue);
    await tester.tap(gridTitles);
    await _settle(tester);
    expect(await library.getSetting(bookshelfGridShowTitlesKey), 'false');
    await tester.tap(
      find.byKey(const ValueKey('bookshelf-list-divider-setting')),
    );
    await tester.tap(
      find.byKey(const ValueKey('bookshelf-newest-first-setting')),
    );
    await _settle(tester);
    expect(await library.getSetting(bookshelfListDividersKey), 'false');
    expect(await library.getSetting(bookshelfNewestFirstKey), 'true');

    await tester.drag(find.byType(ReaderSheetForm), const Offset(0, 700));
    await _settle(tester);
    await tester.tap(find.text('书架'));
    await _settle(tester);
    await tester.tap(find.byTooltip('列表视图'));
    await _settle(tester);
    expect(_listTitles(tester), <String>['C书', 'B书', 'A书']);
  });
}
