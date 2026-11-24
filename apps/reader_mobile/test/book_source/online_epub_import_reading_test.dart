import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/source/chapter_source.dart'
    show ChapterLoadCancelled;
import 'package:reader_mobile/book_source/book_source_cookie_store.dart';
import 'package:reader_mobile/book_source/book_source_http_client.dart';
import 'package:reader_mobile/book_source/book_source_models.dart';
import 'package:reader_mobile/book_source/book_source_service.dart';
import 'package:reader_mobile/book_source/book_source_store.dart';
import 'package:reader_mobile/book_source/online_book_controller.dart';
import 'package:reader_mobile/book_source/online_chapter_content_store.dart';
import 'package:reader_mobile/book_source/online_chapter_request.dart';
import 'package:reader_mobile/book_source/online_epub_metadata.dart';
import 'package:reader_mobile/book_source/online_epub_builder.dart';
import 'package:reader_mobile/book_source/online_reading_book.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/reader/book_opener.dart';
import 'package:reader_mobile/reader/epub_reader_page.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/storage/drift_progress_store.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/reader_pump.dart';
import '../support/test_epub.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('目录入架下载封面且不请求正文，旧目录书可补封面而不替换书籍', () async {
    final f = await _Fixture.create();
    addTearDown(f.dispose);
    final book = OnlineBook(
      sourceId: f.source.id,
      sourceName: f.source.name,
      name: '封面测试',
      author: '作者',
      bookUrl: 'https://example.test/book',
      coverUrl: 'https://example.test/cover.png',
      intro: '在线图书的简介。\n第二段。',
    );
    final catalog = await f.controller.refreshCatalog(f.source, book);
    final entry = await f.controller.addToShelf(
      f.source,
      catalog.book,
      catalog.chapters,
    );
    expect(entry.coverPath, isNotNull);
    expect(entry.description, '在线图书的简介。\n第二段。');
    expect(await File(entry.coverPath!).exists(), isTrue);
    expect(
      f.requested.where((url) => RegExp(r'^/\d+$').hasMatch(url)),
      isEmpty,
    );
    final plain = OnlineBook(
      sourceId: f.source.id,
      sourceName: f.source.name,
      name: '旧目录书',
      author: '作者',
      bookUrl: 'https://example.test/old-book',
    );
    final old = await f.controller.addToShelf(
      f.source,
      plain,
      catalog.chapters,
    );
    expect(old.coverPath, isNull);
    final patched = await f.controller.addToShelf(
      f.source,
      plain.copyWith(coverUrl: book.coverUrl, intro: book.intro),
      catalog.chapters,
    );
    expect(patched.id, old.id);
    expect(patched.contentRevision, old.contentRevision);
    expect(patched.coverPath, isNotNull);
    expect(patched.description, book.intro);
  });

  test('逐章书手动下载全本后保留书架身份并按正文迁移在线续读', () async {
    final f = await _Fixture.create();
    addTearDown(f.dispose);
    final entry = await f.controller.downloadAndImport(
      f.source,
      OnlineBook(
        sourceId: f.source.id,
        sourceName: f.source.name,
        name: '逐章书',
        author: '作者',
        bookUrl: 'https://example.test/book',
      ),
    );
    final reading = await (await f.controller.prepareImportedReading(
      entry,
      f.progress,
    ))!.book;
    final online = reading.open();
    final chapter = await online.loadAnchorChapter(1);
    final cfi = chapter.cfiAt(chapter.text.indexOf('按需读取'))!;
    await OnlineReadingProgress(f.library, reading).save(
      entry.id,
      ReaderProgress(
        spineIndex: 1,
        pageIndex: 0,
        cfi: cfi,
        contentRevision: reading.revision,
      ),
    );
    online.close();
    await online.preparationsStopped;
    final progress = DriftProgressStore(f.db);
    const notifications = MethodChannel(
      'com.spectacular.reader_mobile/online_download',
    );
    final calls = <Map<Object?, Object?>>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(notifications, (call) async {
      final args = call.arguments as Map;
      if (args['done'] == true) {
        // 完成通知必须在正式书架入口成功保存完整正文后出现。
        final saved = await f.library.bookById(entry.id);
        expect(
          (await OnlineEpubMetadata.read(
            f.library,
            saved!,
          ))!.requiresOnlineReading,
          isFalse,
        );
      }
      calls.add(args);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(notifications, null));
    final updated = await f.controller.updateBook(
      entry,
      progressStore: progress,
    );
    expect(updated.id, entry.id);
    expect(calls.first['message'], '正在准备下载');
    expect(calls.last['message'], '已保存到书架');
    expect(calls.last['done'], isTrue);
    expect(
      (await OnlineEpubMetadata.read(
        f.library,
        updated,
      ))!.requiresOnlineReading,
      isFalse,
    );
    final saved = (await progress.load(updated.id))!;
    expect(saved.spineIndex, 1);
    final offline = await EpubChapterSource.openFile(File(updated.filePath));
    try {
      final next = await offline.loadAnchorChapter(saved.spineIndex);
      final offset = next.offsetFor(saved.cfi!)!;
      expect(next.text.substring(offset), startsWith('按需读取'));
    } finally {
      offline.close();
      await offline.preparationsStopped;
    }
  });

  test('逐章加入书架不下载正文，重复加入保持身份，书架打开自动刷新目录', () async {
    final f = await _Fixture.create();
    addTearDown(f.dispose);
    final book = OnlineBook(
      sourceId: f.source.id,
      sourceName: f.source.name,
      name: '逐章书',
      author: '作者',
      bookUrl: 'https://example.test/book',
    );
    final entry = await f.controller.downloadAndImport(f.source, book);
    expect(f.requested, ['/book', '/toc']);
    expect(
      (await OnlineEpubMetadata.read(f.library, entry))!.requiresOnlineReading,
      isTrue,
    );
    expect(f.controller.shelfEntryFor(f.source, book)?.id, entry.id);
    f.requested.clear();
    final duplicate = await f.controller.addToShelf(f.source, book, const [
      OnlineChapter(index: 0, title: '第一章', url: 'https://example.test/1'),
    ]);
    expect(duplicate.id, entry.id);
    expect(await f.library.list(), hasLength(1));
    expect(f.requested, isEmpty);
    final reading = await (await f.controller.prepareImportedReading(
      entry,
      f.progress,
    ))!.book;
    expect(reading.bookshelfId, entry.id);
    expect(f.requested, ['/book', '/toc']);
  });

  test('阅微旧完整索引、按需索引和仅进度标记按真实格式识别', () {
    final legacy = OnlineEpubMetadata.fromJson(
      {..._index(), 'version': 1}..remove('mode'),
    )!;
    expect(legacy.requiresOnlineReading, isFalse);
    expect(legacy.chapters.every((chapter) => chapter.ready), isTrue);
    final fullWithMarker = OnlineEpubMetadata.fromJson(
      _index(ready: true),
      marker: _marker(progressOnly: false),
    )!;
    expect(fullWithMarker.syncMarker, isTrue);
    expect(fullWithMarker.requiresOnlineReading, isFalse);

    final pending = OnlineEpubMetadata.fromJson(_index())!;
    expect(pending.requiresOnlineReading, isTrue);
    expect(pending.chapters.every((chapter) => !chapter.ready), isTrue);

    final progressOnly = OnlineEpubMetadata.fromJson(
      _index(chapters: false),
      marker: _marker(),
    )!;
    expect(progressOnly.progressOnly, isTrue);
    expect(progressOnly.chapters, isEmpty);
    expect(progressOnly.requiresOnlineReading, isTrue);
    expect(OnlineEpubMetadata.fromJson(_index(chapters: false)), isNull);
    expect(
      OnlineEpubMetadata.fromJson(
        _index(chapters: false),
        marker: {..._marker(), 'sourceId': '其他源'},
      ),
      isNull,
    );
  });

  test('稳定源 ID、模块别名和 URL 摘要匹配，重名和重复别名不猜测', () {
    final original = BookSource.fromJson(_sourceJson());
    final metadata = OnlineEpubMetadata.fromJson(_index())!;
    expect(metadata.sourceIn([original]), same(original));
    final stable = OnlineEpubMetadata.fromJson({
      ..._index(),
      'sourceId': stableBookSourceId(original.sourceUrl),
    })!;
    expect(stable.sourceIn([original]), same(original));
    final exact = OnlineEpubMetadata.fromJson({
      ..._index(),
      'sourceId': original.id,
    })!;
    final ambiguous = original.copyWith(id: '第二源');
    expect(metadata.sourceIn([original, ambiguous]), isNull);
    expect(exact.sourceIn([original, ambiguous]), same(original));
    final unrelated = OnlineEpubMetadata.fromJson({
      ..._index(),
      'sourceId': '不相关模块',
    })!;
    expect(unrelated.sourceIn([original]), isNull);
  });

  test('关联持久化保留 POST 详情和目录请求身份，兼容旧内联 URL', () async {
    final f = await _Fixture.create();
    addTearDown(f.dispose);
    await f.store.saveLink(
      'legacy-local-book',
      const OnlineBookLink(
        sourceId: 'synced-source',
        bookUrl: 'https://example.test/book',
        name: '旧书架关联',
        author: '',
      ),
    );
    await f.controller.initialize(refresh: true);
    expect(f.controller.sourceForBook('legacy-local-book')?.id, f.source.id);
    const detailUrl =
        'https://example.test/book,{"method":"POST","body":"book=42"}';
    final entry = await f.library.importBytes(_epub(detailUrl: detailUrl));
    await f.controller.registerImportedBooks();
    final reader = BookSourceStore(directoryProvider: () async => f.directory);
    addTearDown(reader.dispose);
    final loaded = (await reader.loadLinks())[entry.id]!.bookFor(f.source);
    expect(loaded.bookUrl, 'https://example.test/book');
    expect(loaded.bookOptions, {'method': 'POST', 'body': 'book=42'});
    expect(loaded.tocOptions, loaded.bookOptions);
    final legacy = OnlineBookLink.fromJson({
      'sourceId': f.source.id,
      'bookUrl': detailUrl,
      'tocUrl':
          'https://example.test/toc,{"method":"POST","body":"catalog=42"}',
    }).bookFor(f.source);
    expect(legacy.bookOptions, loaded.bookOptions);
    expect(legacy.tocOptions, {'method': 'POST', 'body': 'catalog=42'});
    f.tocUrl = '/toc,{"method":"POST","body":"catalog=42"}';
    final reading = await (await f.controller.prepareImportedReading(
      entry,
      f.progress,
    ))!.book;
    expect(reading.book.tocOptions, {'method': 'POST', 'body': 'catalog=42'});
    expect(f.requestBodies, ['POST /book book=42', 'POST /toc catalog=42']);
  });

  test('同步替换的显式源和详情 POST 身份覆盖旧关联，不读取旧书目录', () async {
    final f = await _Fixture.create();
    addTearDown(f.dispose);
    final original = await f.library.importBytes(_epub());
    await f.controller.registerImportedBooks();
    expect(f.controller.links[original.id]?.sourceId, f.source.id);
    final replacementSource = await f.controller.importText(
      jsonEncode({
        ..._sourceJson(),
        'bookSourceId': 'replacement-source',
        'bookSourceUrl': 'https://replacement.test',
        'reamicroSourceId': 'replacement-module',
        'reamicroSourceAliases': ['replacement-alias'],
      }),
    );
    final replaced = await f.library.updateBytes(
      original.id,
      _epub(
        sourceId: 'replacement-alias',
        detailUrl:
            'https://replacement.test/book,{"method":"POST","body":"book=84"}',
      ),
    );
    f.tocUrl = '/toc,{"method":"POST","body":"catalog=84"}';
    final reading = await (await f.controller.prepareImportedReading(
      replaced,
      f.progress,
    ))!.book;
    expect(reading.source.id, replacementSource.id);
    expect(reading.book.bookOptions, {'method': 'POST', 'body': 'book=84'});
    expect(f.controller.links[original.id]?.sourceId, replacementSource.id);
    expect(
      f.requestUrls.every((url) => url.host == 'replacement.test'),
      isTrue,
    );
    expect(f.requestBodies, ['POST /book book=84', 'POST /toc catalog=84']);

    f.requestBodies.clear();
    final sameSourceNewRequest = await f.library.updateBytes(
      original.id,
      _epub(
        sourceId: 'replacement-alias',
        detailUrl:
            'https://replacement.test/book,{"method":"POST","body":"book=85"}',
      ),
    );
    f.tocUrl = '/toc,{"method":"POST","body":"catalog=85"}';
    final next = await (await f.controller.prepareImportedReading(
      sameSourceNewRequest,
      f.progress,
    ))!.book;
    expect(next.book.bookOptions['body'], 'book=85');
    expect(f.controller.links[original.id]?.bookOptions['body'], 'book=85');
    expect(f.requestBodies, ['POST /book book=85', 'POST /toc catalog=85']);
  });

  test('重复别名或缺失显式源不能借用已有旧关联，保留原关联数据', () async {
    final f = await _Fixture.create();
    addTearDown(f.dispose);
    final original = await f.library.importBytes(_epub());
    await f.controller.registerImportedBooks();
    final oldLink = f.controller.links[original.id]!;
    await f.controller.importText(
      jsonEncode({
        ..._sourceJson(),
        'bookSourceId': 'ambiguous-source',
        'reamicroSourceId': 'ambiguous-source',
        'bookSourceUrl': 'https://ambiguous.test',
      }),
    );
    expect(f.controller.sources, hasLength(2));
    expect(f.controller.links[original.id]?.bookUrl, oldLink.bookUrl);
    expect(f.controller.sourceForBook(original.id), isNull);
    await expectLater(
      f.controller.prepareImportedReading(original, f.progress),
      throwsA(isA<BookSourceException>()),
    );
    await expectLater(
      f.controller.updateBook(original),
      throwsA(isA<BookSourceException>()),
    );
    final unknown = await f.library.updateBytes(
      original.id,
      _epub(sourceId: '尚未导入的新模块'),
    );
    await expectLater(
      f.controller.prepareImportedReading(unknown, f.progress),
      throwsA(isA<BookSourceException>()),
    );
    expect(f.controller.links[original.id]?.sourceId, oldLink.sourceId);
    expect(f.requested, isEmpty);
  });

  test('索引 data 正文地址完整保留，并通过正式章节入口解码读取', () async {
    final f = await _Fixture.create();
    addTearDown(f.dispose);
    const contents = ['这一章的正文保存在索引中，进度100%+保留。', '已编码的正文仍保留100%+字符。'];
    final dataUrls = [
      'data:text/plain,${jsonEncode({'text': contents[0]})}',
      'data:text/plain,${Uri.encodeComponent(jsonEncode({'text': contents[1]}))}',
    ];
    final entry = await f.library.importBytes(_epub(chapterUrls: dataUrls));
    final metadata = (await OnlineEpubMetadata.read(f.library, entry))!;
    final chapters = [
      for (final (index, chapter) in metadata.chapters.indexed)
        chapter.toChapter(index, metadata.detailUrl),
    ];
    for (final (index, chapter) in chapters.indexed) {
      expect(chapter.url, dataUrls[index]);
      expect(chapter.requestOptions, isEmpty);
      expect(
        await metadata.chapterIdentityForSpine(f.library, entry, index + 1),
        onlineChapterIdentity(chapter),
      );
    }
    final dataSource = f.source.copyWith(
      content: const ContentRule(content: r'@regex:"text":"([^"]+)"'),
    );
    final book = OnlineReadingBook(
      source: dataSource,
      book: metadata.linkFor(dataSource, entry).bookFor(dataSource),
      chapters: chapters,
      service: f.controller.service,
      bookshelfId: entry.id,
    );
    final source = book.open();
    try {
      for (final (index, content) in contents.indexed) {
        expect((await source.loadAnchorChapter(index)).text, contains(content));
      }
      expect(f.requested, isEmpty);
    } finally {
      source.close();
      await source.preparationsStopped;
    }
  });

  test('Base64 章节附带 type 选项，从索引和旧目录均可正式打开正文', () async {
    final f = await _Fixture.create();
    addTearDown(f.dispose);
    const chapterId = '7600783039009915417';
    const dataUrl = 'data:;base64,NzYwMDc4MzAzOTAwOTkxNTQxNw==';
    final entry = await f.library.importBytes(
      _epub(
        chapterUrls: [
          '$dataUrl,{"type":"novel"}',
          'data:;base64,MTIz,{"type":"novel"}',
        ],
      ),
    );
    final metadata = (await OnlineEpubMetadata.read(f.library, entry))!;
    final indexed = metadata.chapters.first.toChapter(0, metadata.detailUrl);
    expect(indexed.url, dataUrl);
    expect(indexed.requestOptions, {'type': 'novel'});
    final dataSource = f.source.copyWith(
      content: const ContentRule(
        content:
            '<js>var id = java.hexDecodeToString(result);'
            'if (id !== "7600783039009915417") throw new Error("章节编号错误");'
            'result = "<p>章节编号：" + id + "，正文正常加载。</p>";</js>',
      ),
    );
    for (final chapter in [
      indexed,
      const OnlineChapter(
        index: 0,
        title: '旧目录第一章',
        url: '$dataUrl,{"type":"novel"}',
      ),
    ]) {
      final source = OnlineReadingBook(
        source: dataSource,
        book: metadata.linkFor(dataSource, entry).bookFor(dataSource),
        chapters: [chapter],
        service: f.controller.service,
      ).open();
      try {
        final content = (await source.loadAnchorChapter(0)).text;
        expect(content, contains(chapterId));
        expect(content, contains('正文正常加载'));
      } finally {
        source.close();
        await source.preparationsStopped;
      }
    }
    expect(f.requested, isEmpty);
  });

  test('原 spine 对应同一正文接口的 POST 章节时，按请求体恢复到新目录', () async {
    final f = await _Fixture.create();
    addTearDown(f.dispose);
    final entry = await f.library.importBytes(
      _epub(
        chapterUrls: [
          for (var index = 1; index <= 2; index++)
            'https://example.test/content,{"method":"POST","body":"chapter=$index"}',
        ],
      ),
    );
    await f.progress.save(
      entry.id,
      ReaderProgress(
        spineIndex: 2,
        pageIndex: 3,
        cfi: 'epubcfi(/6/6!/4/2/1:3)',
        contentRevision: entry.contentRevision,
      ),
    );
    f.remoteChapters = [
      for (final index in [2, 1])
        {
          'title': '同名章节',
          'url': '/content,{"method":"POST","body":"chapter=$index"}',
        },
    ];
    final book = await (await f.controller.prepareImportedReading(
      entry,
      f.progress,
    ))!.book;
    final restored = await OnlineReadingProgress(
      f.library,
      book,
    ).load(entry.id);
    expect(restored?.spineIndex, 0);
    expect(restored?.cfi, isNull);
    final source = book.open();
    try {
      await source.loadAnchorChapter(restored!.spineIndex);
      expect(f.requestBodies.last, 'POST /content chapter=2');
    } finally {
      source.close();
      await source.preparationsStopped;
    }
    expect((await f.progress.load(entry.id))?.spineIndex, 2);
  });

  test('导入书按 href 恢复源章节并逐章读取，目录追加保留在线锚点和原书进度', () async {
    final f = await _Fixture.create();
    addTearDown(f.dispose);
    final bytes = _epub();
    final entry = await f.library.importBytes(bytes);
    final local = await EpubChapterSource.openFile(File(entry.filePath));
    final cfi = (await local.loadAnchorChapter(2)).cfiAt(5);
    local.close();
    await local.preparationsStopped;
    expect(cfi, isNotNull);
    final prior = ReaderProgress(
      spineIndex: 2,
      pageIndex: 4,
      cfi: cfi,
      scrollOffset: 31,
      layoutFingerprint: '原 EPUB 排版',
      contentRevision: entry.contentRevision,
    );
    await f.progress.save(entry.id, prior);
    await f.controller.registerImportedBooks();
    expect(f.controller.sourceForBook(entry.id)?.id, f.source.id);
    expect(f.requested, isEmpty);

    final pending = await f.controller.prepareImportedReading(
      entry,
      f.progress,
    );
    final book = await pending!.book;
    expect(book.id, entry.id);
    expect(book.chapters, hasLength(3));
    final store = OnlineReadingProgress(f.library, book);
    final initial = (await store.load(entry.id))!;
    expect(initial.spineIndex, 1);
    expect(initial.approximate, isTrue);
    expect(initial.cfi, isNull);
    expect(initial.scrollOffset, isNull);
    expect(initial.layoutFingerprint, isNull);
    final source = book.open();
    final session = ReaderSession(
      source: source,
      store: store,
      bookId: book.id,
      contentRevision: book.revision,
      persistInitialPosition: true,
    );
    try {
      await session.open(contentWidth: 325, contentHeight: 580);
      expect(f.requested.take(3), ['/book', '/toc', '/2']);
      expect((await source.loadAnchorChapter(1)).text, contains('源站第2章正文'));
      await session.flushProgress();
    } finally {
      session.dispose();
      source.close();
      await source.preparationsStopped;
    }
    final saved = (await store.load(entry.id))!;
    expect(saved.spineIndex, 1);
    expect(saved.cfi, isNotNull);
    expect(await f.progress.load(entry.id), prior);
    expect(await File(entry.filePath).readAsBytes(), bytes);
    expect(await f.library.list(), hasLength(1));

    f.remoteOrder = [1, 2, 3, 4];
    final reopened = await (await f.controller.prepareImportedReading(
      entry,
      f.progress,
    ))!.book;
    expect(reopened.chapters, hasLength(4));
    final resumed = await OnlineReadingProgress(
      f.library,
      reopened,
    ).load(entry.id);
    expect(resumed?.cfi, saved.cfi);
    expect(resumed?.spineIndex, 1);
    f.remoteOrder = [1, 2, 3, 4, 5];
    f.requested.clear();
    final updated = await f.controller.updateBook(entry);
    expect(updated.id, entry.id);
    expect(updated.contentRevision, isNot(entry.contentRevision));
    expect(f.controller.lastUpdateWasCatalogOnly, isFalse);
    expect(f.controller.lastAddedChapters, 5);
    // 第 2 章已阅读并缓存，手动全本更新复用缓存，其余章仍完整获取。
    expect(f.requested, ['/book', '/toc', '/1', '/3', '/4', '/5']);
    expect(
      (await OnlineEpubMetadata.read(
        f.library,
        updated,
      ))!.requiresOnlineReading,
      isFalse,
    );
  });

  test('仅进度在线 EPUB 可获取新目录，不把占位 CFI 套到在线正文', () async {
    final f = await _Fixture.create();
    addTearDown(f.dispose);
    final entry = await f.library.importBytes(_epub(progressOnly: true));
    final prior = ReaderProgress(
      spineIndex: 0,
      pageIndex: 0,
      cfi: 'epubcfi(/6/2!/4/2/1:0)',
      contentRevision: entry.contentRevision,
    );
    await f.progress.save(entry.id, prior);
    final online = await (await f.controller.prepareImportedReading(
      entry,
      f.progress,
    ))!.book;
    expect(online.id, entry.id);
    expect(online.chapters, hasLength(3));
    expect(
      await OnlineReadingProgress(f.library, online).load(entry.id),
      isNull,
    );
    expect(await f.progress.load(entry.id), prior);
  });

  test('完整离线 EPUB 保持原阅读，缺少对应源时给出可处理的错误', () async {
    final f = await _Fixture.create();
    addTearDown(f.dispose);
    final full = await f.library.importBytes(
      _epub(ready: true, syncMarker: true),
    );
    expect(await f.controller.prepareImportedReading(full, f.progress), isNull);
    expect(f.controller.sourceForBook(full.id)?.id, f.source.id);
    final unmatched = await f.library.importBytes(
      _epub(sourceId: '未导入模块', title: '另一本在线书'),
    );
    await expectLater(
      f.controller.prepareImportedReading(unmatched, f.progress),
      throwsA(
        isA<BookSourceException>().having(
          (error) => error.message,
          'message',
          contains('对应书源'),
        ),
      ),
    );
    expect(f.requested, isEmpty);
  });

  testWidgets('书架打开在线同步书等待目录，退出首帧恢复入口并保留身份和续读', (tester) async {
    final f = (await tester.runAsync(_Fixture.create))!;
    addTearDown(f.dispose);
    final entry = await pumpReaderTask(
      tester,
      f.library.importBytes(_epub(progressOnly: true)),
    );
    f.catalogGate = Completer<void>();
    var finished = 0;
    final opener = BookOpener(
      library: f.library,
      progressStore: f.progress,
      onlineBooks: f.controller,
      onReadingFinished: () => finished++,
    );
    Future<void>? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => opened = opener.open(context, entry),
              child: const Text('打开同步书'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开同步书'));
    await pumpReaderUntil(tester, find.byType(EpubReaderPage));
    expect(find.byKey(const ValueKey('reader-content')), findsNothing);
    f.catalogGate!.complete();
    await pumpReaderUntil(tester, find.byKey(const ValueKey('reader-content')));
    final reader = tester.widget<EpubReaderPage>(find.byType(EpubReaderPage));
    expect(reader.bookId, entry.id);
    expect(reader.readingSessions, isNotNull);
    final source = await pumpReaderTask(tester, reader.sourceFuture!);
    expect(
      (await pumpReaderTask(tester, source.loadAnchorChapter(0))).text,
      contains('源站第1章正文'),
    );
    expect(tester.widget<ReaderPage>(find.byType(ReaderPage)).onSearch, isNull);
    // 先完成入场，避免尚未展开的路由掩盖退出动画。
    await tester.pump(
      ModalRoute.of(tester.element(find.byType(EpubReaderPage)))!
          .transitionDuration,
    );
    Navigator.of(tester.element(find.byType(EpubReaderPage))).pop();
    await tester.pump();
    expect(find.text('打开同步书').hitTestable(), findsOneWidget);
    expect(find.byType(EpubReaderPage), findsNothing);
    await pumpReaderTask(tester, opened!);
    expect(finished, 1);
    expect(
      (await pumpReaderTask(tester, f.library.bookById(entry.id)))?.lastReadAt,
      isNotNull,
    );
    expect(await pumpReaderTask(tester, f.library.list()), hasLength(1));
    await pumpReaderTask(tester, f.service.waitForIdle());
    await tester.pumpWidget(const SizedBox());
  }, timeout: const Timeout(Duration(seconds: 45)));

  testWidgets('目录失败由正式阅读页展示，不产生派生异常或写坏原 EPUB 位置', (tester) async {
    final f = (await tester.runAsync(_Fixture.create))!;
    addTearDown(f.dispose);
    final entry = await pumpReaderTask(tester, f.library.importBytes(_epub()));
    final prior = ReaderProgress(
      spineIndex: 2,
      pageIndex: 3,
      cfi: 'epubcfi(/6/6!/4/2/1:3)',
      contentRevision: entry.contentRevision,
    );
    await f.progress.save(entry.id, prior);
    f.catalogFailure = const BookSourceException('测试目录获取失败');
    final opener = BookOpener(
      library: f.library,
      progressStore: f.progress,
      onlineBooks: f.controller,
    );
    Future<void>? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => opened = opener.open(context, entry),
              child: const Text('打开同步书'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开同步书'));
    await pumpReaderUntil(
      tester,
      find.byKey(const ValueKey('epub-open-error')),
    );
    expect(find.textContaining('测试目录获取失败'), findsOneWidget);
    expect(tester.takeException(), isNull);
    Navigator.of(tester.element(find.byType(EpubReaderPage))).pop();
    await pumpReaderTask(tester, opened!);
    expect(tester.takeException(), isNull);
    expect(
      (await pumpReaderTask(tester, f.library.bookById(entry.id)))?.lastReadAt,
      isNull,
    );
    expect(await f.progress.load(entry.id), prior);
    expect(
      await pumpReaderTask(
        tester,
        f.library.getSetting('online_reading_progress:${entry.id}'),
      ),
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
  }, timeout: const Timeout(Duration(seconds: 45)));

  testWidgets('目录等待时返回立即解锁重开，晚到请求不创建旧源或回写位置', (tester) async {
    final f = (await tester.runAsync(_Fixture.create))!;
    addTearDown(f.dispose);
    final entry = await pumpReaderTask(tester, f.library.importBytes(_epub()));
    final prior = ReaderProgress(
      spineIndex: 2,
      pageIndex: 3,
      cfi: 'epubcfi(/6/6!/4/2/1:3)',
      contentRevision: entry.contentRevision,
    );
    await f.progress.save(entry.id, prior);
    f.catalogGate = Completer<void>();
    final opener = BookOpener(
      library: f.library,
      progressStore: f.progress,
      onlineBooks: f.controller,
    );
    Future<void>? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => opened = opener.open(context, entry),
              child: const Text('打开同步书'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开同步书'));
    await pumpReaderUntil(tester, find.byType(EpubReaderPage));
    final oldSource = tester
        .widget<EpubReaderPage>(find.byType(EpubReaderPage))
        .sourceFuture!;
    Object? sourceFailure;
    unawaited(
      oldSource.then<void>(
        (_) => fail('取消目录等待后不应创建旧章节源'),
        onError: (Object error, StackTrace _) {
          sourceFailure = error;
        },
      ),
    );
    Navigator.of(tester.element(find.byType(EpubReaderPage))).pop();
    await pumpReaderTask(tester, opened!);
    expect(f.catalogGate!.isCompleted, isFalse);
    expect(sourceFailure, isA<ChapterLoadCancelled>());
    expect(
      (await pumpReaderTask(tester, f.library.bookById(entry.id)))?.lastReadAt,
      isNull,
    );
    expect(await f.progress.load(entry.id), prior);
    expect(
      await pumpReaderTask(
        tester,
        f.library.getSetting('online_reading_progress:${entry.id}'),
      ),
      isNull,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('打开同步书'));
    await pumpReaderUntil(tester, find.byType(EpubReaderPage));
    f.catalogGate!.complete();
    await pumpReaderUntil(tester, find.byKey(const ValueKey('reader-content')));
    expect(sourceFailure, isA<ChapterLoadCancelled>());
    expect(f.requested.where((path) => path == '/book'), hasLength(1));
    expect(await f.progress.load(entry.id), prior);
    Navigator.of(tester.element(find.byType(EpubReaderPage))).pop();
    await pumpReaderTask(tester, opened!);
    expect(tester.takeException(), isNull);
    expect(await pumpReaderTask(tester, f.library.list()), hasLength(1));
    await pumpReaderTask(tester, f.service.waitForIdle());
    await tester.pumpWidget(const SizedBox());
  }, timeout: const Timeout(Duration(seconds: 45)));
}

Map<String, Object?> _index({
  String sourceId = 'synced-source',
  String detailUrl = 'https://example.test/book',
  bool chapters = true,
  bool ready = false,
  List<String>? chapterUrls,
}) => {
  'version': 2,
  'sourceId': sourceId,
  'detailUrl': detailUrl,
  'bookName': '在线同步书',
  'mode': ready ? 'FULL' : 'ON_DEMAND',
  'chapters': [
    if (chapters)
      for (var index = 1; index <= (chapterUrls?.length ?? 2); index++)
        {
          'sourceChapterId': 'chapter-$index',
          'url': chapterUrls?[index - 1] ?? 'https://example.test/$index',
          'title': '第$index章',
          'volumeTitle': '',
          'href': 'c${index + 1}.xhtml',
          if (ready) 'state': 'READY',
          'downloadedAtMs': 0,
          'attempts': 0,
          'lastError': '',
        },
  ],
};

Map<String, Object?> _marker({
  String sourceId = 'synced-source',
  String detailUrl = 'https://example.test/book',
  bool progressOnly = true,
}) => {
  'version': 1,
  'uuid': 'remote-online-uuid',
  'sourceId': sourceId,
  'detailUrl': detailUrl,
  'bookName': '在线同步书',
  'progressOnly': progressOnly,
};

Uint8List _epub({
  String sourceId = 'synced-source',
  String detailUrl = 'https://example.test/book',
  String title = '在线同步书',
  bool ready = false,
  bool progressOnly = false,
  bool syncMarker = false,
  List<String>? chapterUrls,
}) {
  final archive = ZipDecoder().decodeBytes(
    buildMultiChapterEpub(
      title: title,
      chapters: progressOnly
          ? ['请配置对应书源后更新章节。']
          : [
              '封面',
              for (var index = 1; index <= (chapterUrls?.length ?? 2); index++)
                ready ? '本地第$index章完整正文。' : '章节等待从书源更新。',
            ],
    ),
  );
  void addJson(String path, Map<String, Object?> value) {
    final bytes = utf8.encode(jsonEncode(value));
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  addJson(
    OnlineEpubMetadata.indexPath,
    _index(
      sourceId: sourceId,
      detailUrl: detailUrl,
      chapters: !progressOnly,
      ready: ready,
      chapterUrls: chapterUrls,
    ),
  );
  if (progressOnly || syncMarker) {
    addJson(
      OnlineEpubMetadata.markerPath,
      _marker(
        sourceId: sourceId,
        detailUrl: detailUrl,
        progressOnly: progressOnly,
      ),
    );
  }
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

Map<String, Object?> _sourceJson() => {
  'bookSourceName': '在线同步书源',
  'bookSourceUrl': 'https://example.test',
  'reamicroSourceId': 'installed-source',
  'reamicroPackageId': 'module-package',
  'reamicroSourceAliases': ['synced-source'],
  'searchUrl': '/search?key={{key}}',
  'ruleSearch': {'bookList': r'$.books[*]'},
  'ruleBookInfo': {'tocUrl': r'$.toc'},
  'ruleToc': {
    'chapterList': r'$.chapters[*]',
    'chapterName': r'$.title',
    'chapterUrl': r'$.url',
  },
  'ruleContent': {'content': r'$.content'},
};

class _Fixture {
  _Fixture(
    this.directory,
    this.db,
    this.library,
    this.store,
    this.source,
    this.service,
    this.controller,
  );

  final Directory directory;
  final AppDatabase db;
  final LibraryStore library;
  final BookSourceStore store;
  final BookSource source;
  final _TrackedBookSourceService service;
  final OnlineBookController controller;
  final progress = MemoryReaderProgressStore();
  final requested = <String>[];
  final requestUrls = <Uri>[];
  final requestBodies = <String>[];
  String tocUrl = '/toc';
  List<int> remoteOrder = [1, 2, 3];
  List<Map<String, Object?>>? remoteChapters;
  Completer<void>? catalogGate;
  BookSourceException? catalogFailure;

  static Future<_Fixture> create() async {
    final directory = await Directory.systemTemp.createTemp(
      'online-epub-import-',
    );
    final db = AppDatabase(NativeDatabase.memory());
    final library = LibraryStore(
      database: db,
      directoryProvider: () async => directory,
    );
    final store = BookSourceStore(directoryProvider: () async => directory);
    final source = await store.importText(jsonEncode(_sourceJson()));
    final cookies = BookSourceCookieStore(
      directoryProvider: () async => directory,
    );
    late final _Fixture fixture;
    final originalService = BookSourceService(
      cookieStore: cookies,
      chapterContentStore: OnlineChapterContentStore(
        directoryProvider: () async => directory,
      ),
      httpClient: BookSourceHttpClient(
        cookieStore: cookies,
        client: MockClient((request) async {
          final path = request.url.path;
          fixture.requested.add(path);
          fixture.requestUrls.add(request.url);
          fixture.requestBodies.add('${request.method} $path ${request.body}');
          if (path == '/cover.png') {
            return http.Response.bytes(
              base64Decode(
                'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==',
              ),
              200,
              headers: {'content-type': 'image/png'},
            );
          }
          if (path == '/book') {
            await fixture.catalogGate?.future;
            final failure = fixture.catalogFailure;
            if (failure != null) throw failure;
          }
          return http.Response(
            jsonEncode(switch (path) {
              '/book' => {'toc': fixture.tocUrl},
              '/toc' => {
                'chapters':
                    fixture.remoteChapters ??
                    [
                      for (final index in fixture.remoteOrder)
                        {'title': '第$index章', 'url': '/$index'},
                    ],
              },
              _ => {'content': '<p>源站第${path.substring(1)}章正文，按需读取而非整本下载。</p>'},
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );
    final service = _TrackedBookSourceService(originalService);
    fixture = _Fixture(
      directory,
      db,
      library,
      store,
      source,
      service,
      OnlineBookController(
        library: library,
        store: store,
        service: service,
        cookieStore: cookies,
      ),
    );
    await fixture.controller.initialize();
    return fixture;
  }

  Future<void> dispose() async {
    if (catalogGate != null && !catalogGate!.isCompleted) {
      catalogGate!.complete();
    }
    await controller.registerImportedBooks();
    await service.waitForIdle();
    controller.dispose();
    await db.close();
    await directory.delete(recursive: true);
  }
}

/// 追踪完整正文请求，防止引擎取消等待后夹具抢先删除仍在写入的缓存。
class _TrackedBookSourceService implements BookSourceService {
  _TrackedBookSourceService(this._delegate);

  final BookSourceService _delegate;
  final _pendingContent = <Future<String>>{};

  @override
  Future<OnlineBookDownloadResult> download(
    BookSource source,
    OnlineBook book, {
    OnlineDownloadProgress? onProgress,
    bool Function()? isCancelled,
    OnlineBook? preparedBook,
    List<OnlineChapter>? selectedChapters,
    List<OnlineChapter>? chapterDirectory,
  }) => _delegate.download(
    source,
    book,
    onProgress: onProgress,
    isCancelled: isCancelled,
    preparedBook: preparedBook,
    selectedChapters: selectedChapters,
    chapterDirectory: chapterDirectory,
  );

  Future<void> waitForIdle() async {
    while (_pendingContent.isNotEmpty) {
      await Future.wait(_pendingContent.toList());
    }
  }

  @override
  Future<String> fetchChapterContent(
    BookSource source,
    OnlineChapter chapter,
    String bookUrl, {
    bool forceRefresh = false,
    OnlineChapter? nextChapter,
    String? nextChapterUrl,
  }) {
    final task = _delegate.fetchChapterContent(
      source,
      chapter,
      bookUrl,
      forceRefresh: forceRefresh,
      nextChapter: nextChapter,
      nextChapterUrl: nextChapterUrl,
    );
    _pendingContent.add(task);
    task.whenComplete(() => _pendingContent.remove(task)).ignore();
    return task;
  }

  @override
  Future<OnlineBook> loadBookInfo(BookSource source, OnlineBook book) =>
      _delegate.loadBookInfo(source, book);

  @override
  Future<List<OnlineChapter>> fetchToc(BookSource source, OnlineBook book) =>
      _delegate.fetchToc(source, book);

  @override
  String contentRulesFingerprint(BookSource source) =>
      _delegate.contentRulesFingerprint(source);

  @override
  String chapterContentRevision(
    BookSource source,
    OnlineChapter chapter, {
    OnlineChapter? nextChapter,
    String? nextChapterUrl,
  }) => _delegate.chapterContentRevision(
    source,
    chapter,
    nextChapter: nextChapter,
    nextChapterUrl: nextChapterUrl,
  );

  @override
  Future<OnlineEpubImage?> downloadCover(BookSource source, OnlineBook book) =>
      _delegate.downloadCover(source, book);

  @override
  Future<Uint8List?> loadCover(
    BookSource source,
    String url, {
    String referer = '',
  }) => _delegate.loadCover(source, url, referer: referer);

  @override
  BookSourceCookieStore get cookieStore => _delegate.cookieStore;

  @override
  BookSourceHttpClient get http => _delegate.http;

  @override
  void dispose() => _delegate.dispose();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('夹具未配置书源服务入口：${invocation.memberName}');
}
