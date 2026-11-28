import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/book_cover_stack.dart';
import 'package:reader_mobile/home/bookshelf_page.dart';
import 'package:reader_mobile/home/bookshelf_stacks.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/theme/app_theme.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/test_epub.dart';
import '../support/reader_pump.dart';

void main() {
  test('标签叠加开关兼容旧版已选标签，空配置默认关闭', () async {
    for (final scenario in [
      (raw: null, enabled: false),
      (raw: 'false', enabled: false),
      (raw: 'true', enabled: true),
      (raw: '{}', enabled: false),
      (raw: '{"default":[],"group":[]}', enabled: false),
      (raw: '{"default":[],"group":["tag"]}', enabled: true),
    ]) {
      final library = LibraryStore.memory();
      if (scenario.raw case final raw?) {
        await library.setSetting(bookshelfTagStacksKey, raw);
      }
      expect(
        await loadBookshelfTagStacking(library),
        scenario.enabled,
        reason: '配置：${scenario.raw}',
      );
    }
  });

  test('标签堆叠按标签顺序展示，多标签书可重复，未堆叠书保持原顺序', () {
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
      ['1', '2', '5'],
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
      ['1', '3'],
    ]);
    expect(reversed.map((stack) => stack.tag?.id), ['b', 'a']);
  });

  for (final grid in [true, false]) {
    testWidgets('历史分组内同书出现在三个标签堆叠，搜索与多选不重复：网格=$grid', (tester) async {
      tester.view.physicalSize = const Size(700, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final library = LibraryStore.memory();
      final books = <BookEntry>[];
      final tags = <BookTag>[];
      late ShelfGroup group;
      await tester.runAsync(() async {
        group = await library.createGroup('历史');
        for (final title in ['共同书', '穿越书', '明朝书', '寒门书', '其他分组书']) {
          books.add(await library.importBytes(buildTestEpub(title: title)));
        }
        await library.setBooksGroup(
          books.take(4).map((book) => book.id),
          groupId: group.id,
        );
        for (final name in ['穿越', '明朝', '寒门']) {
          tags.add(await library.createTag(name));
        }
        for (var i = 0; i < tags.length; i++) {
          await library.addBookTag(books.first.id, tags[i].id);
          await library.addBookTag(books[i + 1].id, tags[i].id);
        }
        await library.addBookTag(books.last.id, tags.first.id);
        await library.setSetting('bookshelf.grid', '$grid');
        await library.setSetting(
          bookshelfTagStacksKey,
          grid
              ? 'true'
              : jsonEncode({
                  group.id: [tags.first.id],
                }),
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: BookshelfPage(
            library: library,
            progressStore: MemoryReaderProgressStore(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('bookshelf-group-${group.id}')));
      await tester.pumpAndSettle();
      Finder book(BookEntry entry) =>
          find.byKey(ValueKey('book-${grid ? 'card' : 'row'}-${entry.id}'));
      expect(find.byType(BookCoverStack), findsNWidgets(3));
      expect(
        tester
            .widgetList<BookCoverStack>(find.byType(BookCoverStack))
            .map((stack) => stack.books.map((book) => book.title).toList()),
        [
          unorderedEquals(['共同书', '穿越书']),
          unorderedEquals(['共同书', '明朝书']),
          unorderedEquals(['共同书', '寒门书']),
        ],
      );
      for (var i = 0; i < tags.length; i++) {
        await tester.tap(find.byKey(ValueKey('book-stack-${tags[i].id}')));
        await tester.pumpAndSettle();
        expect(book(books.first), findsOneWidget);
        expect(book(books[i + 1]), findsOneWidget);
        expect(book(books.last), findsNothing);
        await tester.tap(find.byKey(const ValueKey('bookshelf-stack-back')));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const ValueKey('bookshelf-multi-select')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('bookshelf-select-all')));
      await tester.pumpAndSettle();
      expect(find.text('已选 4 本'), findsOneWidget);
      await tester.tap(find.byTooltip('退出多选'));
      await tester.pumpAndSettle();
      final search = find.byKey(const ValueKey('bookshelf-search-field'));
      await tester.tap(search);
      await tester.enterText(search, '共同书');
      await tester.pumpAndSettle();
      expect(book(books.first), findsOneWidget);
      expect(find.byType(BookCoverStack), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final grid in [true, false]) {
    testWidgets('分组内同标签自动堆叠，可展开、搜索、多选与恢复：网格=$grid', (tester) async {
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
        await library.setSetting(bookshelfTagStacksKey, 'true');
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
      expect(stack, findsOneWidget);
      expect(find.byKey(const ValueKey('bookshelf-tag-stacks')), findsNothing);
      expect(find.text('小说 · 2 本'), findsNothing);
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
      expect(stack, findsOneWidget, reason: '重新打开保留统一叠加开关');
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

      late BookTag newTag;
      await pumpReaderTask(tester, () async {
        newTag = await library.createTag('新标签');
        await library.addBookTag(books[0].id, newTag.id);
        await library.addBookTag(books[3].id, newTag.id);
      }());
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('book-stack-${newTag.id}')),
        findsOneWidget,
        reason: '新标签无需选择，达到两本后自动叠加',
      );

      await pumpReaderTask(tester, () async {
        await library.addBookTag(books[3].id, tag.id);
        await library.setBooksGroup([books[3].id], groupId: group.id);
      }());
      await tester.tap(find.byKey(ValueKey('bookshelf-group-${group.id}')));
      await tester.pumpAndSettle();
      expect(stack, findsOneWidget, reason: '其他分组达到两本时也自动叠加');
      expect(
        find.byKey(ValueKey('book-stack-${newTag.id}')),
        findsNothing,
        reason: '不同分组中同标签各一本，不跨组叠加',
      );
      await tester.tap(stack);
      await tester.pumpAndSettle();
      expect(book(books[2]), findsOneWidget);
      expect(book(books[3]), findsOneWidget);
      expect(book(books[0]), findsNothing);
      expect(await library.getSetting(bookshelfTagStacksKey), 'true');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('隐藏书名时堆叠无标签和书数横条，保留语义及键盘展开收起', (tester) async {
    final library = LibraryStore.memory();
    late BookTag tag;
    await tester.runAsync(() async {
      tag = await library.createTag('文学');
      for (final title in ['第一本', '第二本']) {
        final book = await library.importBytes(buildTestEpub(title: title));
        await library.addBookTag(book.id, tag.id);
      }
      await library.setSetting('bookshelf.showTitles', 'false');
      await library.setSetting(bookshelfTagStacksKey, 'true');
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
      expect(find.text('文学 · 2 本'), findsNothing);
      expect(find.bySemanticsLabel('文学 · 2 本，点击展开'), findsOneWidget);
      final cover = find.descendant(
        of: stack,
        matching: find.byType(BookCoverStack),
      );
      expect(tester.getSize(cover).aspectRatio, closeTo(3 / 4, .001));
      final target = Focus.of(tester.element(cover));
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
