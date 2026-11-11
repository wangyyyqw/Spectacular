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
  testWidgets('书架用自定义分组替代状态标签，并支持移入与重命名', (tester) async {
    final library = LibraryStore.memory();
    late BookEntry first;
    late BookEntry second;
    late BookEntry third;
    await tester.runAsync(() async {
      first = await library.importBytes(
        buildTestEpub(title: '分组甲', identifier: 'widget-group-a'),
      );
      second = await library.importBytes(
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

    expect(find.text('全部 3'), findsNothing);
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
    await tester.tap(find.text('新建分组'));
    await _settle(tester, frames: 4);
    await tester.enterText(
      find.byKey(const ValueKey<String>('bookshelf-group-create-name')),
      '小说',
    );
    await tester.pump();
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(ValueKey<String>('bookshelf-group-book-${first.id}')),
          )
          .value,
      isTrue,
      reason: '长按的那本书应已预选',
    );
    await tester.tap(
      find.byKey(ValueKey<String>('bookshelf-group-book-${second.id}')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('bookshelf-group-create-confirm')),
    );
    await _settle(tester);

    expect(find.text('小说 2'), findsOneWidget);
    expect(find.text('分组甲'), findsWidgets);
    expect(find.text('分组乙'), findsWidgets);
    expect(find.text('分组丙'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey<String>('bookshelf-group-options')),
    );
    await _settle(tester, frames: 4);
    await tester.tap(find.text('退出分组'));
    await _settle(tester, frames: 4);
    expect(find.text('分组丙'), findsWidgets);

    await tester.longPress(
      find.byKey(ValueKey<String>('book-card-${third.id}')),
    );
    await _settle(tester, frames: 4);
    await tester.tap(find.text('多选'));
    await _settle(tester, frames: 4);
    expect(find.text('已选 1 本'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('bookshelf-batch-group')),
    );
    await _settle(tester, frames: 4);
    final group = (await library.listGroups()).single;
    await tester.tap(
      find.byKey(ValueKey<String>('bookshelf-group-pick-${group.id}')),
    );
    await _settle(tester);
    expect(find.text('已移入「小说」'), findsOneWidget);

    await tester.tap(
      find.byKey(ValueKey<String>('bookshelf-group-${group.id}')),
    );
    await _settle(tester, frames: 4);
    expect(find.text('小说 3'), findsOneWidget);
    expect(find.text('分组甲'), findsWidgets);
    expect(find.text('分组乙'), findsWidgets);
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
    expect(find.text('文学 3'), findsOneWidget);
  });

  testWidgets('多选底栏新建分组并预选已选书籍', (tester) async {
    final library = LibraryStore.memory();
    late BookEntry first;
    late BookEntry second;
    await tester.runAsync(() async {
      first = await library.importBytes(
        buildTestEpub(title: '新建甲', identifier: 'widget-new-group-a'),
      );
      second = await library.importBytes(
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

    await tester.longPress(
      find.byKey(ValueKey<String>('book-card-${first.id}')),
    );
    await _settle(tester, frames: 4);
    await tester.tap(find.text('多选'));
    await _settle(tester, frames: 4);
    expect(find.text('已选 1 本'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('bookshelf-batch-create-group')),
    );
    await _settle(tester, frames: 4);
    await tester.enterText(
      find.byKey(const ValueKey<String>('bookshelf-group-create-name')),
      '待读',
    );
    await tester.pump();
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(ValueKey<String>('bookshelf-group-book-${first.id}')),
          )
          .value,
      isTrue,
    );
    await tester.tap(
      find.byKey(ValueKey<String>('bookshelf-group-book-${second.id}')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('bookshelf-group-create-confirm')),
    );
    await _settle(tester);

    expect(find.text('待读 2'), findsOneWidget);
    final groups = await library.listGroups();
    expect(groups, hasLength(1));
    expect(await library.groupAssignments(), <String, String>{
      first.id: groups.single.id,
      second.id: groups.single.id,
    });
  });
}
