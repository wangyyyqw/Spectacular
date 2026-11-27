import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/bookshelf_page.dart';
import 'package:reader_mobile/home/bookshelf_stacks.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/theme/app_theme.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/test_epub.dart';
import '../support/reader_pump.dart';

void main() {
  test('堆叠按标签优先级认领、占首本位置、单本与未选标签保持原顺序', () {
    final tags = [
      for (final id in ['a', 'b', 'c'])
        BookTag(id: id, name: id, createdAt: DateTime(2026)),
    ];
    final stacks = stackBooksByTags(
      books: ['1', '2', '3', '4', '5', '6', '7'],
      bookId: (book) => book,
      bookTags: {
        '1': {'a', 'b'},
        '2': {'b'},
        '3': {'a'},
        '4': {'a'},
        '5': {'b'},
        '6': {'c'},
      },
      tags: tags,
    );
    expect(stacks.map((stack) => stack.books), [
      ['1', '3', '4'],
      ['2', '5'],
      ['6'],
      ['7'],
    ]);
    expect(stacks.map((stack) => stack.tag?.id), ['a', 'b', null, null]);
    expect(stacks.expand((stack) => stack.books).toSet(), hasLength(7));
    final reversed = stackBooksByTags(
      books: ['1', '2', '3'],
      bookId: (book) => book,
      bookTags: {
        '1': {'a', 'b'},
        '2': {'b'},
        '3': {'a'},
      },
      tags: tags.reversed.toList(),
    );
    expect(reversed.map((stack) => stack.books), [
      ['1', '2'],
      ['3'],
    ]);
  });

  for (final grid in [true, false]) {
    testWidgets('分组内标签堆叠可设置、展开、搜索、多选与恢复：网格=$grid', (tester) async {
      tester.view
        ..physicalSize = const Size(390, 850)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final library = LibraryStore.memory();
      final books = <BookEntry>[];
      late BookTag tag;
      late ShelfGroup group;
      await tester.runAsync(() async {
        for (final title in ['甲书', '乙书', '丙书', '丁书']) {
          books.add(await library.importBytes(buildTestEpub(title: title)));
        }
        tag = await library.createTag('小说');
        for (final book in books.take(3)) {
          await library.addBookTag(book.id, tag.id);
        }
        group = await library.createGroup('另一个书架');
        await library.setBooksGroup([books[2].id], groupId: group.id);
        await library.setSetting('bookshelf.grid', '$grid');
      });
      Future<void> show() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(),
            home: BookshelfPage(
              key: UniqueKey(),
              library: library,
              progressStore: MemoryReaderProgressStore(),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      Finder book(BookEntry entry) =>
          find.byKey(ValueKey('book-${grid ? 'card' : 'row'}-${entry.id}'));
      final stack = find.byKey(ValueKey('book-stack-${tag.id}'));
      await show();
      expect(stack, findsNothing);
      await tester.tap(find.byKey(const ValueKey('bookshelf-tag-stacks')));
      await tester.pumpAndSettle();
      expect(find.text('仅应用于「默认分组」'), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('stack-tag-option-${tag.id}')));
      await tester.tap(find.byKey(const ValueKey('tag-stacks-save')));
      await tester.pumpAndSettle();
      expect(stack, findsOneWidget);
      expect(find.text('小说 · 2 本'), findsOneWidget);
      expect(book(books[0]), findsNothing);
      expect(book(books[1]), findsNothing);
      expect(book(books[2]), findsNothing);
      expect(book(books[3]), findsOneWidget);
      final originalGroup = await library.groupAssignments();
      await tester.tap(stack);
      await tester.pumpAndSettle();
      expect(book(books[0]), findsOneWidget);
      expect(book(books[1]), findsOneWidget);
      expect(book(books[3]), findsNothing);
      await tester.tap(find.byKey(const ValueKey('bookshelf-stack-back')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('bookshelf-multi-select')));
      await tester.pumpAndSettle();
      expect(stack, findsNothing);
      await tester.tap(find.byKey(const ValueKey('bookshelf-select-all')));
      await tester.pumpAndSettle();
      expect(find.text('已选 3 本'), findsOneWidget);
      await tester.tap(find.byTooltip('退出多选'));
      await tester.pumpAndSettle();
      expect(stack, findsOneWidget);
      final search = find.byKey(const ValueKey('bookshelf-search-field'));
      await tester.tap(search);
      await tester.enterText(search, '甲书');
      await tester.pumpAndSettle();
      expect(stack, findsNothing);
      expect(book(books[0]), findsOneWidget);
      await tester.tap(find.byTooltip('关闭搜索'));
      await tester.pumpAndSettle();
      expect(stack, findsOneWidget);
      await tester.tap(find.byKey(ValueKey('bookshelf-group-${group.id}')));
      await tester.pumpAndSettle();
      expect(stack, findsNothing);
      expect(book(books[2]), findsOneWidget);
      await show();
      expect(stack, findsOneWidget, reason: '重新打开保留每组堆叠偏好');
      expect(await library.groupAssignments(), originalGroup);
      final assignments = await library.bookTagAssignments();
      assignments[books.first.id]!.clear();
      expect((await library.bookTags(books.first.id)).single.id, tag.id);
      await pumpReaderTask(tester, library.removeBookTag(books[0].id, tag.id));
      await tester.pumpAndSettle();
      expect(stack, findsNothing, reason: '仅剩一本时恢复单本显示');
      await pumpReaderTask(tester, library.addBookTag(books[0].id, tag.id));
      await tester.pumpAndSettle();
      expect(stack, findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('bookshelf-tag-stacks')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tag-stacks-clear')));
      await tester.tap(find.byKey(const ValueKey('tag-stacks-save')));
      await tester.pumpAndSettle();
      expect(stack, findsNothing);
      expect(jsonDecode((await library.getSetting(bookshelfTagStacksKey))!), {
        'default': <String>[],
      });
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('隐藏书名仍显示堆叠标签，键盘展开及收起可用', (tester) async {
    final library = LibraryStore.memory();
    late BookTag tag;
    await tester.runAsync(() async {
      tag = await library.createTag('文学');
      for (final title in ['第一本', '第二本']) {
        final book = await library.importBytes(buildTestEpub(title: title));
        await library.addBookTag(book.id, tag.id);
      }
      await library.setSetting('bookshelf.showTitles', 'false');
      await library.setSetting(
        bookshelfTagStacksKey,
        jsonEncode({
          'default': [tag.id],
        }),
      );
    });
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme().copyWith(platform: TargetPlatform.macOS),
          home: BookshelfPage(
            library: library,
            progressStore: MemoryReaderProgressStore(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final stack = find.byKey(ValueKey('book-stack-${tag.id}'));
      expect(find.text('文学 · 2 本'), findsOneWidget);
      expect(find.bySemanticsLabel('文学 · 2 本，点击展开'), findsOneWidget);
      final target = Focus.of(tester.element(find.text('文学 · 2 本')));
      for (var attempt = 0; attempt < 12 && !target.hasFocus; attempt++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(target.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('bookshelf-stack-back')),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(stack, findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });
}
