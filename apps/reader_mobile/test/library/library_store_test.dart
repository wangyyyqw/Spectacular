import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/db.dart';

import '../support/test_epub.dart';

/// 内存数据库 + 临时目录的书库。
({LibraryStore store, AppDatabase db}) _open(Directory dir) {
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  return (
    store: LibraryStore(
      database: db,
      directoryProvider: () async => dir,
    ),
    db: db,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('导入成功：元数据来自 OPF，文件落盘并可回读', () async {
    final dir = Directory.systemTemp.createTempSync('library_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = _open(dir).store;
    final entry = await store.importBytes(buildTestEpub());
    expect(entry.title, '测试书');
    expect(entry.author, '测试作者');
    expect(entry.spineCount, 1);
    expect(File(entry.filePath).existsSync(), isTrue);
    expect(await store.list(), hasLength(1));
    final bytes = await store.readBytes(entry);
    expect(bytes.length, greaterThan(0));
  });

  test('条目跨实例持久化；删除后目录与条目都消失', () async {
    final dir = Directory.systemTemp.createTempSync('library_persist');
    addTearDown(() => dir.deleteSync(recursive: true));
    final opened = _open(dir);
    final entry = await opened.store.importBytes(buildTestEpub(title: '持久书'));
    await opened.store.touchLastRead(entry.id);

    // 同一数据库、新 Store 实例 ≈ 重启后重新打开书库。
    final second = LibraryStore(
      database: opened.db,
      directoryProvider: () async => dir,
    );
    final books = await second.list();
    expect(books.single.title, '持久书');
    expect(books.single.lastReadAt, isNotNull);
    expect(books.single.status, BookReadingStatus.reading);
    expect(File(books.single.filePath).existsSync(), isTrue);

    final bookDir = Directory(entry.filePath).parent;
    await second.remove(books.single.id);
    expect(await second.list(), isEmpty);
    expect(bookDir.existsSync(), isFalse, reason: '删书清理整个书目录');
  });

  test('同一本书（OPF identifier）重复导入被拒', () async {
    final dir = Directory.systemTemp.createTempSync('library_dup');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = _open(dir).store;
    await store.importBytes(buildTestEpub(title: '唯一书'));
    await expectLater(
      store.importBytes(buildTestEpub(title: '唯一书')),
      throwsA(
        isA<LibraryImportException>().having(
          (error) => error.errorCode,
          'errorCode',
          'E_DUPLICATE',
        ),
      ),
    );
    expect(await store.list(), hasLength(1));
  });

  test('点段标识使用独立书目录，删除不影响其他书与设置', () async {
    final dir = Directory.systemTemp.createTempSync('library_dot_id');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = _open(dir).store;
    final sentinel = File('${dir.path}/settings-sentinel.txt')
      ..writeAsStringSync('保留');
    final other = await store.importBytes(buildTestEpub(identifier: 'other'));
    for (final identifier in ['.', '..']) {
      final book = await store.importBytes(
        buildTestEpub(identifier: identifier),
      );
      expect(book.id, isNot(anyOf('.', '..')));
      expect(
        p.isWithin(p.join(dir.path, 'books'), p.normalize(book.filePath)),
        isTrue,
      );
      await expectLater(
        store.importBytes(buildTestEpub(identifier: identifier)),
        throwsA(isA<LibraryImportException>()),
      );
      await store.remove(book.id);
      expect(File(book.filePath).existsSync(), isFalse);
      expect(sentinel.readAsStringSync(), '保留');
      expect(File(other.filePath).existsSync(), isTrue);
    }
  });

  test('旧库恶意标识只删记录，拒绝递归删除父目录或目录外原书', () async {
    final dir = Directory.systemTemp.createTempSync('library_unsafe_legacy');
    addTearDown(() => dir.deleteSync(recursive: true));
    final opened = _open(dir);
    final sentinel = File('${dir.path}/sentinel.txt')..writeAsStringSync('保留');
    for (final id in ['.', '..', '../outside']) {
      await opened.db
          .into(opened.db.books)
          .insert(
            BooksCompanion.insert(
              uuid: id,
              title: '旧库异常标识',
              contentDir: 'books/$id',
              sourcePath: Value(sentinel.path),
              createdAt: 0,
            ),
          );
      await opened.store.remove(id);
      expect(sentinel.readAsStringSync(), '保留');
    }
    await opened.store.remove('..');
    expect(await opened.store.list(), isEmpty);
    expect(sentinel.existsSync(), isTrue);
  });

  test('导入报告落库：诊断码与分级（P4-06）', () async {
    final dir = Directory.systemTemp.createTempSync('library_reports');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = _open(dir).store;
    final entry = await store.importBytes(buildWarningEpub());
    final reports = await store.importReports(entry.id);
    expect(reports, isNotEmpty);
    final manifest = reports.firstWhere(
      (item) => item.code == 'E_MANIFEST_MEDIA_TYPE_INFERRED',
    );
    expect(manifest.severity, 1, reason: 'recoverable 映射为警告');
    expect(manifest.message, contains('media-type'));
    expect(
      reports.map((item) => item.code),
      contains('IMPORT_WARNING'),
      reason: '没有诊断码的告警也要落库，不能丢',
    );
  });

  test('干净书没有错误级报告明细', () async {
    final dir = Directory.systemTemp.createTempSync('library_reports_ok');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = _open(dir).store;
    final entry = await store.importBytes(buildTestEpub(title: '干净书'));
    final reports = await store.importReports(entry.id);
    expect(
      reports.where((item) => item.severity >= 2),
      isEmpty,
      reason: '干净书不应有错误级报告',
    );
  });

  test('坏 EPUB 导入抛可读错误，不入库', () async {
    final dir = Directory.systemTemp.createTempSync('library_bad');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = _open(dir).store;
    await expectLater(
      store.importBytes(Uint8List.fromList(List<int>.generate(64, (i) => i))),
      throwsA(isA<LibraryImportException>()),
    );
    expect(await store.list(), isEmpty);
  });

  test('导入统计字符数：books.char_count 与进度权重落地（P4-09）', () async {
    final dir = Directory.systemTemp.createTempSync('library_chars');
    addTearDown(() => dir.deleteSync(recursive: true));
    final opened = _open(dir);
    final store = opened.store;
    final entry = await store.importBytes(buildTestEpub(title: '字数书'));

    final bookRow = (await opened.db.select(opened.db.books).get()).single;
    expect(bookRow.charCount, greaterThan(0), reason: '导入期统计全书字符数');
    final spineRows = await opened.db.select(opened.db.spineItems).get();
    expect(spineRows, hasLength(1));
    expect(spineRows.single.charCount, bookRow.charCount);
    expect(spineRows.single.charStart, 0);

    final weights = await store.progressWeights(entry.id);
    expect(weights.estimated, isFalse);
    expect(weights.total, bookRow.charCount);
    expect(weights.percentOf(0), 0);
    expect(
      weights.percentOf(0, charOffsetInChapter: weights.total.toDouble()),
      1,
    );
  });

  test('progressWeights：无统计的旧书按章等权估算', () async {
    final dir = Directory.systemTemp.createTempSync('library_chars_legacy');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = _open(dir).store;
    final weights = await store.progressWeights('不存在');
    expect(weights.total, 0);
    expect(weights.estimated, isFalse);
  });

  test('封面提取并缓存到书目录；无封面时为 null 交给占位', () async {
    final dir = Directory.systemTemp.createTempSync('library_cover');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = _open(dir).store;
    final withCover = await store.importBytes(
      buildTestEpub(title: '有封面', cover: true),
    );
    expect(withCover.coverPath, isNotNull);
    expect(File(withCover.coverPath!).existsSync(), isTrue);

    final withoutCover = await store.importBytes(buildTestEpub(title: '无封面'));
    expect(withoutCover.coverPath, isNull);
  });

  test('排序：最近阅读优先，未读按导入时间倒序', () async {
    final dir = Directory.systemTemp.createTempSync('library_sort');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = _open(dir).store;
    final first = await store.importBytes(buildTestEpub(title: '先导入'));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final second = await store.importBytes(buildTestEpub(title: '后导入'));
    var books = await store.list();
    expect(books.first.title, '后导入', reason: '未读按导入时间倒序');

    await store.touchLastRead(first.id);
    books = await store.list();
    expect(books.first.title, '先导入', reason: '最近阅读优先');
    expect(books.first.status, BookReadingStatus.reading);
    expect(second.id, isNot(books.first.id));
  });

  test('删除旧格式迁移书：原书文件一并删除', () async {
    final dir = Directory.systemTemp.createTempSync('library_remove_legacy');
    addTearDown(() => dir.deleteSync(recursive: true));
    final epubFile = File('${dir.path}/books/legacy-del.epub')
      ..createSync(recursive: true)
      ..writeAsBytesSync(buildTestEpub(title: '待删旧书'));
    File('${dir.path}/books.json').writeAsStringSync(
      '{"books":[{"id":"legacy-del","title":"待删旧书","author":"作者",'
      '"filePath":"${epubFile.path}","addedAt":1700000000000}]}',
    );
    final store = _open(dir).store;
    await store.migrateLegacyJson();
    await store.remove('legacy-del');
    expect(await store.list(), isEmpty);
    expect(epubFile.existsSync(), isFalse, reason: '磁盘不留孤儿原书');
  });

  test('孤儿扫描：删未入库目录与旧格式文件，保留在册书籍', () async {
    final dir = Directory.systemTemp.createTempSync('library_sweep');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = _open(dir).store;
    final entry = await store.importBytes(buildTestEpub(title: '在册书'));

    // 制造孤儿：未知 uuid 目录 + 未引用的旧格式 epub。
    final orphanDir = Directory('${dir.path}/books/orphan-dir')
      ..createSync(recursive: true);
    File('${orphanDir.path}/a.bin').writeAsBytesSync(List<int>.filled(16, 1));
    final orphanFile = File('${dir.path}/books/orphan.epub')
      ..writeAsBytesSync(List<int>.filled(8, 2));

    final swept = await store.sweepOrphans();
    expect(swept.removed, 2);
    expect(swept.bytes, 24);
    expect(orphanDir.existsSync(), isFalse);
    expect(orphanFile.existsSync(), isFalse);
    expect(File(entry.filePath).existsSync(), isTrue, reason: '在册书不受影响');
    expect(await store.list(), hasLength(1));
  });

  test('孤儿扫描不误删旧格式在册文件（迁移场景）', () async {
    final dir = Directory.systemTemp.createTempSync('library_sweep_keep');
    addTearDown(() => dir.deleteSync(recursive: true));
    final epubFile = File('${dir.path}/books/legacy.epub')
      ..createSync(recursive: true)
      ..writeAsBytesSync(buildTestEpub(title: '旧格式'));
    File('${dir.path}/books.json').writeAsStringSync(
      '{"books":[{"id":"legacy-keep","title":"旧格式","author":"作者",'
      '"filePath":"${epubFile.path}","addedAt":1700000000000}]}',
    );
    final store = _open(dir).store;
    await store.migrateLegacyJson();
    final swept = await store.sweepOrphans();
    expect(swept.removed, 0, reason: '数据库引用中的文件必须保留');
    expect(epubFile.existsSync(), isTrue);
  });

  test('封面回填：给缺封面的旧书补提封面', () async {
    final dir = Directory.systemTemp.createTempSync('library_backfill');
    addTearDown(() => dir.deleteSync(recursive: true));
    final withCover = buildTestEpub(title: '可回填', cover: true);
    final epubFile = File('${dir.path}/books/legacy-cover.epub')
      ..createSync(recursive: true)
      ..writeAsBytesSync(withCover);
    File('${dir.path}/books.json').writeAsStringSync(
      '{"books":[{"id":"legacy-cover","title":"可回填","author":"作者",'
      '"filePath":"${epubFile.path}","addedAt":1700000000000}]}',
    );
    final store = _open(dir).store;
    await store.migrateLegacyJson();
    expect((await store.list()).single.coverPath, isNull, reason: '迁移不带封面');

    expect(await store.backfillCovers(), 1);
    final entry = (await store.list()).single;
    expect(entry.coverPath, isNotNull);
    expect(File(entry.coverPath!).existsSync(), isTrue);
    expect(await store.backfillCovers(), 0, reason: '幂等：已有封面不再处理');
  });

  test('旧版 books.json 一次性迁入 drift 且幂等', () async {
    final dir = Directory.systemTemp.createTempSync('library_migrate');
    addTearDown(() => dir.deleteSync(recursive: true));
    final epubFile = File('${dir.path}/legacy.epub')
      ..writeAsBytesSync(buildTestEpub(title: '旧书'));
    File('${dir.path}/books.json').writeAsStringSync(
      '{"books":[{"id":"legacy-1","title":"旧书","author":"旧作者",'
      '"filePath":"${epubFile.path}","addedAt":1700000000000,'
      '"spineCount":1,"readabilityLevel":1}]}',
    );
    final store = _open(dir).store;
    expect(await store.migrateLegacyJson(), 1);
    final books = await store.list();
    expect(books.single.title, '旧书');
    expect(books.single.readabilityLevel, 1);
    expect(await store.migrateLegacyJson(), 0, reason: '幂等：库非空不再迁');
  });
}
