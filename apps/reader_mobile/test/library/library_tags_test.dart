import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/library/revision_anchor_index.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/storage/drift_progress_store.dart';
import 'package:reader_mobile/sync/sync_engine.dart';
import 'package:reader_mobile/sync/sync_models.dart';
import 'package:reader_mobile/sync/sync_storage.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:xml/xml.dart';

import '../support/test_epub.dart';

typedef _Library = ({Directory root, AppDatabase db, LibraryStore store});

Future<_Library> _library() async {
  final root = await Directory.systemTemp.createTemp('delete-library-tag-');
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });
  return (
    root: root,
    db: db,
    store: LibraryStore(database: db, directoryProvider: () async => root),
  );
}

Future<BookEntry> _book(LibraryStore store, String name) => store.importBytes(
  buildTestEpub(title: name, identifier: 'tag-delete-$name', cover: true),
);

Future<List<String>> _subjects(BookEntry book) async {
  final opened = await openEpubFile(File(book.filePath), verifyCrc: true);
  expect(opened.ok, isTrue);
  final document = opened.document!;
  try {
    return XmlDocument.parse(document.archive.readString(document.opfPath)!)
        .descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'subject')
        .map((element) => element.innerText)
        .toList();
  } finally {
    document.archive.close();
  }
}

Future<List<Map<String, Object?>>> _rows(AppDatabase db, String table) async =>
    [
      for (final row
          in await db.customSelect('SELECT * FROM $table ORDER BY rowid').get())
        Map<String, Object?>.from(row.data),
    ];

Future<Set<String>> _versionDirectories(_Library library) async {
  final paths = <String>{};
  await for (final entry in library.root.list(recursive: true)) {
    if (entry is Directory && entry.parent.path.endsWith('/versions')) {
      paths.add(entry.path);
    }
  }
  return paths;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('内存标签全局删除清关联且保留叠加开关，重复删除不通知', () async {
    final store = LibraryStore.memory();
    final first = await _book(store, '内存甲');
    final second = await _book(store, '内存乙');
    final removed = await store.createTag('删除');
    final kept = await store.createTag('保留');
    await store.addBookTag(first.id, removed.id);
    await store.addBookTag(second.id, removed.id);
    await store.addBookTag(first.id, kept.id);
    await store.setSetting(bookshelfTagStacksKey, 'true');
    var notifications = 0;
    store.addListener(() => notifications++);

    await store.deleteTag(removed.id);

    expect((await store.listTags()).map((tag) => tag.id), [kept.id]);
    expect((await store.bookTags(first.id)).map((tag) => tag.id), [kept.id]);
    expect(await store.bookTags(second.id), isEmpty);
    expect(await store.getSetting(bookshelfTagStacksKey), 'true');
    expect(notifications, 1);
    await store.deleteTag(removed.id);
    await store.deleteTag('不存在');
    expect(notifications, 1);
    expect(await store.list(), hasLength(2));
  });

  test('多书删除标签一次切换EPUB，保留其他资料、封面、正文和阅读进度', () async {
    final f = await _library();
    final first = await _book(f.store, '保留资料甲');
    final second = await _book(f.store, '保留资料乙');
    final removed = await f.store.createTag('删除');
    final kept = await f.store.createTag('保留');
    for (final book in [first, second]) {
      await f.store.addBookTag(book.id, removed.id);
      await f.store.addBookTag(book.id, kept.id);
    }
    final before = [
      (await f.store.bookById(first.id))!,
      (await f.store.bookById(second.id))!,
    ];
    final originals = {
      for (final book in before)
        book.id: await File(book.filePath).readAsBytes(),
    };
    final index = await buildRevisionAnchorBookFile(
      File(before.first.filePath),
      revision: before.first.contentRevision!,
    );
    final cfi = index.chapter(0)!.cfiAt(0)!;
    final progress = DriftProgressStore(f.db);
    await progress.save(
      first.id,
      ReaderProgress(
        spineIndex: 0,
        pageIndex: 3,
        cfi: cfi,
        contentRevision: before.first.contentRevision,
        readingPercent: .42,
        scrollOffset: 91,
      ),
    );
    final previousProgress = await _rows(f.db, 'reading_progress');
    final previousSpine = await _rows(f.db, 'spine_items');
    await f.store.setSetting(bookshelfTagStacksKey, 'true');
    var notifications = 0;
    f.store.addListener(() => notifications++);

    await f.store.deleteTag(removed.id);

    expect(notifications, 1);
    for (final original in before) {
      final current = (await f.store.bookById(original.id))!;
      expect(current.contentRevision, isNot(original.contentRevision));
      expect(current.title, original.title);
      expect(current.author, original.author);
      expect(current.description, original.description);
      expect(current.coverPath, original.coverPath);
      expect(
        await File(original.filePath).readAsBytes(),
        originals[original.id],
      );
      expect(await _subjects(current), ['保留']);
      final oldDocument = (await openEpubFile(File(original.filePath)))
          .document!;
      final nextDocument = (await openEpubFile(File(current.filePath)))
          .document!;
      try {
        expect(
          nextDocument.archive.readBytes('OEBPS/c1.xhtml'),
          oldDocument.archive.readBytes('OEBPS/c1.xhtml'),
        );
        expect(nextDocument.readCoverBytes(), oldDocument.readCoverBytes());
      } finally {
        oldDocument.archive.close();
        nextDocument.archive.close();
      }
    }
    final saved = (await progress.load(first.id))!;
    expect(saved.cfi, cfi);
    expect(saved.pageIndex, 3);
    expect(saved.readingPercent, .42);
    expect(saved.scrollOffset, 91);
    final nextProgress = await _rows(f.db, 'reading_progress');
    final oldAnchor = jsonDecode(
      previousProgress.single['anchor_json']! as String,
    ) as Map<String, dynamic>;
    final newAnchor = jsonDecode(
      nextProgress.single['anchor_json']! as String,
    ) as Map<String, dynamic>;
    expect(
      (newAnchor['current'] as Map)['revision'],
      (await f.store.bookById(first.id))!.contentRevision,
    );
    newAnchor['current'] = oldAnchor['current'];
    expect(newAnchor, oldAnchor);
    nextProgress.single['anchor_json'] = previousProgress.single['anchor_json'];
    expect(nextProgress, previousProgress);
    expect(await _rows(f.db, 'spine_items'), previousSpine);
    expect((await f.store.listTags()).map((tag) => tag.id), [kept.id]);
    expect(await f.store.getSetting(bookshelfTagStacksKey), 'true');
    final revision = (await f.store.bookById(first.id))!.contentRevision;
    await f.store.deleteTag(removed.id);
    expect((await f.store.bookById(first.id))!.contentRevision, revision);
    expect(notifications, 1);
  });

  test('第二本源文件外改时整次失败，不发布第一本暂存版本', () async {
    final f = await _library();
    final first = await _book(f.store, '外改甲');
    final second = await _book(f.store, '外改乙');
    final tag = await f.store.createTag('删除');
    await f.store.addBookTag(first.id, tag.id);
    await f.store.addBookTag(second.id, tag.id);
    final rows = await _rows(f.db, 'books');
    final links = await _rows(f.db, 'book_tag_links');
    final directories = await _versionDirectories(f);
    final currentSecond = (await f.store.bookById(second.id))!;
    await File(currentSecond.filePath).writeAsBytes([1], mode: FileMode.append);

    await expectLater(f.store.deleteTag(tag.id), throwsA(anything));

    expect(await _rows(f.db, 'books'), rows);
    expect(await _rows(f.db, 'book_tag_links'), links);
    expect((await f.store.listTags()).single.id, tag.id);
    expect(await _versionDirectories(f), directories);
    expect(await _subjects((await f.store.bookById(first.id))!), ['删除']);
  });

  test('标签最终删除失败回滚所有书籍版本、关联和堆叠设置并清暂存', () async {
    final f = await _library();
    final books = [await _book(f.store, '回滚甲'), await _book(f.store, '回滚乙')];
    final tag = await f.store.createTag('删除');
    for (final book in books) {
      await f.store.addBookTag(book.id, tag.id);
    }
    await f.store.setSetting(bookshelfTagStacksKey, 'true');
    final rows = await _rows(f.db, 'books');
    final links = await _rows(f.db, 'book_tag_links');
    final directories = await _versionDirectories(f);
    await f.db.customStatement(
      "CREATE TRIGGER reject_tag_delete BEFORE DELETE ON book_tags BEGIN SELECT RAISE(ABORT, '模拟删除失败'); END",
    );

    await expectLater(f.store.deleteTag(tag.id), throwsA(anything));

    expect(await _rows(f.db, 'books'), rows);
    expect(await _rows(f.db, 'book_tag_links'), links);
    expect((await f.store.listTags()).single.id, tag.id);
    expect(await f.store.getSetting(bookshelfTagStacksKey), 'true');
    expect(await _versionDirectories(f), directories);
  });

  test('阅读或编辑草稿保护全部关联书籍，未发生部分删除', () async {
    final f = await _library();
    final first = await _book(f.store, '保护甲');
    final second = await _book(f.store, '保护乙');
    final tag = await f.store.createTag('删除');
    await f.store.addBookTag(first.id, tag.id);
    await f.store.addBookTag(second.id, tag.id);
    final rows = await _rows(f.db, 'books');
    final directories = await _versionDirectories(f);
    f.store.beginSyncRead();
    await expectLater(
      f.store.deleteTag(tag.id),
      throwsA(isA<LibraryImportException>()),
    );
    f.store.endSyncRead();
    final currentSecond = (await f.store.bookById(second.id))!;
    await f.store.persistEditDraft(
      second.id,
      currentSecond.contentRevision!,
      (_) => {'version': 1},
    );

    await expectLater(
      f.store.deleteTag(tag.id),
      throwsA(isA<LibraryImportException>()),
    );

    expect(await _rows(f.db, 'books'), rows);
    expect((await f.store.listTags()).single.id, tag.id);
    expect(await f.store.loadEditDraft(second.id), isNotNull);
    expect(await _versionDirectories(f), directories);
  });

  test('软删、尚无源路径和已清理本机文件的书只清标签关联', () async {
    final f = await _library();
    final deleted = await _book(f.store, '软删');
    final absent = await _book(f.store, '无源路径');
    final cleared = await _book(f.store, '清理文件');
    final tag = await f.store.createTag('删除');
    for (final book in [deleted, absent, cleared]) {
      await f.store.addBookTag(book.id, tag.id);
    }
    await f.store.remove(deleted.id);
    await (f.db.update(f.db.books)..where((row) => row.uuid.equals(absent.id)))
        .write(const BooksCompanion(sourcePath: Value(null)));
    await f.store.syncRepository().clearBookFile(cleared.id);
    final rows = await _rows(f.db, 'books');

    await f.store.deleteTag(tag.id);

    expect(await f.store.listTags(), isEmpty);
    expect(await _rows(f.db, 'book_tag_links'), isEmpty);
    expect(await _rows(f.db, 'books'), rows);
  });

  test('删除不存在的标签不改变叠加开关，也不触发书库刷新', () async {
    final f = await _library();
    await f.store.setSetting(bookshelfTagStacksKey, 'true');
    var notifications = 0;
    f.store.addListener(() => notifications++);

    await f.store.deleteTag('missing');

    expect(await f.store.getSetting(bookshelfTagStacksKey), 'true');
    await f.store.deleteTag('missing');
    expect(await f.store.listTags(), isEmpty);
    expect(notifications, 0);
  });

  test('全局删除由现有同步快照缺失产生标签和关联tombstone', () async {
    final f = await _library();
    final book = await _book(f.store, '同步标签');
    final tag = await f.store.createTag('删除');
    await f.store.addBookTag(book.id, tag.id);
    final engine = SyncEngine(
      repository: f.store.syncRepository(),
      storage: _TagCloud(),
      profile: const SyncProfile(
        provider: SyncProvider.webdav,
        endpoint: 'http://localhost',
        automatic: false,
      ),
      credentials: const SyncCredentials(),
    );
    await engine.create(encrypted: false);
    await engine.sync();
    final keys = engine.state.heads.keys
        .where(
          (key) =>
              key.startsWith('book_tags/') || key.startsWith('book_tag_links/'),
        )
        .toList();
    expect(keys, hasLength(2));

    await f.store.deleteTag(tag.id);
    await engine.sync();

    for (final key in keys) {
      expect(engine.state.heads[key]!.deleted, isTrue);
    }
  });
}

class _TagCloud implements SyncStorage {
  final _objects = <String, Uint8List>{};

  @override
  Future<Uint8List?> read(String key) async => _objects[key];

  @override
  Future<void> upload(String key, File file, {bool createOnly = false}) async {
    if (createOnly && _objects.containsKey(key)) throw StateError('对象已存在');
    _objects[key] = await file.readAsBytes();
  }

  @override
  Future<void> download(String key, File file) async {
    await file.parent.create(recursive: true);
    await file.writeAsBytes(_objects[key]!);
  }

  @override
  Future<List<String>> list(String directory) async => _objects.keys
      .where((key) => key.startsWith('$directory/'))
      .map(
        (key) =>
            '$directory/${key.substring(directory.length + 1).split('/').first}',
      )
      .toSet()
      .toList();

  @override
  Future<void> delete(String key) async => _objects.remove(key);

  @override
  void close() {}
}
