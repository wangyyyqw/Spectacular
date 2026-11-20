import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../library/library_store.dart';
import 'book_source_auth.dart';
import 'book_source_cookie_store.dart';
import 'book_source_models.dart';
import 'book_source_service.dart';
import 'book_source_store.dart';
import 'online_epub_update.dart';
import 'online_reading_catalog_store.dart';

/// 缓存先显示，快速刷新完成后使用新目录，慢请求继续在后台更新快照。
class OnlineCatalogLoad {
  const OnlineCatalogLoad({
    required this.source,
    required this.cached,
    required this.refresh,
  });

  final BookSource source;
  final Future<OnlineReadingCatalog?> cached;
  final Future<OnlineReadingCatalog> refresh;

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
  List<String> _lastSkippedReasons = const <String>[];
  final Map<String, Future<OnlineReadingCatalog>> _catalogRefreshes = {};
  bool _disposed = false;

  List<BookSource> get sources => List<BookSource>.unmodifiable(_sources);
  Map<String, OnlineBookLink> get links =>
      Map<String, OnlineBookLink>.unmodifiable(_links);
  bool get initialized => _initialized;
  bool get loading => _loading;
  String? get error => _error;
  int get lastSkippedChapters => _lastSkippedChapters;
  int get lastAddedChapters => _lastAddedChapters;
  List<String> get lastSkippedReasons =>
      List<String>.unmodifiable(_lastSkippedReasons);
  int get enabledCount => _sources.where((source) => source.enabled).length;
  bool isLoggedIn(BookSource source) => _loggedInSourceIds.contains(source.id);

  /// 初次读取本地书源与书籍关联。
  Future<void> initialize({bool refresh = false}) async {
    if (_loading || (_initialized && !refresh)) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await cookieStore.load();
      _sources = await _store.load(refresh: refresh);
      _links = await _store.loadLinks();
      final loggedIn = <String>{};
      for (final source in _sources) {
        if (await cookieStore.hasLoginFor(source)) loggedIn.add(source.id);
      }
      _loggedInSourceIds = loggedIn;
      _initialized = true;
    } on Object catch (error) {
      _error = '$error';
    } finally {
      _loading = false;
      notifyListeners();
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
    await _store.setEnabled(id, enabled);
    await initialize(refresh: true);
  }

  Future<void> setSourceLoadMode(String id, BookSourceLoadMode mode) async {
    await _store.setLoadMode(id, mode);
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
    await _store.remove(id);
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
      _loggedInSourceIds = <String>{..._loggedInSourceIds, source.id};
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

  /// 为搜索结果异步补齐详情页标签字段。
  Future<List<OnlineSourceSearchResult>> enrichSearchResults(
    List<OnlineSourceSearchResult> results,
  ) async {
    if (results.isEmpty) return results;
    return Future.wait(
      results.map((result) async {
        if (result.books.isEmpty) return result;
        try {
          final books = await service.enrichSearchResults(
            result.source,
            result.books,
          );
          return OnlineSourceSearchResult(
            source: result.source,
            books: books,
            error: result.error,
          );
        } on Object {
          return result;
        }
      }),
    );
  }

  /// 详情、最近阅读和选章共享同一刷新，过期缓存只保留最近入口。
  OnlineCatalogLoad loadCatalog(BookSource source, OnlineBook book) {
    final cached = catalogs.read(source, book);
    final refresh = cached.then(
      (catalog) => refreshCatalog(source, catalog?.book ?? book),
    );
    // 页面关闭后刷新仍可落盘，异常由仍在显示的页面或缓存回退处理。
    refresh.ignore();
    return OnlineCatalogLoad(source: source, cached: cached, refresh: refresh);
  }

  /// 只合并完整请求和目录规则相同的网络任务。
  Future<OnlineReadingCatalog> refreshCatalog(
    BookSource source,
    OnlineBook book,
  ) {
    final key = catalogs.requestIdentity(source, book);
    final pending = _catalogRefreshes[key];
    if (pending != null) return pending;
    final task = _refreshCatalog(source, book);
    _catalogRefreshes[key] = task;
    void finished() {
      if (identical(_catalogRefreshes[key], task)) {
        _catalogRefreshes.remove(key);
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
    OnlineBook book,
  ) async {
    final info = await service.loadBookInfo(source, book);
    final chapters = await service.fetchToc(source, info);
    bool isCurrent() => !_disposed && _matchesCurrentSource(source, book);
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
    final link = _links[bookId];
    if (link == null) return null;
    for (final source in _sources) {
      if (source.id == link.sourceId) return source;
    }
    return null;
  }

  /// 下载在线书籍并加入书架。
  Future<BookEntry> downloadAndImport(
    BookSource source,
    OnlineBook book, {
    OnlineDownloadProgress? onProgress,
    bool Function()? isCancelled,
  }) async {
    _lastSkippedChapters = 0;
    _lastSkippedReasons = const <String>[];
    final result = await service.download(
      source,
      book,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
    onProgress?.call(0, 0, '正在加入书架');
    final entry = await library.importBytes(
      result.bytes,
      fallbackTitle: result.book.name,
    );
    await _store.saveLink(
      entry.id,
      OnlineBookLink(
        sourceId: source.id,
        bookUrl: result.book.bookUrl,
        name: result.book.name,
        author: result.book.author,
      ),
    );
    _links = await _store.loadLinks();
    _lastSkippedChapters = result.skippedChapters;
    _lastSkippedReasons = List<String>.unmodifiable(result.skippedReasons);
    notifyListeners();
    return entry;
  }

  /// 获取最新目录，只追加新增正文，复用原章节和阅读数据。
  Future<BookEntry> updateBook(
    BookEntry entry, {
    OnlineDownloadProgress? onProgress,
    bool Function()? isCancelled,
  }) async {
    _lastSkippedChapters = 0;
    _lastAddedChapters = 0;
    _lastSkippedReasons = const <String>[];
    final link = _links[entry.id];
    final source = sourceForBook(entry.id);
    if (link == null || source == null) {
      throw const BookSourceException('未找到这本书的在线来源');
    }
    final book = OnlineBook(
      sourceId: source.id,
      sourceName: source.name,
      name: link.name,
      author: link.author,
      bookUrl: link.bookUrl,
      tocUrl: link.bookUrl,
    );
    onProgress?.call(0, 0, '正在获取最新目录');
    final original = await OnlineEpubUpdate.open(entry.filePath);
    final info = await service.loadBookInfo(source, book);
    final toc = await service.fetchToc(source, info);
    if (isCancelled?.call() ?? false) {
      throw const BookSourceException('已取消更新', code: 'ONLINE_CANCELLED');
    }
    final added = original.newChapters(toc);
    if (added.isEmpty) return entry;
    final result = await service.download(
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
    await _store.saveLink(
      entry.id,
      OnlineBookLink(
        sourceId: source.id,
        bookUrl: result.book.bookUrl,
        name: result.book.name,
        author: result.book.author,
      ),
    );
    _links = await _store.loadLinks();
    _lastSkippedChapters = result.skippedChapters;
    _lastSkippedReasons = List<String>.unmodifiable(result.skippedReasons);
    notifyListeners();
    return updated;
  }

  Future<BookSource> _import(Future<BookSource> Function() operation) async {
    try {
      final source = await operation();
      await initialize(refresh: true);
      return source;
    } on BookSourceException {
      rethrow;
    } on Object catch (error) {
      throw BookSourceException('$error');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _store.dispose();
    service.dispose();
    super.dispose();
  }
}
