import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/book_cover_stack.dart';
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

class _PreferencesLibrary extends LibraryStore {
  _PreferencesLibrary() : super.memory();

  Completer<void>? pending;

  @override
  Future<String?> getSetting(String key) async {
    await pending?.future;
    return super.getSetting(key);
  }
}

void main() {
  testWidgets('返回书架读取相同偏好时不再次重建，偏好变化仍立即生效', (tester) async {
    final library = _PreferencesLibrary();
    final progress = MemoryReaderProgressStore();
    Widget app(int refresh) => MaterialApp(
      home: BookshelfPage(
        library: library,
        progressStore: progress,
        refreshToken: refresh,
      ),
    );
    await tester.pumpWidget(app(0));
    await tester.pumpAndSettle();
    library.pending = Completer<void>();
    await tester.pumpWidget(app(1));
    var rebuilds = 0;
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtBefore) {
      previous?.call(element, builtBefore);
      if (element.widget is BookshelfPage) rebuilds++;
    };
    try {
      library.pending!.complete();
      await tester.pumpAndSettle();
      expect(rebuilds, 0);
      await library.setSetting('bookshelf.grid', 'false');
      await tester.pumpWidget(app(2));
      await tester.pumpAndSettle();
      expect(find.byTooltip('网格视图'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      debugOnRebuildDirtyWidget = previous;
    }
  });

  testWidgets('“显示书名”只控制宫格，列表始终显示书名', (tester) async {
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
    final switchTile = find.byKey(
      const ValueKey<String>('bookshelf-title-setting'),
    );
    expect(tester.widget<SwitchListTile>(switchTile).value, isTrue);
    await tester.ensureVisible(switchTile);
    await tester.pumpAndSettle();
    await tester.tap(switchTile);
    await _settle(tester);
    expect(tester.widget<SwitchListTile>(switchTile).value, isFalse);
    expect(await library.getSetting(bookshelfShowTitlesKey), 'false');

    await tester.tap(find.text('书架'));
    await _settle(tester);
    for (final id in ids) {
      expect(cardTitle(id), findsNothing);
    }

    // 列表不受开关影响，始终显示书名。
    await tester.tap(find.byTooltip('列表视图'));
    await _settle(tester);
    for (final id in ids) {
      expect(rowTitle(id), findsOneWidget);
    }

    // 重新构建页面（≈ 重启）宫格保持隐藏，列表仍显示书名。
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
      expect(rowTitle(id), findsOneWidget);
    }
    await tester.tap(find.byTooltip('网格视图'));
    await _settle(tester);
    for (final id in ids) {
      expect(cardTitle(id), findsNothing);
    }
  });

  testWidgets('显示书名时宫格行间距缩至三分之一，封面尺寸及标题留白不变', (tester) async {
    tester.view
      ..physicalSize = const Size(390, 850)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final library = LibraryStore.memory();
    final books = <BookEntry>[];
    late BookTag tag;
    await tester.runAsync(() async {
      for (final title in ['A书', 'B书', 'C书', 'D书', 'E书']) {
        books.add(await library.importBytes(buildTestEpub(title: title)));
      }
      tag = await library.createTag('科幻');
      for (final book in books.take(2)) {
        await library.addBookTag(book.id, tag.id);
      }
      await library.setSetting(bookshelfSortKey, BookSortOrder.title.value);
      await library.setSetting(
        bookshelfTagStacksKey,
        jsonEncode({
          'default': [tag.id],
        }),
      );
    });
    final progress = MemoryReaderProgressStore();
    final coverSizes = <Size>[];
    final rowGaps = <double>[];
    for (final showTitles in [false, true]) {
      await library.setSetting(bookshelfShowTitlesKey, '$showTitles');
      await tester.pumpWidget(
        MaterialApp(
          home: BookshelfPage(
            library: library,
            progressStore: progress,
            refreshToken: showTitles ? 1 : 0,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final stack = find.byKey(ValueKey('book-stack-${tag.id}'));
      final firstRow = find.byKey(ValueKey('book-card-${books[2].id}'));
      final nextRow = find.byKey(ValueKey('book-card-${books.last.id}'));
      final cover = find.descendant(
        of: firstRow,
        matching: find.byKey(const ValueKey('book-card-cover')),
      );
      coverSizes.add(tester.getSize(cover));
      expect(
        tester.getSize(
          find.descendant(of: stack, matching: find.byType(BookCoverStack)),
        ),
        coverSizes.last,
      );
      expect(
        tester.getSize(firstRow).height - coverSizes.last.height,
        closeTo(showTitles ? 26 : 0, .01),
      );
      expect(tester.getBottomLeft(stack).dy, tester.getBottomLeft(firstRow).dy);
      rowGaps.add(
        tester.getTopLeft(nextRow).dy - tester.getBottomLeft(firstRow).dy,
      );
    }
    expect(coverSizes.last, coverSizes.first);
    expect(rowGaps.first, closeTo(20, .01));
    expect(rowGaps.last, closeTo(rowGaps.first / 3, .01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('开启显示书名后标签堆叠恢复名称，列表不随开关隐藏，长名称大字无溢出', (tester) async {
    tester.view
      ..physicalSize = const Size(390, 850)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final library = LibraryStore.memory();
    final books = <BookEntry>[];
    late BookTag tag;
    await tester.runAsync(() async {
      tag = await library.createTag('文学与历史中的长标签分组名称');
      for (final title in ['堆叠甲', '堆叠乙', '单本书']) {
        books.add(await library.importBytes(buildTestEpub(title: title)));
      }
      for (final book in books.take(2)) {
        await library.addBookTag(book.id, tag.id);
      }
      await library.setSetting(bookshelfShowTitlesKey, 'false');
      await library.setSetting(
        bookshelfTagStacksKey,
        jsonEncode({
          'default': [tag.id],
        }),
      );
    });
    final progress = MemoryReaderProgressStore();
    Future<void> show(int refresh) async {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: BookshelfPage(
            library: library,
            progressStore: progress,
            refreshToken: refresh,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    final stack = find.byKey(ValueKey('book-stack-${tag.id}'));
    final title = find.byKey(ValueKey('book-stack-title-${tag.id}'));
    final bookTitle = find.byKey(ValueKey('book-card-title-${books.last.id}'));
    await show(0);
    expect(stack, findsOneWidget);
    expect(title, findsNothing);
    await library.setSetting(bookshelfShowTitlesKey, 'true');
    await show(1);
    expect(title, findsOneWidget);
    expect(tester.widget<Text>(title).data, tag.name);
    expect(tester.widget<Text>(title).maxLines, 1);
    expect(tester.widget<Text>(title).overflow, TextOverflow.ellipsis);
    expect(
      tester.widget<Text>(title).style,
      tester.widget<Text>(bookTitle).style,
    );
    expect(
      tester.getCenter(title).dy,
      closeTo(tester.getCenter(bookTitle).dy, .01),
    );
    final cover = find.descendant(
      of: stack,
      matching: find.byType(BookCoverStack),
    );
    expect(
      tester.getBottomLeft(title).dy,
      lessThanOrEqualTo(tester.getBottomLeft(stack).dy),
    );
    expect(
      tester.getTopLeft(title).dy,
      greaterThan(tester.getBottomLeft(cover).dy),
    );
    await tester.tap(find.byTooltip('列表视图'));
    await tester.pumpAndSettle();
    expect(title, findsOneWidget);
    await library.setSetting(bookshelfShowTitlesKey, 'false');
    await show(2);
    expect(title, findsOneWidget, reason: '列表名称与普通书名一样始终显示');
    await tester.tap(find.byTooltip('网格视图'));
    await tester.pumpAndSettle();
    expect(title, findsNothing);
    expect(bookTitle, findsNothing);
    await library.setSetting(bookshelfShowTitlesKey, 'true');
    await show(3);
    expect(title, findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await show(3);
    expect(title, findsOneWidget, reason: '重新打开保留显示设置');
    expect(tester.takeException(), isNull);
  });
}
