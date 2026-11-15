import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/diagnostics/reader_log.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/storage/drift_progress_store.dart';
import 'package:reader_mobile/storage/startup_storage.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/test_epub.dart';

class _MemorySweepProbe extends LibraryStore {
  _MemorySweepProbe() : super.memory();

  int sweepCalls = 0;

  @override
  Future<({int removed, int bytes})> sweepOrphans() async {
    sweepCalls++;
    throw StateError('临时模式不应调用清理');
  }
}

class _ClosingDatabase extends AppDatabase {
  _ClosingDatabase() : super(NativeDatabase.memory());

  int closeCalls = 0;

  @override
  Future<void> close() {
    closeCalls++;
    return super.close();
  }
}

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

  test('临时书库的启动准备不调用磁盘清理', () async {
    final temporary = _MemorySweepProbe();

    await prepareLibraryStorage(temporary, log);

    expect(temporary.supportsPersistence, isFalse);
    expect(temporary.sweepCalls, 0);
    expect(await log.exportText(), isNot(contains('library_prepare_failed')));
  });

  test('损坏数据库失败保留原文件；重试后恢复真实书库与进度', () async {
    final entry = await library.importBytes(buildTestEpub(title: '恢复的书'));
    await DriftProgressStore(db).save(
      entry.id,
      const ReaderProgress(spineIndex: 0, pageIndex: 1, readingPercent: 0.65),
    );
    final bytes = List<int>.filled(128, 0x5a);
    final brokenFile = File('${directory.path}/reader.sqlite')
      ..writeAsBytesSync(bytes);
    final orphan = Directory('${directory.path}/books/orphan')
      ..createSync(recursive: true);
    File('${orphan.path}/source.epub').writeAsBytesSync([1, 2, 3]);
    var attempts = 0;
    var libraryCreations = 0;
    final storage = StartupStorage(
      log: log,
      openDatabase: () async => ++attempts == 1
          ? AppDatabase(NativeDatabase(brokenFile))
          : db,
      createLibrary: (database) {
        expect(database, same(db));
        libraryCreations++;
        return library;
      },
    );
    addTearDown(storage.dispose);

    expect(await storage.retry(), isFalse);
    expect(storage.isTemporary, isTrue);
    expect(libraryCreations, 0);
    expect(brokenFile.readAsBytesSync(), bytes);
    expect(orphan.existsSync(), isTrue);
    expect(File(entry.filePath).existsSync(), isTrue);

    expect(await storage.retry(), isTrue);
    expect(storage.isTemporary, isFalse);
    expect(storage.library, same(library));
    expect(storage.progressStore, isA<DriftProgressStore>());
    expect(libraryCreations, 1);
    expect((await storage.library.list()).single.id, entry.id);
    expect((await storage.progressStore.load(entry.id))?.readingPercent, 0.65);
    expect(brokenFile.readAsBytesSync(), bytes);
    expect(orphan.existsSync(), isFalse);
    expect(File(entry.filePath).existsSync(), isTrue);
  });

  test('并发与监听回调重试共用任务，失败不替换临时存储', () async {
    final pending = Completer<AppDatabase?>();
    var attempts = 0;
    final storage = StartupStorage(
      log: log,
      openDatabase: () => ++attempts == 1 ? pending.future : Future.value(db),
      createLibrary: (_) => library,
    );
    addTearDown(storage.dispose);
    final temporaryLibrary = storage.library;
    final temporaryProgress = storage.progressStore;
    Future<bool>? listenerRetry;
    storage.addListener(() {
      if (storage.isOpening) listenerRetry ??= storage.retry();
    });

    final first = storage.retry();
    expect(storage.retry(), same(first));
    expect(listenerRetry, same(first));
    expect(storage.isOpening, isTrue);
    pending.complete(null);
    expect(await first, isFalse);
    expect(attempts, 1);
    expect(storage.isOpening, isFalse);
    expect(storage.library, same(temporaryLibrary));
    expect(storage.progressStore, same(temporaryProgress));

    expect(await storage.retry(), isTrue);
    expect(await storage.retry(), isTrue);
    expect(attempts, 2, reason: '恢复后不重复打开数据库');
  });

  test('恢复入口销毁后关闭迟到连接，不创建书库或清理目录', () async {
    final pending = Completer<AppDatabase?>();
    final connection = _ClosingDatabase();
    var libraryCreations = 0;
    final storage = StartupStorage(
      log: log,
      openDatabase: () => pending.future,
      createLibrary: (_) {
        libraryCreations++;
        return library;
      },
    );
    final task = storage.retry();
    await Future<void>.delayed(Duration.zero);
    storage.dispose();
    pending.complete(connection);

    expect(await task, isFalse);
    expect(connection.closeCalls, 1);
    expect(libraryCreations, 0);
  });
}
