import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/bookshelf_page.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/theme/reader_frosted_surface.dart';

import '../support/test_epub.dart';

Future<void> _settle(WidgetTester tester, {int frames = 10}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _enterMultiSelect(WidgetTester tester, String bookId) async {
  await tester.longPress(find.byKey(ValueKey<String>('book-card-$bookId')));
  await _settle(tester, frames: 4);
  await tester.tap(find.text('多选'));
  await _settle(tester, frames: 4);
}

void main() {
  testWidgets('书架支持全选、取消全选和确认后批量删除', (tester) async {
    final library = LibraryStore.memory();
    final progressStore = MemoryReaderProgressStore();
    late BookEntry first;
    late BookEntry second;
    late BookEntry third;
    await tester.runAsync(() async {
      first = await library.importBytes(
        buildTestEpub(title: '批量甲', identifier: 'batch-a'),
      );
      second = await library.importBytes(
        buildTestEpub(title: '批量乙', identifier: 'batch-b'),
      );
      third = await library.importBytes(
        buildTestEpub(title: '批量丙', identifier: 'batch-c'),
      );
      await progressStore.save(
        first.id,
        const ReaderProgress(spineIndex: 0, pageIndex: 2),
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        home: BookshelfPage(library: library, progressStore: progressStore),
      ),
    );
    await _settle(tester);

    await _enterMultiSelect(tester, first.id);
    expect(find.text('已选 1 本'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('bookshelf-select-all')),
    );
    await _settle(tester, frames: 3);
    expect(find.text('已选 3 本'), findsOneWidget);
    expect(find.text('取消全选'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('bookshelf-select-all')),
    );
    await _settle(tester, frames: 3);
    expect(find.text('多选'), findsOneWidget);
    expect(find.text('请选择书籍'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey<String>('book-card-${first.id}')));
    await tester.tap(find.byKey(ValueKey<String>('book-card-${second.id}')));
    await _settle(tester, frames: 3);
    expect(find.text('已选 2 本'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('bookshelf-batch-delete')),
    );
    await _settle(tester);
    expect(find.text('删除选中的 2 本书？'), findsOneWidget);
    expect(find.textContaining('书签、笔记和高亮'), findsOneWidget);
    expect(find.byType(ReaderFrostedSurface), findsOneWidget);
    expect(
      tester.widget<Dialog>(find.byType(Dialog)).backgroundColor,
      Colors.transparent,
    );

    await tester.tap(
      find.descendant(
        of: find.byWidgetPredicate((widget) => widget is AlertDialog),
        matching: find.widgetWithText(TextButton, '取消'),
      ),
    );
    await _settle(tester);
    expect((await library.list()).length, 3);
    expect(find.text('已选 2 本'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('bookshelf-batch-delete')),
    );
    await _settle(tester);
    await tester.tap(
      find.descendant(
        of: find.byWidgetPredicate((widget) => widget is AlertDialog),
        matching: find.widgetWithText(FilledButton, '删除'),
      ),
    );
    await _settle(tester, frames: 16);

    expect((await library.list()).map((entry) => entry.id), <String>[third.id]);
    expect(
      await progressStore.load(first.id),
      isNotNull,
      reason: '删书保留阅读进度，重新导入后可恢复',
    );
    expect(find.text('批量甲'), findsNothing);
    expect(find.text('批量乙'), findsNothing);
    expect(find.text('批量丙'), findsWidgets);
    expect(find.byTooltip('批量管理'), findsNothing);
    expect(find.text('已删除 2 本书'), findsOneWidget);
  });

  testWidgets('列表视图支持勾选书籍进入批量管理', (tester) async {
    final library = LibraryStore.memory();
    late BookEntry first;
    await tester.runAsync(() async {
      first = await library.importBytes(
        buildTestEpub(title: '列表甲', identifier: 'batch-list-a'),
      );
      await library.importBytes(
        buildTestEpub(title: '列表乙', identifier: 'batch-list-b'),
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

    await tester.tap(find.byTooltip('列表视图'));
    await _settle(tester);
    await tester.longPress(
      find.byKey(ValueKey<String>('book-row-${first.id}')),
    );
    await _settle(tester, frames: 4);
    await tester.tap(find.text('多选'));
    await _settle(tester);

    expect(find.text('已选 1 本'), findsOneWidget);
    final checkbox = tester.widget<Checkbox>(
      find.byKey(ValueKey<String>('book-row-check-${first.id}')),
    );
    expect(checkbox.value, isTrue);
  });
}
