import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/book_source/book_source_models.dart';
import 'package:reader_mobile/book_source/online_reading_catalog_store.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/db.dart';

const _source = BookSource(
  id: 'catalog-source',
  name: '目录来源',
  sourceUrl: 'https://example.test',
  searchUrl: '/search',
  search: BookListRule(bookList: r'$.books'),
  bookInfo: BookInfoRule(tocUrl: r'$.toc'),
  toc: TocRule(
    chapterList: r'$.chapters',
    chapterName: r'$.title',
    chapterUrl: r'$.url',
  ),
  content: ContentRule(content: r'$.content'),
);

const _chapters = [
  OnlineChapter(
    index: 0,
    title: '第一章',
    url: 'https://example.test/content',
    volume: '上卷',
    updateTime: '2026-11-19',
    requestOptions: {
      'method': 'POST',
      'body': {'chapter': 'one'},
      'headers': {'X-Book': '故事'},
    },
  ),
  OnlineChapter(
    index: 1,
    title: '第二章',
    url: 'https://example.test/content',
    volume: '下卷',
    updateTime: '2026-11-20',
    requestOptions: {
      'method': 'POST',
      'body': {'chapter': 'two'},
      'headers': {'X-Book': '故事'},
    },
  ),
];

OnlineBook _book([String id = 'one', BookSource source = _source]) =>
    OnlineBook(
      sourceId: source.id,
      sourceName: source.name,
      name: '故事$id',
      author: '作者',
      bookUrl: 'https://example.test/book/$id',
      tocUrl: 'https://example.test/toc/$id',
      coverUrl: 'https://example.test/cover/$id',
      intro: '保留简介与目录，供离线续读。',
      kind: '小说',
      status: '连载',
      wordCount: '12万字',
      chapterCount: 2,
      updateTime: '2026-11-20',
      lastChapter: '第二章',
      bookOptions: {
        'method': 'POST',
        'body': {'book': id},
        'headers': {'X-Detail': 'yes'},
      },
      tocOptions: {
        'method': 'POST',
        'body': 'book=$id',
        'headers': {'X-Catalog': 'yes'},
      },
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('旧缓存从明确卷名时间规则恢复分卷，普通更新时间不误识别', () async {
    final library = LibraryStore.memory();
    final store = OnlineReadingCatalogStore(library);
    final source = _source.copyWith(
      toc: const TocRule(
        chapterList: r'$.chapters',
        chapterName: r'$.title',
        chapterUrl: r'$.url',
        updateTime: r'{{$.volume_name}} {{$.first_pass_time}}',
      ),
    );
    final book = _book('one', source);
    await store.save(source, book, [
      const OnlineChapter(
        index: 0,
        title: '第一章',
        url: 'https://example.test/1',
        updateTime: '第一卷：我听到了你们 2022年12月4日 17:03:22',
      ),
    ]);
    expect(
      (await store.read(source, book))!.chapters.single.volume,
      '第一卷：我听到了你们',
    );
    await store.save(_source, _book(), [
      const OnlineChapter(
        index: 0,
        title: '第一章',
        url: 'https://example.test/1',
        updateTime: '普通文本 2022年12月4日 17:03:22',
      ),
    ]);
    expect((await store.read(_source, _book()))!.chapters.single.volume, '');
  });

  test('详情与目录持久化到现有设置，保留同地址不同请求的章节', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final library = LibraryStore(database: db);
    final book = _book();
    await OnlineReadingCatalogStore(library).save(_source, book, _chapters);

    final catalog = await OnlineReadingCatalogStore(library)
        .read(_source, book);
    expect(catalog, isNotNull);
    final stored = catalog!.book;
    expect(stored.sourceId, book.sourceId);
    expect(stored.sourceName, book.sourceName);
    expect(stored.name, book.name);
    expect(stored.author, book.author);
    expect(stored.bookUrl, book.bookUrl);
    expect(stored.tocUrl, book.tocUrl);
    expect(stored.coverUrl, book.coverUrl);
    expect(stored.intro, book.intro);
    expect(stored.kind, book.kind);
    expect(stored.status, book.status);
    expect(stored.wordCount, book.wordCount);
    expect(stored.chapterCount, book.chapterCount);
    expect(stored.updateTime, book.updateTime);
    expect(stored.lastChapter, book.lastChapter);
    expect(stored.bookOptions, book.bookOptions);
    expect(stored.tocOptions, book.tocOptions);
    expect(catalog.lastReadAt, isNull);
    expect(catalog.chapters, hasLength(2));
    for (final (index, chapter) in catalog.chapters.indexed) {
      expect(chapter.index, _chapters[index].index);
      expect(chapter.title, _chapters[index].title);
      expect(chapter.url, _chapters[index].url);
      expect(chapter.volume, _chapters[index].volume);
      expect(chapter.updateTime, _chapters[index].updateTime);
      expect(chapter.requestOptions, _chapters[index].requestOptions);
    }
    expect(() => catalog.chapters.clear(), throwsUnsupportedError);
    expect(await library.list(), isEmpty);
    expect(await OnlineReadingCatalogStore(library).recent([_source]), isEmpty);
  });

  test('书籍缓存按来源和详情地址隔离', () async {
    final store = OnlineReadingCatalogStore(LibraryStore.memory());
    final otherSource = _source.copyWith(id: 'other-source', name: '另一个来源');
    final first = _book();
    final second = _book('two');
    final sameUrl = _book('one', otherSource).copyWith(name: '另一份故事');
    await store.save(_source, first, _chapters);
    await store.save(_source, second, _chapters);
    await store.save(otherSource, sameUrl, _chapters);

    expect((await store.read(_source, first))?.book.name, first.name);
    expect((await store.read(_source, second))?.book.name, second.name);
    expect((await store.read(otherSource, sameUrl))?.book.name, '另一份故事');
    expect(await store.read(otherSource, first), isNull);
    expect(await store.read(_source, _book('missing')), isNull);
  });

  test('同一详情POST接口的不同书籍参数不借用目录，保存仍覆盖当前缓存', () async {
    final store = OnlineReadingCatalogStore(LibraryStore.memory());
    final first = _book();
    final second = _book('two').copyWith(bookUrl: first.bookUrl);
    await store.save(_source, first, _chapters);
    expect(await store.read(_source, second), isNull);

    final equivalent = first.copyWith(
      bookOptions: {
        'headers': {'X-Detail': 'yes'},
        'body': {'book': 'one'},
        'method': 'POST',
      },
    );
    expect((await store.read(_source, equivalent))?.book.name, first.name);

    await store.save(_source, second, _chapters);
    expect(await store.read(_source, first), isNull);
    expect((await store.read(_source, second))?.book.name, second.name);
  });

  test('最近登记不同详情请求时创建传入快照，不保留另一书的目录', () async {
    final store = OnlineReadingCatalogStore(LibraryStore.memory());
    final first = _book();
    final second = _book('two').copyWith(bookUrl: first.bookUrl);
    const otherChapters = [
      OnlineChapter(
        index: 0,
        title: '另一书第一章',
        url: 'https://example.test/other-content',
        requestOptions: {'method': 'POST', 'body': 'book=two&chapter=one'},
      ),
    ];
    await store.remember(_source, first, _chapters);
    await store.remember(_source, second, otherChapters);

    expect(await store.read(_source, first), isNull);
    final cached = await store.read(_source, second);
    expect(cached?.book.name, second.name);
    expect(cached?.book.bookOptions, second.bookOptions);
    expect(cached?.chapters, hasLength(1));
    expect(cached?.chapters.single.title, '另一书第一章');
    final recent = await store.recent([_source]);
    expect(recent, hasLength(1));
    expect(recent.single.book.name, second.name);
    expect(recent.single.chapters.single.title, '另一书第一章');
  });

  test('详情目录与共享请求规则变更失效，显示和加载开关保留目录', () async {
    final store = OnlineReadingCatalogStore(LibraryStore.memory());
    final book = _book();
    await store.save(_source, book, _chapters);
    for (final changed in [
      _source.copyWith(bookInfo: const BookInfoRule(init: r'$.detail')),
      _source.copyWith(toc: const TocRule(chapterList: r'$.newChapters')),
      _source.copyWith(sourceUrl: 'https://another.test'),
      _source.copyWith(header: '{"X-Reader":"changed"}'),
      _source.copyWith(jsLib: 'const version = 2;'),
      _source.copyWith(enabledCookieJar: false),
    ]) {
      expect(await store.read(changed, book), isNull);
    }
    for (final compatible in [
      _source.copyWith(enabled: false),
      _source.copyWith(loadMode: BookSourceLoadMode.book),
      _source.copyWith(content: const ContentRule(content: r'$.newContent')),
      _source.copyWith(search: const BookListRule(bookList: r'$.results')),
      _source.copyWith(name: '来源新名称', group: '新分组', comment: '新备注'),
    ]) {
      expect(await store.read(compatible, book), isNotNull);
    }
    final renamed = _source.copyWith(name: '来源新名称');
    expect((await store.read(renamed, book))?.book.sourceName, '来源新名称');
  });

  test('目录规则变更保留最近书籍信息，过期目录不能作为阅读缓存', () async {
    final store = OnlineReadingCatalogStore(LibraryStore.memory());
    final book = _book();
    await store.remember(_source, book, _chapters);
    final changed = _source.copyWith(
      toc: const TocRule(chapterList: r'$.newCatalog'),
    );

    expect(await store.read(changed, book), isNull);
    final recent = await store.recent([changed]);
    expect(recent, hasLength(1));
    expect(recent.single.book.bookOptions, book.bookOptions);
    expect(recent.single.isStale, isTrue);
    await store.save(changed, book, _chapters);
    expect((await store.recent([changed])).single.isStale, isFalse);
  });

  test('无效身份和目录不覆盖有效缓存，重复请求不登记最近阅读', () async {
    final store = OnlineReadingCatalogStore(LibraryStore.memory());
    final book = _book();
    await store.save(_source, book, _chapters);
    await store.remember(
      _source,
      book.copyWith(sourceId: 'wrong-source'),
      _chapters,
    );
    for (final chapters in <List<OnlineChapter>>[
      [],
      [const OnlineChapter(index: 1, title: '序号错位', url: '/chapter')],
      [const OnlineChapter(index: 0, title: '', url: '/chapter')],
      [const OnlineChapter(index: 0, title: '无地址', url: '')],
      [
        _chapters.first,
        const OnlineChapter(
          index: 1,
          title: '同一请求',
          url: 'https://example.test/content#fragment',
          requestOptions: {
            'headers': {'X-Book': '故事'},
            'body': {'chapter': 'one'},
            'method': 'POST',
          },
        ),
      ],
    ]) {
      await store.remember(_source, book, chapters);
    }
    expect(await store.recent([_source]), isEmpty);
    expect((await store.read(_source, book))?.chapters, hasLength(2));
  });

  test('更新快照保留阅读时间，规则更新成功后原最近入口仍可使用', () async {
    final library = LibraryStore.memory();
    final when = DateTime.utc(2026, 11, 20, 8);
    final store = OnlineReadingCatalogStore(library, now: () => when);
    final book = _book();
    await store.remember(_source, book, _chapters);
    final updated = book.copyWith(intro: '更新后的简介');
    final changed = _source.copyWith(
      toc: const TocRule(chapterList: r'$.updatedCatalog'),
    );
    await store.save(changed, updated, _chapters);

    final catalog = await store.read(changed, book);
    expect(catalog?.lastReadAt, when);
    expect(catalog?.book.intro, '更新后的简介');
    expect(await store.read(_source, book), isNull);
    final recent = await store.recent([changed]);
    expect(recent, hasLength(1));
    expect(recent.single.lastReadAt, when);
    expect(recent.single.book.intro, '更新后的简介');
  });

  test('首次登记创建目录，后台保存新目录后旧阅读快照不回退最近入口', () async {
    var when = DateTime.utc(2026, 11, 20, 8);
    final library = LibraryStore.memory();
    final store = OnlineReadingCatalogStore(library, now: () => when);
    final book = _book();
    await store.remember(_source, book, _chapters);
    final first = await store.read(_source, book);
    expect(first?.book.intro, book.intro);
    expect(first?.chapters, hasLength(2));
    expect(first?.lastReadAt, when);

    final updated = book.copyWith(
      intro: '后台刷新的新简介',
      chapterCount: 3,
      lastChapter: '第三章',
    );
    final chapters = [
      ..._chapters,
      const OnlineChapter(
        index: 2,
        title: '第三章',
        url: 'https://example.test/content/three',
      ),
    ];
    await store.save(_source, updated, chapters);
    when = when.add(const Duration(minutes: 1));
    await store.remember(_source, book, _chapters);
    final cached = await store.read(_source, book);
    expect(cached?.book.intro, updated.intro);
    expect(cached?.book.chapterCount, 3);
    expect(cached?.chapters.last.title, '第三章');
    expect(cached?.lastReadAt, when);
    final recent = await store.recent([_source]);
    expect(recent.single.book.intro, updated.intro);
    expect(recent.single.chapters, hasLength(3));
    expect(recent.single.lastReadAt, when);
  });

  test('已有目录因规则失效时登记使用传入的新快照', () async {
    final store = OnlineReadingCatalogStore(LibraryStore.memory());
    final book = _book();
    await store.remember(_source, book, _chapters);
    final changed = _source.copyWith(
      toc: const TocRule(chapterList: r'$.newCatalog'),
    );
    final updated = book.copyWith(intro: '新规则解析的简介', chapterCount: 1);
    await store.remember(changed, updated, [_chapters.first]);

    expect(await store.read(_source, book), isNull);
    final cached = await store.read(changed, book);
    expect(cached?.book.intro, updated.intro);
    expect(cached?.chapters, hasLength(1));
    expect((await store.recent([changed])).single.chapters, hasLength(1));
  });

  test('旧阅读会话登记最近时间时不把新规则目录覆盖回旧快照', () async {
    var when = DateTime.utc(2026, 11, 20, 8);
    final store = OnlineReadingCatalogStore(
      LibraryStore.memory(),
      now: () => when,
    );
    final book = _book();
    await store.remember(_source, book, _chapters);
    final changed = _source.copyWith(
      toc: const TocRule(chapterList: r'$.newCatalog'),
    );
    final updated = book.copyWith(intro: '新规则简介', chapterCount: 1);
    await store.save(changed, updated, [_chapters.first]);
    when = when.add(const Duration(minutes: 1));
    await store.remember(_source, book, _chapters, preserveSavedCatalog: true);

    expect(await store.read(_source, book), isNull);
    final catalog = await store.read(changed, book);
    expect(catalog?.book.intro, '新规则简介');
    expect(catalog?.chapters, hasLength(1));
    expect(catalog?.lastReadAt, when);
    final recent = await store.recent([changed]);
    expect(recent.single.isStale, isFalse);
    expect(recent.single.lastReadAt, when);
  });

  test('最近阅读最多记录二十本，再次阅读提升顺序且保存目录不增加记录', () async {
    var seconds = 0;
    final start = DateTime.utc(2026, 11, 20);
    final library = _ProbeLibrary();
    final store = OnlineReadingCatalogStore(
      library,
      now: () => start.add(Duration(seconds: seconds++)),
    );
    for (var index = 0; index < 25; index++) {
      await store.remember(_source, _book('$index'), _chapters);
    }
    var recent = await store.recent([_source]);
    expect(recent, hasLength(20));
    expect(recent.first.book.name, '故事24');
    expect(recent.last.book.name, '故事5');
    expect(await store.read(_source, _book('0')), isNotNull);
    final recorded = jsonDecode(library.values[library.recentKey]!) as Map;
    expect(recorded['books'], hasLength(20));

    await store.remember(_source, _book('10'), _chapters);
    await store.save(_source, _book('never-read'), _chapters);
    recent = await OnlineReadingCatalogStore(library).recent([_source]);
    expect(recent, hasLength(20));
    expect(recent.first.book.name, '故事10');
    expect(recent.where((item) => item.book.name == '故事10'), hasLength(1));
    expect(recent.any((item) => item.book.name == '故事never-read'), isFalse);
  });

  test('相同阅读时间仍保留最后登记顺序', () async {
    final store = OnlineReadingCatalogStore(
      LibraryStore.memory(),
      now: () => DateTime.utc(2026, 11, 20),
    );
    for (final id in ['one', 'two', 'three', 'one']) {
      await store.remember(_source, _book(id), _chapters);
    }
    expect((await store.recent([_source])).map((item) => item.book.name), [
      '故事one',
      '故事three',
      '故事two',
    ]);
  });

  test('不同存储实例并发登记时不丢最近记录，读取等待已提交的更新', () async {
    final library = _ProbeLibrary(yieldOperations: true);
    var ticks = 0;
    DateTime now() =>
        DateTime.utc(2026, 11, 20).add(Duration(milliseconds: ticks++));
    final stores = [
      OnlineReadingCatalogStore(library, now: now),
      OnlineReadingCatalogStore(library, now: now),
    ];
    final writes = [
      for (var index = 0; index < 12; index++)
        stores[index % 2].remember(_source, _book('$index'), _chapters),
    ];
    final read = OnlineReadingCatalogStore(library).recent([_source]);
    await Future.wait(writes);
    final recent = await read;
    expect(recent, hasLength(12));
    expect(recent.map((item) => item.book.bookUrl).toSet(), hasLength(12));
    expect(recent.first.book.name, '故事11');
    expect(recent.last.book.name, '故事0');
  });

  test('停用或移除来源隐藏入口，切回逐章后保留原缓存和记录', () async {
    final store = OnlineReadingCatalogStore(LibraryStore.memory());
    final book = _book();
    await store.remember(_source, book, _chapters);
    expect(await store.recent([]), isEmpty);
    expect(await store.recent([_source.copyWith(enabled: false)]), isEmpty);
    expect(
      await store.recent([_source.copyWith(loadMode: BookSourceLoadMode.book)]),
      isEmpty,
    );
    expect(await store.read(_source.copyWith(enabled: false), book), isNotNull);
    expect(await store.recent([_source]), hasLength(1));
  });

  test('损坏的目录与单条最近记录被忽略，其他入口继续可用', () async {
    final library = _ProbeLibrary();
    final store = OnlineReadingCatalogStore(library);
    final first = _book();
    final second = _book('two');
    await store.remember(_source, first, _chapters);
    await store.remember(_source, second, _chapters);
    final key = library.catalogKey(first.bookUrl);
    final json = jsonDecode(library.values[key]!) as Map<String, dynamic>;
    (json['book'] as Map)['sourceId'] = 'wrong-source';
    library.values[key] = jsonEncode(json);
    expect(await store.read(_source, first), isNull);
    expect((await store.recent([_source])).single.book.name, second.name);

    final recent = jsonDecode(library.values[library.recentKey]!) as Map;
    (recent['books'] as List).insert(0, {
      'sourceId': <Object?>[],
      'lastReadAt': false,
    });
    library.values[library.recentKey] = jsonEncode(recent);
    expect((await store.recent([_source])).single.book.name, second.name);
    library.values[library.recentKey] = '{损坏';
    library.values[key] = '{损坏';
    expect(await store.recent([_source]), isEmpty);
    expect(await store.read(_source, first), isNull);
    await store.remember(_source, first, _chapters);
    expect((await store.recent([_source])).single.book.name, first.name);
  });

  test('设置读写失败不阻止阅读，也不以空索引覆盖旧记录或阻塞后续保存', () async {
    final library = _ProbeLibrary();
    final store = OnlineReadingCatalogStore(library);
    final first = _book();
    final second = _book('two');
    await store.remember(_source, first, _chapters);
    library.failReads = true;
    expect(await store.read(_source, first), isNull);
    expect(await store.recent([_source]), isEmpty);
    await expectLater(store.remember(_source, second, _chapters), completes);
    library.failReads = false;
    expect((await store.recent([_source])).single.book.name, first.name);

    library.failWrites = true;
    await expectLater(store.save(_source, second, _chapters), completes);
    await expectLater(store.remember(_source, second, _chapters), completes);
    await expectLater(store.remove(_source, first), completes);
    library.failWrites = false;
    expect(await store.read(_source, second), isNull);
    expect((await store.recent([_source])).single.book.name, first.name);
    await store.remember(_source, second, _chapters);
    expect(await store.recent([_source]), hasLength(2));
  });

  test('移除只影响指定来源的书籍与最近入口', () async {
    final store = OnlineReadingCatalogStore(LibraryStore.memory());
    final otherSource = _source.copyWith(id: 'other-source');
    final first = _book();
    final second = _book('two');
    final sameUrl = _book('one', otherSource);
    await store.remember(_source, first, _chapters);
    await store.remember(_source, second, _chapters);
    await store.remember(otherSource, sameUrl, _chapters);
    await store.remove(_source, first);
    expect(await store.read(_source, first), isNull);
    expect(await store.read(_source, second), isNotNull);
    expect(await store.read(otherSource, sameUrl), isNotNull);
    expect(await store.recent([_source, otherSource]), hasLength(2));
  });
}

/// 可注入损坏、异步交错和失败的设置存储，不触碰应用私有目录。
class _ProbeLibrary extends LibraryStore {
  _ProbeLibrary({this.yieldOperations = false}) : super.memory();

  final bool yieldOperations;
  final values = <String, String>{};
  bool failReads = false;
  bool failWrites = false;

  String get recentKey => values.keys.singleWhere(
    (key) => key.startsWith('online_reading_recent:'),
  );

  String catalogKey(String bookUrl) => values.entries.firstWhere((entry) {
    if (!entry.key.startsWith('online_reading_catalog:')) return false;
    final json = jsonDecode(entry.value) as Map;
    return json['bookUrl'] == bookUrl;
  }).key;

  @override
  Future<String?> getSetting(String key) async {
    if (failReads) throw StateError('模拟设置读取失败');
    final value = values[key];
    if (yieldOperations) await Future<void>.delayed(Duration.zero);
    return value;
  }

  @override
  Future<void> setSetting(String key, String value) async {
    if (failWrites) throw StateError('模拟设置写入失败');
    if (yieldOperations) await Future<void>.delayed(Duration.zero);
    values[key] = value;
  }
}
