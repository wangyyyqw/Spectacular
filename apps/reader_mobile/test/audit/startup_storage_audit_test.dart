import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/diagnostics/reader_log.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/storage/drift_progress_store.dart';
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

  for (final contents in ['{', '[]', '{}']) {
    test('旧书库损坏（$contents）时继续启动，且保留迁移前的 EPUB', () async {
      File('${directory.path}/books.json').writeAsStringSync(contents);
      final books = Directory('${directory.path}/books')..createSync();
      final source = File('${books.path}/legacy.epub')
        ..writeAsBytesSync(buildTestEpub());

      expect(await prepareLibraryStorage(library, log), isFalse);
      expect(source.existsSync(), isTrue);
      expect(File('${directory.path}/books.json').readAsStringSync(), contents);
      expect(await log.exportText(), contains('library_prepare_failed'));
    });
  }

  test('旧进度损坏时继续使用数据库，保留旧文件并记诊断', () async {
    final file = File('${directory.path}/reader_progress.json')
      ..writeAsStringSync('{');
    final store = DriftProgressStore(db);

    await prepareProgressStorage(store, () async => directory, log);
    expect(await store.snapshot(), isEmpty);
    expect(file.readAsStringSync(), '{');
    expect(await log.exportText(), contains('progress_migrate_failed'));
  });
}
