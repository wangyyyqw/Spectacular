import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/book_detail_sheet.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/theme/app_theme.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';

import '../support/test_epub.dart';

void main() {
  late Directory dir;
  late AppDatabase db;
  late LibraryStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('book-detail');
    db = AppDatabase(NativeDatabase.memory());
    store = LibraryStore(database: db, directoryProvider: () async => dir);
  });

  tearDown(() async {
    await db.close();
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });

  testWidgets('长按面板保留书籍资料，不展示导入报告和关闭按钮', (tester) async {
    late BookEntry entry;
    await tester.runAsync(() async {
      entry = await store.importBytes(buildWarningEpub());
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookDetailSheet(entry: entry, library: store),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('告警书'), findsWidgets);
    expect(find.text('内容完整'), findsOneWidget);
    expect(find.text('E_MANIFEST_MEDIA_TYPE_INFERRED'), findsNothing);
    expect(find.textContaining('缺少 media-type'), findsNothing);
    expect(find.text('导入报告'), findsNothing);
    expect(find.text('关闭'), findsNothing);
  });

  testWidgets('无报告的书保留封面和未知作者，不显示报告空状态', (tester) async {
    final entry = BookEntry(
      id: 'clean-book',
      title: '干净书',
      author: '',
      filePath: '',
      addedAt: DateTime(2026),
      spineCount: 3,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookDetailSheet(entry: entry, library: store),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('无修复或告警'), findsNothing);
    expect(find.text('未知作者'), findsOneWidget);
    final coverSize = tester.getSize(
      find.byKey(const ValueKey<String>('book-detail-cover')),
    );
    expect(coverSize, const Size(80, 108));
  });

  testWidgets('窄屏和放大文字下两组操作分别同行，遮罩和下拉仍可关闭', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final entry = BookEntry(
      id: 'layout-book',
      title: '长按布局检查',
      author: '作者',
      filePath: '',
      addedAt: DateTime(2026),
    );
    for (final (size, scale) in [
      (const Size(384, 2560 / 3), 1.0),
      (const Size(320, 640), 1.3),
    ]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showReaderBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (_) => BookDetailSheet(entry: entry, library: store),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      for (final (left, right) in [
        ('book-detail-update', 'book-detail-create-group'),
        ('book-detail-multi-select', 'book-detail-delete'),
      ]) {
        final leftButton = find.byKey(ValueKey(left));
        final rightButton = find.byKey(ValueKey(right));
        final leftRect = tester.getRect(leftButton);
        final rightRect = tester.getRect(rightButton);
        expect(leftRect.center.dy, closeTo(rightRect.center.dy, 0.1));
        expect(leftRect.right, lessThan(rightRect.left));
        expect(leftRect.height, greaterThanOrEqualTo(48));
        expect(rightRect.height, greaterThanOrEqualTo(48));
        expect(leftButton.hitTestable(), findsOneWidget);
        expect(rightButton.hitTestable(), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.tapAt(const Offset(10, 80));
      await tester.pumpAndSettle();
      expect(find.byType(BookDetailSheet), findsNothing);
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      final sheet = tester.getRect(find.byType(BottomSheet));
      await tester.flingFrom(
        Offset(sheet.center.dx, sheet.top + 20),
        const Offset(0, 400),
        1200,
      );
      await tester.pumpAndSettle();
      expect(find.byType(BookDetailSheet), findsNothing);
    }
  });

  testWidgets('点删除返回 delete，由书架执行确认流程', (tester) async {
    final entry = BookEntry(
      id: 'clean-book',
      title: '干净书',
      author: '作者',
      filePath: '',
      addedAt: DateTime(2026),
    );
    String? popped;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async {
                popped = await Navigator.of(context).push<String>(
                  MaterialPageRoute<String>(
                    builder: (_) =>
                        BookDetailSheet(entry: entry, library: store),
                  ),
                );
              },
              child: const Text('打开详情'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开详情'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(popped, 'delete');
  });

  testWidgets('点图书详情返回 detail，由书架打开完整详情页', (tester) async {
    final entry = BookEntry(
      id: 'clean-book',
      title: '干净书',
      author: '作者',
      filePath: '',
      addedAt: DateTime(2026),
    );
    String? popped;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async {
                popped = await Navigator.of(context).push<String>(
                  MaterialPageRoute<String>(
                    builder: (_) =>
                        BookDetailSheet(entry: entry, library: store),
                  ),
                );
              },
              child: const Text('打开详情'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开详情'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('图书详情'));
    await tester.pumpAndSettle();
    expect(popped, 'detail');
  });

  testWidgets('点分组返回 create-group', (tester) async {
    final entry = BookEntry(
      id: 'clean-book',
      title: '干净书',
      author: '作者',
      filePath: '',
      addedAt: DateTime(2026),
    );
    String? popped;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async {
                popped = await Navigator.of(context).push<String>(
                  MaterialPageRoute<String>(
                    builder: (_) =>
                        BookDetailSheet(entry: entry, library: store),
                  ),
                );
              },
              child: const Text('打开详情'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开详情'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('分组'));
    await tester.pumpAndSettle();
    expect(popped, 'create-group');
  });

  testWidgets('点多选返回 multi-select', (tester) async {
    final entry = BookEntry(
      id: 'clean-book',
      title: '干净书',
      author: '作者',
      filePath: '',
      addedAt: DateTime(2026),
    );
    String? popped;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async {
                popped = await Navigator.of(context).push<String>(
                  MaterialPageRoute<String>(
                    builder: (_) =>
                        BookDetailSheet(entry: entry, library: store),
                  ),
                );
              },
              child: const Text('打开详情'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开详情'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('book-detail-multi-select')),
    );
    await tester.pumpAndSettle();
    expect(popped, 'multi-select');
  });
}
