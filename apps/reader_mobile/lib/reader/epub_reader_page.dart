import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/paint/image_cache.dart';
import 'package:reader_core/perf/trace.dart';
import 'package:reader_ui/loading_skeleton.dart';
import 'package:reader_ui/annotations/annotation.dart';
import 'package:reader_ui/panels/search_panel.dart';
import 'package:reader_ui/theme/reader_margins.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';

import '../diagnostics/reader_log.dart';
import '../search/scan_search_service.dart';
import '../storage/reading_session_store.dart';
import 'epub_chapter_source.dart';
import 'reading_session_tracker.dart';
import 'reader_settings.dart';
import 'reader_background_store.dart';

/// 默认阅读设置：段距 10dp（对齐阅微默认档，约 0.625em @16dp 字号）。
///
/// 字号/行高/对齐默认不覆盖，跟随书籍 CSS；用户设置面板接入后由
/// `ReaderOverrides` 覆盖作者声明（reader origin 高于 author）。
const ReaderOverrides defaultReaderOverrides = ReaderOverrides(
  paragraphSpacing: 10,
);

/// 从内存 EPUB 打开的最小阅读页。
class EpubReaderPage extends StatefulWidget {
  /// 创建页面。
  const EpubReaderPage({
    super.key,
    required this.bytes,
    required this.bookId,
    required this.store,
    this.bookmarks,
    this.annotations,
    this.readingSessions,
    this.settings,
    this.onSettingsChanged,
    this.bookTitle = '阅读',
    this.onMarginsChanged,
  });

  /// EPUB 字节。
  final Uint8List bytes;

  /// 书籍标识。
  final String bookId;

  /// 进度存储。
  final ReaderProgressStore store;

  /// 书签存储（P4-13）；为 null 时菜单不显示书签入口。
  final ReaderBookmarkStore? bookmarks;

  /// 标注存储（P4-17）；为 null 时选区菜单不显示高亮/笔记。
  final ReaderAnnotationStore? annotations;

  /// 阅读会话存储；用于统计前台阅读时长。
  final ReadingSessionStore? readingSessions;

  /// 初始阅读设置（P4-21）。
  final ReaderSettings? settings;

  /// 设置变化（调用方持久化）。
  final ValueChanged<ReaderSettings>? onSettingsChanged;

  /// 书名（菜单顶部栏用）。
  final String bookTitle;

  /// 页边距变化（边距调节器「保留」）。
  final ValueChanged<ReaderMargins>? onMarginsChanged;

  @override
  State<EpubReaderPage> createState() => _EpubReaderPageState();
}

class _EpubReaderPageState extends State<EpubReaderPage>
    with WidgetsBindingObserver {
  late ReaderSettings _settings = widget.settings ?? ReaderSettings.defaults;
  final _backgroundStore = ReaderBackgroundStore();

  void _changeSettings(ReaderSettings next) {
    setState(() => _settings = next);
    widget.onSettingsChanged?.call(next);
  }

  @override
  void didUpdateWidget(covariant EpubReaderPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.settings != oldWidget.settings) {
      _settings = widget.settings ?? ReaderSettings.defaults;
    }
  }

  EpubChapterSource? _source;
  ScanSearchService? _search;
  DecodedImageCache? _imageCache;
  ReadingSessionTracker? _readingTracker;
  ReaderSession? _readerSession;
  int _trackedPageTurns = 0;
  int _trackedCharactersRead = 0;
  Object? _error;
  bool _loading = true;

  /// 打开书埋点（P4-31）：从 initState 到首帧渲染完成。
  late final ReaderTraceHandle? _openTrace = readerTraceEnabled
      ? ReaderTrace.instance.start(
          ReaderTraceName.bookOpen,
          bookId: widget.bookId,
        )
      : null;

  @override
  void initState() {
    super.initState();
    final sessionStore = widget.readingSessions;
    if (sessionStore != null) {
      _readingTracker = ReadingSessionTracker(
        store: sessionStore,
        bookId: widget.bookId,
      )..start();
      WidgetsBinding.instance.addObserver(this);
    }
    // 先让加载骨架绘制一帧，再做同步解析：openEpub 对 156MB 的书要 1.5 秒，
    // 直接同步跑会让页面转场期间黑屏（用户看不到任何东西）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _open();
      }
    });
  }

  Future<void> _open() async {
    final watch = Stopwatch()..start();
    try {
      // 阅读时跳过 CRC 校验：这本书导入时已完整校验过一次，150MB+ 的大书
      // 光校验就要多花近一倍时间。
      final source = await EpubChapterSource.open(
        widget.bytes,
        verifyCrc: false,
      );
      unawaited(
        ReaderLog.instance.log(
          'epub_parse',
          fields: <String, Object?>{
            'kb': widget.bytes.length ~/ 1024,
            'chapters': source.chapterCount,
            'ms': watch.elapsedMilliseconds,
          },
        ),
      );
      if (!mounted) {
        source.close();
        return;
      }
      source.bookIdForTrace = widget.bookId;
      setState(() {
        _source = source;
        _search = ScanSearchService(
          source: source,
          onLog: (event, fields) =>
              unawaited(ReaderLog.instance.log(event, fields: fields)),
        );
        _imageCache = DecodedImageCache(
          // P4-32：条数与字节双上限（§44.4 的 512 张按解码字节折算成 32 张
          // + 48MB，避免大图书一次性吃满内存）。
          maxEntries: 32,
          loadBytes: (url) => _loadImageBytes(source, url),
        );
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _openTrace?.stop());
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final tracker = _readingTracker;
    if (tracker == null) {
      return;
    }
    switch (state) {
      case AppLifecycleState.resumed:
        tracker.start();
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        unawaited(tracker.pause());
      case AppLifecycleState.detached:
        unawaited(tracker.finish());
    }
  }

  @override
  void dispose() {
    _readerSession?.removeListener(_syncReadingStats);
    _readerSession = null;
    if (_readingTracker != null) {
      WidgetsBinding.instance.removeObserver(this);
      unawaited(_readingTracker!.finish());
    }
    _search?.dispose();
    _imageCache?.clear();
    _source?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 打开书期间先出骨架；就绪后由 ReaderPage 平滑接管（P2-27）。
    return Scaffold(
      key: const ValueKey<String>('epub-reader-scaffold'),
      // 阅读页自行处理安全区，并让正文始终铺满可用区域。
      resizeToAvoidBottomInset: false,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return ReaderLoadingSkeleton(title: widget.bookTitle);
    }
    final error = _error;
    if (error != null) {
      return Center(
        key: const ValueKey<String>('epub-open-error'),
        child: Text('打开失败：$error'),
      );
    }
    final settings = _settings;
    return ReaderPage(
      key: const ValueKey<String>('reader-page'),
      source: _source!,
      store: widget.store,
      bookId: widget.bookId,
      imageCache: _imageCache,
      bookmarks: widget.bookmarks,
      annotations: widget.annotations,
      overrides: settings.overrides,
      theme: settings.theme,
      customTheme: settings.customTheme,
      backgroundImageLoader: _backgroundStore.load,
      onPickBackgroundImage: _backgroundStore.pick,
      backgroundId: settings.backgroundId,
      inkMode: settings.inkMode,
      onOverridesChanged: (overrides) =>
          _changeSettings(_settings.copyWithOverrides(overrides)),
      onThemeChanged: (themeId) =>
          _changeSettings(_settings.copyWithTheme(themeId)),
      onBackgroundChanged: (backgroundId) =>
          _changeSettings(_settings.copyWithBackground(backgroundId)),
      onInkModeChanged: (enabled) =>
          _changeSettings(_settings.copyWithInkMode(enabled)),
      onSearch: _searchResults,
      bookTitle: widget.bookTitle,
      margins: settings.margins,
      onMarginsChanged: (margins) {
        _changeSettings(_settings.copyWithMargins(margins));
        widget.onMarginsChanged?.call(margins);
      },
      tapZones: settings.tapZones,
      onTapZonesChanged: (zones) =>
          _changeSettings(_settings.copyWithTapZones(zones)),
      pageTurnMode: settings.pageTurnMode,
      onPageTurnModeChanged: (mode) =>
          _changeSettings(_settings.copyWithPageTurnMode(mode)),
      onSessionReady: _bindReaderSession,
      onLog: (event, fields) =>
          unawaited(ReaderLog.instance.log(event, fields: fields)),
      onResolveSearchCfi: _resolveSearchCfi,
      onSearchStream: _searchStream,
    );
  }

  void _bindReaderSession(ReaderSession session) {
    _readerSession?.removeListener(_syncReadingStats);
    _readerSession = session;
    _trackedPageTurns = session.pageTurns;
    _trackedCharactersRead = session.charactersRead;
    session.addListener(_syncReadingStats);
  }

  void _syncReadingStats() {
    final session = _readerSession;
    if (session == null) {
      return;
    }
    final pageTurns = session.pageTurns - _trackedPageTurns;
    final characters = session.charactersRead - _trackedCharactersRead;
    if (pageTurns <= 0 && characters <= 0) {
      return;
    }
    _trackedPageTurns = session.pageTurns;
    _trackedCharactersRead = session.charactersRead;
    _readingTracker?.recordPageTurn(count: pageTurns, characters: characters);
  }

  Future<List<SearchPanelResult>> _searchResults(String query) async => [
    for (final result in await _search!.search(query)) _panelResult(result),
  ];

  Stream<SearchProgress> _searchStream(String query) async* {
    await for (final progress in _search!.searchStream(query)) {
      yield SearchProgress(
        results: [for (final result in progress.results) _panelResult(result)],
        scanned: progress.scanned,
        total: progress.total,
      );
    }
  }

  Future<String?> _resolveSearchCfi(SearchPanelResult result) =>
      _search!.resolveCfi(
        SearchResult(
          spineIndex: result.spineIndex,
          charOffset: result.charOffset,
          chapterTitle: result.chapterTitle,
          context: result.context,
          matchLength: result.matchLength,
        ),
      );

  static SearchPanelResult _panelResult(SearchResult result) =>
      SearchPanelResult(
        spineIndex: result.spineIndex,
        charOffset: result.charOffset,
        chapterTitle: result.chapterTitle,
        context: result.context,
        matchLength: result.matchLength,
        cfi: result.cfi,
      );
}

/// 从 EPUB 归档读取图片字节：先按原样路径找，再按 OPF 目录解析，
/// 最后按各 spine 章节目录逐个尝试（背景图 URL 相对所在章节）。
Future<Uint8List?> _loadImageBytes(EpubChapterSource source, String url) async {
  final document = source.document;
  final direct = document.archive.readBytes(url);
  if (direct != null) {
    return direct;
  }
  final resolved = document.resources.resolve(url);
  if (resolved != null) {
    final bytes = document.archive.readBytes(resolved);
    if (bytes != null) {
      return bytes;
    }
  }
  var tried = 0;
  for (final item in document.spine) {
    if (tried >= 64) {
      break;
    }
    tried += 1;
    final slash = item.href.lastIndexOf('/');
    final baseDir = slash < 0 ? '' : item.href.substring(0, slash);
    final candidate = document.resources.resolve(url, baseDir: baseDir);
    if (candidate == null) {
      continue;
    }
    final bytes = document.archive.readBytes(candidate);
    if (bytes != null) {
      return bytes;
    }
  }
  return null;
}
