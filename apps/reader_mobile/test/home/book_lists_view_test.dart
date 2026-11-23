import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/bookshelf_page.dart';
import 'package:reader_mobile/home/reviews_page.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/theme/app_theme.dart';

import '../support/test_epub.dart';

import 'package:reader_ui/reader_session.dart';

Future<void> _settle(WidgetTester tester, {int frames = 10}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('书单页可新建、编辑名称简介，添加与移除书籍', (tester) async {
    final library = LibraryStore.memory();
    late BookEntry first;
    late BookEntry second;
    await tester.runAsync(() async {
      first = await library.importBytes(buildTestEpub(title: '甲书'));
      second = await library.importBytes(buildTestEpub(title: '乙书'));
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ReviewsPage(library: library),
      ),
    );
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('booklists-tab')));
    await _settle(tester);
    expect(find.text('还没有书单'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('booklist-create-empty')));
    await _settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('booklist-editor-name')),
      '长期主义',
    );
    await tester.enterText(
      find.byKey(const ValueKey('booklist-editor-description')),
      '9 本好书，把时间变成自己的',
    );
    await tester.tap(find.byKey(const ValueKey('booklist-editor-save')));
    await _settle(tester);

    final bookList = (await library.bookListStore().list()).single;
    expect(find.text('长期主义'), findsOneWidget);
    expect(find.text('9 本好书，把时间变成自己的'), findsOneWidget);
    expect(find.text('0 本书'), findsOneWidget);
    expect(
      find.byKey(ValueKey('booklist-card-${bookList.id}')),
      findsOneWidget,
    );

    // 详情内从书架多选添加两本书。
    await tester.tap(find.byKey(ValueKey('booklist-card-${bookList.id}')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('booklist-detail')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('booklist-detail-add')));
    await _settle(tester);
    await tester.tap(find.byKey(ValueKey('booklist-picker-${first.id}')));
    await tester.tap(find.byKey(ValueKey('booklist-picker-${second.id}')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('booklist-picker-confirm')));
    await _settle(tester);
    expect(
      (await library.bookListStore().list()).single.bookIds,
      <String>[first.id, second.id],
    );
    expect(find.text('2 本书'), findsOneWidget);

    // 移出一本。
    await tester.tap(find.byKey(ValueKey('booklist-book-remove-${second.id}')));
    await _settle(tester);
    expect(
      (await library.bookListStore().list()).single.bookIds,
      <String>[first.id],
    );

    // 编辑名称与简介。
    await tester.tap(find.byKey(const ValueKey('booklist-detail-edit')));
    await _settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('booklist-editor-name')),
      '长期主义书单',
    );
    await tester.enterText(
      find.byKey(const ValueKey('booklist-editor-description')),
      '把时间变成自己的',
    );
    await tester.tap(find.byKey(const ValueKey('booklist-editor-save')));
    await _settle(tester);

    await tester.tap(find.byTooltip('关闭'));
    await _settle(tester);
    expect(find.text('长期主义书单'), findsOneWidget);
    expect(find.text('把时间变成自己的'), findsOneWidget);
    expect(find.text('1 本书'), findsOneWidget);
    expect(
      find.byKey(ValueKey('booklist-cover-${bookList.id}-${first.id}')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('书单卡片沿用阅读日历的底色与细边框', (tester) async {
    final library = LibraryStore.memory();
    final bookList = await library.bookListStore().create(name: '样式书单');
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ReviewsPage(library: library),
      ),
    );
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('booklists-tab')));
    await _settle(tester);

    final card = find.byKey(ValueKey('booklist-card-${bookList.id}'));
    final material = tester.widget<Material>(
      find.ancestor(of: card, matching: find.byType(Material)).first,
    );
    final scheme = Theme.of(tester.element(card)).colorScheme;
    final shape = material.shape! as RoundedRectangleBorder;
    expect(material.color, scheme.surface);
    expect(shape.side.color, scheme.outlineVariant);
    expect(shape.side.width, 1);
    expect(shape.borderRadius, BorderRadius.circular(20));
    expect(tester.takeException(), isNull);
  });

  testWidgets('长按书架卡片可把书加入书单', (tester) async {
    final library = LibraryStore.memory();
    late BookEntry entry;
    await tester.runAsync(() async {
      entry = await library.importBytes(buildTestEpub(title: '待入单的書'));
    });
    final bookList = await library.bookListStore().create(name: '书单甲');

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: BookshelfPage(
          library: library,
          progressStore: MemoryReaderProgressStore(),
        ),
      ),
    );
    await _settle(tester);
    await tester.longPress(
      find.byKey(ValueKey('book-card-${entry.id}')),
    );
    await _settle(tester);
    await tester.tap(
      find.byKey(const ValueKey('book-detail-booklists')),
    );
    await _settle(tester);
    expect(find.byKey(const ValueKey('booklist-membership')), findsOneWidget);
    await tester.tap(
      find.byKey(ValueKey('booklist-membership-${bookList.id}')),
    );
    await _settle(tester);
    expect(
      (await library.bookListStore().list()).single.bookIds,
      <String>[entry.id],
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('删除书单不影响书架书籍', (tester) async {
    final library = LibraryStore.memory();
    late BookEntry entry;
    await tester.runAsync(() async {
      entry = await library.importBytes(buildTestEpub(title: '留存的書'));
    });
    final store = library.bookListStore();
    final bookList = await store.create(name: '待删书单');
    await store.addBooks(bookList.id, <String>[entry.id]);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ReviewsPage(library: library),
      ),
    );
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('booklists-tab')));
    await _settle(tester);
    await tester.tap(find.byKey(ValueKey('booklist-card-${bookList.id}')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('booklist-detail-delete')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('booklist-delete-confirm')));
    await _settle(tester);

    expect(await store.list(), isEmpty);
    expect(find.text('还没有书单'), findsOneWidget);
    expect((await library.list()).single.id, entry.id);
    expect(tester.takeException(), isNull);
  });
}
