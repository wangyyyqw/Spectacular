import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/book_identity.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_mobile/library/book_identity_migration.dart';
import 'package:reader_mobile/diagnostics/reader_log.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/storage/drift_progress_store.dart';
import 'package:reader_mobile/storage/startup_storage.dart';
import 'package:reader_ui/annotations/annotation.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/test_epub.dart';

const _identifier = 'urn:uuid:12345678-1234-1234-1234-123456789abc';
const _legacyId = 'urn_uuid_12345678-1234-1234-1234-123456789abc';

Uint8List _opfVariant({required bool missing}) {
  final source = ZipDecoder().decodeBytes(
    buildTestEpub(identifier: _identifier),
  );
  final archive = Archive();
  for (final file in source.files) {
    if (file.name == 'OEBPS/content.opf') {
      if (!missing) {
        archive.addFile(ArchiveFile('fallback.opf', file.size, file.content));
      }
    } else if (!missing && file.name == 'META-INF/container.xml') {
      final text = utf8
          .decode(file.content)
          .replaceAll('OEBPS/content.opf', 'fallback.opf');
      final bytes = utf8.encode(text);
      archive.addFile(ArchiveFile(file.name, bytes.length, bytes));
    } else {
      archive.addFile(file);
    }
  }
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

Future<int> _insertLegacy(AppDatabase db, Directory root) async {
  final file = File('${root.path}/books/$_legacyId/source.epub')
    ..createSync(recursive: true)
    ..writeAsBytesSync(buildTestEpub(title: '原书名', identifier: _identifier));
  return db
      .into(db.books)
      .insert(
        BooksCompanion.insert(
          uuid: _legacyId,
          title: '展示新书名',
          author: const Value('展示新作者'),
          contentDir: 'books/$_legacyId',
          sourcePath: Value(file.path),
          createdAt: 100,
        ),
      );
}

Future<void> _seedUserData(LibraryStore library, AppDatabase db) async {
  await DriftProgressStore(db)
      .save(_legacyId, const ReaderProgress(spineIndex: 0, pageIndex: 7));
  await library
      .annotationStore(_legacyId)!
      .add(
        type: ReaderAnnotationType.highlight,
        startCfi: 'epubcfi(/6/2!/4/2/1:0)',
        endCfi: 'epubcfi(/6/2!/4/2/1:3)',
        quote: '原标注',
      );
  await library
      .bookmarkStore(_legacyId)!
      .add(cfi: 'epubcfi(/6/2!/4/2/1:0)', spineIndex: 0, label: '原书签');
  await library.reviewStore()!.save(_legacyId, rating: 5, content: '原书评');
  await library.readingSessionStore()!.add(
    bookId: _legacyId,
    startedAt: DateTime(2026, 1, 1),
    endedAt: DateTime(2026, 1, 1, 0, 5),
  );
  final group = await library.createGroup('原分组');
  await library.setBooksGroup([_legacyId], groupId: group.id);
  final tag = await library.createTag('原标签');
  await library.addBookTag(_legacyId, tag.id);
}

void main() {
  late Directory root;
  late AppDatabase db;
  late LibraryStore library;
  setUp(() {
    root = Directory.systemTemp.createTempSync('book-identity');
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryStore(database: db, directoryProvider: () async => root);
  });
  tearDown(() async {
    await db.close();
    root.deleteSync(recursive: true);
  });

  test('三元组生成32位ID，修改展示资料后重导入仍识别原书', () async {
    final bytes = buildTestEpub(title: '原书名', identifier: _identifier);
    final book = await library.importBytes(bytes, fallbackTitle: '文件名甲');
    final expected = generateBookId(
      title: '原书名',
      author: '测试作者',
      identifier: _identifier,
    );
    expect(book.id, expected);
    final other = await LibraryStore.memory().importBytes(
      bytes,
      fallbackTitle: '不同文件名',
    );
    expect(other.id, expected);
    await library.updateBookMetadata(
      book.id,
      title: '编辑名',
      author: '编辑作者',
      description: '简介',
    );
    final again = await library.importBytes(bytes);
    expect(again.importOutcome, BookImportOutcome.unchanged);
    expect(again.title, '编辑名');
    expect(
      (await db.select(db.books).get()).single.epubIdentifier,
      _identifier,
    );
  });

  test('同UUID不同书名或作者、同书名作者不同UUID可以分别导入', () async {
    final entries = [
      await library.importBytes(
        buildTestEpub(title: '甲', author: '作者', identifier: 'a:b'),
      ),
      await library.importBytes(
        buildTestEpub(title: '乙', author: '作者', identifier: 'a:b'),
      ),
      await library.importBytes(
        buildTestEpub(title: '甲', author: '另一作者', identifier: 'a:b'),
      ),
      await library.importBytes(
        buildTestEpub(title: '甲', author: '作者', identifier: 'a/b'),
      ),
    ];
    expect(entries.map((e) => e.id).toSet(), hasLength(4));
    expect(await library.list(), hasLength(4));
  });

  test('缺失UUID采用固定空值，缺失标题不受文件名影响', () async {
    final bytes = buildTestEpub(title: '', author: '', identifier: '');
    final first = await library.importBytes(bytes, fallbackTitle: '文件甲');
    final second = await LibraryStore.memory().importBytes(
      bytes,
      fallbackTitle: '文件乙',
    );
    expect(first.id, second.id);
    expect(first.id, generateBookId(title: '', author: '', identifier: ''));
    expect(
      (await library.importBytes(bytes)).importOutcome,
      BookImportOutcome.unchanged,
    );
  });

  test('无OPF兜底使用空标识，合法fallback.opf仍保留原UUID', () async {
    final missing = (await openEpub(_opfVariant(missing: true))).document!;
    final valid = (await openEpub(_opfVariant(missing: false))).document!;
    expect(originalEpubIdentifier(missing), '');
    expect(originalEpubIdentifier(valid), _identifier);
    final book = await library.importBytes(
      _opfVariant(missing: true),
      fallbackTitle: '兜底书',
    );
    expect(book.id, generateBookId(title: '', author: '', identifier: ''));
  });

  test('并发重复导入只保留一本，队列可继续使用', () async {
    final bytes = buildTestEpub(identifier: _identifier);
    final first = library.importBytes(bytes);
    final second = LibraryStore(
      database: db,
      directoryProvider: () async => root,
    ).importBytes(bytes);
    await first;
    expect((await second).importOutcome, BookImportOutcome.unchanged);
    expect(await library.list(), hasLength(1));
    await library.importBytes(buildTestEpub(title: '下一本'));
    expect(await library.list(), hasLength(2));
  });

  test('旧书迁移取原EPUB元数据，保留整数外键和字符串关联并幂等', () async {
    final internalId = await _insertLegacy(db, root);
    await _seedUserData(library, db);
    final progress = (await db.select(db.readingProgress).get()).single;
    final annotations = await db.select(db.annotations).get();
    final reviews = await db.select(db.bookReviews).get();
    final sessions = await db.select(db.readingSessions).get();
    expect(await library.migrateBookIds(), 1);
    final book = (await library.list()).single;
    expect(
      book.id,
      generateBookId(title: '原书名', author: '测试作者', identifier: _identifier),
    );
    expect(book.title, '展示新书名');
    expect(await library.internalBookId(book.id), internalId);
    expect(await db.select(db.annotations).get(), annotations);
    expect(await db.select(db.readingProgress).get(), [progress]);
    expect(await db.select(db.bookReviews).get(), reviews);
    expect(await db.select(db.readingSessions).get(), sessions);
    expect((await library.groupAssignments()).keys, [book.id]);
    expect((await library.bookTags(book.id)).single.name, '原标签');
    expect(await library.migrateBookIds(), 0);
    expect((await DriftProgressStore(db).load(_legacyId))?.pageIndex, 7);
  });

  test('迁移后孤儿清理、读书、换封面和删除均保护其他书', () async {
    await _insertLegacy(db, root);
    final original = File('${root.path}/books/$_legacyId/source.epub')
        .readAsBytesSync();
    await library.migrateBookIds();
    final book = (await library.list()).single;
    final other = await library.importBytes(buildTestEpub(title: '另一书'));
    expect((await library.sweepOrphans()).removed, 0);
    expect(await library.readBytes(book), original);
    final changed = await library.replaceCover(
      book.id,
      buildTestEpub(),
      extension: 'png',
    );
    expect(File(changed.coverPath!).existsSync(), isTrue);
    await library.remove(book.id);
    expect(Directory('${root.path}/books/$_legacyId').existsSync(), isFalse);
    expect(File(changed.coverPath!).existsSync(), isFalse);
    expect(File(other.filePath).existsSync(), isTrue);
  });

  test('旧JSON书库和旧键进度按真实启动顺序迁移', () async {
    final file = File('${root.path}/books/legacy.epub')
      ..createSync(recursive: true)
      ..writeAsBytesSync(buildTestEpub(title: '原书名', identifier: _identifier));
    File('${root.path}/books.json').writeAsStringSync(
      jsonEncode({
        'books': [
          {
            'id': 'legacy-json',
            'title': '展示名',
            'author': '作者',
            'filePath': file.path,
            'addedAt': 100,
          },
        ],
      }),
    );
    File('${root.path}/reader_progress.json').writeAsStringSync(
      jsonEncode({
        'legacy-json': {'spine': 0, 'page': 8},
      }),
    );
    final log = ReaderLog();
    expect(await prepareLibraryStorage(library, log), isTrue);
    await prepareProgressStorage(DriftProgressStore(db), () async => root, log);
    final book = (await library.list()).single;
    expect(
      book.id,
      generateBookId(title: '原书名', author: '测试作者', identifier: _identifier),
    );
    expect((await DriftProgressStore(db).load(book.id))?.pageIndex, 8);
    expect(file.existsSync(), isTrue);
  });

  test('旧软删除记录缺少原UUID时保留数据，不凭有损旧ID合并新书', () async {
    final internalId = await _insertLegacy(db, root);
    await DriftProgressStore(db)
        .save(_legacyId, const ReaderProgress(pageIndex: 9, spineIndex: 0));
    await (db.update(db.books)).write(
      const BooksCompanion(
        title: Value('原书名'),
        author: Value('测试作者'),
        sourcePath: Value(null),
        deletedAt: Value(200),
      ),
    );
    expect(await library.migrateBookIds(), 0);
    final book = await library.importBytes(
      buildTestEpub(title: '原书名', identifier: _identifier),
    );
    expect(await library.internalBookId(book.id), isNot(internalId));
    expect((await DriftProgressStore(db).load(_legacyId))?.pageIndex, 9);
    expect(await db.select(db.books).get(), hasLength(2));
  });

  test('旧身份冲突或原书损坏时保留文件和用户记录，不执行孤儿清理', () async {
    await _insertLegacy(db, root);
    await library.importBytes(buildTestEpub(title: '另一书'));
    final first = (await db.select(db.books).get()).first;
    await db
        .into(db.books)
        .insert(
          BooksCompanion.insert(
            uuid: 'legacy-copy',
            title: '副本',
            contentDir: 'books/legacy-copy',
            sourcePath: Value(first.sourcePath),
            createdAt: 101,
          ),
        );
    expect(await prepareLibraryStorage(library, ReaderLog()), isFalse);
    expect(await db.select(db.books).get(), hasLength(3));
    expect(File(first.sourcePath!).existsSync(), isTrue);
    final orphan = File('${root.path}/books/keep.epub')
      ..writeAsStringSync('保留');
    File(first.sourcePath!).writeAsStringSync('损坏');
    expect(await prepareLibraryStorage(library, ReaderLog()), isFalse);
    expect(orphan.existsSync(), isTrue);
    await library.importBytes(buildTestEpub(title: '无关新书'));
    expect(await db.select(db.books).get(), hasLength(4));
  });

  test('旧目录名与新ID相同不会覆盖原书，精确进度查询优先且删除互不影响', () async {
    final newBytes = buildTestEpub(title: '新书', identifier: 'new-book');
    final newId = generateBookId(
      title: '新书',
      author: '测试作者',
      identifier: 'new-book',
    );
    final oldBytes = buildTestEpub(title: '旧书', identifier: newId);
    final oldSource = File('${root.path}/books/$newId/source.epub')
      ..createSync(recursive: true)
      ..writeAsBytesSync(oldBytes);
    await db
        .into(db.books)
        .insert(
          BooksCompanion.insert(
            uuid: newId,
            title: '旧书',
            author: const Value('测试作者'),
            sourcePath: Value(oldSource.path),
            contentDir: 'books/$newId',
            createdAt: 1,
          ),
        );
    await library.migrateBookIds();
    final oldBook = (await library.list()).single;
    final progress = DriftProgressStore(db);
    await progress.save(
      oldBook.id,
      const ReaderProgress(spineIndex: 0, pageIndex: 3),
    );
    final newBook = await library.importBytes(newBytes);
    await progress.save(
      newBook.id,
      const ReaderProgress(spineIndex: 0, pageIndex: 8),
    );
    expect(oldSource.readAsBytesSync(), oldBytes);
    expect((await progress.load(newId))?.pageIndex, 8);
    expect((await library.sweepOrphans()).removed, 0);
    await library.remove(oldBook.id);
    expect(File(newBook.filePath).readAsBytesSync(), newBytes);
    expect((await progress.load(newBook.id))?.pageIndex, 8);
  });

  test('未迁移旧记录与新ID同值时明确拒绝，不把旧用户数据挂到新书', () async {
    final bytes = buildTestEpub(title: '新书', identifier: 'new-book');
    final id = generateBookId(
      title: '新书',
      author: '测试作者',
      identifier: 'new-book',
    );
    await db
        .into(db.books)
        .insert(
          BooksCompanion.insert(
            uuid: id,
            title: '已删旧书',
            contentDir: 'books/$id',
            createdAt: 1,
            deletedAt: const Value(2),
          ),
        );
    final oldId = (await db.select(db.books).get()).single.id;
    await db
        .into(db.readingProgress)
        .insert(
          ReadingProgressCompanion.insert(
            bookId: Value(oldId),
            locatorCfi: 'spine:0/page:4',
            percent: const Value(0.0),
            spineIndex: const Value(0),
            pageIndex: const Value(4),
            updatedAt: 1,
          ),
        );
    await expectLater(
      library.importBytes(bytes),
      throwsA(
        isA<LibraryImportException>().having(
          (e) => e.errorCode,
          '标识冲突',
          'E_IDENTITY_CONFLICT',
        ),
      ),
    );
    expect((await db.select(db.books).get()).single.title, '已删旧书');
    expect((await DriftProgressStore(db).load(id))?.pageIndex, 4);
  });

  test('旧ID已经等于新摘要时仍能清理旧命名空间文件', () async {
    final bytes = buildTestEpub(title: '原书名', identifier: _identifier);
    final id = generateBookId(
      title: '原书名',
      author: '测试作者',
      identifier: _identifier,
    );
    final file = File('${root.path}/books/$id/source.epub')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
    await db
        .into(db.books)
        .insert(
          BooksCompanion.insert(
            uuid: id,
            title: '原书名',
            contentDir: 'books/$id',
            sourcePath: Value(file.path),
            createdAt: 1,
          ),
        );
    expect(await library.migrateBookIds(), 1);
    await library.remove(id);
    expect(file.existsSync(), isFalse);
    expect(file.parent.existsSync(), isFalse);
  });
}
