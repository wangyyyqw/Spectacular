import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/library/revision_anchor_index.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/storage/drift_progress_store.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/test_epub.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final databases = <LibraryStore, AppDatabase>{};

  Future<LibraryStore> open() async {
    final root = await Directory.systemTemp.createTemp('import-conflict-');
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async {
      await db.close();
      await root.delete(recursive: true);
    });
    final library = LibraryStore(
      database: db,
      directoryProvider: () async => root,
    );
    databases[library] = db;
    return library;
  }

  test('同名不同身份覆盖沿用更新路径，保留书评和身份，取消不改文件', () async {
    final library = await open();
    final originalBytes = buildTestEpub(title: '同名书', identifier: 'version-a');
    final original = await library.importBytes(originalBytes);
    final reviewStore = library.reviewStore()!;
    await DriftProgressStore(databases[library]!)
        .setFinished(original.id, true);
    await reviewStore.save(original.id, rating: 4, content: '已有评价');
    final incoming = buildTestEpub(
      title: '同名书',
      identifier: 'version-b',
      paragraphs: ['替换后的正文'],
    );
    final updated = await library.importBytes(
      incoming,
      onConflict: (conflict) async {
        expect(conflict.books.single.id, original.id);
        return BookImportChoice.overwrite;
      },
    );
    expect(updated.id, original.id);
    expect(updated.importOutcome, BookImportOutcome.updated);
    expect(await library.list(), hasLength(1));
    expect(await library.readBytes(updated), incoming);
    expect(await File(original.filePath).exists(), isFalse);
    expect((await reviewStore.snapshot())[original.id]!.content, '已有评价');
    await expectLater(
      library.importBytes(
        originalBytes,
        onConflict: (_) async => BookImportChoice.cancel,
      ),
      throwsA(isA<LibraryImportException>()),
    );
    expect(await library.readBytes(updated), incoming);
    expect(await library.list(), hasLength(1));
  });

  test('相同UUID和内容可独立导入，重名覆盖只更新所选版本', () async {
    final library = await open();
    final bytes = buildTestEpub(title: '独立版', identifier: 'same-uuid');
    final first = await library.importBytes(bytes);
    final independent = await library.importBytes(
      bytes,
      onConflict: (_) async => BookImportChoice.independent,
    );
    expect(independent.id, isNot(first.id));
    expect(await library.list(), hasLength(2));
    expect(independent.filePath, isNot(first.filePath));
    expect(await library.readBytes(first), bytes);
    expect(await library.readBytes(independent), bytes);
  });

  test('真实EPUB UUID跨书名变化仍识别同书，覆盖保持本地身份', () async {
    final library = await open();
    const uuid = 'urn:uuid:4f9c9e21-4ab3-4f8b-8b93-536c689824a1';
    final first = await library.importBytes(
      buildTestEpub(title: '旧书名', identifier: uuid),
    );
    final next = await library.importBytes(
      buildTestEpub(title: '新书名', identifier: uuid),
    );
    expect(next.id, first.id);
    expect(next.importOutcome, BookImportOutcome.updated);
    expect(await library.list(), hasLength(1));
  });

  test('直接导入UUID相同但书名不同仍提示覆盖，取消保留原书', () async {
    final library = await open();
    const uuid = 'urn:uuid:4f9c9e21-4ab3-4f8b-8b93-536c689824a1';
    final original = buildTestEpub(title: '旧书名', identifier: uuid);
    final book = await library.importBytes(original);
    await expectLater(
      library.importBytes(
        buildTestEpub(title: '新书名', identifier: uuid),
        onConflict: (conflict) async {
          expect(conflict.books.single.id, book.id);
          return BookImportChoice.cancel;
        },
      ),
      throwsA(isA<LibraryImportException>()),
    );
    expect(await library.readBytes(book), original);
    expect(await library.list(), hasLength(1));
  });

  test('同版本文件补回原记录，不改已保存的文字位置和读完标记', () async {
    final library = await open();
    final bytes = buildTestEpub(title: '文件恢复书', paragraphs: ['已有阅读位置的正文']);
    final book = await library.importBytes(bytes);
    final index = await buildRevisionAnchorBook(bytes);
    final progress = DriftProgressStore(databases[library]!);
    await progress.save(
      book.id,
      ReaderProgress(
        spineIndex: 0,
        pageIndex: 2,
        cfi: index.chapter(0)!.cfiAt(3),
        contentRevision: index.revision,
        finished: true,
      ),
    );
    final db = databases[library]!;
    final before = (await db.select(db.readingProgress).getSingle()).toJson();
    await File(book.filePath).delete();
    final restored = await library.updateBytes(
      book.id,
      bytes,
      preserveIdentity: true,
    );
    expect(restored.id, book.id);
    expect(await library.readBytes(restored), bytes);
    expect((await db.select(db.readingProgress).getSingle()).toJson(), before);
    expect(await library.list(), hasLength(1));
  });
}
