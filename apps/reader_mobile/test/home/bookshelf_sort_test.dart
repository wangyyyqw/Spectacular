import 'dart:convert';

import 'package:flutter/material.dart';
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
  final books = [
    BookEntry(
      id: 'reading',
      title: 'C在读',
      author: '',
      filePath: '',
      addedAt: DateTime(2026, 1, 1),
      lastReadAt: DateTime(2026, 1, 4),
    ),
    BookEntry(
      id: 'unread',
      title: 'A未读',
      author: '',
      filePath: '',
      addedAt: DateTime(2026, 1, 2),
    ),
    BookEntry(
      id: 'new',
      title: 'B新书',
      author: '',
      filePath: '',
      addedAt: DateTime(2026, 1, 5),
    ),
  ];
  for (final first in [true, false]) {
    test('最近阅读将新书放在${first ? '最前' : '最后'}，阅读后按阅读时间排序', () {
      List<String> sorted(List<BookEntry> entries) =>
          (List<BookEntry>.of(entries)..sort(
                (a, b) =>
                    BookSortOrder.recent.compare(a, b, newBooksFirst: first),
              ))
              .map((book) => book.id)
              .toList();
      expect(
        sorted(books),
        first ? ['new', 'reading', 'unread'] : ['reading', 'unread', 'new'],
      );
      expect(
        sorted([
          ...books.take(2),
          books.last.copyWith(lastReadAt: DateTime(2026, 1, 6)),
        ]),
        ['new', 'reading', 'unread'],
      );
    });
  }

  for (final sort in BookSortOrder.values) {
    for (final first in [true, false]) {
      testWidgets('${sort.label}：新书${first ? '在前' : '在后'}，批量导入与重建页面保持顺序', (
        tester,
      ) async {
        tester.view
          ..physicalSize = const Size(800, 1000)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final library = LibraryStore.memory();
        late BookEntry pinned;
        late BookEntry reading;
        await tester.runAsync(() async {
          pinned = await library.importBytes(buildTestEpub(title: '置顶书'));
          await library.importBytes(buildTestEpub(title: 'A未读'));
          reading = await library.importBytes(buildTestEpub(title: 'Z在读'));
          await library.touchLastRead(reading.id);
        });
        final readAt = (await library.bookById(reading.id))!.lastReadAt;
        await library.setSetting('bookshelf.grid', 'false');
        await library.setSetting('bookshelf.pinned', jsonEncode([pinned.id]));
        await library.setSetting(bookshelfSortKey, sort.value);
        await library.setSetting(bookshelfNewBooksFirstKey, '$first');
        Future<void> showShelf() async {
          await tester.pumpWidget(
            MaterialApp(
              home: BookshelfPage(
                key: UniqueKey(),
                library: library,
                progressStore: MemoryReaderProgressStore(),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        await showShelf();
        await tester.runAsync(() async {
          for (final title in ['B新书', 'M新书']) {
            await library.importBytes(buildTestEpub(title: title));
          }
        });
        await tester.pumpAndSettle();
        final expected = switch (sort) {
          BookSortOrder.title => ['置顶书', 'A未读', 'B新书', 'M新书', 'Z在读'],
          BookSortOrder.recent when !first => [
            '置顶书',
            'Z在读',
            'A未读',
            'B新书',
            'M新书',
          ],
          BookSortOrder.added when !first => [
            '置顶书',
            'A未读',
            'Z在读',
            'B新书',
            'M新书',
          ],
          _ => ['置顶书', 'M新书', 'B新书', 'Z在读', 'A未读'],
        };
        expect(_listTitles(tester), expected);
        await showShelf();
        expect(_listTitles(tester), expected);
        // 重复导入与调整显示顺序不伪造阅读记录，也不改变原导入时间。
        final before = await library.list();
        await tester.runAsync(
          () => library.importBytes(buildTestEpub(title: 'A未读')),
        );
        await tester.pumpAndSettle();
        expect(_listTitles(tester), expected);
        final after = await library.list();
        for (final book in before) {
          final current = after.singleWhere((item) => item.id == book.id);
          expect(current.addedAt, book.addedAt);
          expect(current.lastReadAt, book.lastReadAt);
        }
        expect((await library.bookById(reading.id))!.lastReadAt, readAt);
      });
    }
  }

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
          progressStore: MemoryReaderProgressStore(),
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

    final position = find.byKey(
      const ValueKey('bookshelf-new-books-first-setting'),
    );
    await tester.ensureVisible(position);
    await tester.tap(position);
    await _settle(tester);
    expect(await library.getSetting(bookshelfNewBooksFirstKey), 'false');
    await tester.tap(find.text('书架'));
    await _settle(tester);
    await tester.tap(find.byTooltip('列表视图'));
    await _settle(tester);
    expect(_listTitles(tester), ['B书', 'A书', 'C书']);

    await tester.tap(find.text('我的'));
    await _settle(tester);
    await Scrollable.ensureVisible(
      tester.element(find.byKey(const ValueKey('bookshelf-sort-setting'))),
      alignment: .5,
    );
    await _settle(tester);
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
    expect(_listTitles(tester), <String>['A书', 'B书', 'C书']);
  });
}
