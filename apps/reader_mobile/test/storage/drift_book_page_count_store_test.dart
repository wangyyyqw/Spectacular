import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/storage/drift_book_page_count_store.dart';
import 'package:reader_mobile/storage/drift_progress_store.dart';

void main() {
  late AppDatabase db;
  late DriftBookPageCountStore store;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db
        .into(db.books)
        .insert(
          BooksCompanion.insert(
            uuid: 'page-count-book',
            title: '计页缓存测试书',
            contentDir: '',
            contentRevision: const Value('revision-1'),
            createdAt: 1,
          ),
        );
    store = DriftBookPageCountStore(
      db,
      bookId: 'page-count-book',
      contentRevision: 'revision-1',
    );
  });
  tearDown(() => db.close());

  test('分章页数可恢复，复用设置表且不改其他设置', () async {
    await db
        .into(db.settingsTable)
        .insert(
          SettingsTableCompanion.insert(key: 'reader-font', value: 'serif'),
        );
    final shared = DriftProgressStore(db)
        .pageCountStore('page-count-book', 'revision-1');
    await shared.save('layout-a', {0: 12, 2: 0});
    expect(await store.load('layout-a'), {0: 12, 2: 0});
    expect(await store.load('unknown'), isEmpty);
    final retained = await (db.select(
      db.settingsTable,
    )..where((table) => table.key.equals('reader-font'))).getSingle();
    expect(retained.value, 'serif');
  });

  test('每本书仅保存最近两套完整布局，重用配置更新顺序', () async {
    await store.save('layout-a', {0: 1});
    await store.save('layout-b', {0: 2});
    await store.save('layout-a', {0: 3});
    await store.save('layout-c', {0: 4});
    expect(await store.load('layout-b'), isEmpty);
    expect(await store.load('layout-a'), {0: 3});
    expect(await store.load('layout-c'), {0: 4});
    final row = (await db.select(db.settingsTable).get()).single;
    expect((jsonDecode(row.value) as Map)['layouts'], hasLength(2));
  });

  test('内容更新拒绝旧缓存，旧会话不能覆盖新版计数', () async {
    await store.save('layout-a', {0: 1});
    await (db.update(db.books)
          ..where((table) => table.uuid.equals('page-count-book')))
        .write(const BooksCompanion(contentRevision: Value('revision-2')));
    final current = DriftBookPageCountStore(
      db,
      bookId: 'page-count-book',
      contentRevision: 'revision-2',
    );
    expect(await current.load('layout-a'), isEmpty);
    expect(await store.load('layout-a'), isEmpty);
    await current.save('layout-a', {0: 7});
    await store.save('layout-a', {0: 99});
    expect(await current.load('layout-a'), {0: 7});
  });

  test('损坏或未知版本缓存不会被当作已完成章节', () async {
    await store.save('layout-a', {0: 3});
    final key = (await db.select(db.settingsTable).get()).single.key;
    for (final value in [
      '{损坏',
      jsonEncode({
        'schemaVersion': 9,
        'contentRevision': 'revision-1',
        'layouts': <Object>[],
      }),
      jsonEncode({
        'schemaVersion': 1,
        'contentRevision': 'revision-1',
        'layouts': [
          {
            'layoutKey': 'layout-a',
            'counts': {'0': 3, '1': -1},
          },
        ],
      }),
    ]) {
      await db
          .into(db.settingsTable)
          .insertOnConflictUpdate(
            SettingsTableCompanion.insert(key: key, value: value),
          );
      expect(await store.load('layout-a'), isEmpty);
    }
  });

  test('并发保存不同布局不丢失另一套计数', () async {
    await Future.wait([
      store.save('layout-a', {0: 1}),
      store.save('layout-b', {0: 2}),
    ]);
    expect(await store.load('layout-a'), {0: 1});
    expect(await store.load('layout-b'), {0: 2});
    await expectLater(store.save('layout-a', {-1: 5}), throwsArgumentError);
    expect(await store.load('layout-a'), {0: 1});
  });
}
