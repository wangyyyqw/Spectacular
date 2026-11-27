import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/book_detail_page.dart';
import 'package:reader_mobile/home/bookshelf_page.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/book_review_store.dart';
import 'package:reader_mobile/theme/app_theme.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/theme/reader_frosted_surface.dart';

import '../support/test_epub.dart';

class _MemoryReviews implements BookReviewStore {
  final Map<String, BookReview> items = <String, BookReview>{};

  @override
  Future<Map<String, BookReview>> snapshot() async => Map.of(items);

  @override
  Future<void> save(
    String bookId, {
    int? rating,
    required String content,
  }) async {
    final now = DateTime.now();
    items[bookId] = BookReview(
      bookId: bookId,
      rating: rating,
      content: content,
      createdAt: now,
      updatedAt: now,
    );
  }

  @override
  Future<void> remove(String bookId) async => items.remove(bookId);
}

Finder _key(String value) => find.byKey(ValueKey<String>(value));

Future<BookEntry> _import(
  WidgetTester tester,
  LibraryStore library,
  String title, {
  String author = '甲作者',
}) async {
  late BookEntry book;
  await tester.runAsync(() async {
    book = await library.importBytes(
      buildTestEpub(
        title: title,
        author: author,
        identifier: 'ui-${title.hashCode.toRadixString(16)}',
      ),
    );
  });
  return book;
}

Future<void> _show(WidgetTester tester, Widget page) async {
  await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: page));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('三列书架显示封面和书名，分组、搜索及列表阅读信息可用', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final library = LibraryStore.memory();
    final progress = MemoryReaderProgressStore();
    final first = await _import(tester, library, '山川纪事');
    final second = await _import(tester, library, '江海笔记', author: '乙作者');
    final third = await _import(tester, library, '城市阅读');
    await _import(tester, library, '第四本书');
    final group = await library.createGroup('散文');
    await library.setBooksGroup(<String>{
      first.id,
      second.id,
    }, groupId: group.id);
    await progress.save(
      second.id,
      const ReaderProgress(spineIndex: 0, pageIndex: 0, finished: true),
    );
    await _show(
      tester,
      BookshelfPage(library: library, progressStore: progress),
    );

    final grid = tester.widget<GridView>(_key('bookshelf-grid'));
    final layout =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(layout.crossAxisCount, 3);
    expect(find.byType(ChoiceChip), findsNothing);
    final cover = find.descendant(
      of: _key('book-card-${first.id}'),
      matching: _key('book-card-cover'),
    );
    final title = find
        .descendant(
          of: _key('book-card-${first.id}'),
          matching: find.text(first.title),
        )
        .last;
    expect(
      tester.getTopLeft(title).dy,
      greaterThan(tester.getBottomLeft(cover).dy),
    );
    expect(_key('book-card-meta-${second.id}'), findsNothing);
    expect(find.text('全部'), findsOneWidget);
    expect(find.textContaining('全部 '), findsNothing);

    await _tap(tester, _key('bookshelf-group-${group.id}'));
    expect(_key('book-card-${third.id}'), findsNothing);
    expect(_key('book-card-${first.id}'), findsOneWidget);
    await _tap(tester, _key('bookshelf-group-all'));
    expect(_key('book-card-${third.id}'), findsOneWidget);
    await _tap(tester, find.byTooltip('搜索书架'));
    await tester.enterText(_key('bookshelf-search-field'), '乙作者');
    await tester.pumpAndSettle();
    expect(_key('book-card-${first.id}'), findsNothing);
    expect(_key('book-card-${second.id}'), findsOneWidget);
    await _tap(tester, find.byTooltip('关闭搜索'));
    await _tap(tester, find.byTooltip('列表视图'));
    expect(_key('book-row-${first.id}'), findsOneWidget);
    expect(find.text('乙作者'), findsOneWidget);
    expect(find.text('已读 · 第 1 章'), findsOneWidget);
    final rowCover = tester.getSize(_key('book-row-cover').first);
    expect(rowCover.width / rowCover.height, closeTo(3 / 4, 0.001));
    expect(tester.takeException(), isNull);
  });

  testWidgets('导入后的平面详情操作可新建分组、进入多选并删除书籍', (tester) async {
    final library = LibraryStore.memory();
    final bytes = buildTestEpub(title: '工具栏导入', identifier: 'ui-toolbar');
    await _show(
      tester,
      BookshelfPage(
        library: library,
        progressStore: MemoryReaderProgressStore(),
        pickEpubFiles: () async => <String>['新书.epub'],
        readFile: (_) async => bytes,
      ),
    );
    await tester.runAsync(() async {
      await tester.tap(_key('bookshelf-import'));
      for (var attempt = 0; attempt < 100; attempt++) {
        if ((await library.list()).isNotEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
    final book = (await library.list()).single;
    await tester.longPress(_key('book-card-${book.id}'));
    await tester.pumpAndSettle();
    final cover = tester.getSize(_key('book-detail-cover'));
    expect(cover.height, greaterThan(cover.width));
    expect(
      find.descendant(
        of: _key('book-detail-create-group'),
        matching: find.byType(ListTile),
      ),
      findsOneWidget,
    );
    await _tap(tester, _key('book-detail-create-group'));
    await tester.enterText(_key('bookshelf-group-create-name'), '待读');
    await tester.pump();
    await _tap(tester, _key('bookshelf-group-create-confirm'));
    expect(find.text('待读'), findsOneWidget);
    expect(
      (await library.groupAssignments())[book.id],
      (await library.listGroups()).single.id,
    );
    await tester.longPress(_key('book-card-${book.id}'));
    await tester.pumpAndSettle();
    await _tap(tester, _key('book-detail-multi-select'));
    expect(find.text('已选 1 本'), findsOneWidget);
    await _tap(tester, find.byTooltip('退出多选'));
    await tester.longPress(_key('book-card-${book.id}'));
    await tester.pumpAndSettle();
    await _tap(tester, find.text('删除'));
    await _tap(tester, find.widgetWithText(FilledButton, '删除'));
    expect(await library.list(), isEmpty);
    expect(find.text('书架还是空的'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('详情入口和资料标签编辑在小圆角布局中保持可用', (tester) async {
    final library = LibraryStore.memory();
    final book = await _import(tester, library, '原始书名');
    await _show(
      tester,
      BookshelfPage(
        library: library,
        progressStore: MemoryReaderProgressStore(),
      ),
    );
    await tester.longPress(_key('book-card-${book.id}'));
    await tester.pumpAndSettle();
    await _tap(tester, _key('book-detail-open-page'));
    expect(find.byType(BookDetailPage), findsOneWidget);
    final coverFrame = tester.widget<Container>(
      find.descendant(
        of: _key('book-detail-page-cover'),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.foregroundDecoration is BoxDecoration,
        ),
      ),
    );
    expect(
      (coverFrame.foregroundDecoration! as BoxDecoration).borderRadius,
      BorderRadius.circular(4),
    );
    await tester.enterText(_key('book-detail-title-field'), '编辑后的书名');
    await tester.enterText(_key('book-detail-author-field'), '编辑后的作者');
    await tester.pump();
    await _tap(tester, _key('book-detail-save'));
    expect((await library.bookById(book.id))?.title, '编辑后的书名');
    expect((await library.bookById(book.id))?.author, '编辑后的作者');
    await _scrollTo(tester, _key('book-detail-new-tag-field'));
    await tester.enterText(_key('book-detail-new-tag-field'), '小说');
    await tester.pump();
    await _tap(tester, _key('book-detail-add-tag'));
    final tag = (await library.bookTags(book.id)).single;
    expect(tag.name, '小说');
    await _tap(tester, _key('book-detail-tag-${tag.id}'));
    expect(await library.bookTags(book.id), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('读完弹层保存评分书评与进度，取消读完保留书评', (tester) async {
    final library = LibraryStore.memory();
    final progress = MemoryReaderProgressStore();
    final reviews = _MemoryReviews();
    final book = await _import(tester, library, '读完记录');
    await _show(
      tester,
      BookDetailPage(
        entry: book,
        library: library,
        progressStore: progress,
        reviewStore: reviews,
      ),
    );
    await _scrollTo(tester, _key('book-detail-mark-finished'));
    await _tap(tester, _key('book-detail-mark-finished'));
    final sheet = tester.widget<Material>(_key('book-detail-finish-sheet'));
    expect(find.byType(ReaderFrostedSurface), findsOneWidget);
    expect(sheet.color, Colors.transparent);
    expect(
      sheet.borderRadius,
      const BorderRadius.vertical(top: Radius.circular(8)),
    );
    await _tap(tester, _key('book-detail-finish-rating-4'));
    await tester.enterText(_key('book-detail-finish-review'), '读完后的简短感想');
    await _tap(tester, _key('book-detail-finish-save'));
    expect((await progress.load(book.id))?.finished, isTrue);
    expect(reviews.items[book.id]?.rating, 4);
    expect(reviews.items[book.id]?.content, '读完后的简短感想');
    expect(find.text('已读完'), findsOneWidget);
    await _tap(tester, _key('book-detail-unmark-finished'));
    await _tap(tester, _key('book-detail-unmark-confirm'));
    expect((await progress.load(book.id))?.finished, isFalse);
    expect(reviews.items[book.id]?.content, '读完后的简短感想');
    expect(tester.takeException(), isNull);
  });
}
