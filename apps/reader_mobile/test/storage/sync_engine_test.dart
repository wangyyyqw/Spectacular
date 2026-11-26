import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/sync/sync_engine.dart';
import 'package:reader_mobile/sync/sync_models.dart';
import 'package:reader_mobile/sync/sync_storage.dart';
import 'package:reader_mobile/library/book_list_store.dart';
import 'package:reader_mobile/storage/drift_progress_store.dart';
import 'package:reader_mobile/storage/reading_session_store.dart';
import 'package:reader_mobile/home/reading_insights.dart';
import 'package:reader_mobile/storage/drift_decoration_rule_store.dart';
import 'package:reader_mobile/storage/drift_decoration_store.dart';
import 'package:reader_ui/decorations/decoration.dart';
import 'package:reader_ui/decorations/decoration_rules.dart';
import 'package:reader_ui/annotations/annotation.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/test_epub.dart';

const _profile = SyncProfile(
  provider: SyncProvider.webdav,
  endpoint: 'http://localhost',
  automatic: false,
);

class _Cloud implements SyncStorage {
  final objects = <String, Uint8List>{};
  bool failLog = false;
  String? failPath;
  int logWrites = 0;

  @override
  Future<Uint8List?> read(String key) async => objects[key];
  @override
  Future<void> upload(String key, File file, {bool createOnly = false}) async {
    if (createOnly && objects.containsKey(key)) throw StateError('对象已存在');
    if (failPath != null && key.startsWith(failPath!)) {
      throw const HttpException('模拟分类数据上传失败');
    }
    if (key.startsWith('personal/_sync/logs/')) {
      if (failLog) throw const HttpException('模拟断网');
      logWrites++;
    }
    objects[key] = await file.readAsBytes();
  }

  @override
  Future<void> download(String key, File file) async {
    await file.parent.create(recursive: true);
    await file.writeAsBytes(objects[key]!);
  }

  @override
  Future<List<String>> list(String directory) async =>
      objects.keys
          .where((key) => key.startsWith('$directory/'))
          .map(
            (key) =>
                '$directory/${key.substring(directory.length + 1).split('/').first}',
          )
          .toSet()
          .toList()
        ..sort();
  @override
  Future<void> delete(String key) async {
    objects.remove(key);
  }

  @override
  void close() {}
}

class _Device {
  _Device(this.library, this.db, this.cloud);
  final LibraryStore library;
  final AppDatabase db;
  final _Cloud cloud;
  SyncEngine engine({String recovery = '', SyncProfile profile = _profile}) =>
      SyncEngine(
        repository: library.syncRepository(),
        storage: cloud,
        profile: profile,
        credentials: SyncCredentials(recovery: recovery),
      );
}

Future<_Device> _device(_Cloud cloud, {String? id}) async {
  final root = await Directory.systemTemp.createTemp('spectacular-sync-test-');
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });
  final device = _Device(
    LibraryStore(database: db, directoryProvider: () async => root),
    db,
    cloud,
  );
  if (id != null) await device.library.setSetting('sync.device.v1', id);
  return device;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  test('两台设备恢复 EPUB，无变化不写日志', () async {
    final cloud = _Cloud();
    final a = await _device(cloud);
    final b = await _device(cloud);
    final epub = buildTestEpub(title: '共享书');
    await a.library.importBytes(epub);
    await a.engine().create(encrypted: false);
    expect((await a.engine().sync()).uploaded, 1);
    expect((await b.engine().sync()).downloaded, 1);
    expect((await b.library.list()).single.title, '共享书');
    final writes = cloud.logWrites;
    expect((await b.engine().sync()).uploaded, 0);
    expect(cloud.logWrites, writes);
    final epubPath = cloud.objects.keys.singleWhere(
      (key) => key.endsWith('.epub'),
    );
    expect(
      epubPath,
      matches(r'^book/[a-f0-9]{64}/content/[a-f0-9]{64}\.epub$'),
    );
    expect(cloud.objects[epubPath], epub);
    expect(cloud.objects.keys.map((key) => key.split('/').first).toSet(), {
      'library.json',
      'book',
      'personal',
    });
  });

  test('第三台设备按因果顺序恢复交错日志，图书先于另一台设备的笔记落库', () async {
    final cloud = _Cloud();
    final a = await _device(cloud, id: 'device-z');
    final b = await _device(cloud, id: 'device-a');
    final c = await _device(cloud, id: 'device-c');
    await a.library.importBytes(buildTestEpub(title: '甲书'));
    await a.engine().create(encrypted: false);
    await a.engine().sync();
    await b.engine().sync();
    final first = (await b.library.list()).single;
    await b.library.importBytes(buildTestEpub(title: '乙书'));
    await b.library
        .bookmarkStore(first.id)!
        .add(cfi: 'epubcfi(/6/2!/4/4/1:0)', spineIndex: 0, label: '甲书书签');
    await b.engine().sync();
    await a.engine().sync();
    final second = (await a.library.list()).firstWhere(
      (book) => book.title == '乙书',
    );
    await a.library
        .bookmarkStore(second.id)!
        .add(cfi: 'epubcfi(/6/2!/4/4/1:0)', spineIndex: 0, label: '乙书书签');
    await a.engine().sync();

    expect((await c.engine().sync()).downloaded, 3);
    final books = await c.library.list();
    expect(books, hasLength(2));
    for (final book in books) {
      final marks = await c.library.bookmarkStore(book.id)!.list();
      expect(marks.single.label, '${book.title}书签');
    }
    expect((await c.engine().sync()).uploaded, 0);
  });

  test('未编辑的旧本地副本接收新版，不覆盖云端或重建书籍身份', () async {
    final cloud = _Cloud();
    final a = await _device(cloud);
    final b = await _device(cloud);
    final book = await a.library.importBytes(
      buildTestEpub(title: '原版', identifier: 'stable'),
    );
    await a.engine().create(encrypted: false);
    await a.engine().sync();
    await b.engine().sync();
    final updated = await a.library.updateBytes(
      book.id,
      buildTestEpub(
        title: '新版',
        identifier: 'stable',
        paragraphs: ['新增内容' * 30],
      ),
    );
    await a.library.updateBookMetadata(
      updated.id,
      title: '新版',
      author: '测试作者',
      description: '同步后的简介',
    );
    await a.engine().sync();
    final result = await b.engine().sync();
    expect(result.uploaded, 0);
    expect(result.conflicts, 0);
    expect((await b.library.list()).single.title, '新版');
    expect(await b.db.select(b.db.books).get(), hasLength(1));
    expect((await b.engine().sync()).uploaded, 0);
  });

  test('全端软删除不复活，阅读历史和书评保留', () async {
    final cloud = _Cloud();
    final a = await _device(cloud);
    final b = await _device(cloud);
    final book = await a.library.importBytes(buildTestEpub());
    final sessions = a.library.readingSessionStore()!;
    await sessions.add(
      bookId: book.id,
      startedAt: DateTime(2026),
      endedAt: DateTime(2026).add(const Duration(minutes: 5)),
    );
    await a.engine().create(encrypted: false);
    await a.engine().sync();
    await b.engine().sync();
    await a.library.remove(book.id);
    await a.engine().sync();
    expect((await b.engine().sync()).uploaded, 0);
    expect(await b.library.list(), isEmpty);
    expect(await b.library.readingSessionStore()!.list(), hasLength(1));
    expect((await b.engine().sync()).uploaded, 0);
  });

  test('断网后新引擎重试固定批次，重复接收不重复累计时长', () async {
    final cloud = _Cloud();
    final a = await _device(cloud);
    final b = await _device(cloud);
    final book = await a.library.importBytes(buildTestEpub());
    await a.library.readingSessionStore()!.add(
      bookId: book.id,
      startedAt: DateTime(2026),
      endedAt: DateTime(2026).add(const Duration(minutes: 3)),
    );
    await a.engine().create(encrypted: false);
    cloud.failLog = true;
    await expectLater(a.engine().sync(), throwsA(isA<HttpException>()));
    cloud.failLog = false;
    expect((await a.engine().sync()).uploaded, 1);
    await b.engine().sync();
    await b.engine().sync();
    final sessions = await b.library.readingSessionStore()!.list();
    expect(sessions, hasLength(1));
    expect(sessions.single.duration, const Duration(minutes: 3));
  });

  test('跨目录上传中断不发布半批数据，重试后书籍与个人记录一并恢复', () async {
    final cloud = _Cloud();
    final a = await _device(cloud);
    final b = await _device(cloud);
    final book = await a.library.importBytes(buildTestEpub());
    await a.library.readingSessionStore()!.add(
      bookId: book.id,
      startedAt: DateTime(2026),
      endedAt: DateTime(2026).add(const Duration(minutes: 3)),
    );
    await a.engine().create(encrypted: false);
    cloud.failPath = 'personal/statistics/';
    await expectLater(a.engine().sync(), throwsA(isA<HttpException>()));
    expect(cloud.objects.keys.any((key) => key.startsWith('book/')), isTrue);
    expect(cloud.logWrites, 0);
    expect((await b.engine().sync()).downloaded, 0);
    expect(await b.library.list(), isEmpty);
    cloud.failPath = null;
    expect((await a.engine().sync()).uploaded, 1);
    expect((await b.engine().sync()).downloaded, 1);
    expect(await b.library.list(), hasLength(1));
    expect(await b.library.readingSessionStore()!.list(), hasLength(1));
    expect((await b.engine().sync()).uploaded, 0);
  });

  for (final tampered in [false, true]) {
    test('分类文件${tampered ? '被修改' : '缺失'}时整批不落库，恢复后从原游标重试', () async {
      final cloud = _Cloud();
      final a = await _device(cloud);
      final b = await _device(cloud);
      final book = await a.library.importBytes(buildTestEpub());
      await DriftProgressStore(a.db).save(
        book.id,
        const ReaderProgress(spineIndex: 0, pageIndex: 0, finished: true),
      );
      await a.library.reviewStore()!.save(book.id, rating: 4, content: '书评');
      await a.engine().create(encrypted: false);
      final sender = a.engine();
      await sender.sync();
      final key = cloud.objects.keys.singleWhere(
        (key) => key.startsWith('personal/notes/changes/'),
      );
      final saved = cloud.objects.remove(key)!;
      if (tampered) {
        final part = jsonDecode(utf8.decode(saved)) as Map<String, dynamic>;
        final records = (part['records'] as List).cast<Map<String, dynamic>>();
        (records.single['data'] as Map<String, dynamic>)['content'] = '被修改的书评';
        cloud.objects[key] = Uint8List.fromList(utf8.encode(jsonEncode(part)));
      }
      await expectLater(b.engine().sync(), throwsFormatException);
      expect(await b.library.list(), isEmpty);
      final receiver = b.engine();
      await receiver.connect();
      expect(receiver.state.cursors[sender.state.device], isNull);
      cloud.objects[key] = saved;
      expect((await b.engine().sync()).downloaded, 1);
      expect(
        (await b.library.reviewStore()!.snapshot()).values.single.content,
        '书评',
      );
    });
  }

  test('可选加密恢复完整图书，错误恢复密钥不写本机数据', () async {
    final cloud = _Cloud();
    final a = await _device(cloud);
    final b = await _device(cloud);
    await a.library.importBytes(buildTestEpub(title: '加密书'));
    final recovery = await a.engine().create(encrypted: true);
    final sender = a.engine(recovery: recovery);
    await sender.sync();
    expect(
      cloud.objects.keys.where((key) => key != 'library.json'),
      everyElement(endsWith('.enc')),
    );
    expect(cloud.objects.keys.any((key) => key.endsWith('.epub.enc')), isTrue);
    await expectLater(b.engine().sync(), throwsA(isA<FormatException>()));
    expect(await b.library.list(), isEmpty);
    await b.engine(recovery: recovery).sync();
    expect((await b.library.list()).single.title, '加密书');
  });

  test('统计与笔记页全部持久化内容恢复，重复同步后各项统计不重复累计', () async {
    final cloud = _Cloud();
    final a = await _device(cloud);
    final b = await _device(cloud);
    final book = await a.library.importBytes(
      buildTestEpub(title: '完整数据书', cover: true),
    );
    final annotations = a.library.annotationStore(book.id)!;
    await annotations.add(
      type: ReaderAnnotationType.mark,
      startCfi: 'epubcfi(/6/2!/4/4/1:0)',
      endCfi: 'epubcfi(/6/2!/4/4/1:2)',
      quote: '这是',
      contextBefore: '前文',
      contextAfter: '后文',
      style: ReaderAnnotationStyle.wavyUnderline,
      color: 0xff123456,
      opacity: .42,
    );
    await annotations.add(
      type: ReaderAnnotationType.thought,
      startCfi: 'epubcfi(/6/2!/4/6/1:0)',
      endCfi: 'epubcfi(/6/2!/4/6/1:2)',
      quote: '第二',
      note: '/not/a/file 是笔记正文，不是文件引用',
    );
    await a.library
        .bookmarkStore(book.id)!
        .add(cfi: 'epubcfi(/6/2!/4/4/1:0)', spineIndex: 0, label: '完整书签');
    await DriftProgressStore(a.db).save(
      book.id,
      const ReaderProgress(spineIndex: 0, pageIndex: 0, finished: true),
    );
    await a.library.reviewStore()!.save(
      book.id,
      rating: 4.5,
      content: '/review 正文与评分',
    );
    final group = await a.library.createGroup('分类');
    await a.library.setBooksGroup([book.id], groupId: group.id);
    final tag = await a.library.createTag('标签');
    await a.library.addBookTag(book.id, tag.id);
    final list = await BookListStore(a.library)
        .create(name: '书单', description: '完整简介');
    await BookListStore(a.library).addBooks(list.id, [book.id]);
    await a.library.setSetting(
      'stats.book_colors',
      jsonEncode({
        book.id: {'p': null, 'c': 0xff112233},
      }),
    );
    await a.library.readingSessionStore()!.add(
      bookId: book.id,
      startedAt: DateTime(2026, 11, 24, 23, 50),
      endedAt: DateTime(2026, 11, 25, 0, 10),
      pageTurns: 11,
      charactersRead: 3210,
    );
    await a.library.readingSessionStore()!.add(
      bookId: book.id,
      startedAt: DateTime(2026, 11, 25, 10),
      endedAt: DateTime(2026, 11, 25, 10, 30),
      pageTurns: 7,
      charactersRead: 2345,
    );
    await a.engine().create(encrypted: false);
    final sender = a.engine();
    await sender.sync();
    final bookKey = await a.library.syncRepository().bookKey(book.id);
    final bookPath = '$bookKey/';
    final classified = <String, List<SyncRecord>>{};
    for (final entry in cloud.objects.entries.where(
      (entry) => entry.key.contains('/changes/'),
    )) {
      final part = jsonDecode(utf8.decode(entry.value)) as Map<String, dynamic>;
      classified[entry.key.split('/changes/').first] = [
        for (final raw in part['records'] as List)
          SyncRecord.fromJson(raw as Map<String, dynamic>),
      ];
    }
    expect(classified['${bookPath}content']!.single.type, 'book');
    expect(classified['${bookPath}annotations'], hasLength(3));
    expect(classified['${bookPath}progress']!.single.type, 'reading_progress');
    expect(
      classified['personal/statistics']!.map((record) => record.type),
      unorderedEquals(['reading_sessions', 'reading_sessions', 'book_color']),
    );
    expect(
      classified['personal/notes']!.map((record) => record.type),
      unorderedEquals(['book_reviews', 'list', 'list_member']),
    );
    expect(classified['personal/bookshelf'], hasLength(4));
    expect(
      cloud.objects.keys.any(
        (key) => key.startsWith('${bookPath}content/files/'),
      ),
      isTrue,
    );
    expect(
      classified.values
          .expand((records) => records)
          .map((record) => record.key)
          .toSet(),
      sender.state.heads.keys.toSet(),
    );
    await b.engine().sync();
    await b.engine().sync();
    final restored = (await b.library.list()).single;
    final notes = await b.library.annotationStore(restored.id)!.list();
    expect(notes, hasLength(2));
    expect(
      notes
          .where((note) => note.type == ReaderAnnotationType.thought)
          .single
          .note,
      '/not/a/file 是笔记正文，不是文件引用',
    );
    final highlight = notes
        .where((note) => note.type == ReaderAnnotationType.mark)
        .single;
    expect(highlight.color, 0xff123456);
    expect(highlight.opacity, .42);
    expect(highlight.contextBefore, '前文');
    expect(await b.library.bookmarkStore(restored.id)!.list(), hasLength(1));
    final review = (await b.library.reviewStore()!.snapshot()).values.single;
    expect(review.content, '/review 正文与评分');
    expect(review.rating, 4.5);
    expect(
      (await DriftProgressStore(b.db).load(restored.id))!.finished,
      isTrue,
    );
    expect((await b.library.listGroups()).single.name, '分类');
    expect((await b.library.listTags()).single.name, '标签');
    expect((await BookListStore(b.library).list()).single.bookIds, [
      restored.id,
    ]);
    expect((await BookListStore(b.library).list()).single.description, '完整简介');
    final colors = jsonDecode(
      (await b.library.getSetting('stats.book_colors'))!,
    ) as Map<String, dynamic>;
    expect((colors[restored.id] as Map<String, dynamic>)['c'], 0xff112233);
    final first = ReadingInsights(
      await a.library.readingSessionStore()!.list(),
      now: DateTime(2026, 11, 25),
    );
    final second = ReadingInsights(
      await b.library.readingSessionStore()!.list(),
      now: DateTime(2026, 11, 25),
    );
    expect(second.totalReading, first.totalReading);
    expect(second.byDay, first.byDay);
    expect(second.readingPeriods, first.readingPeriods);
    expect(second.pageTurns, 18);
    expect(second.charactersRead, 5555);
    expect(second.sessions.length, 2);
    expect(second.averageDay, first.averageDay);
    expect(second.averageSession, first.averageSession);
    expect((await b.engine().sync()).uploaded, 0);
  });

  test('同一阅读会话累计快照原位更新，跨设备反复同步不增加次数', () async {
    final cloud = _Cloud();
    final a = await _device(cloud);
    final b = await _device(cloud);
    final book = await a.library.importBytes(buildTestEpub());
    final store =
        a.library.readingSessionStore()! as ReadingSessionCheckpointStore;
    final start = DateTime(2026, 11, 25, 10);
    final id = await store.save(
      ReadingSession(
        bookId: book.id,
        startedAt: start,
        endedAt: start.add(const Duration(minutes: 2)),
        duration: const Duration(minutes: 2),
      ),
    );
    await a.engine().create(encrypted: false);
    await a.engine().sync();
    await b.engine().sync();
    await store.save(
      ReadingSession(
        bookId: book.id,
        startedAt: start,
        endedAt: start.add(const Duration(minutes: 5)),
        duration: const Duration(minutes: 5),
        pageTurns: 9,
        charactersRead: 1000,
      ),
      sessionId: id,
    );
    await a.engine().sync();
    await b.engine().sync();
    await b.engine().sync();
    final records = await b.library.readingSessionStore()!.list();
    expect(records, hasLength(1));
    expect(records.single.duration, const Duration(minutes: 5));
    expect(records.single.pageTurns, 9);
    expect(records.single.charactersRead, 1000);
  });

  test('远端日志缺失不推进游标，下一轮补齐后仍可接收', () async {
    final cloud = _Cloud();
    final a = await _device(cloud);
    final b = await _device(cloud);
    final book = await a.library.importBytes(buildTestEpub());
    await a.engine().create(encrypted: false);
    await a.engine().sync();
    await a.library.touchLastRead(book.id);
    await a.engine().sync();
    final key = cloud.objects.keys.firstWhere(
      (key) =>
          key.startsWith('personal/_sync/logs/') &&
          key.endsWith('000000000001.json'),
    );
    final saved = cloud.objects.remove(key)!;
    await expectLater(b.engine().sync(), throwsA(isA<FormatException>()));
    expect(await b.library.list(), isEmpty);
    cloud.objects[key] = saved;
    await b.engine().sync();
    expect(await b.library.list(), hasLength(1));
  });

  test('仅清理本机文件不产生墓碑，再次打开恢复原文件与全部记录', () async {
    final cloud = _Cloud();
    final a = await _device(cloud);
    final book = await a.library.importBytes(buildTestEpub());
    await a.engine().create(encrypted: false);
    await a.engine().sync();
    await a.engine().clearLocalBook(book.id);
    expect(await File(book.filePath).exists(), isFalse);
    expect(await a.library.list(), hasLength(1));
    expect((await a.engine().sync()).uploaded, 0);
    await a.engine().restoreBook(book.id);
    expect(await File(book.filePath).exists(), isTrue);
    expect(await a.library.list(), hasLength(1));
  });

  test('当前阅读时仅发送本机数据，关闭后再接收远端更新', () async {
    final cloud = _Cloud();
    final a = await _device(cloud);
    final b = await _device(cloud);
    await a.library.importBytes(buildTestEpub());
    await a.engine().create(encrypted: false);
    await a.engine().sync();
    b.library.beginSyncRead();
    expect((await b.engine().sync()).deferred, isTrue);
    expect(await b.library.list(), isEmpty);
    b.library.endSyncRead();
    expect((await b.engine().sync()).downloaded, 1);
  });

  test('双端修改保留完整冲突版本，明确选择后向其他设备传播', () async {
    final cloud = _Cloud();
    final a = await _device(cloud);
    final b = await _device(cloud);
    final bookA = await a.library.importBytes(buildTestEpub());
    await a.engine().create(encrypted: false);
    await a.engine().sync();
    await b.engine().sync();
    final bookB = (await b.library.list()).single;
    await a.library.updateBookMetadata(
      bookA.id,
      title: 'A的版本',
      author: '作者',
      description: 'A正文',
    );
    await a.engine().sync();
    await b.library.updateBookMetadata(
      bookB.id,
      title: 'B的版本',
      author: '作者',
      description: 'B正文',
    );
    final engineB = b.engine();
    expect((await engineB.sync()).conflicts, 1);
    final key = engineB.state.conflicts.keys.single;
    final versions = engineB.state.conflicts[key]!;
    expect(
      versions.values.map((record) => record.data['description']),
      containsAll(['A正文', 'B正文']),
    );
    expect((await b.library.list()).single.title, 'B的版本');
    final selected = versions.values.firstWhere(
      (record) => record.data['title'] == 'A的版本',
    );
    await b.engine().resolve(key, selected);
    await b.engine().sync();
    await a.engine().sync();
    expect((await a.library.list()).single.title, 'A的版本');
    expect((await b.library.list()).single.title, 'A的版本');
    expect((await b.engine().sync()).conflicts, 0);
  });

  test('第三台设备提交相同版本不清除已有冲突，选择结果仍可向三端传播', () async {
    final cloud = _Cloud();
    final a = await _device(cloud, id: 'device-a');
    final b = await _device(cloud, id: 'device-b');
    final c = await _device(cloud, id: 'device-c');
    final book = await a.library.importBytes(buildTestEpub());
    await a.engine().create(encrypted: false);
    await a.engine().sync();
    await b.engine().sync();
    await c.engine().sync();
    for (final device in [a, b, c]) {
      await device.library.updateBookMetadata(
        book.id,
        title: device == a ? '甲版' : '乙版',
        author: '作者',
        description: '正文',
      );
      await device.engine().sync();
    }

    for (final device in [a, b, c]) {
      final engine = device.engine();
      expect((await engine.sync()).conflicts, 1);
      expect(
        engine.state.conflicts.values.single.values
            .map((record) => record.data['title'])
            .toSet(),
        {'甲版', '乙版'},
      );
    }
    final resolver = c.engine();
    await resolver.connect();
    final conflict = resolver.state.conflicts.entries.single;
    await resolver.resolve(
      conflict.key,
      conflict.value.values.firstWhere(
        (record) => record.data['title'] == '甲版',
      ),
    );
    await resolver.sync();
    for (final device in [a, b, c]) {
      expect((await device.engine().sync()).conflicts, 0);
      expect((await device.library.list()).single.title, '甲版');
    }
  });

  test('冲突分支继续更新后移除被替代的旧版本，重启同步仍保留其他分支', () async {
    final cloud = _Cloud();
    final a = await _device(cloud, id: 'device-a');
    final b = await _device(cloud, id: 'device-b');
    final book = await a.library.importBytes(buildTestEpub());
    await a.engine().create(encrypted: false);
    await a.engine().sync();
    await b.engine().sync();
    for (final device in [a, b]) {
      await device.library.updateBookMetadata(
        book.id,
        title: device == a ? '甲版' : '乙版',
        author: '作者',
        description: '正文',
      );
      await device.engine().sync();
    }
    await a.library.updateBookMetadata(
      book.id,
      title: '甲版修订',
      author: '作者',
      description: '修订正文',
    );
    await a.engine().sync();
    final receiver = b.engine();
    expect((await receiver.sync()).conflicts, 1);
    final reloaded = b.engine();
    await reloaded.connect();
    expect(
      reloaded.state.conflicts.values.single.values.map(
        (record) => record.data['title'],
      ),
      unorderedEquals(['甲版修订', '乙版']),
    );
    expect((await b.library.list()).single.title, '乙版');
  });

  test('后开启阅读偏好与素材同步时恢复已接收的选项，不要求重新安装', () async {
    final cloud = _Cloud();
    final a = await _device(cloud);
    final b = await _device(cloud);
    await a.library.importBytes(buildTestEpub());
    final root = await a.library.syncRepository().directory();
    final image = File('${root.path}/reader_backgrounds/background-test.png');
    await image.parent.create(recursive: true);
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==',
    );
    await image.writeAsBytes(bytes);
    await a.library.setSetting('reader.fontSize', '24');
    await a.library.setSetting('reader.backgroundId', 'image:${image.path}');
    for (final mode in ['day', 'night']) {
      await a.library.setSetting(
        'reader.${mode}Background',
        jsonEncode({
          'backgroundId': 'image:${image.path}',
          'opacity': mode == 'day' ? 0.65 : 0.35,
        }),
      );
    }
    const profile = SyncProfile(
      provider: SyncProvider.webdav,
      endpoint: 'http://localhost',
      automatic: false,
      preferences: true,
      resources: true,
    );
    await a.engine().create(encrypted: false);
    await a.engine(profile: profile).sync();
    expect(
      cloud.objects.keys.any(
        (key) => key.startsWith('personal/preferences/changes/'),
      ),
      isTrue,
    );
    expect(
      cloud.objects.keys.any(
        (key) => key.startsWith('personal/resources/backgrounds/files/'),
      ),
      isTrue,
    );
    await b.engine().sync();
    expect(await b.library.getSetting('reader.fontSize'), isNull);
    const preferencesOnly = SyncProfile(
      provider: SyncProvider.webdav,
      endpoint: 'http://localhost',
      automatic: false,
      preferences: true,
      resources: false,
    );
    await b.engine(profile: preferencesOnly).sync();
    expect(await b.library.getSetting('reader.dayBackground'), isNull);
    expect(await b.library.getSetting('reader.nightBackground'), isNull);
    await b.engine(profile: profile).sync();
    expect(await b.library.getSetting('reader.fontSize'), '24');
    final background = (await b.library.getSetting('reader.backgroundId'))!;
    expect(background, isNot('image:${image.path}'));
    expect(await File(background.substring(6)).readAsBytes(), bytes);
    for (final mode in ['day', 'night']) {
      final preference = jsonDecode(
        (await b.library.getSetting('reader.${mode}Background'))!,
      ) as Map<String, dynamic>;
      final path = preference['backgroundId'] as String;
      expect(path, isNot('image:${image.path}'));
      expect(await File(path.substring(6)).readAsBytes(), bytes);
      expect(preference['opacity'], mode == 'day' ? 0.65 : 0.35);
    }
  });

  test('各书装饰和规则按书归档，共用图片分别落入所属书和全局素材目录', () async {
    final cloud = _Cloud();
    final a = await _device(cloud);
    final b = await _device(cloud);
    final root = await a.library.syncRepository().directory();
    final image = File('${root.path}/decoration_images/shared.png');
    await image.parent.create(recursive: true);
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==',
    );
    await image.writeAsBytes(bytes);
    for (final title in ['甲书', '乙书']) {
      final book = await a.library.importBytes(buildTestEpub(title: title));
      await DriftDecorationStore(a.db, book.id).add(
        startCfi: 'epubcfi(/6/2!/4/4/1:0)',
        endCfi: 'epubcfi(/6/2!/4/4/1:2)',
        quote: '这是',
        style: ReaderDecorationStyle(backgroundImagePath: image.path),
      );
      final rules = DriftDecorationRuleStore(a.db, book.id);
      final groups = await rules.listGroups();
      await rules.saveRule(
        ReaderDecorationRule(
          id: 'rule-$title',
          groupId: groups.singleWhere((group) => group.bookId == book.id).id,
          pattern: '这是',
          style: ReaderDecorationRuleStyle(backgroundImagePath: image.path),
        ),
      );
      await rules.saveStyle(
        ReaderDecorationNamedStyle(
          id: 'shared-style',
          name: '共享样式',
          style: ReaderDecorationRuleStyle(backgroundImagePath: image.path),
        ),
      );
      await rules.listRules();
    }
    await a.engine().create(encrypted: false);
    await a.engine().sync();
    final paths = cloud.objects.keys
        .where((key) => key.endsWith('.png'))
        .toList();
    expect(paths, hasLength(3));
    expect(paths.where((key) => key.startsWith('book/')), hasLength(2));
    expect(
      paths.singleWhere((key) => key.startsWith('personal/')),
      startsWith('personal/resources/decorations/files/'),
    );
    for (final path in paths) {
      expect(cloud.objects[path], bytes);
    }
    await b.engine().sync();
    for (final book in await b.library.list()) {
      final decoration = (await DriftDecorationStore(
        b.db,
        book.id,
      ).list()).single;
      expect(
        await File(decoration.style.backgroundImagePath!).readAsBytes(),
        bytes,
      );
      final rules = DriftDecorationRuleStore(b.db, book.id);
      final rule = (await rules.listRules()).singleWhere(
        (rule) => rule.id == 'rule-${book.title}',
      );
      expect(await File(rule.style.backgroundImagePath!).readAsBytes(), bytes);
    }
    expect((await b.engine().sync()).uploaded, 0);
  });

  test('断网后装饰规则改变作用域，旧批次目录保持固定且新批次同步到新位置', () async {
    final cloud = _Cloud();
    final a = await _device(cloud);
    final b = await _device(cloud);
    final book = await a.library.importBytes(buildTestEpub());
    final rules = DriftDecorationRuleStore(a.db, book.id);
    final groups = await rules.listGroups();
    final rule = ReaderDecorationRule(
      id: 'moving-rule',
      groupId: groups.singleWhere((group) => group.bookId == book.id).id,
      pattern: '这是',
      style: const ReaderDecorationRuleStyle(backgroundColor: 0xff112233),
    );
    await rules.saveRule(rule);
    await a.engine().create(encrypted: false);
    cloud.failLog = true;
    await expectLater(a.engine().sync(), throwsA(isA<HttpException>()));
    final before = {
      for (final entry in cloud.objects.entries)
        if (entry.key.contains('/changes/')) entry.key: entry.value,
    };
    await rules.saveRule(
      rule.copyWith(
        groupId: groups.singleWhere((group) => group.bookId == null).id,
      ),
    );
    cloud.failLog = false;
    expect((await a.engine().sync()).uploaded, 2);
    for (final entry in before.entries) {
      expect(cloud.objects[entry.key], entry.value);
    }
    await b.engine().sync();
    final store = DriftDecorationRuleStore(
      b.db,
      (await b.library.list()).single.id,
    );
    final restoredGroups = await store.listGroups();
    final restored = (await store.listRules()).singleWhere(
      (rule) => rule.id == 'moving-rule',
    );
    expect(
      restored.groupId,
      restoredGroups.singleWhere((group) => group.bookId == null).id,
    );
  });

  test('修改书名和 EPUB 内容仍沿用原书目录，重建后笔记仍关联同一本书', () async {
    final cloud = _Cloud();
    final a = await _device(cloud);
    final b = await _device(cloud);
    final book = await a.library.importBytes(
      buildTestEpub(title: '原书', identifier: 'stable'),
    );
    await a.library
        .bookmarkStore(book.id)!
        .add(cfi: 'epubcfi(/6/2!/4/4/1:0)', spineIndex: 0, label: '原书书签');
    await a.engine().create(encrypted: false);
    await a.engine().sync();
    final directories = await cloud.list('book');
    final updated = await a.library.updateBytes(
      book.id,
      buildTestEpub(
        title: '修订书名',
        identifier: 'stable',
        paragraphs: ['这是修订内容。', '这是新段落。'],
      ),
    );
    await a.engine().sync();
    expect(await cloud.list('book'), directories);
    expect(
      cloud.objects.keys.where((key) => key.endsWith('.epub')),
      hasLength(2),
    );
    await b.engine().sync();
    final restored = (await b.library.list()).single;
    expect(await b.library.bookmarkStore(restored.id)!.list(), hasLength(1));
    expect(
      await File(restored.filePath).readAsBytes(),
      await File(updated.filePath).readAsBytes(),
    );
  });

  test('装饰默认组按稳定书籍身份同步，不混用设备整数主键，命名样式与规则选择保留', () async {
    final cloud = _Cloud();
    final a = await _device(cloud);
    final b = await _device(cloud);
    await a.library.importBytes(buildTestEpub(title: 'A先导入的书'));
    final shared = buildTestEpub(title: '共同书');
    final bookA = await a.library.importBytes(shared);
    final bookB = await b.library.importBytes(shared);
    final storeA = DriftDecorationRuleStore(a.db, bookA.id);
    final storeB = DriftDecorationRuleStore(b.db, bookB.id);
    await storeA.listGroups();
    await storeB.listGroups();
    await storeA.saveStyle(
      const ReaderDecorationNamedStyle(
        id: 'shared-style',
        name: '共享样式',
        style: ReaderDecorationRuleStyle(backgroundColor: 0xff112233),
      ),
    );
    await storeA.saveGlobalRuleSelection({'shared-rule'});
    await a.engine().create(encrypted: false);
    await a.engine().sync();
    await b.engine().sync();
    final groups = await storeB.listGroups();
    expect(groups.where((group) => group.bookId == bookB.id), hasLength(1));
    final style = (await storeB.listStyles()).firstWhere(
      (style) => style.id == 'shared-style',
    );
    expect(style.style.backgroundColor, 0xff112233);
    expect(await storeB.loadGlobalRuleSelection(), {'shared-rule'});
  });
}
