import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/bookshelf_page.dart';
import 'package:reader_mobile/library/library_store.dart';

import '../support/test_epub.dart';

import 'package:reader_ui/reader_session.dart';

Future<void> _settle(WidgetTester tester, {int frames = 12}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
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

    // 全部页向右不循环；短距离和纵向滑动不切换。
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
    await tester.drag(pages, const Offset(-180, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final grids = find.byKey(const ValueKey('bookshelf-grid'));
    expect(grids, findsNWidgets(2));
    expect(tester.getTopLeft(grids.first).dx, lessThan(0));
    expect(tester.getTopLeft(grids.last).dx, greaterThan(0));
    expect(grids.first.hitTestable(), findsNothing);
    await tester.pump(const Duration(milliseconds: 125));
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
      final tab = tester.getRect(
        find.byKey(ValueKey('bookshelf-group-${group.id}')),
      );
      final bar = tester.getRect(find.byType(SingleChildScrollView).first);
      expect(tab.left, greaterThanOrEqualTo(bar.left));
      expect(tab.right, lessThanOrEqualTo(bar.right));
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
      await _settle(tester, frames: 3);
    }
    expect(find.text('滑动乙'), findsWidgets);
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
    expect(find.byTooltip('分组选项'), findsOneWidget);
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

    expect(find.text('全部 3'), findsOneWidget);
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

    expect(find.text('小说 1'), findsOneWidget);
    final allTab = tester.getRect(
      find.byKey(const ValueKey('bookshelf-group-all')),
    );
    expect(allTab.left, 16);
    expect(
      tester.getTopLeft(find.text('小说 1')).dx,
      greaterThanOrEqualTo(allTab.right),
    );
    expect(find.text('分组甲'), findsWidgets);
    expect(find.text('分组乙'), findsNothing);
    expect(find.text('分组丙'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey<String>('bookshelf-group-options')),
    );
    await _settle(tester, frames: 4);
    await tester.tap(find.text('退出分组'));
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
    expect(find.text('小说 2'), findsOneWidget);
    expect(find.text('分组甲'), findsWidgets);
    expect(find.text('分组乙'), findsNothing);
    expect(find.text('分组丙'), findsWidgets);

    await tester.tap(
      find.byKey(const ValueKey<String>('bookshelf-group-options')),
    );
    await _settle(tester, frames: 4);
    await tester.tap(find.text('管理当前分组'));
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
    expect(find.text('文学 2'), findsOneWidget);
  });

  testWidgets('多选底栏新建分组直接使用已选书籍', (tester) async {
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

    expect(find.text('待读 1'), findsOneWidget);
    final groups = await library.listGroups();
    expect(groups, hasLength(1));
    expect(await library.groupAssignments(), <String, String>{
      first.id: groups.single.id,
    });
  });

  testWidgets('长按分组仅移动当前书籍，也可为当前书籍新建分组', (tester) async {
    final library = LibraryStore.memory();
    final books = <BookEntry>[];
    await tester.runAsync(() async {
      for (final title in ['当前书籍', '其他书籍']) {
        books.add(await library.importBytes(buildTestEpub(title: title)));
      }
    });
    final original = await library.createGroup('原分组');
    final target = await library.createGroup('待读');
    await library.setBooksGroup(
      books.map((book) => book.id),
      groupId: original.id,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: BookshelfPage(
          library: library,
          progressStore: MemoryReaderProgressStore(),
        ),
      ),
    );
    await _settle(tester);
    await tester.longPress(find.byKey(ValueKey('book-card-${books.first.id}')));
    await _settle(tester);
    await tester.tap(find.text('分组'));
    await _settle(tester);
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.text('当前分组'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('bookshelf-book-group-${target.id}')));
    await _settle(tester);
    expect(await library.groupAssignments(), {
      books.first.id: target.id,
      books.last.id: original.id,
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
      books.last.id: original.id,
    });
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
