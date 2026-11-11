import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/diagnostics/reader_log.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/storage/startup_storage.dart';

import '../support/test_epub.dart';

void main() {
  late Directory directory;
  late AppDatabase db;
  late LibraryStore library;
  late ReaderLog log;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('startup-storage');
    db = AppDatabase(NativeDatabase.memory());
    library = LibraryStore(
      database: db,
      directoryProvider: () async => directory,
    );
    log = ReaderLog();
  });

  tearDown(() async {
    await db.close();
    directory.deleteSync(recursive: true);
  });

  test('启动清理孤儿目录，保留已导入书籍并记录清理结果', () async {
    final bytes = buildTestEpub();
    final entry = await library.importBytes(bytes);
    final orphan = Directory('${directory.path}/books/orphan')
      ..createSync(recursive: true);
    File('${orphan.path}/source.epub').writeAsBytesSync([1, 2, 3]);

    await prepareLibraryStorage(library, log);

    expect(orphan.existsSync(), isFalse);
    expect(File(entry.filePath).readAsBytesSync(), bytes);
    expect((await library.list()).single.id, entry.id);
    expect(await log.exportText(), contains('library_swept'));
  });

  test('书库目录不可读时记录错误并继续启动', () async {
    final unavailable = LibraryStore(
      database: db,
      directoryProvider: () async => throw const FileSystemException('目录不可读'),
    );

    await prepareLibraryStorage(unavailable, log);

    expect(await log.exportText(), contains('library_prepare_failed'));
    expect(await db.select(db.books).get(), isEmpty);
  });
}
