import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/book_detail_sheet.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/db.dart';

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

  testWidgets('详情面板展示导入报告（诊断码 + 分级 + 文案）', (tester) async {
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
    expect(find.text('E_MANIFEST_MEDIA_TYPE_INFERRED'), findsOneWidget);
    expect(find.textContaining('缺少 media-type'), findsOneWidget);
    expect(find.text('导入报告'), findsOneWidget);
  });

  testWidgets('无报告的书显示「无修复或告警」', (tester) async {
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
    expect(find.text('无修复或告警'), findsOneWidget);
    expect(find.text('未知作者'), findsOneWidget);
    final coverSize = tester.getSize(
      find.byKey(const ValueKey<String>('book-detail-cover')),
    );
    expect(coverSize, const Size(80, 108));
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
    await tester.tap(find.text('删除本书'));
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

  testWidgets('点新建分组返回 create-group', (tester) async {
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
      find.byKey(const ValueKey<String>('book-detail-create-group')),
    );
    await tester.pumpAndSettle();
    expect(popped, 'create-group');
  });

  testWidgets('点关联阅微公开阅读返回 reamicro-link', (tester) async {
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
      find.byKey(const ValueKey<String>('book-detail-public-reading')),
    );
    await tester.pumpAndSettle();
    expect(popped, 'reamicro-link');
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
