import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/book_detail_page.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/db.dart';

import '../support/test_epub.dart';

class _FakeCoverLibrary extends LibraryStore {
  _FakeCoverLibrary() : super.memory();

  bool replaced = false;

  @override
  Future<BookEntry> replaceCover(
    String id,
    Uint8List bytes, {
    required String extension,
  }) async {
    replaced = true;
    return (await bookById(id))!;
  }
}

void main() {
  late Directory dir;
  late AppDatabase db;
  late LibraryStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('book-detail-page');
    db = AppDatabase(NativeDatabase.memory());
    store = LibraryStore(database: db, directoryProvider: () async => dir);
  });

  tearDown(() async {
    await db.close();
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });

  testWidgets('详情页可编辑资料、新建标签并切换标签', (tester) async {
    late BookEntry entry;
    await tester.runAsync(() async {
      entry = await store.importBytes(
        buildTestEpub(title: '旧书名', identifier: 'detail-edit'),
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        home: BookDetailPage(entry: entry, library: store),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey<String>('book-detail-title-field')),
      '新书名',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('book-detail-author-field')),
      '新作者',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('book-detail-description-field')),
      '新的简介',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('book-detail-save')));
    await tester.pumpAndSettle();

    late BookEntry updated;
    await tester.runAsync(() async {
      updated = (await store.bookById(entry.id))!;
    });
    expect(updated.title, '新书名');
    expect(updated.author, '新作者');
    expect(updated.description, '新的简介');

    final tagField = find.byKey(
      const ValueKey<String>('book-detail-new-tag-field'),
    );
    await tester.scrollUntilVisible(
      tagField,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(tagField, '科幻');
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('book-detail-add-tag')),
    );
    await tester.tap(find.byKey(const ValueKey<String>('book-detail-add-tag')));
    await tester.pumpAndSettle();

    late List<BookTag> tags;
    await tester.runAsync(() async {
      tags = await store.bookTags(entry.id);
    });
    expect(tags.single.name, '科幻');
    final chip = find.byKey(
      ValueKey<String>('book-detail-tag-${tags.single.id}'),
    );
    expect(chip, findsOneWidget);
    await tester.tap(chip);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      tags = await store.bookTags(entry.id);
    });
    expect(tags, isEmpty, reason: '再次点击标签应取消关联');
  });

  testWidgets('详情页更换封面调用存储并提示成功', (tester) async {
    final coverStore = _FakeCoverLibrary();
    late BookEntry entry;
    await tester.runAsync(() async {
      entry = await coverStore.importBytes(
        buildTestEpub(title: '换封面', identifier: 'detail-cover'),
      );
    });
    final png = Uint8List.fromList(<int>[1, 2, 3]);

    await tester.pumpWidget(
      MaterialApp(
        home: BookDetailPage(
          entry: entry,
          library: coverStore,
          pickCover: () async => (bytes: png, extension: 'png'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('book-detail-change-cover')),
    );
    await tester.pumpAndSettle();

    expect(coverStore.replaced, isTrue);
    expect(find.text('封面已更新'), findsOneWidget);
  });

  testWidgets('详情页按书汇总阅读时长、次数和翻页', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    late BookEntry entry;
    late BookEntry other;
    await tester.runAsync(() async {
      entry = await store.importBytes(
        buildTestEpub(title: '记录书', identifier: 'detail-stats'),
      );
      other = await store.importBytes(
        buildTestEpub(title: '另一本', identifier: 'detail-stats-other'),
      );
      final sessions = store.readingSessionStore()!;
      await sessions.add(
        bookId: entry.id,
        startedAt: yesterday.add(const Duration(hours: 20)),
        endedAt: yesterday.add(const Duration(hours: 21)),
        pageTurns: 5,
        charactersRead: 100,
      );
      await sessions.add(
        bookId: entry.id,
        startedAt: yesterday.add(const Duration(hours: 23, minutes: 30)),
        endedAt: today.add(const Duration(minutes: 30)),
        pageTurns: 3,
        charactersRead: 80,
      );
      await sessions.add(
        bookId: entry.id,
        startedAt: today.add(const Duration(hours: 9)),
        endedAt: today.add(const Duration(hours: 9, minutes: 10)),
        pageTurns: 2,
        charactersRead: 40,
      );
      await sessions.add(
        bookId: other.id,
        startedAt: today.add(const Duration(hours: 10)),
        endedAt: today.add(const Duration(hours: 11)),
        pageTurns: 99,
        charactersRead: 999,
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        home: BookDetailPage(entry: entry, library: store),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('book-detail-total-duration')),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    String valueOf(String key) =>
        tester.widget<Text>(find.byKey(ValueKey<String>(key))).data!;

    expect(valueOf('book-detail-total-duration'), '2 小时 10 分');
    expect(valueOf('book-detail-session-count'), '3');
    expect(valueOf('book-detail-reading-days'), '2');
    expect(valueOf('book-detail-page-turns'), '10');
    expect(valueOf('book-detail-characters-read'), '220');

    final todayKey = _dateKey(today);
    final yesterdayKey = _dateKey(yesterday);
    await tester.scrollUntilVisible(
      find.byKey(ValueKey<String>('book-detail-daily-$yesterdayKey')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      valueOf('book-detail-daily-duration-$todayKey'),
      '40 分钟',
      reason: '跨午夜会话的今日部分应计入今日时长',
    );
    expect(valueOf('book-detail-daily-detail-$todayKey'), '1 次 · 翻页 2 · 40 字');
    expect(valueOf('book-detail-daily-duration-$yesterdayKey'), '1 小时 30 分');
    expect(
      valueOf('book-detail-daily-detail-$yesterdayKey'),
      '2 次 · 翻页 8 · 180 字',
    );
  });
}

String _dateKey(DateTime date) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)}';
}
