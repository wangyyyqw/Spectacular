import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/paint/image_cache.dart';
import 'package:reader_core/perf/trace.dart';
import 'package:reader_ui/loading_skeleton.dart';
import 'package:reader_ui/annotations/annotation.dart';
import 'package:reader_ui/decorations/decoration.dart';
import 'package:reader_ui/decorations/decoration_rules.dart';
import 'package:reader_ui/decorations/decoration_image_store.dart';
import 'package:reader_ui/panels/search_panel.dart';
import 'package:reader_ui/panels/settings_panel.dart';
import 'package:reader_ui/theme/reader_margins.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';

import '../diagnostics/reader_log.dart';
import '../search/scan_search_service.dart';
import '../storage/reading_session_store.dart';
import '../storage/drift_progress_store.dart';
import 'epub_chapter_source.dart';
import 'reading_session_tracker.dart';
import 'reader_settings.dart';
import 'reader_background_store.dart';
import 'reader_font_store.dart';

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
    this.bytes,
    this.bytesFuture,
    this.sourcePath,
    this.sourceFuture,
    required this.bookId,
    required this.store,
    this.bookmarks,
    this.annotations,
    this.decorations,
    this.decorationRules,
    this.decorationImages,
    this.readingSessions,
    this.settings,
    this.settingsFuture,
    this.onSettingsChanged,
    this.bookTitle = '阅读',
    this.onMarginsChanged,
    this.fontStore,
    this.contentRevision,
    this.contentRevisionFuture,
    this.readingActive = true,
    this.onReady,
    this.onClosed,
  });

  /// EPUB 字节（内存入口；与 [sourcePath] 二选一）。
  final Uint8List? bytes;

  /// 打开宿主读取一次的字节；与封面动画同时准备。
  final Future<Uint8List>? bytesFuture;

  /// EPUB 文件路径（阅读页默认入口，惰性读取，不常驻整本字节）。
  final String? sourcePath;

  /// 可共享的打开任务；本页唯一负责关闭已完成或取消后晚到的源。
  final Future<EpubChapterSource>? sourceFuture;

  /// 书籍标识。
  final String bookId;

  /// 进度存储。
  final ReaderProgressStore store;

  /// 书签存储（P4-13）；为 null 时菜单不显示书签入口。
  final ReaderBookmarkStore? bookmarks;

  /// 标注存储（P4-17）；为 null 时选区菜单不显示高亮/笔记。
  final ReaderAnnotationStore? annotations;

  /// 本书手工装饰。
  final ReaderDecorationStore? decorations;

  /// 本书与全局自动装饰规则。
  final ReaderDecorationRuleStore? decorationRules;

  /// 独立装饰图片存储。
  final ReaderDecorationImageStore? decorationImages;

  /// 阅读会话存储；用于统计前台阅读时长。
  final ReadingSessionStore? readingSessions;

  /// 初始阅读设置（P4-21）。
  final ReaderSettings? settings;

  /// 设置尚未读完时先挂载页面，首次排版仍等待设置和用户字体。
  final Future<ReaderSettings>? settingsFuture;

  /// 设置变化（调用方持久化）。
  final ValueChanged<ReaderSettings>? onSettingsChanged;

  /// 书名（菜单顶部栏用）。
  final String bookTitle;

  /// 页边距变化（边距调节器「保留」）。
  final ValueChanged<ReaderMargins>? onMarginsChanged;

  /// 自定义字体存储；宿主负责导入、注册和恢复。
  final ReaderFontStore? fontStore;

  /// 书库已存的原书 SHA-256；为 null 时才现算。
  final String? contentRevision;

  /// 旧书的流式摘要与源打开并行，首次排版前必须得到实际版本。
  final Future<String>? contentRevisionFuture;

  /// 封面已揭开后才记录前台阅读时长。
  final bool readingActive;

  /// 目标正文和进度数字已绘制，或打开失败可以展示错误时通知宿主。
  final VoidCallback? onReady;

  /// 阅读页退出动画结束后，进度已落盘且章节源已释放。
  final VoidCallback? onClosed;

  @override
  State<EpubReaderPage> createState() => _EpubReaderPageState();
}

class _EpubReaderPageState extends State<EpubReaderPage>
    with WidgetsBindingObserver {
  late ReaderSettings _settings = widget.settings ?? ReaderSettings.defaults;
  final _backgroundStore = ReaderBackgroundStore();
  String _contentRevision = '';
  List<ReaderFontOption> _customFonts = const [];

  Future<void> _prepareInitialSettings() async {
    final pending = widget.settingsFuture;
    if (pending != null) {
      final settings = await pending;
      if (_openingCancelled) return;
      _settings = settings;
    }
    await _prepareFonts();
  }

  Future<void> _prepareFonts() async {
    final store = widget.fontStore;
    if (store == null || _openingCancelled) return;
    final fonts = await store.list();
    if (_openingCancelled) return;
    _customFonts = [
      for (final font in fonts)
        ReaderFontOption(family: font.family, label: font.displayName),
    ];
    if (!_settings.overrides.isCustomFont) return;
    try {
      await store.load(_settings.fontFamily!);
    } catch (_) {
      if (!mounted || _openingCancelled) return;
      _changeSettings(_settings.copyWithFont(null));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('自定义字体不可用，已恢复书籍字体，请重新导入')));
    }
  }

  Future<ReaderFontOption?> _pickFont() async {
    final font = await widget.fontStore!.pick();
    if (font == null) return null;
    return ReaderFontOption(family: font.family, label: font.displayName);
  }

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
    if (widget.readingActive != oldWidget.readingActive) {
      _syncReadingActivity();
    }
  }

  EpubChapterSource? _source;
  ScanSearchService? _search;
  DecodedImageCache? _imageCache;
  ReadingSessionTracker? _readingTracker;
  ReaderSession? _readerSession;
  late final Future<EpubChapterSource> _sourceTask;
  Future<void Function()>? _anchorBinding;
  Future<void>? _sourceCloseTask;
  Future<void> _backgroundFlush = Future<void>.value();
  int _trackedPageTurns = 0;
  int _trackedCharactersRead = 0;
  Object? _error;
  bool _loading = true;
  bool _closing = false;
  bool _openingFailed = false;
  bool _readable = false;
  bool _readyNotified = false;
  bool _readyScheduled = false;

  bool get _openingCancelled => _closing || _openingFailed;

  /// 打开书埋点（P4-31）：从 initState 到首帧渲染完成。
  ReaderTraceHandle? _openTrace;

  @override
  void initState() {
    super.initState();
    if (readerTraceEnabled) {
      _openTrace = ReaderTrace.instance.start(
        ReaderTraceName.bookOpen,
        bookId: widget.bookId,
      );
    }
    final sessionStore = widget.readingSessions;
    if (sessionStore != null) {
      _readingTracker = ReadingSessionTracker(
        store: sessionStore,
        bookId: widget.bookId,
      );
    }
    WidgetsBinding.instance.addObserver(this);
    // 源打开与设置/字体准备并行，首屏排版等待二者和实际内容版本到齐。
    final watch = Stopwatch()..start();
    _sourceTask = widget.sourceFuture ?? _openSource();
    _sourceTask.ignore();
    unawaited(_open(watch));
  }

  Future<void> _open(Stopwatch watch) async {
    try {
      final revision = _resolveContentRevision();
      revision.ignore();
      await Future.wait([
        _prepareInitialSettings(),
        _prepareSource(revision, watch),
      ], eagerError: true);
      if (!mounted || _closing) return;
      _showSource();
    } catch (error) {
      _openingFailed = true;
      if (mounted && !_closing) {
        setState(() {
          _error = error;
          _loading = false;
        });
        _scheduleReady();
      }
      await _closeSource();
    }
  }

  void _showSource() {
    final source = _source!;
    setState(() {
      _search = ScanSearchService(
        source: source,
        onLog: (event, fields) =>
            unawaited(ReaderLog.instance.log(event, fields: fields)),
      );
      _imageCache = DecodedImageCache(
        // 条数与字节双上限，翻回上一屏仍可复用图片解码。
        maxEntries: 16,
        maxBytes: 12 << 20,
        loadBytes: (url) => _loadImageBytes(source, url),
      );
      _loading = false;
    });
  }

  Future<EpubChapterSource> _openSource() async {
    // 导入已经校验归档，阅读期间只按需读取目标章节。
    final path = widget.sourcePath;
    if (path != null) {
      return EpubChapterSource.openFile(
        File(path),
        verifyCrc: false,
        contentVersion: widget.contentRevision,
      );
    }
    final bytes = widget.bytes ?? await widget.bytesFuture;
    if (bytes == null) throw StateError('阅读页缺少 EPUB 来源');
    return EpubChapterSource.open(
      bytes,
      verifyCrc: false,
      contentVersion: widget.contentRevision,
    );
  }

  Future<String> _resolveContentRevision() async {
    final pending = widget.contentRevisionFuture;
    if (pending != null) return pending;
    final known = widget.contentRevision;
    if (known != null && known.isNotEmpty) return known;
    final path = widget.sourcePath;
    if (path != null) {
      return (await sha256.bind(File(path).openRead()).first).toString();
    }
    final bytes = widget.bytes ?? await widget.bytesFuture;
    if (bytes == null) throw StateError('阅读页缺少 EPUB 内容版本');
    return sha256.convert(bytes).toString();
  }

  Future<void> _prepareSource(Future<String> revision, Stopwatch watch) async {
    final source = await _sourceTask;
    if (_openingCancelled) return;
    _source = source;
    source.bookIdForTrace = widget.bookId;
    unawaited(_logParsedSource(source, watch));
    _contentRevision = await revision;
    if (_openingCancelled) return;
    if (_contentRevision.isEmpty) throw StateError('阅读页缺少 EPUB 内容版本');
    source.setContentVersion(_contentRevision);
    if (widget.store case DriftProgressStore store) {
      source.setPageCountStore(
        store.pageCountStore(widget.bookId, _contentRevision),
      );
      _anchorBinding = store.bindSource(
        widget.bookId,
        source,
        _contentRevision,
      );
      await _anchorBinding;
    }
  }

  Future<void> _logParsedSource(
    EpubChapterSource source,
    Stopwatch watch,
  ) async {
    final elapsedMs = watch.elapsedMilliseconds;
    try {
      final length = widget.sourcePath == null
          ? (widget.bytes ?? await widget.bytesFuture)?.length ?? 0
          : await File(widget.sourcePath!).length();
      await ReaderLog.instance.log(
        'epub_parse',
        fields: {
          'kb': length ~/ 1024,
          'source': widget.sourcePath == null ? 'memory' : 'file',
          'chapters': source.chapterCount,
          'ms': elapsedMs,
        },
      );
    } catch (_) {
      // 日志晚到或来源已经释放，不影响页面退出。
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final tracker = _readingTracker;
    switch (state) {
      case AppLifecycleState.resumed:
        _syncReadingActivity();
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        unawaited(tracker?.pause() ?? Future<void>.value());
        _flushProgressInBackground();
      case AppLifecycleState.detached:
        unawaited(tracker?.finish() ?? Future<void>.value());
        _flushProgressInBackground();
    }
  }

  @override
  void didHaveMemoryPressure() {
    _source?.clearNonCurrentLayouts();
  }

  void _flushProgressInBackground() {
    final session = _readerSession;
    final source = _source;
    session?.setPageCountingActive(false);
    _backgroundFlush = _backgroundFlush.then(
      (_) => _flushStores(session, source),
    );
    unawaited(_backgroundFlush);
  }

  Future<void> _flushStores(
    ReaderSession? session,
    EpubChapterSource? source,
  ) async {
    try {
      await session?.flushProgress();
    } catch (error) {
      await ReaderLog.instance.log(
        'progress_save_error',
        fields: {'bookId': widget.bookId, 'error': '$error'},
      );
    }
    if (source == null || source.isClosed) return;
    try {
      await source.flushPageCounts();
    } catch (error) {
      await ReaderLog.instance.log(
        'page_count_save_error',
        fields: {'bookId': widget.bookId, 'error': '$error'},
      );
    }
  }

  @override
  void dispose() {
    _closing = true;
    _openTrace?.stop();
    final session = _readerSession;
    final onClosed = widget.onClosed;
    session?.setPageCountingActive(false);
    session?.removeListener(_syncReadingStats);
    _readerSession = null;
    WidgetsBinding.instance.removeObserver(this);
    _search?.dispose();
    _imageCache?.clear();
    unawaited(
      _finishClose(session).whenComplete(() {
        onClosed?.call();
      }),
    );
    super.dispose();
  }

  Future<void> _finishClose(ReaderSession? session) async {
    try {
      await _backgroundFlush;
      await _flushStores(session, _source);
      await _readingTracker?.finish();
    } finally {
      // 保存可能仍需校验原始 CFI，进度与计页落盘后才释放源。
      await _closeSource();
    }
  }

  Future<void> _closeSource() => _sourceCloseTask ??= _releaseSource();

  Future<void> _releaseSource() async {
    EpubChapterSource? source;
    try {
      source = await _sourceTask;
      final binding = _anchorBinding;
      if (binding != null) (await binding)();
    } catch (_) {
      // 打开或借用失败仍继续释放已经取得的归档。
    } finally {
      source?.close();
      _source = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 打开书期间先出骨架；就绪后由 ReaderPage 平滑接管（P2-27）。
    return Scaffold(
      key: const ValueKey<String>('epub-reader-scaffold'),
      // 阅读页自行处理安全区，并让正文始终铺满可用区域。
      resizeToAvoidBottomInset: false,
      body: AnimatedSwitcher(
        duration: widget.readingActive
            ? const Duration(milliseconds: 250)
            : Duration.zero,
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
      contentRevision: _contentRevision,
      imageCache: _imageCache,
      bookmarks: widget.bookmarks,
      annotations: widget.annotations,
      decorations: widget.decorations,
      decorationRules: widget.decorationRules,
      decorationImages: widget.decorationImages,
      markSettings: settings.markSettings,
      onMarkSettingsChanged: (mark) =>
          _changeSettings(_settings.copyWithMarkSettings(mark)),
      overrides: settings.overrides,
      theme: settings.theme,
      customTheme: settings.customTheme,
      backgroundImageLoader: _backgroundStore.load,
      onPickBackgroundImage: _backgroundStore.pick,
      customFonts: _customFonts,
      onPickFont: widget.fontStore == null ? null : _pickFont,
      onLoadFont: widget.fontStore == null
          ? null
          : (family) async {
              await widget.fontStore!.load(family);
            },
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
      keepScreenOn: settings.keepScreenOn,
      onKeepScreenOnChanged: (enabled) =>
          _changeSettings(_settings.copyWithKeepScreenOn(enabled)),
      volumeKeyPaging: settings.volumeKeyPaging,
      onVolumeKeyPagingChanged: (enabled) =>
          _changeSettings(_settings.copyWithVolumeKeyPaging(enabled)),
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
    _scheduleReady();
  }

  void _syncReadingStats() {
    final session = _readerSession;
    if (session == null) {
      return;
    }
    _scheduleReady();
    final pageTurns = session.pageTurns - _trackedPageTurns;
    final characters = session.charactersRead - _trackedCharactersRead;
    if (pageTurns <= 0 && characters <= 0) {
      return;
    }
    _trackedPageTurns = session.pageTurns;
    _trackedCharactersRead = session.charactersRead;
    _readingTracker?.recordPageTurn(count: pageTurns, characters: characters);
  }

  void _scheduleReady() {
    if (_readyNotified || _readyScheduled || _closing) return;
    final session = _readerSession;
    final failed = _error != null || session?.error != null;
    final complete = _hasPreparedFrame(session);
    if (!failed && !complete) return;
    _readyScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _readyScheduled = false;
      if (!mounted || _closing || _readyNotified) return;
      final session = _readerSession;
      if (_error == null && session?.error == null) {
        if (!_hasPreparedFrame(session)) return;
        _readable = true;
      }
      _readyNotified = true;
      _openTrace?.stop();
      _syncReadingActivity();
      widget.onReady?.call();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  bool _hasPreparedFrame(ReaderSession? session) =>
      session != null &&
      !session.loading &&
      session.hasContent &&
      session.readingPercent != null;

  void _syncReadingActivity() {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    final foreground =
        lifecycle == null || lifecycle == AppLifecycleState.resumed;
    if (_readable && widget.readingActive && foreground && !_closing) {
      _readingTracker?.start();
    } else {
      unawaited(_readingTracker?.pause() ?? Future<void>.value());
    }
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
