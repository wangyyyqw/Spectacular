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
  testWidgets('默认分组可管理、重命名，并接收单书与批量移回', (tester) async {
    final library = LibraryStore.memory();
    final books = (await tester.runAsync(
      () async => [
        for (final title in ['甲书', '乙书', '丙书'])
          await library.importBytes(buildTestEpub(title: title)),
      ],
    ))!;
    final custom = await library.createGroup('收藏');
    await library.setBooksGroup(
      books.map((book) => book.id),
      groupId: custom.id,
    );
    await library.setSetting(bookshelfAllAsGroupKey, 'true');
    await tester.pumpWidget(
      MaterialApp(
        home: BookshelfPage(
          library: library,
          progressStore: MemoryReaderProgressStore(),
        ),
      ),
    );
    await _settle(tester);
    expect(find.text('这个分组还没有书'), findsOneWidget);
    await tester.longPress(find.text('默认'));
    await _settle(tester);
    expect(find.text('0 本书'), findsOneWidget);
    expect(find.text('删除分组'), findsNothing);
    await tester.tap(find.text('重命名分组'));
    await _settle(tester);
    await tester.enterText(find.byType(TextField).last, '收件箱');
    await tester.tap(
      find.byKey(const ValueKey('bookshelf-group-name-confirm')),
    );
    await _settle(tester);
    expect(await library.getSetting(bookshelfDefaultGroupNameKey), '收件箱');
    await tester.tap(find.text('收藏'));
    await _settle(tester);
    await tester.longPress(find.byKey(ValueKey('book-card-${books.first.id}')));
    await _settle(tester);
    await tester.tap(find.text('分组'));
    await _settle(tester);
    final target = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.text('收件箱'),
    );
    await tester.tap(target);
    await _settle(tester);
    expect(find.text('甲书'), findsWidgets);
    expect(find.text('乙书'), findsNothing);
    expect(
      (await library.groupAssignments()).keys,
      isNot(contains(books.first.id)),
    );
    await tester.tap(find.text('收藏'));
    await _settle(tester);
    await tester.tap(find.byTooltip('多选'));
    await _settle(tester);
    for (final book in books.skip(1)) {
      await tester.tap(find.byKey(ValueKey('book-card-${book.id}')));
      await _settle(tester);
    }
    await tester.tap(find.byKey(const ValueKey('bookshelf-batch-group')));
    await _settle(tester);
    expect(find.text('移出分组'), findsNothing);
    await tester.tap(target);
    await _settle(tester);
    expect(await library.groupAssignments(), isEmpty);
    expect((await library.listGroups()).single.id, custom.id);
    await tester.tap(find.text('收件箱'));
    await _settle(tester);
    for (final book in books) {
      expect(find.byKey(ValueKey('book-card-${book.id}')), findsOneWidget);
    }
  });

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
    for (var i = 1; i <= 5; i++) {
      await library.createGroup('阅读分组$i');
    }
    // 测试时钟固定，同一时间创建的分组按存储中的标识顺序排列。
    final groups = await library.listGroups();
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
    Future<void> dragPages(Offset offset) => tester.dragFrom(
      tester.getTopLeft(pages) + Offset(offset.dx < 0 ? 360 : 40, 60),
      offset,
    );

    // 全部页向右不循环；短距离和纵向滑动不切换。
    for (final offset in [
      const Offset(180, 0),
      const Offset(-32, 0),
      const Offset(0, -120),
    ]) {
      await dragPages(offset);
      await _settle(tester, frames: 3);
      expect(find.text('滑动乙'), findsWidgets);
      expect(find.byTooltip('分组选项'), findsNothing);
    }
    // 手指未松开时两页已按完整页面宽度联动，短拖动回弹。
    final start = tester.getTopLeft(
      find.byKey(const ValueKey('bookshelf-grid')),
    );
    final gesture = await tester.startGesture(
      tester.getTopLeft(pages) + const Offset(360, 60),
    );
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

    await dragPages(const Offset(-180, 0));
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
    await dragPages(const Offset(-180, 0));
    await _settle(tester, frames: 3);
    expect(tester.widget<TextField>(search).controller!.text, '滑动乙');
    await tester.tap(find.byTooltip('关闭搜索'));
    await _settle(tester, frames: 3);
    expect(find.text('这个分组还没有书'), findsOneWidget);

    for (final group in groups.skip(2)) {
      await dragPages(const Offset(-180, 0));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.text(group.name)).style?.fontWeight,
        FontWeight.w600,
      );
      final tab = tester.getRect(
        find.byKey(ValueKey('bookshelf-group-${group.id}')),
      );
      final bar = tester.getRect(find.byType(SingleChildScrollView).first);
      expect(tab.left, greaterThanOrEqualTo(bar.left));
      expect(tab.right, lessThanOrEqualTo(bar.right));
    }
    await dragPages(const Offset(-180, 0));
    await _settle(tester, frames: 3);
    expect(
      tester.widget<Text>(find.text(groups.last.name)).style?.fontWeight,
      FontWeight.w600,
    );

    // 空组也可向右返回；列表使用相同分组顺序。
    for (var i = 0; i < groups.length; i++) {
      await dragPages(const Offset(180, 0));
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
    await tester.tap(find.byTooltip('列表视图'));
    await tester.pumpAndSettle();
    await dragPages(const Offset(-180, 0));
    await tester.pumpAndSettle();
    expect(find.text('滑动甲'), findsWidgets);
    expect(find.text('滑动乙'), findsNothing);
    expect(find.byKey(const ValueKey('bookshelf-list')), findsOneWidget);

    await tester.tap(find.byTooltip('多选'));
    await _settle(tester, frames: 3);
    await tester.tap(find.text('滑动甲').first);
    await _settle(tester, frames: 3);
    await dragPages(const Offset(-180, 0));
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

    expect(find.text('全部'), findsOneWidget);
    expect(find.textContaining('全部 '), findsNothing);
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
    final allTab = tester.getRect(
      find.byKey(const ValueKey('bookshelf-group-all')),
    );
    expect(allTab.left, 16);
    expect(
      tester.getTopLeft(find.text('小说')).dx,
      greaterThanOrEqualTo(allTab.right),
    );
    expect(find.text('分组甲'), findsWidgets);
    expect(find.text('分组乙'), findsNothing);
    expect(find.text('分组丙'), findsNothing);

    expect(find.text('退出分组'), findsNothing);
    expect(find.text('管理当前分组'), findsNothing);
    await tester.tap(find.byKey(const ValueKey<String>('bookshelf-group-all')));
    await _settle(tester, frames: 4);
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
    await tester.tap(find.byKey(const ValueKey('bookshelf-group-all')));
    await _settle(tester, frames: 3);
    expect(find.text('新建甲'), findsWidgets);
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
