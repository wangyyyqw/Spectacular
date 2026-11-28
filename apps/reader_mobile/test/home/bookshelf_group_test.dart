import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/bookshelf_page.dart';
import 'package:reader_mobile/home/bookshelf_sort.dart';
import 'package:reader_mobile/home/book_cover_image.dart';
import 'package:reader_mobile/library/library_store.dart';

import '../support/test_epub.dart';

import 'package:reader_ui/reader_session.dart';

Future<void> _settle(WidgetTester tester, {int frames = 12}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('默认保持首位且不可拖动，旧顺序只用于自定义分组并保留选中项', (tester) async {
    final library = LibraryStore.memory();
    await tester.runAsync(() async {
      await library.importBytes(buildTestEpub(title: '默认书籍'));
    });
    final first = await library.createGroup('收藏');
    final second = await library.createGroup('待读');
    final legacyOrder = [first.id, null, second.id];
    await library.setSetting(bookshelfGroupOrderKey, jsonEncode(legacyOrder));
    Widget page() => MaterialApp(
      home: BookshelfPage(
        library: library,
        progressStore: MemoryReaderProgressStore(),
      ),
    );
    await tester.pumpWidget(page());
    await _settle(tester);
    final custom = find.text('待读');
    final defaultTab = find.text('默认');
    expect(
      tester.getCenter(defaultTab).dx,
      lessThan(tester.getCenter(find.text('收藏')).dx),
    );
    expect(
      find.ancestor(
        of: defaultTab,
        matching: find.byType(ReorderableDelayedDragStartListener),
      ),
      findsNothing,
    );
    final ink = tester.widget<InkWell>(
      find.ancestor(of: custom, matching: find.byType(InkWell)).first,
    );
    expect(ink.splashFactory, NoSplash.splashFactory);
    expect(ink.highlightColor, Colors.transparent);
    Future<void> dragTab(Finder tab, Offset end) async {
      final start = tester.getCenter(tab);
      final drag = await tester.startGesture(start);
      await tester.pump(const Duration(milliseconds: 600));
      for (var step = 1; step <= 8; step++) {
        await drag.moveTo(Offset.lerp(start, end, step / 8)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pumpAndSettle();
      await drag.up();
      await tester.pumpAndSettle();
    }

    await dragTab(defaultTab, tester.getCenter(custom));
    expect(
      jsonDecode((await library.getSetting(bookshelfGroupOrderKey))!),
      legacyOrder,
    );
    expect(find.byType(BottomSheet), findsNothing);
    await tester.tap(custom);
    await _settle(tester);
    await dragTab(custom, tester.getCenter(defaultTab));
    expect(find.byType(BottomSheet), findsNothing);
    expect(
      tester.getCenter(custom).dx,
      greaterThan(tester.getCenter(defaultTab).dx),
    );
    expect(
      tester.getCenter(custom).dx,
      lessThan(tester.getCenter(find.text('收藏')).dx),
    );
    expect(tester.widget<Text>(custom).style?.fontWeight, FontWeight.w600);
    expect(jsonDecode((await library.getSetting(bookshelfGroupOrderKey))!), [
      second.id,
      first.id,
    ]);
    await tester.drag(
      find.byKey(const ValueKey('bookshelf-group-pages')),
      const Offset(240, 0),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(defaultTab).style?.fontWeight, FontWeight.w600);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(page());
    await _settle(tester);
    expect(
      tester.getCenter(custom).dx,
      greaterThan(tester.getCenter(defaultTab).dx),
    );
    expect(
      tester.getCenter(custom).dx,
      lessThan(tester.getCenter(find.text('收藏')).dx),
    );
    await tester.longPress(custom);
    await tester.pumpAndSettle();
    expect(find.text('重命名分组'), findsOneWidget);
  });

  testWidgets('空书架隐藏默认，导入后显示，移走最后一本后切换到首个可见分组', (tester) async {
    final library = LibraryStore.memory();
    await tester.pumpWidget(
      MaterialApp(
        home: BookshelfPage(
          library: library,
          progressStore: MemoryReaderProgressStore(),
        ),
      ),
    );
    await _settle(tester);
    final defaultTab = find.byKey(const ValueKey('bookshelf-group-default'));
    expect(defaultTab, findsNothing);
    expect(find.text('书架还是空的'), findsOneWidget);
    late BookEntry book;
    await tester.runAsync(() async {
      book = await library.importBytes(buildTestEpub(title: '唯一书籍'));
    });
    await _settle(tester);
    expect(find.text('默认'), findsOneWidget);
    expect(find.byKey(ValueKey('book-card-${book.id}')), findsOneWidget);
    final first = await library.createGroup('收藏');
    final second = await library.createGroup('待读');
    await library.setSetting(
      bookshelfGroupOrderKey,
      jsonEncode([second.id, null, first.id]),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MaterialApp(
        home: BookshelfPage(
          library: library,
          progressStore: MemoryReaderProgressStore(),
        ),
      ),
    );
    await _settle(tester);
    await library.setBooksGroup([book.id], groupId: first.id);
    await _settle(tester);
    expect(defaultTab, findsNothing);
    expect(
      tester.widget<Text>(find.text('待读')).style?.fontWeight,
      FontWeight.w600,
    );
    expect(find.textContaining('「待读」'), findsOneWidget);
    final pages = find.byKey(const ValueKey('bookshelf-group-pages'));
    await tester.drag(pages, const Offset(240, 0));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.text('待读')).style?.fontWeight,
      FontWeight.w600,
    );
    await tester.drag(pages, const Offset(-240, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('book-card-${book.id}')), findsOneWidget);
    await library.setBooksGroup([book.id]);
    await _settle(tester);
    expect(defaultTab, findsOneWidget);
    expect(
      tester.widget<Text>(find.text('收藏')).style?.fontWeight,
      FontWeight.w600,
    );
    await tester.tap(defaultTab);
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('bookshelf-search-field'));
    await tester.tap(search);
    await tester.enterText(search, '不存在');
    await tester.pumpAndSettle();
    expect(defaultTab, findsOneWidget, reason: '搜索无结果不等于默认没有书籍');
    expect(find.text('没有找到相关书籍'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭搜索'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => library.remove(book.id));
    await _settle(tester);
    expect(defaultTab, findsNothing);
    expect(
      tester.widget<Text>(find.text('待读')).style?.fontWeight,
      FontWeight.w600,
    );
    await tester.longPress(find.text('待读'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除分组'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(defaultTab, findsNothing);
    expect(find.text('待读'), findsNothing);
    expect(
      tester.widget<Text>(find.text('收藏')).style?.fontWeight,
      FontWeight.w600,
    );
    expect(tester.takeException(), isNull);
  });

  for (final grid in [true, false]) {
    testWidgets('分组互斥、单本和批量移回默认分组，删除分组保留书籍：网格=$grid', (tester) async {
      final library = LibraryStore.memory();
      final books = <BookEntry>[];
      await tester.runAsync(() async {
        for (final title in ['甲书', '乙书', '丙书']) {
          books.add(await library.importBytes(buildTestEpub(title: title)));
        }
      });
      final first = await library.createGroup('小说');
      final second = await library.createGroup('散文');
      await library.setBooksGroup(
        books.take(2).map((book) => book.id),
        groupId: first.id,
      );
      await library.setBooksGroup([books.last.id], groupId: second.id);
      await library.setSetting('bookshelf.grid', '$grid');
      Future<void> show() async {
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

      Future<void> select(String? id) async {
        await tester.tap(
          find.byKey(ValueKey('bookshelf-group-${id ?? 'default'}')),
        );
        await tester.pumpAndSettle();
      }

      void expectBooks(List<BookEntry> expected) {
        for (final book in books) {
          expect(
            find.byKey(ValueKey('book-${grid ? 'card' : 'row'}-${book.id}')),
            expected.contains(book) ? findsOneWidget : findsNothing,
          );
        }
      }

      await show();
      expect(
        find.byKey(const ValueKey('bookshelf-group-default')),
        findsNothing,
      );
      expect(find.text('全部'), findsNothing);
      expect(find.text('查看全部书籍'), findsNothing);
      expectBooks(books.take(2).toList());
      await select(first.id);
      expectBooks(books.take(2).toList());
      await select(first.id);
      expectBooks(books.take(2).toList());

      final search = find.byKey(const ValueKey('bookshelf-search-field'));
      await tester.tap(search);
      await tester.enterText(search, '不存在');
      await tester.pumpAndSettle();
      await tester.tap(find.text('清除筛选'));
      await tester.pumpAndSettle();
      expectBooks(books.take(2).toList());

      await tester.longPress(find.text(books.first.title).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('分组'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('bookshelf-book-group-default')),
      );
      await tester.pumpAndSettle();
      expectBooks([books.first]);
      await select(first.id);
      expectBooks([books[1]]);

      await tester.tap(find.byTooltip('多选'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(books[1].title).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('bookshelf-batch-group')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('bookshelf-book-group-default')),
      );
      await tester.pumpAndSettle();
      expectBooks(books.take(2).toList());
      await select(first.id);
      expectBooks([]);
      await select(second.id);
      expectBooks([books.last]);

      await tester.longPress(
        find.byKey(ValueKey('bookshelf-group-${second.id}')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除分组'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();
      expectBooks(books);
      expect(await library.groupAssignments(), isEmpty);
      await show();
      expectBooks(books);
      expect(await library.list(), hasLength(3));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('内容区左右滑动切换分组，兼容空组、列表、多选及溢出标签', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final library = LibraryStore.memory();
    late BookEntry first;
    await tester.runAsync(() async {
      first = await library.importBytes(
        buildTestEpub(title: '滑动甲', identifier: 'swipe-a'),
      );
      await library.importBytes(
        buildTestEpub(title: '滑动乙', identifier: 'swipe-b'),
      );
    });
    final groups = <ShelfGroup>[
      for (var i = 1; i <= 5; i++) await library.createGroup('阅读分组$i'),
    ];
    await library.setBooksGroup([first.id], groupId: groups.first.id);
    await tester.pumpWidget(
      MaterialApp(
        home: BookshelfPage(
          library: library,
          progressStore: MemoryReaderProgressStore(),
        ),
      ),
    );
    await _settle(tester);
    final pages = find.byKey(const ValueKey('bookshelf-group-pages'));
    final defaultTab = find.byKey(
      const ValueKey('bookshelf-group-default'),
      skipOffstage: false,
    );
    final defaultBounds = tester.getRect(defaultTab);
    final groupBar = find.byKey(const ValueKey('bookshelf-group-strip'));
    await tester.drag(groupBar, const Offset(-180, 0));
    await tester.pumpAndSettle();
    expect(
      tester.getRect(defaultTab).left,
      lessThan(defaultBounds.left),
      reason: '默认与自定义分组共用滚动区域，不固定在屏幕边缘',
    );
    expect(find.text('滑动乙'), findsWidgets, reason: '滚动分组栏不改变选中分组');
    expect(await library.getSetting(bookshelfGroupOrderKey), isNull);
    await tester.drag(groupBar, const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(tester.getRect(defaultTab), defaultBounds);

    // 默认分组向右不循环；短距离和纵向滑动不切换。
    for (final offset in [
      const Offset(180, 0),
      const Offset(-32, 0),
      const Offset(0, -120),
    ]) {
      await tester.drag(pages, offset);
      await _settle(tester, frames: 3);
      expect(find.text('滑动乙'), findsWidgets);
      expect(find.byTooltip('分组选项'), findsNothing);
    }
    // 手指未松开时两页已按完整页面宽度联动，短拖动回弹。
    final start = tester.getTopLeft(
      find.byKey(const ValueKey('bookshelf-grid')),
    );
    final gesture = await tester.startGesture(tester.getCenter(pages));
    await gesture.moveBy(const Offset(-24, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-12, 0));
    await tester.pump();
    final draggingGrids = find.byKey(const ValueKey('bookshelf-grid'));
    expect(draggingGrids, findsNWidgets(2));
    expect(tester.getTopLeft(draggingGrids.first).dx, lessThan(start.dx));
    expect(
      tester.getTopLeft(draggingGrids.last).dx -
          tester.getTopLeft(draggingGrids.first).dx,
      closeTo(tester.getSize(pages).width, .01),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('滑动乙'), findsWidgets);
    expect(find.byKey(const ValueKey('bookshelf-grid')), findsOneWidget);

    await tester.drag(pages, const Offset(-180, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final grids = find.byKey(const ValueKey('bookshelf-grid'));
    expect(grids, findsNWidgets(2));
    expect(tester.getTopLeft(grids.first).dx, lessThan(0));
    expect(tester.getTopLeft(grids.last).dx, greaterThan(0));
    expect(grids.first.hitTestable(), findsNothing);
    final rebuiltCovers = <Element>[];
    final previousRebuild = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtBefore) {
      previousRebuild?.call(element, builtBefore);
      if (element.widget is BookCoverImage) rebuiltCovers.add(element);
    };
    try {
      for (var frame = 0; frame < 4; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(rebuiltCovers, isEmpty, reason: '分组动画只改变位置，不重复构建封面和书目');
    } finally {
      debugOnRebuildDirtyWidget = previousRebuild;
    }
    await tester.pump(const Duration(milliseconds: 61));
    expect(grids, findsOneWidget, reason: '分组过渡应在 200ms 内完成');
    await _settle(tester, frames: 3);
    expect(find.text('滑动甲'), findsWidgets);
    expect(find.text('滑动乙'), findsNothing);

    // 切换时保留查询，即使当前没有匹配项也能滑动。
    final search = find.byKey(const ValueKey('bookshelf-search-field'));
    await tester.tap(search);
    await tester.enterText(search, '滑动乙');
    tester.testTextInput.hide();
    await tester.pump();
    expect(find.text('没有找到相关书籍'), findsOneWidget);
    await tester.drag(pages, const Offset(-180, 0));
    await _settle(tester, frames: 3);
    expect(tester.widget<TextField>(search).controller!.text, '滑动乙');
    await tester.tap(find.byTooltip('关闭搜索'));
    await _settle(tester, frames: 3);
    expect(find.text('这个分组还没有书'), findsOneWidget);

    for (final group in groups.skip(2)) {
      await tester.drag(pages, const Offset(-180, 0));
      await _settle(tester, frames: 3);
      expect(find.textContaining('「${group.name}」'), findsOneWidget);
      await tester.pumpAndSettle();
      final tab = tester.getRect(
        find.byKey(ValueKey('bookshelf-group-${group.id}')),
      );
      final bar = tester.getRect(
        find.byKey(const ValueKey('bookshelf-group-strip')),
      );
      expect(tab.left, greaterThanOrEqualTo(bar.left));
      expect(tab.right, lessThanOrEqualTo(bar.right));
      expect(
        tester.getRect(defaultTab).left,
        lessThan(defaultBounds.left),
        reason: '切换到后面的分组时，默认随分组栏一起滚动',
      );
    }
    await tester.drag(pages, const Offset(-180, 0));
    await _settle(tester, frames: 3);
    expect(find.textContaining('「${groups.last.name}」'), findsOneWidget);

    // 空组也可向右返回；列表使用相同分组顺序。
    for (var i = 0; i < groups.length; i++) {
      await tester.drag(pages, const Offset(180, 0));
      if (i == groups.length - 1) {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        final grids = find.byKey(const ValueKey('bookshelf-grid'));
        expect(grids, findsNWidgets(2));
        expect(tester.getTopLeft(grids.first).dx, greaterThan(0));
        expect(tester.getTopLeft(grids.last).dx, lessThan(0));
      }
      await tester.pumpAndSettle();
    }
    expect(find.text('滑动乙'), findsWidgets);
    expect(tester.getRect(defaultTab), defaultBounds, reason: '切回默认时自动滚回首位');
    await tester.tap(find.byTooltip('列表视图'));
    await tester.pumpAndSettle();
    await tester.drag(pages, const Offset(-180, 0));
    await tester.pumpAndSettle();
    expect(find.text('滑动甲'), findsWidgets);
    expect(find.text('滑动乙'), findsNothing);
    expect(find.byKey(const ValueKey('bookshelf-list')), findsOneWidget);

    await tester.tap(find.byTooltip('多选'));
    await _settle(tester, frames: 3);
    await tester.tap(find.text('滑动甲').first);
    await _settle(tester, frames: 3);
    await tester.drag(pages, const Offset(-180, 0));
    await _settle(tester, frames: 3);
    expect(find.text('已选 1 本'), findsOneWidget);
    expect(find.text('滑动甲'), findsWidgets);
    expect(
      find.byKey(const ValueKey('bookshelf-search-field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('bookshelf-group-toolbar')),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('退出多选'));
    await _settle(tester, frames: 3);
    expect(find.text('滑动甲'), findsWidgets);
    expect(find.text('滑动乙'), findsNothing);
    expect(find.byTooltip('分组选项'), findsNothing);
  });

  testWidgets('书架用自定义分组替代状态标签，并支持移入与重命名', (tester) async {
    final library = LibraryStore.memory();
    late BookEntry first;
    late BookEntry third;
    await tester.runAsync(() async {
      first = await library.importBytes(
        buildTestEpub(title: '分组甲', identifier: 'widget-group-a'),
      );
      await library.importBytes(
        buildTestEpub(title: '分组乙', identifier: 'widget-group-b'),
      );
      third = await library.importBytes(
        buildTestEpub(title: '分组丙', identifier: 'widget-group-c'),
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        home: BookshelfPage(
          library: library,
          progressStore: MemoryReaderProgressStore(),
        ),
      ),
    );
    await _settle(tester);

    expect(find.text('默认'), findsOneWidget);
    expect(find.text('全部'), findsNothing);
    expect(find.text('未读 3'), findsNothing);
    expect(find.text('在读 0'), findsNothing);
    expect(find.text('已读完 0'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('bookshelf-group-create')),
      findsNothing,
    );

    await tester.longPress(
      find.byKey(ValueKey<String>('book-card-${first.id}')),
    );
    await _settle(tester, frames: 4);
    await tester.tap(find.text('分组'));
    await _settle(tester, frames: 4);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey<String>('bookshelf-group-create-name')),
      '小说',
    );
    await tester.pump();
    expect(find.byType(CheckboxListTile), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey<String>('bookshelf-group-create-confirm')),
    );
    await _settle(tester);

    expect(find.text('小说'), findsOneWidget);
    expect(find.textContaining('小说 '), findsNothing);
    final defaultTab = tester.getRect(
      find.byKey(const ValueKey('bookshelf-group-default')),
    );
    expect(defaultTab.left, 16);
    expect(
      tester.getTopLeft(find.text('小说')).dx,
      greaterThanOrEqualTo(defaultTab.right),
    );
    expect(find.text('分组甲'), findsWidgets);
    expect(find.text('分组乙'), findsNothing);
    expect(find.text('分组丙'), findsNothing);

    expect(find.text('退出分组'), findsNothing);
    expect(find.text('管理当前分组'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('bookshelf-group-default')));
    await _settle(tester, frames: 4);
    expect(find.text('分组甲'), findsNothing);
    expect(find.text('分组丙'), findsWidgets);

    await tester.tap(find.byTooltip('多选'));
    await _settle(tester, frames: 4);
    await tester.tap(find.byKey(ValueKey<String>('book-card-${third.id}')));
    await _settle(tester, frames: 4);
    expect(find.text('已选 1 本'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('bookshelf-search-field')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('bookshelf-group-toolbar')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('bookshelf-batch-group')),
    );
    await _settle(tester, frames: 4);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNothing);
    final group = (await library.listGroups()).single;
    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text(group.name),
      ),
    );
    await _settle(tester);
    expect(find.text('已移入「小说」'), findsNothing);

    await tester.tap(
      find.byKey(ValueKey<String>('bookshelf-group-${group.id}')),
    );
    await _settle(tester, frames: 4);
    expect(find.text('小说'), findsOneWidget);
    expect(find.text('分组甲'), findsWidgets);
    expect(find.text('分组乙'), findsNothing);
    expect(find.text('分组丙'), findsWidgets);

    expect(find.byTooltip('分组选项'), findsNothing);
    await tester.longPress(
      find.byKey(ValueKey<String>('bookshelf-group-${group.id}')),
    );
    await _settle(tester, frames: 4);
    await tester.tap(find.text('重命名分组'));
    await _settle(tester, frames: 4);
    await tester.enterText(
      find.byKey(const ValueKey<String>('bookshelf-group-name-field')),
      '文学',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('bookshelf-group-name-confirm')),
    );
    await _settle(tester);
    expect(find.text('文学'), findsOneWidget);
  });

  testWidgets('搜索后多选新建分组清空输入并保留已选书籍', (tester) async {
    final library = LibraryStore.memory();
    late BookEntry first;
    await tester.runAsync(() async {
      first = await library.importBytes(
        buildTestEpub(title: '新建甲', identifier: 'widget-new-group-a'),
      );
      await library.importBytes(
        buildTestEpub(title: '新建乙', identifier: 'widget-new-group-b'),
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        home: BookshelfPage(
          library: library,
          progressStore: MemoryReaderProgressStore(),
        ),
      ),
    );
    await _settle(tester);

    final search = find.byKey(const ValueKey('bookshelf-search-field'));
    await tester.tap(search);
    await tester.enterText(search, '新建甲');
    await _settle(tester, frames: 3);
    expect(find.text('新建乙'), findsNothing);

    await tester.tap(find.byTooltip('多选'));
    await _settle(tester, frames: 4);
    await tester.tap(find.byKey(ValueKey<String>('book-card-${first.id}')));
    await _settle(tester, frames: 4);
    expect(find.text('已选 1 本'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('bookshelf-batch-create-group')),
    );
    await _settle(tester, frames: 4);
    await tester.enterText(
      find.byKey(const ValueKey<String>('bookshelf-group-name-field')),
      '待读',
    );
    await tester.pump();
    expect(find.byType(CheckboxListTile), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey<String>('bookshelf-group-name-confirm')),
    );
    await _settle(tester);

    expect(tester.widget<TextField>(search).controller!.text, isEmpty);
    expect(find.text('待读'), findsOneWidget);
    expect(find.text('新建甲'), findsWidgets);
    expect(find.text('新建乙'), findsNothing);
    final groups = await library.listGroups();
    expect(groups, hasLength(1));
    expect(await library.groupAssignments(), <String, String>{
      first.id: groups.single.id,
    });
    await tester.tap(find.byKey(const ValueKey('bookshelf-group-default')));
    await tester.pumpAndSettle();
    expect(find.text('新建甲'), findsNothing);
    expect(find.text('新建乙'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('搜索后移入现有分组清空输入，可继续为当前书籍新建分组', (tester) async {
    final library = LibraryStore.memory();
    final books = <BookEntry>[];
    await tester.runAsync(() async {
      for (final title in ['当前书籍', '其他书籍', '已有书籍']) {
        books.add(await library.importBytes(buildTestEpub(title: title)));
      }
    });
    final original = await library.createGroup('原分组');
    final target = await library.createGroup('待读');
    await library.setBooksGroup(
      books.take(2).map((book) => book.id),
      groupId: original.id,
    );
    await library.setBooksGroup([books.last.id], groupId: target.id);
    await tester.pumpWidget(
      MaterialApp(
        home: BookshelfPage(
          library: library,
          progressStore: MemoryReaderProgressStore(),
        ),
      ),
    );
    await _settle(tester);
    await tester.tap(find.byKey(ValueKey('bookshelf-group-${original.id}')));
    await _settle(tester, frames: 3);
    final search = find.byKey(const ValueKey('bookshelf-search-field'));
    await tester.tap(search);
    await tester.enterText(search, '当前');
    await _settle(tester, frames: 3);
    expect(find.text('其他书籍'), findsNothing);
    expect(find.text('已有书籍'), findsNothing);
    await tester.longPress(find.byKey(ValueKey('book-card-${books.first.id}')));
    await _settle(tester);
    await tester.tap(find.text('分组'));
    await _settle(tester);
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.text('当前分组'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('bookshelf-book-group-${target.id}')));
    await _settle(tester);
    expect(tester.widget<TextField>(search).controller!.text, isEmpty);
    expect(find.text('当前书籍'), findsWidgets);
    expect(find.text('已有书籍'), findsWidgets);
    expect(find.text('其他书籍'), findsNothing);
    expect(await library.groupAssignments(), {
      books.first.id: target.id,
      books[1].id: original.id,
      books.last.id: target.id,
    });
    expect(await library.listGroups(), hasLength(2));
    await tester.longPress(find.byKey(ValueKey('book-card-${books.first.id}')));
    await _settle(tester);
    await tester.tap(find.text('分组'));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('bookshelf-book-group-new')));
    await _settle(tester);
    expect(find.byType(CheckboxListTile), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('bookshelf-group-create-name')),
      '收藏',
    );
    await tester.pump();
    await tester.tap(find.text('创建并移入'));
    await _settle(tester);
    final created = (await library.listGroups()).singleWhere(
      (group) => group.name == '收藏',
    );
    expect(await library.groupAssignments(), {
      books.first.id: created.id,
      books[1].id: original.id,
      books.last.id: target.id,
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('小屏键盘弹出时新建分组抽屉保留输入和操作，取消不创建分组', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final library = LibraryStore.memory();
    late BookEntry book;
    await tester.runAsync(() async {
      book = await library.importBytes(buildTestEpub(title: '抽屉测试书籍'));
    });
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(1.3)),
          child: child!,
        ),
        home: BookshelfPage(
          library: library,
          progressStore: MemoryReaderProgressStore(),
        ),
      ),
    );
    await _settle(tester);
    await tester.longPress(find.byKey(ValueKey('book-card-${book.id}')));
    await _settle(tester);
    await tester.tap(find.text('分组'));
    await _settle(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    await _settle(tester);
    final confirm = find.byKey(
      const ValueKey('bookshelf-group-create-confirm'),
    );
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.enterText(
      find.byKey(const ValueKey('bookshelf-group-create-name')),
      '待读',
    );
    await tester.pump();
    expect(confirm.hitTestable(), findsOneWidget);
    expect(tester.getBottomLeft(confirm).dy, lessThanOrEqualTo(380));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('取消'));
    await _settle(tester);
    expect(
      find.byKey(const ValueKey('bookshelf-book-group-sheet')),
      findsNothing,
    );
    expect(await library.listGroups(), isEmpty);
  });
}
