import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/bookshelf_sort.dart';
import 'package:reader_mobile/home/bookshelf_page.dart';
import 'package:reader_mobile/home/home_shell.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_ui/theme/reader_switch.dart';

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
  testWidgets('列表分割线只改变可见性，切换前后相邻图书位置不变', (tester) async {
    final library = LibraryStore.memory();
    final books = (await tester.runAsync(
      () async => [
        for (final name in ['第一本', '第二本', '第三本'])
          await library.importBytes(buildTestEpub(title: name)),
      ],
    ))!;
    await library.setSetting('bookshelf.grid', 'false');
    final progress = MemoryReaderProgressStore();
    List<Rect>? initial;
    for (final (index, show) in [true, false, true].indexed) {
      await library.setSetting(bookshelfListDividersKey, '$show');
      await tester.pumpWidget(
        MaterialApp(
          home: BookshelfPage(
            library: library,
            progressStore: progress,
            refreshToken: index,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final list = find.byKey(const ValueKey('bookshelf-list'));
      expect(
        find.descendant(of: list, matching: find.byType(Divider)),
        findsNWidgets(show ? books.length - 1 : 0),
      );
      final positions = [
        for (final book in books)
          tester.getRect(find.byKey(ValueKey('book-row-${book.id}'))),
      ];
      initial ??= positions;
      expect(positions, initial);
    }
  });

  testWidgets('遗留书名排序设置不再改变最近打开顺序', (tester) async {
    final library = LibraryStore.memory();
    late BookEntry first;
    late BookEntry second;
    await tester.runAsync(() async {
      first = await library.importBytes(buildTestEpub(title: '丙书'));
      second = await library.importBytes(buildTestEpub(title: '乙书'));
      await library.importBytes(buildTestEpub(title: '甲书'));
      await library.touchLastRead(first.id);
    });
    await library.setSetting(bookshelfSortKey, BookSortOrder.title.value);
    await library.setSetting('bookshelf.grid', 'false');
    await library.setSetting('bookshelf.autoUpdateFirst', 'true');
    await library.setSetting(
      bookshelfOnlineUpdatesKey,
      jsonEncode({
        second.id: {
          'updated': true,
          'checkedAt': DateTime.now()
              .subtract(const Duration(minutes: 1))
              .millisecondsSinceEpoch,
        },
      }),
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

    expect(_listTitles(tester), <String>[
      '丙书',
      '乙书',
      '甲书',
    ], reason: '旧排序值不生效，最近打开时间应盖过较早的更新提示');
  });

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
    await tester.pump();
    expect(tester.widget<ReaderSwitchListTile>(gridTitles).value, isFalse);
    await _settle(tester);
    expect(await library.getSetting(bookshelfGridShowTitlesKey), 'false');
    await tester.tap(
      find.byKey(const ValueKey('bookshelf-list-divider-setting')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('bookshelf-newest-first-setting')),
    );
    await tester.pump();
    await _settle(tester);
    expect(await library.getSetting(bookshelfListDividersKey), 'false');
    expect(await library.getSetting(bookshelfNewestFirstKey), 'true');

    Navigator.of(
      tester.element(
        find.byKey(const ValueKey('bookshelf-grid-title-setting')),
      ),
    ).pop();
    await tester.pumpAndSettle();
  });
}
