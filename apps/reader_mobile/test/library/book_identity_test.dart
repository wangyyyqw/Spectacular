import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/book_identity.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_mobile/library/import_analysis.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/db.dart';

import '../support/test_epub.dart';

const _identifier = 'urn:uuid:12345678-1234-1234-1234-123456789abc';

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
    expect(first.title, '未命名书籍');
    expect(second.title, '未命名书籍');
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
}
