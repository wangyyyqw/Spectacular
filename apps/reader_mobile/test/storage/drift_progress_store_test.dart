import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/storage/drift_progress_store.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/test_epub.dart';

void main() {
  late Directory dir;
  late AppDatabase db;
  late LibraryStore library;
  late DriftProgressStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('drift-progress');
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryStore(database: db, directoryProvider: () async => dir);
    store = DriftProgressStore(db);
  });

  tearDown(() async {
    await db.close();
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });

  test('保存后读回：spine/page 与 updated_at 落库（P4-10）', () async {
    final entry = await library.importBytes(buildTestEpub(title: '进度书'));
    await store.save(
      entry.id,
      const ReaderProgress(spineIndex: 1, pageIndex: 3),
    );

    final loaded = await store.load(entry.id);
    expect(loaded, const ReaderProgress(spineIndex: 1, pageIndex: 3));
    final row = (await db.select(db.readingProgress).get()).single;
    expect(row.spineIndex, 1);
    expect(row.pageIndex, 3);
    expect(row.locatorCfi, 'spine:1/page:3');
    expect(row.updatedAt, greaterThan(0));
  });

  test('重复保存是 upsert，不产生第二行', () async {
    final entry = await library.importBytes(buildTestEpub(title: '进度书2'));
    await store.save(
      entry.id,
      const ReaderProgress(spineIndex: 0, pageIndex: 1),
    );
    await store.save(
      entry.id,
      const ReaderProgress(spineIndex: 2, pageIndex: 5),
    );
    final rows = await db.select(db.readingProgress).get();
    expect(rows, hasLength(1));
    expect(
      await store.load(entry.id),
      const ReaderProgress(spineIndex: 2, pageIndex: 5),
    );
  });

  test('连续滚动的页内偏移可从位置串恢复', () async {
    final entry = await library.importBytes(buildTestEpub(title: '滚动进度书'));
    await store.save(
      entry.id,
      const ReaderProgress(spineIndex: 1, pageIndex: 3, scrollOffset: 87.5),
    );

    expect(
      await store.load(entry.id),
      const ReaderProgress(spineIndex: 1, pageIndex: 3, scrollOffset: 87.5),
    );
    final row = (await db.select(db.readingProgress).get()).single;
    expect(row.locatorCfi, 'spine:1/page:3/scroll:87.5');
  });

  test('clear 删进度；snapshot 返回 uuid → 进度', () async {
    final first = await library.importBytes(buildTestEpub(title: '甲书'));
    final second = await library.importBytes(buildTestEpub(title: '乙书'));
    await store.save(
      first.id,
      const ReaderProgress(spineIndex: 0, pageIndex: 1),
    );
    await store.save(
      second.id,
      const ReaderProgress(spineIndex: 1, pageIndex: 2),
    );

    final snapshot = await store.snapshot();
    expect(
      snapshot[first.id],
      const ReaderProgress(spineIndex: 0, pageIndex: 1),
    );
    expect(
      snapshot[second.id],
      const ReaderProgress(spineIndex: 1, pageIndex: 2),
    );

    await store.clear(first.id);
    expect(await store.load(first.id), isNull);
    expect((await store.snapshot()).containsKey(first.id), isFalse);
  });

  test('旧版 reader_progress.json 一次性迁入（幂等）', () async {
    final entry = await library.importBytes(buildTestEpub(title: '旧进度书'));
    final file = File('${dir.path}/reader_progress.json')
      ..writeAsStringSync(
        '{"${entry.id}":{"spine":2,"page":4},"missing-book":{"spine":0,"page":0}}',
      );

    expect(await store.migrateLegacyJson(file), 1, reason: '只迁存在的书');
    expect(
      await store.load(entry.id),
      const ReaderProgress(spineIndex: 2, pageIndex: 4),
    );
    expect(await store.migrateLegacyJson(file), 0, reason: '已有进度则跳过');
  });
}
