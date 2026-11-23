import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:reader_ui/reader_session.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/position/location_anchor.dart';
import 'package:reader_core/position/revision_relocator.dart';

import '../diagnostics/reader_log.dart';
import '../library/library_store.dart';
import 'book_source_auth.dart';
import 'book_source_cookie_store.dart';
import 'book_source_models.dart';
import 'book_source_service.dart';
import 'book_source_store.dart';
import 'online_chapter_request.dart';
import 'online_epub_update.dart';
import 'online_epub_metadata.dart';
import 'online_epub_builder.dart';
import 'online_download_notification.dart';
import 'online_reading_book.dart';
import 'online_reading_catalog_store.dart';

const _cancelledDownload = BookSourceException(
  '已取消下载',
  code: 'ONLINE_CANCELLED',
);

/// 缓存先显示，快速刷新完成后使用新目录，慢请求继续在后台更新快照。
class OnlineCatalogLoad {
  const OnlineCatalogLoad({
    required this.source,
    required this.cached,
    required this.refresh,
    this.info,
  });

  final BookSource source;
  final Future<OnlineReadingCatalog?> cached;
  final Future<OnlineReadingCatalog> refresh;
  final Future<OnlineBook>? info;

  /// 有效缓存最多等待 200 毫秒，不把站点超时带入续读。
  Future<OnlineReadingCatalog> forReading() async {
    final fallback = await cached;
    if (fallback == null) return refresh;
    try {
      return await refresh.timeout(const Duration(milliseconds: 200));
    } on Object {
      return fallback;
    }
  }
}

/// 书架身份已确定，目录请求交给阅读页的加载状态继续等待。
class ImportedOnlineReading {
  const ImportedOnlineReading(this.book);

  final Future<OnlineReadingBook> book;
}

/// 在线书源状态与下载入库入口。
class OnlineBookController extends ChangeNotifier {
  OnlineBookController({
    required this.library,
    BookSourceStore? store,
    BookSourceService? service,
    BookSourceCookieStore? cookieStore,
    BookSourceAuthService? authService,
    OnlineReadingCatalogStore? readingCatalogStore,
  }) : _store = store ?? BookSourceStore(),
       cookieStore = cookieStore ?? BookSourceCookieStore(),
       catalogs = readingCatalogStore ?? OnlineReadingCatalogStore(library),
       auth = authService ?? BookSourceAuthService() {
    this.service = service ?? BookSourceService(cookieStore: this.cookieStore);
    library.addListener(_libraryChanged);
  }

  final LibraryStore library;
  final BookSourceStore _store;
  final BookSourceCookieStore cookieStore;
  final BookSourceAuthService auth;
  final OnlineReadingCatalogStore catalogs;
  late final BookSourceService service;
  List<BookSource> _sources = const <BookSource>[];
  Map<String, OnlineBookLink> _links = const <String, OnlineBookLink>{};
  Set<String> _loggedInSourceIds = <String>{};
  bool _initialized = false;
  bool _loading = false;
  String? _error;
  int _lastSkippedChapters = 0;
  int _lastAddedChapters = 0;
  bool _lastUpdateWasCatalogOnly = false;
  List<String> _lastSkippedReasons = const <String>[];
  final Map<String, Future<OnlineReadingCatalog>> _catalogRefreshes = {};
  final Map<String, Completer<OnlineBook>> _catalogDetails = {};
  final Map<
    String,
    ({String path, String? revision, OnlineEpubMetadata? metadata})
  >
  _importedMetadata = {};
  final Map<String, Future<OnlineEpubMetadata?>> _metadataReads = {};
  Future<void>? _initializing;
  Future<void>? _registration;
  Future<void> _configurationWork = Future.value();
  bool _disposed = false;
  String? selectedDiscoverSourceId;

  /// 成功导入含发现能力的书源后递增，首页据此显示一次启用提示。
  int discoveryImportRevision = 0;
  Map<String, BookEntry> _shelfEntries = {};

  /// 已加入书架按来源与完整详情请求判断，不按标题猜测。
  BookEntry? shelfEntryFor(BookSource source, OnlineBook book) {
    for (final entry in _shelfEntries.values) {
      final link = _links[entry.id];
      if (link == null || link.sourceId != source.id) continue;
      final linked = link.bookFor(source);
      if (onlineRequestIdentity(linked.bookUrl, linked.bookOptions) ==
          onlineRequestIdentity(book.bookUrl, book.bookOptions)) {
        return entry;
      }
    }
    return null;
  }

  Future<void> selectDiscoverSource(String id) async {
    selectedDiscoverSourceId = id;
    await library.setSetting('discover.sourceId', id);
  }

  List<BookSource> get sources => List<BookSource>.unmodifiable(_sources);
  Map<String, OnlineBookLink> get links =>
      Map<String, OnlineBookLink>.unmodifiable(_links);
  bool get initialized => _initialized;
  bool get loading => _loading;
  String? get error => _error;
  int get lastSkippedChapters => _lastSkippedChapters;
  int get lastAddedChapters => _lastAddedChapters;
  bool get lastUpdateWasCatalogOnly => _lastUpdateWasCatalogOnly;
  List<String> get lastSkippedReasons =>
      List<String>.unmodifiable(_lastSkippedReasons);
  int get enabledCount => _sources.where((source) => source.enabled).length;
  int get searchableCount =>
      _sources.where((source) => source.canSearch).length;
  int get lastImportedCount => _store.lastImportedCount;
  bool isLoggedIn(BookSource source) => _loggedInSourceIds.contains(source.id);

  /// 初次读取本地书源与书籍关联。
  Future<void> initialize({bool refresh = false}) {
    if (_disposed) return Future.value();
    final pending = _initializing;
    if (pending != null) {
      return refresh ? pending.then((_) => initialize(refresh: true)) : pending;
    }
    if (_initialized && !refresh) return Future.value();
    final task = _initialize(refresh: refresh);
    _initializing = task;
    task.whenComplete(() {
      if (identical(_initializing, task)) _initializing = null;
    }).ignore();
    return task;
  }

  Future<void> _initialize({required bool refresh}) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await cookieStore.load();
      await _withConfiguration(() async {
        final loaded = await Future.wait<Object>(<Future<Object>>[
          _store.load(refresh: refresh),
          _store.loadLinks(),
        ]);
        _sources = loaded[0] as List<BookSource>;
        _links = loaded[1] as Map<String, OnlineBookLink>;
      });
      final loggedIn = <String>{};
      for (final source in _sources) {
        if (await cookieStore.hasLoginFor(source)) loggedIn.add(source.id);
      }
      _loggedInSourceIds = loggedIn;
      selectedDiscoverSourceId = await library.getSetting('discover.sourceId');
      _initialized = true;
      await registerImportedBooks();
    } on Object catch (error) {
      _error = '$error';
    } finally {
      _loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// 从剪贴板导入 JSON 书源。
  Future<BookSource?> importFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      throw const BookSourceException('剪贴板中没有文本');
    }
    return importText(text);
  }

  /// 从 JSON 文本导入。
  Future<BookSource> importText(String text) async {
    return _import(() => _store.importText(text));
  }

  /// 从文件导入。
  Future<BookSource> importFile(String path) async {
    return _import(() => _store.importFile(path));
  }

  /// 从网络地址导入。
  Future<BookSource> importUrl(String url) async {
    return _import(() => _store.importUrl(url));
  }

  /// 启用或停用来源。
  Future<void> setSourceEnabled(String id, bool enabled) async {
    await _withConfiguration(() => _store.setEnabled(id, enabled));
    await initialize(refresh: true);
  }

  Future<void> setSourceLoadMode(String id, BookSourceLoadMode mode) async {
    await _withConfiguration(() => _store.setLoadMode(id, mode));
    await initialize(refresh: true);
  }

  /// 删除来源。
  Future<void> removeSource(String id) async {
    for (final source in _sources) {
      if (source.id == id) {
        await auth.logout(source, cookieStore);
        break;
      }
    }
    await _withConfiguration(() => _store.remove(id));
    await initialize(refresh: true);
  }

  /// 打开书源网页登录并保存 Cookie。
  Future<BookSourceLoginResult> login(
    BookSource source, {
    Map<String, String>? credentials,
  }) async {
    final result = credentials == null
        ? await auth.login(source, cookieStore)
        : await auth.loginWithCredentials(source, cookieStore, credentials);
    if (result.success) {
      service.invalidateSourceSettings();
      _loggedInSourceIds = <String>{..._loggedInSourceIds, source.id};
      notifyListeners();
    }
    return result;
  }

  Future<BookSourceLoginResult> runLoginAction(
    BookSource source,
    Map<String, String> values,
    String action,
  ) async {
    final result = await auth.runAction(source, cookieStore, values, action);
    if (result.success) {
      service.invalidateSourceSettings();
      _loggedInSourceIds = {..._loggedInSourceIds, source.id};
      notifyListeners();
    }
    return result;
  }

  /// 清除书源登录 Cookie。
  Future<void> logout(BookSource source) async {
    await auth.logout(source, cookieStore);
    _loggedInSourceIds = <String>{..._loggedInSourceIds}..remove(source.id);
    notifyListeners();
  }

  /// 多来源并发搜索。
  Future<List<OnlineSourceSearchResult>> search(String query) async {
    await initialize();
    return service.searchMany(_sources, query);
  }

  /// 详情、最近阅读和选章共享同一刷新，过期缓存只保留最近入口。
  OnlineCatalogLoad loadCatalog(BookSource source, OnlineBook book) {
    final cached = catalogs.read(source, book);
    final info = Completer<OnlineBook>();
    info.future.ignore();
    final refresh = cached.then(
      (catalog) => refreshCatalog(
        source,
        catalog?.book ?? book,
        onInfo: (value) {
          if (!info.isCompleted) info.complete(value);
        },
      ),
    );
    refresh.then<void>(
      (value) {
        if (!info.isCompleted) info.complete(value.book);
      },
      onError: (Object error, StackTrace stack) {
        if (!info.isCompleted) info.completeError(error, stack);
      },
    );
    // 页面关闭后刷新仍可落盘，异常由仍在显示的页面或缓存回退处理。
    refresh.ignore();
    return OnlineCatalogLoad(
      source: source,
      cached: cached,
      refresh: refresh,
      info: info.future,
    );
  }

  /// 只合并完整请求和目录规则相同的网络任务。
  Future<OnlineReadingCatalog> refreshCatalog(
    BookSource source,
    OnlineBook book, {
    ValueChanged<OnlineBook>? onInfo,
  }) {
    final key = catalogs.requestIdentity(source, book);
    final pending = _catalogRefreshes[key];
    if (pending != null) {
      if (onInfo != null) _catalogDetails[key]?.future.then(onInfo).ignore();
      return pending;
    }
    final detail = _catalogDetails[key] = Completer<OnlineBook>();
    detail.future.ignore();
    if (onInfo != null) detail.future.then(onInfo).ignore();
    final task = _refreshCatalog(source, book, detail: detail);
    _catalogRefreshes[key] = task;
    void finished() {
      if (identical(_catalogRefreshes[key], task)) {
        _catalogRefreshes.remove(key);
        _catalogDetails.remove(key);
        if (!detail.isCompleted) {
          detail.completeError(const BookSourceException('详情加载失败'));
        }
      }
    }

    task.then<void>(
      (_) => finished(),
      onError: (Object error, StackTrace stack) => finished(),
    );
    return task;
  }

  Future<OnlineReadingCatalog> _refreshCatalog(
    BookSource source,
    OnlineBook book, {
    required Completer<OnlineBook> detail,
  }) async {
    final info = await service.loadBookInfo(source, book);
    bool isCurrent() => !_disposed && _matchesCurrentSource(source, book);
    if (!isCurrent()) throw const BookSourceException('来源已更新，请重新获取目录');
    detail.complete(info);
    final entry = shelfEntryFor(source, info);
    if (entry != null) {
      final updated = await library.fillBookDescription(entry.id, info.intro);
      if (updated != null) _shelfEntries[entry.id] = updated;
    }
    final chapters = await service.fetchToc(source, info);
    if (!isCurrent()) {
      throw const BookSourceException('来源已更新，请重新获取目录');
    }
    await catalogs.save(source, info, chapters, isCurrent: isCurrent);
    if (!isCurrent()) {
      throw const BookSourceException('来源已更新，请重新获取目录');
    }
    notifyListeners();
    return OnlineReadingCatalog(book: info, chapters: chapters);
  }

  bool _matchesCurrentSource(BookSource source, OnlineBook book) {
    if (!_initialized) return true;
    for (final current in _sources) {
      if (current.id == source.id) {
        return catalogs.requestIdentity(current, book) ==
            catalogs.requestIdentity(source, book);
      }
    }
    return false;
  }

  /// 按书架条目查找关联来源。
  BookSource? sourceForBook(String bookId) {
    final metadata = _importedMetadata[bookId]?.metadata;
    if (metadata != null) return metadata.sourceIn(_sources);
    final link = _links[bookId];
    if (link == null) return null;
    return OnlineEpubMetadata.findSource(link.sourceId, _sources);
  }

  /// 同步和本地导入共用书库通知，已有文件只按内容版本读一次源元数据。
  void _libraryChanged() {
    if (!_initialized || _loading || _disposed) return;
    registerImportedBooks().catchError((Object error, StackTrace stack) {
      recordAppError('online_import_link_failed', error, stackTrace: stack);
    }).ignore();
  }

  Future<void> registerImportedBooks() {
    if (_disposed) return Future.value();
    final pending = _registration;
    if (pending != null) return pending;
    final task = _registerImportedBooks();
    _registration = task;
    task.whenComplete(() {
      if (identical(_registration, task)) _registration = null;
    }).ignore();
    return task;
  }

  Future<void> _registerImportedBooks() async {
    if (_sources.isEmpty) return;
    final entries = await library.list();
    _shelfEntries = {for (final entry in entries) entry.id: entry};
    for (final entry in entries) {
      if (_disposed) return;
      try {
        await _linkImportedBook(entry);
      } on Object catch (error, stack) {
        recordAppError('online_import_link_failed', error, stackTrace: stack);
      }
    }
    if (!_loading && !_disposed) notifyListeners();
  }

  Future<OnlineEpubMetadata?> _metadataFor(BookEntry entry) {
    final cached = _importedMetadata[entry.id];
    if (cached != null &&
        cached.path == entry.filePath &&
        cached.revision == entry.contentRevision) {
      return Future.value(cached.metadata);
    }
    final key = '${entry.id}:${entry.contentRevision}:${entry.filePath}';
    final pending = _metadataReads[key];
    if (pending != null) return pending;
    final task = OnlineEpubMetadata.read(library, entry).then((metadata) {
      if (!_disposed) {
        _importedMetadata[entry.id] = (
          path: entry.filePath,
          revision: entry.contentRevision,
          metadata: metadata,
        );
      }
      return metadata;
    });
    _metadataReads[key] = task;
    task.whenComplete(() {
      if (identical(_metadataReads[key], task)) _metadataReads.remove(key);
    }).ignore();
    return task;
  }

  Future<bool> _linkImportedBook(
    BookEntry entry, {
    OnlineEpubMetadata? metadata,
  }) async {
    metadata ??= await _metadataFor(entry);
    if (metadata == null || _disposed) return false;
    final indexed = metadata;
    final source = metadata.sourceIn(_sources);
    if (source == null) return false;
    if (_linkMatchesMetadata(_links[entry.id], source, metadata, entry)) {
      return false;
    }
    return _withConfiguration(() async {
      if (_disposed) return false;
      final currentEntry = await library.bookById(entry.id);
      if (currentEntry == null ||
          currentEntry.filePath != entry.filePath ||
          currentEntry.contentRevision != entry.contentRevision) {
        return false;
      }
      final currentSource = indexed.sourceIn(await _store.load());
      if (currentSource == null) return false;
      final currentLinks = await _store.loadLinks();
      if (_linkMatchesMetadata(
        currentLinks[entry.id],
        currentSource,
        indexed,
        entry,
      )) {
        _links = currentLinks;
        return false;
      }
      await _store.saveLink(entry.id, indexed.linkFor(currentSource, entry));
      _links = await _store.loadLinks();
      return true;
    });
  }

  /// 同步替换后的显式源和详情请求优先，原生离线书的关联不受影响。
  bool _linkMatchesMetadata(
    OnlineBookLink? link,
    BookSource source,
    OnlineEpubMetadata metadata,
    BookEntry entry,
  ) {
    if (link == null || link.sourceId != source.id) return false;
    final current = link.bookFor(source);
    final indexed = metadata.linkFor(source, entry).bookFor(source);
    return onlineRequestIdentity(current.bookUrl, current.bookOptions) ==
        onlineRequestIdentity(indexed.bookUrl, indexed.bookOptions);
  }

  /// 完整离线 EPUB 使用原阅读页；在线占位书打开时自动更新目录并按章加载。
  Future<ImportedOnlineReading?> prepareImportedReading(
    BookEntry entry,
    ReaderProgressStore progressStore,
  ) async {
    await initialize();
    await _registration;
    final OnlineEpubMetadata? metadata;
    try {
      metadata = await _metadataFor(entry);
    } on Object {
      // 本地归档无法读取时由原阅读页展示文件错误，不阻断常规打开路径。
      return null;
    }
    if (metadata == null) return null;
    if (await _linkImportedBook(entry, metadata: metadata) && !_disposed) {
      notifyListeners();
    }
    if (!metadata.requiresOnlineReading) return null;
    final source = metadata.sourceIn(_sources);
    final link = _links[entry.id];
    if (source == null ||
        !_linkMatchesMetadata(link, source, metadata, entry)) {
      throw const BookSourceException('未找到在线图书对应的书源，请先导入对应书源');
    }
    if (!source.enabled) {
      throw const BookSourceException('在线图书对应的书源已停用，请在书源管理中启用');
    }
    final task = _loadImportedReading(
      entry,
      metadata,
      source,
      link!.bookFor(source),
      progressStore,
    );
    task.ignore();
    return ImportedOnlineReading(task);
  }

  Future<OnlineReadingBook> _loadImportedReading(
    BookEntry entry,
    OnlineEpubMetadata metadata,
    BookSource source,
    OnlineBook book,
    ReaderProgressStore progressStore,
  ) async {
    final load = loadCatalog(source, book);
    final prior = await progressStore.load(entry.id);
    final chapterIdentity = prior == null
        ? null
        : await metadata.chapterIdentityForSpine(
            library,
            entry,
            prior.spineIndex,
          );
    final catalog = await load.forReading();
    if (entry.coverPath == null && library.supportsPersistence) {
      unawaited(_restoreShelfCover(entry, source, catalog.book));
    }
    final currentEntry = await library.bookById(entry.id);
    if (!_matchesCurrentSource(source, book) ||
        currentEntry == null ||
        currentEntry.contentRevision != entry.contentRevision ||
        currentEntry.filePath != entry.filePath) {
      throw const BookSourceException('来源已更新，请重新打开图书');
    }
    return OnlineReadingBook(
      source: source,
      book: catalog.book,
      chapters: catalog.chapters,
      service: service,
      bookshelfId: entry.id,
      initialChapterIdentity: chapterIdentity,
    );
  }

  /// 默认只保存目录占位书，阅读时获取正文；整本模式才下载全部。
  Future<BookEntry> downloadAndImport(
    BookSource source,
    OnlineBook book, {
    OnlineDownloadProgress? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (source.loadMode == BookSourceLoadMode.chapter) {
      final catalog = await waitOnlineOperation(
        loadCatalog(source, book).forReading(),
        isCancelled,
      );
      if (isCancelled?.call() == true) throw _cancelledDownload;
      return addToShelf(
        source,
        catalog.book,
        catalog.chapters,
        isCancelled: isCancelled,
      );
    }
    _lastSkippedChapters = 0;
    _lastSkippedReasons = const <String>[];
    final result = await _downloadWithNotification(
      source,
      book,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
    if (isCancelled?.call() == true) throw _cancelledDownload;
    onProgress?.call(0, 0, '正在加入书架');
    final entry = await library.importBytes(
      result.bytes,
      fallbackTitle: result.book.name,
      isCancelled: isCancelled,
    );
    await _withConfiguration(() async {
      await _store.saveLink(
        entry.id,
        OnlineBookLink(
          sourceId: source.id,
          bookUrl: result.book.bookUrl,
          name: result.book.name,
          author: result.book.author,
          tocUrl: result.book.tocUrl,
          bookOptions: result.book.bookOptions,
          tocOptions: result.book.tocOptions,
        ),
      );
      _links = await _store.loadLinks();
    });
    _lastSkippedChapters = result.skippedChapters;
    _lastSkippedReasons = List<String>.unmodifiable(result.skippedReasons);
    notifyListeners();
    return entry;
  }

  /// 把现有在线目录加入书架，不请求章节正文，保留试读位置。
  Future<BookEntry> addToShelf(
    BookSource source,
    OnlineBook book,
    List<OnlineChapter> chapters, {
    bool Function()? isCancelled,
  }) async {
    void check() {
      if (isCancelled?.call() == true) throw _cancelledDownload;
    }

    check();
    await initialize();
    await registerImportedBooks();
    check();
    final existing = shelfEntryFor(source, book);
    if (existing != null) {
      final updated =
          await library.fillBookDescription(existing.id, book.intro) ??
          existing;
      _shelfEntries[existing.id] = updated;
      return await _restoreShelfCover(updated, source, book) ?? updated;
    }
    final input = OnlineEpubInput(
      title: book.name,
      author: book.author,
      intro: book.intro,
      sourceName: source.name,
      sourceId: source.id,
      bookUrl: book.bookUrl,
      onDemand: true,
      cover: await waitOnlineOperation(
        service.downloadCover(source, book),
        isCancelled,
      ),
      chapters: [
        for (final chapter in chapters)
          OnlineEpubChapter(
            title: chapter.title,
            html: '<p>章节将在阅读时加载。</p>',
            sourceUrl: chapter.requestOptions.isEmpty
                ? chapter.url
                : '${chapter.url},${jsonEncode(chapter.requestOptions)}',
            volume: chapter.volume,
          ),
      ],
    );
    check();
    final entry = await library.importBytes(
      const OnlineEpubBuilder().build(input),
      fallbackTitle: book.name,
      isCancelled: isCancelled,
    );
    await _withConfiguration(() async {
      await _store.saveLink(
        entry.id,
        OnlineBookLink(
          sourceId: source.id,
          bookUrl: book.bookUrl,
          name: book.name,
          author: book.author,
          tocUrl: book.tocUrl,
          bookOptions: book.bookOptions,
          tocOptions: book.tocOptions,
        ),
      );
      _links = await _store.loadLinks();
    });
    _shelfEntries[entry.id] = entry;
    await catalogs.save(source, book, chapters);
    final trial = OnlineReadingBook(
      source: source,
      book: book,
      chapters: chapters,
      service: service,
    );
    final saved = await library.getSetting(
      'online_reading_progress:${trial.id}',
    );
    if (saved != null && saved.isNotEmpty) {
      final progress = jsonDecode(saved) as Map<String, dynamic>;
      progress['revision'] = OnlineReadingBook(
        source: source,
        book: book,
        chapters: chapters,
        service: service,
        bookshelfId: entry.id,
      ).revision;
      await library.setSetting(
        'online_reading_progress:${entry.id}',
        jsonEncode(progress),
      );
    }
    notifyListeners();
    return entry;
  }

  /// 旧版目录入架缺少封面时补齐，保留书籍文件、身份和阅读位置。
  Future<BookEntry?> _restoreShelfCover(
    BookEntry entry,
    BookSource source,
    OnlineBook book,
  ) async {
    if (entry.coverPath != null || !library.supportsPersistence) return null;
    try {
      final cover = await service.downloadCover(source, book);
      if (cover == null || _disposed) return null;
      final latest = await library.bookById(entry.id);
      if (latest == null || latest.coverPath != null) return latest;
      final updated = await library.replaceCover(
        entry.id,
        cover.bytes,
        extension: cover.path.split('.').last,
      );
      _shelfEntries[entry.id] = updated;
      if (!_disposed) notifyListeners();
      return updated;
    } on Object {
      // 封面失败仍可阅读，下一次打开重试。
      return null;
    }
  }

  /// 获取最新目录，只追加新增正文，复用原章节和阅读数据。
  Future<BookEntry> updateBook(
    BookEntry entry, {
    ReaderProgressStore? progressStore,
    OnlineDownloadProgress? onProgress,
    bool Function()? isCancelled,
  }) async {
    _lastSkippedChapters = 0;
    _lastAddedChapters = 0;
    _lastUpdateWasCatalogOnly = false;
    _lastSkippedReasons = const <String>[];
    await initialize();
    await _registration;
    final metadata = await _metadataFor(entry);
    await _linkImportedBook(entry, metadata: metadata);
    final link = _links[entry.id];
    final source = metadata == null
        ? sourceForBook(entry.id)
        : metadata.sourceIn(_sources);
    if (link == null ||
        source == null ||
        (metadata != null &&
            !_linkMatchesMetadata(link, source, metadata, entry))) {
      throw const BookSourceException('未找到这本书的在线来源');
    }
    final book = link.bookFor(source);
    onProgress?.call(0, 0, '正在获取最新目录');
    if (metadata?.requiresOnlineReading == true) {
      final catalog = await refreshCatalog(source, book);
      if (isCancelled?.call() ?? false) {
        throw const BookSourceException('已取消更新', code: 'ONLINE_CANCELLED');
      }
      final result = await _downloadWithNotification(
        source,
        catalog.book,
        preparedBook: catalog.book,
        selectedChapters: catalog.chapters,
        chapterDirectory: catalog.chapters,
        onProgress: onProgress,
        isCancelled: isCancelled,
      );
      if (result.skippedChapters > 0) {
        throw const BookSourceException('章节未全部获取成功，原书保持不变');
      }
      final reading = OnlineReadingBook(
        source: source,
        book: catalog.book,
        chapters: catalog.chapters,
        service: service,
        bookshelfId: entry.id,
      );
      final prior = await OnlineReadingProgress(
        library,
        reading,
      ).load(entry.id);
      AnchorBook? oldAnchors;
      LocationAnchor? oldLocation;
      if (prior?.cfi != null && progressStore != null) {
        final online = reading.open();
        try {
          oldAnchors = AnchorBook(
            revision: reading.revision,
            chapters: [await online.loadAnchorChapter(prior!.spineIndex)],
          );
          oldLocation = oldAnchors.capture(prior.cfi!);
        } finally {
          online.close();
          await online.preparationsStopped;
        }
      }
      final updated = await library.updateBytes(
        entry.id,
        await OnlineEpubUpdate.preserveBookIdentity(
          entry.filePath,
          result.bytes,
        ),
        isCancelled: isCancelled,
      );
      if (prior != null && progressStore != null) {
        final offline = await EpubChapterSource.openFile(
          File(updated.filePath),
        );
        try {
          final nextMetadata = await OnlineEpubMetadata.read(library, updated);
          final identity = onlineChapterIdentity(
            reading.chapters[prior.spineIndex],
          );
          var spine = -1;
          for (var index = 0; index < offline.chapterCount; index++) {
            final href = offline.document.resources.resolve(
              offline.document.spine[index].href,
              baseDir: p.posix.dirname(offline.document.opfPath),
            );
            final indexed = nextMetadata?.chapters
                .where((chapter) => chapter.href == href)
                .firstOrNull;
            if (indexed != null &&
                onlineChapterIdentity(
                      indexed.toChapter(index, nextMetadata!.detailUrl),
                    ) ==
                    identity) {
              spine = index;
              break;
            }
          }
          if (spine >= 0) {
            final chapter = await offline.loadAnchorChapter(spine);
            final nextAnchors = AnchorBook(
              revision: updated.contentRevision!,
              chapters: [chapter],
            );
            final relocated = oldLocation == null || oldAnchors == null
                ? null
                : RevisionRelocator.relocate(
                    oldBook: oldAnchors,
                    newBook: nextAnchors,
                    record: AnchorRecord(original: oldLocation),
                    progress: true,
                  );
            await progressStore.save(
              updated.id,
              ReaderProgress(
                spineIndex: spine,
                pageIndex: 0,
                cfi: relocated?.effective.revision == updated.contentRevision
                    ? relocated!.effective.start.cfi
                    : chapter.cfiAt(0),
                approximate: relocated == null || !relocated.isResolved,
                finished: prior.finished,
                chapterTitle: chapter.title,
                contentRevision: updated.contentRevision,
              ),
            );
          }
        } finally {
          offline.close();
          await offline.preparationsStopped;
        }
      }
      _lastAddedChapters = catalog.chapters.length;
      _shelfEntries[entry.id] = updated;
      notifyListeners();
      return updated;
    }
    final original = await OnlineEpubUpdate.open(
      entry.filePath,
      sourceMetadata: metadata,
    );
    final info = await service.loadBookInfo(source, book);
    final toc = await service.fetchToc(source, info);
    if (isCancelled?.call() ?? false) {
      throw const BookSourceException('已取消更新', code: 'ONLINE_CANCELLED');
    }
    final added = original.newChapters(toc);
    if (added.isEmpty) return entry;
    final result = await _downloadWithNotification(
      source,
      book,
      onProgress: onProgress,
      isCancelled: isCancelled,
      preparedBook: info,
      selectedChapters: added,
      chapterDirectory: toc,
    );
    if (result.skippedChapters > 0) {
      throw const BookSourceException('新增章节未全部获取成功，原书保持不变');
    }
    final bytes = original.append(result.bytes, toc);
    if (isCancelled?.call() ?? false) {
      throw const BookSourceException('已取消更新', code: 'ONLINE_CANCELLED');
    }
    final latest = await library.bookById(entry.id);
    if (latest == null || latest.contentRevision != entry.contentRevision) {
      throw const BookSourceException('本地图书已变化，已停止更新');
    }
    onProgress?.call(0, 0, '正在更新书架');
    final updated = await library.updateBytes(
      entry.id,
      bytes,
      isCancelled: isCancelled,
    );
    _lastAddedChapters = added.length;
    await _withConfiguration(() async {
      await _store.saveLink(
        entry.id,
        OnlineBookLink(
          sourceId: source.id,
          bookUrl: result.book.bookUrl,
          name: result.book.name,
          author: result.book.author,
          tocUrl: result.book.tocUrl,
          bookOptions: result.book.bookOptions,
          tocOptions: result.book.tocOptions,
        ),
      );
      _links = await _store.loadLinks();
    });
    _lastSkippedChapters = result.skippedChapters;
    _lastSkippedReasons = List<String>.unmodifiable(result.skippedReasons);
    notifyListeners();
    return updated;
  }

  Future<OnlineBookDownloadResult> _downloadWithNotification(
    BookSource source,
    OnlineBook book, {
    OnlineDownloadProgress? onProgress,
    bool Function()? isCancelled,
    OnlineBook? preparedBook,
    List<OnlineChapter>? selectedChapters,
    List<OnlineChapter>? chapterDirectory,
  }) async {
    final notification = OnlineDownloadNotification(book.name);
    await notification.update(0, 0, '正在准备下载');
    try {
      final result = await service.download(
        source,
        book,
        preparedBook: preparedBook,
        selectedChapters: selectedChapters,
        chapterDirectory: chapterDirectory,
        isCancelled: isCancelled,
        onProgress: (completed, total, message) {
          onProgress?.call(completed, total, message);
          unawaited(notification.update(completed, total, message));
        },
      );
      await notification.update(
        0,
        0,
        result.skippedChapters > 0
            ? '下载完成，${result.skippedChapters} 章未能获取'
            : '下载完成',
        done: true,
      );
      return result;
    } catch (error) {
      await notification.update(
        0,
        0,
        isCancelled?.call() == true ? '已取消下载' : '下载失败',
        done: true,
      );
      rethrow;
    }
  }

  Future<BookSource> _import(Future<BookSource> Function() operation) async {
    try {
      final previousExplore = {
        for (final source in _sources)
          if (source.enabled &&
              source.enabledExplore &&
              source.exploreUrl.trim().isNotEmpty)
            source.sourceUrl,
      };
      final source = await _withConfiguration(operation);
      await initialize(refresh: true);
      if (_sources.any(
        (source) =>
            source.enabled &&
            source.enabledExplore &&
            source.exploreUrl.trim().isNotEmpty &&
            !previousExplore.contains(source.sourceUrl),
      )) {
        discoveryImportRevision++;
        notifyListeners();
      }
      return source;
    } on BookSourceException {
      rethrow;
    } on Object catch (error) {
      throw BookSourceException('$error');
    }
  }

  /// 自动关联与书源导入共用配置文件，串行读改写避免临时文件互相覆盖。
  Future<T> _withConfiguration<T>(Future<T> Function() operation) {
    final task = _configurationWork.then((_) => operation());
    _configurationWork = task.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return task;
  }

  @override
  void dispose() {
    _disposed = true;
    library.removeListener(_libraryChanged);
    _store.dispose();
    service.dispose();
    super.dispose();
  }
}
