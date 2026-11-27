import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/bookshelf_page.dart';
import 'package:reader_mobile/home/reviews_page.dart';
import 'package:reader_mobile/library/book_list_store.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/theme/app_theme.dart';
import 'package:reader_ui/annotations/annotation.dart';
import 'package:reader_ui/theme/reader_ui_style.dart';

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
    expect((await library.bookListStore().list()).single.bookIds, <String>[
      first.id,
      second.id,
    ]);
    expect(find.text('2 本书'), findsOneWidget);

    // 移出一本。
    await tester.tap(find.byKey(ValueKey('booklist-book-remove-${second.id}')));
    await _settle(tester);
    expect((await library.bookListStore().list()).single.bookIds, <String>[
      first.id,
    ]);

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

    await tester.binding.handlePopRoute();
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
    expect(
      shape.borderRadius,
      ReaderUiStyle.cardRadiusOf(Theme.of(tester.element(card))),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏大字号下书单卡片与操作不溢出', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final library = LibraryStore.memory();
    late BookList bookList;
    await tester.runAsync(() async {
      final entries = <BookEntry>[];
      for (final title in <String>['甲', '乙', '丙']) {
        entries.add(
          await library.importBytes(buildTestEpub(title: '很长的书名$title')),
        );
      }
      final store = library.bookListStore();
      bookList = await store.create(
        name: '一个需要换行的很长很长的书单名称',
        description: '这是一段同样需要换行展示的书单简介，用来检查窄屏布局',
      );
      await store.addBooks(bookList.id, entries.map((entry) => entry.id));
    });
    await tester.binding.setSurfaceSize(const Size(360, 640));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: ReviewsPage(library: library),
      ),
    );
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('booklists-tab')));
    await _settle(tester);

    final card = find.byKey(ValueKey('booklist-card-${bookList.id}'));
    final cardRect = tester.getRect(card);
    final count = find.byKey(ValueKey('booklist-card-count-${bookList.id}'));
    expect(cardRect.contains(tester.getRect(count).center), isTrue);
    expect(
      tester.getRect(find.byKey(const ValueKey('booklists-tab'))).bottom,
      lessThan(cardRect.top),
    );
    expect(
      find.byKey(const ValueKey<String>('booklist-create')),
      findsOneWidget,
    );
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
    await tester.longPress(find.byKey(ValueKey('book-card-${entry.id}')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('book-detail-booklists')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('booklist-membership')), findsOneWidget);
    await tester.tap(
      find.byKey(ValueKey('booklist-membership-${bookList.id}')),
    );
    await _settle(tester);
    expect((await library.bookListStore().list()).single.bookIds, <String>[
      entry.id,
    ]);
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

  testWidgets('移出书架的书仍留在书单并继续出现在笔记中', (tester) async {
    final dir = Directory.systemTemp.createTempSync('booklists-retained');
    addTearDown(() => dir.deleteSync(recursive: true));
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final library = LibraryStore(
      database: db,
      directoryProvider: () async => dir,
    );
    late BookEntry entry;
    late BookList bookList;
    await tester.runAsync(() async {
      entry = await library.importBytes(buildTestEpub(title: '移出的书'));
      await library
          .annotationStore(entry.id)!
          .add(
            type: ReaderAnnotationType.thought,
            startCfi: 'epubcfi(/6/2!/4/2/1:1)',
            endCfi: 'epubcfi(/6/2!/4/2/1:3)',
            quote: '保留下来的划线',
            note: '移出书架后仍要显示的想法',
          );
      final store = library.bookListStore();
      bookList = await store.create(name: '保留书单');
      await store.addBooks(bookList.id, <String>[entry.id]);
      await library.remove(entry.id);
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ReviewsPage(library: library),
      ),
    );
    await _settle(tester);
    expect(find.text('移出的书'), findsOneWidget, reason: '笔记页仍展示这本书');

    await tester.tap(find.byKey(const ValueKey('booklists-tab')));
    await _settle(tester);
    expect(find.text('保留书单'), findsOneWidget);
    expect(find.text('1 本书'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('booklist-card-${bookList.id}')));
    await _settle(tester);
    expect(find.byKey(ValueKey('booklist-book-${entry.id}')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('书单页可按名称简介和书名搜索', (tester) async {
    final library = LibraryStore.memory();
    late BookEntry entry;
    late BookList second;
    await tester.runAsync(() async {
      entry = await library.importBytes(buildTestEpub(title: '山海之间'));
      final store = library.bookListStore();
      await store.create(name: '长期主义', description: '慢读清单');
      second = await store.create(name: '周末消遣', description: '轻松阅读');
      await store.addBooks(second.id, <String>[entry.id]);
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
    expect(find.text('长期主义'), findsOneWidget);
    expect(find.text('周末消遣'), findsOneWidget);

    await tester.tap(find.byTooltip('搜索书单'));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('reviews-search-field'));
    await tester.enterText(field, '慢读');
    await tester.pumpAndSettle();
    expect(find.text('长期主义'), findsOneWidget);
    expect(find.text('周末消遣'), findsNothing);

    await tester.enterText(field, '山海');
    await tester.pumpAndSettle();
    expect(find.text('周末消遣'), findsOneWidget);
    expect(find.text('长期主义'), findsNothing);

    await tester.enterText(field, '不存在');
    await tester.pumpAndSettle();
    expect(find.text('没有找到相关书单'), findsOneWidget);

    await tester.tap(find.byTooltip('关闭搜索'));
    await tester.pumpAndSettle();
    expect(find.text('长期主义'), findsOneWidget);
    expect(find.text('周末消遣'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
