import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/book_cover_image.dart';
import 'package:reader_mobile/home/bookshelf_page.dart';
import 'package:reader_mobile/home/bookshelf_sort.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/test_epub.dart';

List<String> _titles(WidgetTester tester) => [
  for (final text in tester.widgetList<Text>(
    find.descendant(
      of: find.byKey(const ValueKey('bookshelf-list')),
      matching: find.byType(Text),
    ),
  ))
    if (text.key is ValueKey<String> &&
        (text.key! as ValueKey<String>).value.startsWith('book-row-title-'))
      text.data!,
];

double _coverShadowOpacity(WidgetTester tester, Finder cover) => tester
    .widget<Material>(
      find.descendant(of: cover, matching: find.byType(Material)),
    )
    .shadowColor!
    .a;

void main() {
  for (final sort in BookSortOrder.values) {
    testWidgets('置顶、取消和重建页面保持排序，兼容分组与两种视图：${sort.label}', (tester) async {
      final library = LibraryStore.memory();
      final books = <BookEntry>[];
      await tester.runAsync(() async {
        for (final title in ['B书', 'A书', 'C书']) {
          books.add(await library.importBytes(buildTestEpub(title: title)));
        }
      });
      await library.setSetting('bookshelf.grid', 'false');
      await library.setSetting(bookshelfSortKey, sort.value);
      final group = await library.createGroup('置顶分组');

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

      Future<void> togglePin(BookEntry book, String label) async {
        await tester.longPress(find.text(book.title));
        await tester.pumpAndSettle();
        expect(find.text(label), findsOneWidget);
        expect(find.text('图书详情'), findsNothing);
        await tester.tap(find.byKey(const ValueKey('book-detail-pin')));
        await tester.pumpAndSettle();
      }

      await showShelf();
      final original = _titles(tester);
      final unpinnedCover = find.descendant(
        of: find.byKey(ValueKey('book-row-${books[0].id}')),
        matching: find.byType(BookCoverImage),
      );
      expect(_coverShadowOpacity(tester, unpinnedCover), closeTo(.12, .001));
      await togglePin(books[0], '置顶');
      final pinnedCover = find.descendant(
        of: find.byKey(ValueKey('book-row-${books[0].id}')),
        matching: find.byType(BookCoverImage),
      );
      expect(_coverShadowOpacity(tester, pinnedCover), closeTo(.42, .001));
      expect(_titles(tester), ['B书', ...original.where((t) => t != 'B书')]);
      await togglePin(books[1], '置顶');
      expect(_titles(tester), ['A书', 'B书', 'C书']);
      expect(jsonDecode((await library.getSetting('bookshelf.pinned'))!), [
        books[1].id,
        books[0].id,
      ]);

      await showShelf();
      expect(_titles(tester), ['A书', 'B书', 'C书']);
      final search = find.byKey(const ValueKey('bookshelf-search-field'));
      await tester.tap(search);
      await tester.enterText(search, 'B书');
      await tester.pumpAndSettle();
      expect(_titles(tester), ['B书']);
      await tester.enterText(search, 'C书');
      await tester.pumpAndSettle();
      expect(_titles(tester), ['C书']);
      await tester.tap(find.byTooltip('关闭搜索'));
      await tester.pumpAndSettle();
      expect(_titles(tester), ['A书', 'B书', 'C书']);
      expect(jsonDecode((await library.getSetting('bookshelf.pinned'))!), [
        books[1].id,
        books[0].id,
      ]);
      await library.setBooksGroup(
        books.take(2).map((book) => book.id),
        groupId: group.id,
      );
      await tester.pumpAndSettle();
      expect(_titles(tester), ['C书']);
      await tester.tap(find.text('置顶分组'));
      await tester.pumpAndSettle();
      expect(_titles(tester), ['A书', 'B书']);
      await tester.tap(find.byTooltip('网格视图'));
      await tester.pumpAndSettle();
      final pinnedGridCover = find.descendant(
        of: find.byKey(ValueKey('book-card-${books[1].id}')),
        matching: find.byType(BookCoverImage),
      );
      expect(_coverShadowOpacity(tester, pinnedGridCover), closeTo(.42, .001));
      final first = tester.getTopLeft(
        find.byKey(ValueKey('book-card-${books[1].id}')),
      );
      final second = tester.getTopLeft(
        find.byKey(ValueKey('book-card-${books[0].id}')),
      );
      expect(first.dy, second.dy);
      expect(first.dx, lessThan(second.dx));
      expect(find.byKey(ValueKey('book-card-${books[2].id}')), findsNothing);
      await tester.tap(find.byTooltip('列表视图'));
      await tester.pumpAndSettle();
      await togglePin(books[1], '取消置顶');
      expect(_titles(tester), ['B书', 'A书']);
      await tester.tap(find.text('默认'));
      await tester.pumpAndSettle();
      expect(_titles(tester), ['C书']);
      await library.setBooksGroup(books.take(2).map((book) => book.id));
      await tester.pumpAndSettle();
      expect(_titles(tester), ['B书', ...original.where((t) => t != 'B书')]);
      await togglePin(books[0], '取消置顶');
      expect(
        _coverShadowOpacity(
          tester,
          find.descendant(
            of: find.byKey(ValueKey('book-row-${books[0].id}')),
            matching: find.byType(BookCoverImage),
          ),
        ),
        closeTo(.12, .001),
      );
      expect(_titles(tester), original);
      await showShelf();
      expect(_titles(tester), original);
      expect(await library.getSetting('bookshelf.pinned'), '[]');
    });
  }
}
