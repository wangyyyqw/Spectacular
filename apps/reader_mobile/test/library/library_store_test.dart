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
    store: LibraryStore(database: db, directoryProvider: () async => dir),
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

  test('文件导入：直接复制原书并保留查重语义', () async {
    final dir = Directory.systemTemp.createTempSync('library_file_import');
    final sourceDir = Directory.systemTemp.createTempSync(
      'library_file_source',
    );
    addTearDown(() {
      dir.deleteSync(recursive: true);
      sourceDir.deleteSync(recursive: true);
    });
    final bytes = buildTestEpub(
      title: '文件导入书',
      identifier: 'file-import-book',
      cover: true,
    );
    final source = File('${sourceDir.path}/book.epub')..writeAsBytesSync(bytes);
    final store = _open(dir).store;

    final entry = await store.importFile(source.path);

    expect(entry.title, '文件导入书');
    expect(entry.importOutcome, BookImportOutcome.added);
    expect(File(entry.filePath).readAsBytesSync(), bytes);
    expect(
      (await store.importFile(source.path)).importOutcome,
      BookImportOutcome.unchanged,
    );
  });

  test('分析后源文件被替换时拒绝导入，摘要不与其他内容一起落库', () async {
    final dir = Directory.systemTemp.createTempSync('library_changed_input');
    addTearDown(() => dir.deleteSync(recursive: true));
    final opened = _open(dir);
    final original = buildTestEpub(title: '分析时的书', identifier: 'analyzed-book');
    final changed = buildTestEpub(title: '替换后的书', identifier: 'replaced-book');
    final source = File(p.join(dir.path, 'incoming.epub'))
      ..writeAsBytesSync(original);

    await expectLater(
      opened.store.importFile(
        source.path,
        onProgress: (value) {
          if (value == 0.45) source.writeAsBytesSync(changed);
        },
      ),
      throwsA(
        isA<LibraryImportException>().having(
          (error) => error.errorCode,
          '错误码',
          'E_IMPORT_SOURCE_CHANGED',
        ),
      ),
    );

    expect(await opened.store.list(), isEmpty);
    expect(await opened.db.select(opened.db.books).get(), isEmpty);
    expect(source.readAsBytesSync(), orderedEquals(changed));
    expect(
      Directory(p.join(dir.path, 'books'))
          .listSync(recursive: true)
          .whereType<File>(),
      isEmpty,
    );
  });

  test('提交前检查实际暂存副本，源文件未变但副本被修改也拒绝导入', () async {
    final dir = Directory.systemTemp.createTempSync('library_changed_snapshot');
    addTearDown(() => dir.deleteSync(recursive: true));
    final opened = _open(dir);
    final original = buildTestEpub(identifier: 'staged-analysis');
    final changed = buildTestEpub(identifier: 'staged-replacement');
    final source = File(p.join(dir.path, 'incoming.epub'))
      ..writeAsBytesSync(original);

    await expectLater(
      opened.store.importFile(
        source.path,
        onProgress: (value) {
          if (value != 0.95) return;
          final snapshot = Directory(p.join(dir.path, 'books'))
              .listSync(recursive: true)
              .whereType<File>()
              .singleWhere((file) => p.basename(file.path) == 'source.epub');
          snapshot.writeAsBytesSync(changed);
        },
      ),
      throwsA(
        isA<LibraryImportException>().having(
          (error) => error.errorCode,
          '错误码',
          'E_IMPORT_SOURCE_CHANGED',
        ),
      ),
    );

    expect(await opened.store.list(), isEmpty);
    expect(source.readAsBytesSync(), orderedEquals(original));
    expect(
      Directory(p.join(dir.path, 'books'))
          .listSync(recursive: true)
          .whereType<File>(),
      isEmpty,
    );
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

  test('相同文件重复导入不迁移，提示内容未变化', () async {
    final dir = Directory.systemTemp.createTempSync('library_dup');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = _open(dir).store;
    final bytes = buildTestEpub(title: '唯一书');
    await store.importBytes(bytes);
    final again = await store.importBytes(bytes);
    expect(again.importOutcome, BookImportOutcome.unchanged);
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
      expect(
        (await store.importBytes(buildTestEpub(identifier: identifier)))
            .importOutcome,
        BookImportOutcome.unchanged,
      );
      await store.remove(book.id);
      expect(File(book.filePath).existsSync(), isFalse);
      expect(sentinel.readAsStringSync(), '保留');
      expect(File(other.filePath).existsSync(), isTrue);
    }
  });

  test('异常标识只删记录，拒绝递归删除父目录或目录外原书', () async {
    final dir = Directory.systemTemp.createTempSync('library_unsafe_id');
    addTearDown(() => dir.deleteSync(recursive: true));
    final opened = _open(dir);
    final sentinel = File('${dir.path}/sentinel.txt')..writeAsStringSync('保留');
    for (final id in ['.', '..', '../outside']) {
      await opened.db
          .into(opened.db.books)
          .insert(
            BooksCompanion.insert(
              uuid: id,
              contentRevision: 'test-content',
              title: '异常标识',
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

  test('不存在的书籍标识不证明目录归属，删除不清理同名目录', () async {
    final dir = Directory.systemTemp.createTempSync('library_missing_id');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = _open(dir).store;
    final directory = Directory(p.join(dir.path, 'books', 'missing-book'))
      ..createSync(recursive: true);
    final retained = File(p.join(directory.path, 'retained.epub'))
      ..writeAsStringSync('无法证明属于待删除书籍的文件');

    await store.remove('missing-book');

    expect(retained.readAsStringSync(), '无法证明属于待删除书籍的文件');
  });

  test('目录没有本书文件指针时，删除记录不凭标识清理同名目录', () async {
    final dir = Directory.systemTemp.createTempSync(
      'library_unowned_directory',
    );
    addTearDown(() => dir.deleteSync(recursive: true));
    final opened = _open(dir);
    const id = 'unowned-book';
    final source = File(p.join(dir.path, 'external.epub'))
      ..writeAsStringSync('外部文件');
    final directory = Directory(p.join(dir.path, 'books', id))
      ..createSync(recursive: true);
    final retained = File(p.join(directory.path, 'retained.epub'))
      ..writeAsStringSync('没有本书引用的文件');
    await opened.db
        .into(opened.db.books)
        .insert(
          BooksCompanion.insert(
            uuid: id,
            contentRevision: 'test-content',
            title: '目录归属异常',
            contentDir: 'books/$id',
            sourcePath: Value(source.path),
            createdAt: 0,
          ),
        );

    await opened.store.remove(id);

    expect(await opened.store.list(), isEmpty);
    expect(retained.readAsStringSync(), '没有本书引用的文件');
    expect(source.readAsStringSync(), '外部文件');
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

  test('progressWeights：未取得字符统计时按章等权估算', () async {
    final dir = Directory.systemTemp.createTempSync('library_chars_legacy');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = _open(dir).store;
    final weights = await store.progressWeights('不存在');
    expect(weights.total, 0);
    expect(weights.estimated, isFalse);
  });

  test('批量读取进度权重：按书隔离且忽略不存在条目', () async {
    final dir = Directory.systemTemp.createTempSync('library_chars_batch');
    addTearDown(() => dir.deleteSync(recursive: true));
    final opened = _open(dir);
    final store = opened.store;
    final first = await store.importBytes(buildTestEpub(title: '权重书一'));
    final second = await store.importBytes(
      buildTestEpub(
        title: '权重书二',
        paragraphs: const <String>['第二章正文更长一些，用于验证批量权重隔离。'],
      ),
    );

    final weights = await store.progressWeightsForBooks(<String>[
      first.id,
      second.id,
      '不存在',
    ]);
    final firstSingle = await store.progressWeights(first.id);
    final secondSingle = await store.progressWeights(second.id);

    expect(weights.keys, unorderedEquals(<String>[first.id, second.id]));
    expect(weights[first.id]!.charCounts, firstSingle.charCounts);
    expect(weights[first.id]!.charStarts, firstSingle.charStarts);
    expect(weights[second.id]!.charCounts, secondSingle.charCounts);
    expect(weights[second.id]!.charStarts, secondSingle.charStarts);
    expect(weights[second.id]!.total, secondSingle.total);
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

  test('分组：创建、移动、重命名、删除且跨实例持久化', () async {
    final dir = Directory.systemTemp.createTempSync('library_groups');
    addTearDown(() => dir.deleteSync(recursive: true));
    final opened = _open(dir);
    final first = await opened.store.importBytes(
      buildTestEpub(title: '分组甲', identifier: 'group-a'),
    );
    final second = await opened.store.importBytes(
      buildTestEpub(title: '分组乙', identifier: 'group-b'),
    );

    final group = await opened.store.createGroup(' 小说 ');
    expect(group.name, '小说');
    await opened.store.setBooksGroup([first.id], groupId: group.id);
    expect(await opened.store.groupAssignments(), <String, String>{
      first.id: group.id,
    });

    final secondStore = LibraryStore(
      database: opened.db,
      directoryProvider: () async => dir,
    );
    expect((await secondStore.listGroups()).single.name, '小说');
    expect(await secondStore.groupAssignments(), <String, String>{
      first.id: group.id,
    });

    await secondStore.setBooksGroup([second.id], groupId: group.id);
    expect(await secondStore.groupAssignments(), <String, String>{
      first.id: group.id,
      second.id: group.id,
    });
    await secondStore.renameGroup(group.id, '文学');
    expect((await secondStore.listGroups()).single.name, '文学');
    await secondStore.deleteGroup(group.id);
    expect(await secondStore.listGroups(), isEmpty);
    expect(await secondStore.groupAssignments(), isEmpty);
    expect(await secondStore.list(), hasLength(2), reason: '删分组不删书');
  });

  test('分组：拒绝空名和重名，移出分组不删书', () async {
    final store = LibraryStore.memory();
    final book = await store.importBytes(
      buildTestEpub(title: '内存分组书', identifier: 'group-memory'),
    );
    await expectLater(
      store.createGroup('  '),
      throwsA(isA<LibraryImportException>()),
    );
    final group = await store.createGroup('待读');
    await expectLater(
      store.createGroup('待读'),
      throwsA(isA<LibraryImportException>()),
    );
    await store.setBooksGroup([book.id], groupId: group.id);
    expect(await store.groupAssignments(), <String, String>{book.id: group.id});
    await store.setBooksGroup([book.id]);
    expect(await store.groupAssignments(), isEmpty);
    expect(await store.list(), hasLength(1));
  });

  test('图书资料编辑：保存书名、作者、简介并跨实例持久化', () async {
    final dir = Directory.systemTemp.createTempSync('library_metadata');
    addTearDown(() => dir.deleteSync(recursive: true));
    final opened = _open(dir);
    final entry = await opened.store.importBytes(
      buildTestEpub(title: '原书名', identifier: 'metadata-book'),
    );

    final updated = await opened.store.updateBookMetadata(
      entry.id,
      title: ' 新书名 ',
      author: ' 新作者 ',
      description: ' 一段新的简介 ',
    );
    expect(updated.title, '新书名');
    expect(updated.author, '新作者');
    expect(updated.description, '一段新的简介');

    final second = LibraryStore(
      database: opened.db,
      directoryProvider: () async => dir,
    );
    final reloaded = await second.bookById(entry.id);
    expect(reloaded?.title, '新书名');
    expect(reloaded?.author, '新作者');
    expect(reloaded?.description, '一段新的简介');
    await expectLater(
      second.updateBookMetadata(
        entry.id,
        title: '  ',
        author: '',
        description: '',
      ),
      throwsA(isA<LibraryImportException>()),
    );
  });

  test('标签：创建复用、关联取消且跨实例持久化', () async {
    final dir = Directory.systemTemp.createTempSync('library_tags');
    addTearDown(() => dir.deleteSync(recursive: true));
    final opened = _open(dir);
    final first = await opened.store.importBytes(
      buildTestEpub(title: '标签书甲', identifier: 'tag-a'),
    );
    final secondBook = await opened.store.importBytes(
      buildTestEpub(title: '标签书乙', identifier: 'tag-b'),
    );

    final tag = await opened.store.createTag(' 科幻 ');
    expect(tag.name, '科幻');
    expect((await opened.store.createTag('科幻')).id, tag.id);
    await opened.store.addBookTag(first.id, tag.id);
    await opened.store.addBookTag(first.id, tag.id);
    await opened.store.addBookTag(secondBook.id, tag.id);
    expect(
      (await opened.store.bookTags(first.id)).single.name,
      '科幻',
      reason: '重复添加保持幂等',
    );

    final second = LibraryStore(
      database: opened.db,
      directoryProvider: () async => dir,
    );
    expect((await second.listTags()).single.name, '科幻');
    expect(await second.bookTags(secondBook.id), hasLength(1));

    await second.removeBookTag(first.id, tag.id);
    expect(await second.bookTags(first.id), isEmpty);
    expect(await second.bookTags(secondBook.id), hasLength(1));
  });

  test('同数据库跨实例并发创建同名标签，返回唯一已持久化标签', () async {
    final dir = Directory.systemTemp.createTempSync('library_concurrent_tags');
    addTearDown(() => dir.deleteSync(recursive: true));
    final opened = _open(dir);
    final second = LibraryStore(
      database: opened.db,
      directoryProvider: () async => dir,
    );

    final tags = await Future.wait([
      opened.store.createTag(' 并发标签 '),
      second.createTag('并发标签'),
      opened.store.createTag('并发标签'),
    ]);

    expect(tags.map((tag) => tag.id).toSet(), hasLength(1));
    expect(tags.map((tag) => tag.name).toSet(), {'并发标签'});
    final stored = (await second.listTags()).single;
    expect(stored.id, tags.first.id);
    expect(stored.createdAt, tags.first.createdAt);
  });

  test('内存模式并发创建同名标签，查重与写入之间不让出执行', () async {
    final store = LibraryStore.memory();

    final tags = await Future.wait([
      store.createTag(' 内存并发标签 '),
      store.createTag('内存并发标签'),
    ]);

    expect(tags.map((tag) => tag.id).toSet(), hasLength(1));
    expect((await store.listTags()).single.name, '内存并发标签');
  });

  test('内存模式编辑资料和阅读时间保留内容摘要及标签', () async {
    final store = LibraryStore.memory();
    final book = await store.importBytes(
      buildTestEpub(title: '内存书', identifier: 'memory-meta'),
    );
    expect(book.contentRevision, matches(RegExp(r'^[0-9a-f]{64}$')));
    await store.updateBookMetadata(
      book.id,
      title: '内存新书名',
      author: '作者',
      description: '简介',
    );
    final tag = await store.createTag('待读');
    await store.addBookTag(book.id, tag.id);
    await store.touchLastRead(book.id);

    expect((await store.bookById(book.id))?.description, '简介');
    expect(
      (await store.bookById(book.id))?.contentRevision,
      book.contentRevision,
    );
    expect((await store.bookTags(book.id)).single.name, '待读');
    await store.removeBookTag(book.id, tag.id);
    expect(await store.bookTags(book.id), isEmpty);
  });

  test('替换封面：新文件落盘并清理书目录内的旧封面', () async {
    final dir = Directory.systemTemp.createTempSync('library_cover_replace');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = _open(dir).store;
    final entry = await store.importBytes(
      buildTestEpub(title: '换封面', identifier: 'cover-book', cover: true),
    );
    final oldCover = entry.coverPath!;
    expect(File(oldCover).existsSync(), isTrue);

    final first = await store.replaceCover(
      entry.id,
      Uint8List.fromList(<int>[1, 2, 3, 4]),
      extension: 'png',
    );
    expect(first.coverPath, isNot(oldCover));
    expect(first.coverPath, endsWith('.png'));
    expect(File(first.coverPath!).readAsBytesSync(), <int>[1, 2, 3, 4]);
    expect(File(oldCover).existsSync(), isFalse, reason: '旧封面已清理');

    final second = await store.replaceCover(
      entry.id,
      Uint8List.fromList(<int>[5, 6]),
      extension: 'jpeg',
    );
    expect(second.coverPath, endsWith('.jpg'));
    expect(File(first.coverPath!).existsSync(), isFalse);
    expect((await store.bookById(entry.id))?.coverPath, second.coverPath);
    await expectLater(
      store.replaceCover(
        entry.id,
        Uint8List.fromList(<int>[1]),
        extension: 'gif',
      ),
      throwsA(isA<LibraryImportException>()),
    );
  });

  test('孤儿扫描清理未入库目录和临时文件，保留在册书籍', () async {
    final dir = Directory.systemTemp.createTempSync('library_sweep');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = _open(dir).store;
    final entry = await store.importBytes(buildTestEpub(title: '在册书'));

    // 制造孤儿：未知书目录和未提交文件。
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
}
