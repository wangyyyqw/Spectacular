import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/editing.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/position/location_anchor.dart';
import 'package:reader_mobile/editing/epub_export.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/library/revision_anchor_index.dart';
import 'package:reader_mobile/reader/reader_decoration_image_store.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/storage/drift_progress_store.dart';
import 'package:reader_ui/annotations/annotation.dart';
import 'package:reader_ui/decorations/decoration.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:xml/xml.dart';

import 'fixtures/revision_epub.dart';
import '../support/test_epub.dart';

Future<({Directory root, AppDatabase db, LibraryStore library})>
_library() async {
  final root = await Directory.systemTemp.createTemp('book-metadata-');
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });
  return (
    root: root,
    db: db,
    library: LibraryStore(database: db, directoryProvider: () async => root),
  );
}

Future<List<String>> _values(File file, String field) async {
  final session = await EpubEditSession.open(file);
  try {
    return XmlDocument.parse(session.readText(session.opfPath)).descendants
        .whereType<XmlElement>()
        .where((node) => node.name.local == field)
        .map((node) => node.innerText)
        .toList();
  } finally {
    session.close();
  }
}

Future<List<Map<String, Object?>>> _rows(AppDatabase db, String table) async =>
    [
      for (final row in await db.customSelect('SELECT * FROM $table').get())
        Map<String, Object?>.from(row.data),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('资料没有变化时不重写 EPUB、不产生版本或通知', () async {
    final f = await _library();
    final book = await f.library.importBytes(buildTestEpub());
    final before = (await f.db.select(f.db.books).getSingle()).toJson();
    final versions = Directory('${f.root.path}/books/${book.id}/versions');
    final paths = [for (final entry in versions.listSync()) entry.path];
    var notifications = 0;
    f.library.addListener(() => notifications++);

    final unchanged = await f.library.updateBookMetadata(
      book.id,
      title: '  ${book.title}  ',
      author: ' ${book.author} ',
      description: ' ${book.description} ',
    );

    expect(unchanged.filePath, book.filePath);
    expect(unchanged.contentRevision, book.contentRevision);
    expect((await f.db.select(f.db.books).getSingle()).toJson(), before);
    expect([
      for (final entry in versions.listSync()) entry.path,
    ], unorderedEquals(paths));
    expect(notifications, 0);
  });

  test('资料、封面和多个标签写入当前 EPUB，导出重开保留正文和未修改字段', () async {
    final f = await _library();
    final source = buildTestEpub(
      title: '原书名',
      identifier: 'metadata-all',
      cover: true,
    );
    final book = await f.library.importBytes(source);
    final before = await openEpubFile(File(book.filePath));
    final oldChapter = before.document!.archive.readBytes('OEBPS/c1.xhtml');
    before.document!.archive.close();
    await f.library.updateBookMetadata(
      book.id,
      title: '新书名<&>',
      author: '新作者 & 合著',
      description: '简介第一行\n第二行 <正文>',
    );
    final tagA = await f.library.createTag('科幻 & 冒险');
    final tagB = await f.library.createTag('中文标签');
    await f.library.addBookTag(book.id, tagA.id);
    await f.library.addBookTag(book.id, tagB.id);
    final afterTags = (await f.library.bookById(book.id))!;
    await f.library.addBookTag(book.id, tagB.id);
    expect(
      (await f.library.bookById(book.id))!.contentRevision,
      afterTags.contentRevision,
    );
    final cover = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==',
    );
    final updated = await f.library.replaceCover(
      book.id,
      cover,
      extension: 'png',
    );
    expect(updated.id, book.id);
    expect(updated.contentRevision, isNot(book.contentRevision));
    expect(await File(book.filePath).readAsBytes(), source);
    expect(await File(updated.coverPath!).readAsBytes(), cover);
    final output = File('${f.root.path}/exported.epub');
    const channel = MethodChannel('com.spectacular.reader_mobile/epub_export');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(channel, null);
    });
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'saveToDownloads');
      final sourcePath = (call.arguments as Map)['sourcePath'] as String;
      await File(sourcePath).copy(output.path);
      return 'content://downloads/exported';
    });
    expect(
      await EpubExport.saveToDownloads(
        File(updated.filePath),
        fileName: '新书名.epub',
      ),
      isTrue,
    );
    final reopened = await openEpubFile(output, verifyCrc: true);
    try {
      expect(reopened.ok, isTrue);
      expect(reopened.document!.meta.title, '新书名<&>');
      expect(reopened.document!.meta.author, '新作者 & 合著');
      expect(reopened.document!.meta.identifier, 'metadata-all');
      expect(reopened.document!.meta.language, 'zh');
      expect(reopened.document!.readCoverBytes(), cover);
      expect(
        reopened.document!.archive.readBytes('OEBPS/c1.xhtml'),
        oldChapter,
      );
    } finally {
      reopened.document?.archive.close();
    }
    expect(await _values(output, 'description'), ['简介第一行\n第二行 <正文>']);
    expect(await _values(output, 'subject'), ['科幻 & 冒险', '中文标签']);
    await f.library.removeBookTag(book.id, tagA.id);
    expect(
      await _values(
        File((await f.library.bookById(book.id))!.filePath),
        'subject',
      ),
      ['中文标签'],
    );
    await f.library.removeBookTag(book.id, tagB.id);
    final cleared = await f.library.updateBookMetadata(
      book.id,
      title: '新书名',
      author: '',
      description: '',
    );
    expect(await _values(File(cleared.filePath), 'subject'), isEmpty);
    expect(await _values(File(cleared.filePath), 'creator'), isEmpty);
    expect(await _values(File(cleared.filePath), 'description'), ['']);
    await f.library.sweepOrphans();
    expect(await File(cleared.filePath).exists(), isTrue);
    expect(await File(cleared.coverPath!).readAsBytes(), cover);
  });

  test('元数据修改只重指锚点版本，CFI、进度、批注、装饰和分组保持不变', () async {
    final f = await _library();
    final book = await f.library.importBytes(buildRevisionTestEpub());
    final index = await buildRevisionAnchorBookFile(
      File(book.filePath),
      revision: book.contentRevision!,
    );
    final chapter = index.chapter(0)!;
    final cfi = chapter.cfiAt(chapter.text.indexOf(revisionQuote))!;
    await DriftProgressStore(f.db).save(
      book.id,
      ReaderProgress(
        spineIndex: 0,
        pageIndex: 7,
        cfi: cfi,
        contentRevision: book.contentRevision,
        readingPercent: .42,
        finished: true,
        scrollOffset: 92,
        layoutFingerprint: '保留版式',
      ),
    );
    await f.library
        .annotationStore(book.id)!
        .add(
          type: ReaderAnnotationType.thought,
          startCfi: cfi,
          endCfi: cfi,
          quote: revisionQuote,
          note: '保留批注',
        );
    await f.library
        .bookmarkStore(book.id)!
        .add(cfi: cfi, spineIndex: 0, label: '保留书签');
    await f.library
        .decorationStore(
          book.id,
          images: ReaderDecorationImages(directoryProvider: () async => f.root),
        )!
        .add(
          startCfi: cfi,
          endCfi: cfi,
          quote: revisionQuote,
          style: const ReaderDecorationStyle(backgroundColor: 0xff112233),
        );
    final group = await f.library.createGroup('原分组');
    await f.library.setBooksGroup([book.id], groupId: group.id);
    final tables = [
      'reading_progress',
      'annotations',
      'decorations',
      'spine_items',
      'chapters',
      'shelf_group_books',
    ];
    final before = {
      for (final table in tables) table: await _rows(f.db, table),
    };
    final old = await f.db.select(f.db.books).getSingle();
    final updated = await f.library.updateBookMetadata(
      book.id,
      title: '修改资料',
      author: '作者',
      description: '简介',
    );
    final current = await f.db.select(f.db.books).getSingle();
    expect(current.id, old.id);
    expect(current.uuid, old.uuid);
    expect(current.layoutVersion, old.layoutVersion);
    expect(current.createdAt, old.createdAt);
    expect(current.lastReadAt, old.lastReadAt);
    for (final table in tables) {
      final after = await _rows(f.db, table);
      for (final row in after) {
        final anchorJson = row['anchor_json'];
        if (anchorJson is! String) continue;
        final anchor = AnchorRecord.decode(anchorJson)!;
        expect(anchor.effective.revision, updated.contentRevision);
        final original = before[table]!.firstWhere(
          (item) => item['id'] == row['id'],
        );
        final data = jsonDecode(anchorJson) as Map<String, dynamic>;
        data['current'] =
            (jsonDecode(original['anchor_json'] as String) as Map)['current'];
        row['anchor_json'] = jsonEncode(data);
      }
      expect(after, before[table], reason: '$table 只允许重指锚点版本');
    }
  });

  test('资料提交失败回滚源文件、标签和书库，清理未提交文件', () async {
    final f = await _library();
    final book = await f.library.importBytes(buildTestEpub());
    final before = (await f.db.select(f.db.books).getSingle()).toJson();
    final tag = await f.library.createTag('失败标签');
    await f.db.customStatement(
      "CREATE TRIGGER reject_metadata BEFORE INSERT ON book_tag_links BEGIN SELECT RAISE(ABORT, '模拟保存失败'); END",
    );
    await expectLater(f.library.addBookTag(book.id, tag.id), throwsA(anything));
    expect((await f.db.select(f.db.books).getSingle()).toJson(), before);
    expect(await f.library.bookTags(book.id), isEmpty);
    expect(await File(book.filePath).exists(), isTrue);
    expect(
      await Directory('${f.root.path}/books/${book.id}/versions')
          .list()
          .where((entry) => entry.path != File(book.filePath).parent.path)
          .toList(),
      isEmpty,
    );
    await f.db.customStatement('DROP TRIGGER reject_metadata');
    await f.library.addBookTag(book.id, tag.id);
    expect((await f.library.bookTags(book.id)).single.name, '失败标签');
  });

  test('同一书籍并发保存资料和标签按队列合并，不覆盖先完成的修改', () async {
    final f = await _library();
    final book = await f.library.importBytes(buildTestEpub());
    final tag = await f.library.createTag('并发标签');
    await Future.wait([
      f.library.updateBookMetadata(
        book.id,
        title: '并发保存的书名',
        author: '并发作者',
        description: '并发简介',
      ),
      f.library.addBookTag(book.id, tag.id),
    ]);
    final current = (await f.library.bookById(book.id))!;
    expect(current.title, '并发保存的书名');
    expect(await _values(File(current.filePath), 'title'), ['并发保存的书名']);
    expect(await _values(File(current.filePath), 'subject'), ['并发标签']);
    expect((await f.library.bookTags(book.id)).single.id, tag.id);
  });

  test('正在阅读、已有编辑草稿或磁盘版本改变时拒绝写入，不丢失原数据', () async {
    final f = await _library();
    final book = await f.library.importBytes(buildTestEpub());
    Future<BookEntry> save() => f.library.updateBookMetadata(
      book.id,
      title: '禁止保存',
      author: '作者',
      description: '简介',
    );
    f.library.beginSyncRead();
    await expectLater(save(), throwsA(isA<LibraryImportException>()));
    f.library.endSyncRead();
    await f.library.persistEditDraft(
      book.id,
      book.contentRevision!,
      (_) => {'version': 1},
    );
    await expectLater(save(), throwsA(isA<LibraryImportException>()));
    expect(await f.library.loadEditDraft(book.id), isNotNull);
    await f.library.discardEditDraft(book.id);
    await File(book.filePath)
        .writeAsBytes(buildTestEpub(paragraphs: ['外部改变的正文']));
    await expectLater(save(), throwsA(isA<LibraryImportException>()));
    expect((await f.library.bookById(book.id))!.title, book.title);
    expect(
      (await f.library.bookById(book.id))!.contentRevision,
      book.contentRevision,
    );
  });
}
