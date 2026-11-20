import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reader_core/cache/chapter_pagination_store.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/paint/image_cache.dart';
import 'package:reader_core/perf/trace.dart';
import 'package:reader_core/source/format_opener.dart';
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
import 'package:reader_ui/theme/reader_panel_theme.dart';
import 'package:reader_ui/theme/reader_theme.dart';

import '../home/finish_book_sheet.dart';
import '../theme/app_theme.dart';
import '../library/library_store.dart';
import '../storage/book_review_store.dart';
import '../diagnostics/reader_log.dart';
import '../editing/book_edit_repository.dart';
import '../editing/book_editor_route.dart';
import '../search/scan_search_service.dart';
import '../storage/reading_session_store.dart';
import '../storage/drift_progress_store.dart';

import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/epub/epub_format_opener.dart';

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

/// 内容已保存或恢复时，由打开器释放旧会话后重新读取书库版本。
enum EpubReaderExit { contentUpdated }

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
    this.bookEditorRepository,
    this.book,
    this.reviewStore,
  });

  final BookEditRepository? bookEditorRepository;
  final BookEntry? book;
  final BookReviewStore? reviewStore;

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

  /// 阅读页退出动画结束后，保存检查已完成且章节源已释放。
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
  ScaffoldMessengerState? _progressMessenger;
  bool _reportedClosingProgressFailure = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _progressMessenger = ScaffoldMessenger.maybeOf(context);
  }

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
    await _refreshFontList();
    return ReaderFontOption(family: font.family, label: font.displayName);
  }

  Future<void> _refreshFontList() async {
    final fonts = await widget.fontStore!.list();
    if (!mounted) return;
    setState(
      () => _customFonts = [
        for (final font in fonts)
          ReaderFontOption(family: font.family, label: font.displayName),
      ],
    );
  }

  Future<ReaderFontOption> _renameFont(String family, String name) async {
    final font = await widget.fontStore!.rename(family, name);
    await _refreshFontList();
    return ReaderFontOption(family: font.family, label: font.displayName);
  }

  Future<void> _removeFont(String family) async {
    await widget.fontStore!.remove(family);
    if (mounted && _settings.fontFamily == family) {
      _changeSettings(_settings.copyWithFont(null));
    }
    await _refreshFontList();
  }

  void _changeSettings(ReaderSettings next) {
    setState(() => _settings = next);
    widget.onSettingsChanged?.call(next);
  }

  void _changeTheme(String themeId) {
    _changeSettings(_settings.copyWithTheme(themeId));
    final scope = AppThemeScope.maybeOf(context);
    if (scope == null) return;
    final dark = ReaderTheme.byId(themeId).isDark;
    if (dark == (Theme.of(context).brightness == Brightness.dark)) return;
    unawaited(scope.onModeChanged(dark ? ThemeMode.dark : ThemeMode.light));
  }

  void _toggleDayNight() {
    final scope = AppThemeScope.maybeOf(context)!;
    final dark = Theme.of(context).brightness == Brightness.dark;
    unawaited(scope.onModeChanged(dark ? ThemeMode.light : ThemeMode.dark));
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
        // 1080×2400 真机的两页背景与画廊图需共同驻留，仍受双上限约束。
        maxEntries: 32,
        maxBytes: 32 << 20,
        loadBytes: (url) => _loadImageBytes(source, url),
      );
      _loading = false;
    });
  }

  Future<EpubChapterSource> _openSource() async {
    // 导入已经校验归档，阅读期间只按需读取目标章节。
    final ReaderFormatOpener<EpubChapterSource> opener = EpubFormatOpener(
      verifyCrc: false,
      networkImageCacheDirectoryProvider: getTemporaryDirectory,
      paginationStore: FileChapterPaginationStore(
        directoryProvider: getApplicationSupportDirectory,
      ),
    );
    final options = ReaderOpenOptions(contentVersion: widget.contentRevision);
    final path = widget.sourcePath;
    if (path != null) {
      return opener.openFile(File(path), options: options);
    }
    final bytes = widget.bytes ?? await widget.bytesFuture;
    if (bytes == null) throw StateError('阅读页缺少 EPUB 来源');
    return opener.openBytes(bytes, options: options);
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
    _backgroundFlush = _backgroundFlush.then((_) => _flushStores(session));
    unawaited(_backgroundFlush);
  }

  Future<void> _flushStores(ReaderSession? session) async {
    try {
      await session?.flushProgress();
    } catch (error) {
      await ReaderLog.instance.log(
        'progress_save_error',
        fields: {'bookId': widget.bookId, 'error': error},
      );
      if (_closing) _reportClosingProgressError(error);
    }
  }

  void _reportClosingProgressError(Object error) {
    if (_reportedClosingProgressFailure) return;
    final messenger = _progressMessenger;
    if (messenger == null || !messenger.mounted) return;
    _reportedClosingProgressFailure = true;
    final message = error is ReaderProgressSaveException
        ? error.message
        : '本次位置未保存，保留上次保存位置，请稍后重试';
    // 退出后的提示交给仍在显示书架的根消息层，不能依赖已销毁阅读页。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (messenger.mounted) {
        messenger.showSnackBar(SnackBar(content: Text(message)));
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _closing = true;
    _openTrace?.stop();
    final session = _readerSession;
    final onClosed = widget.onClosed;
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
      await _flushStores(session);
      await _readingTracker?.finish();
    } finally {
      // 保存可能仍需校验原始 CFI，进度落盘后才释放源。
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
      await source?.preparationsStopped;
      _source = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 打开书期间先出骨架；就绪后由 ReaderPage 平滑接管（P2-27）。
    return Scaffold(
      key: const ValueKey<String>('epub-reader-scaffold'),
      backgroundColor: _pageTheme.background,
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

  // 深浅色跟随软件模式，分别恢复日间和夜间配色。
  ReaderTheme get _pageTheme {
    if (AppThemeScope.maybeOf(context) == null) return _settings.theme;
    return _settings.themeForBrightness(Theme.of(context).brightness);
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
      theme: _pageTheme,
      pageBrightness: AppThemeScope.maybeOf(context) == null
          ? null
          : Theme.of(context).brightness,
      customTheme: settings.customTheme,
      backgroundImageLoader: _backgroundStore.load,
      onPickBackgroundImage: _backgroundStore.pick,
      customFonts: _customFonts,
      onRenameFont: widget.fontStore == null ? null : _renameFont,
      onRemoveFont: widget.fontStore == null ? null : _removeFont,
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
      onThemeChanged: _changeTheme,
      onToggleDayNight: AppThemeScope.maybeOf(context) == null
          ? null
          : _toggleDayNight,
      onBackgroundChanged: (backgroundId) =>
          _changeSettings(_settings.copyWithBackground(backgroundId)),
      onInkModeChanged: (enabled) =>
          _changeSettings(_settings.copyWithInkMode(enabled)),
      onSearch: _searchResults,
      bookTitle: widget.bookTitle,
      margins: settings.margins,
      cornerInfo: settings.cornerInfo,
      onCornerInfoChanged: (info) =>
          _changeSettings(_settings.copyWithCornerInfo(info)),
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
      onBookEnd: _openFinishPage,
      onOpenEditor: _canEditBook ? () => _openEditor(null) : null,
      onEditTarget: _canEditBook ? _openEditor : null,
      onLog: (event, fields) =>
          unawaited(ReaderLog.instance.log(event, fields: fields)),
      onResolveSearchCfi: _resolveSearchCfi,
      onSearchStream: _searchStream,
    );
  }

  bool _editorOpen = false;
  bool _finishPageOpen = false;

  Future<void> _openFinishPage(ReaderSession session, bool rtl) async {
    if (_finishPageOpen || _editorOpen || _closing) return;
    _finishPageOpen = true;
    _syncReadingActivity();
    try {
      await session.flushProgress();
      final review = (await widget.reviewStore?.snapshot())?[widget.bookId];
      if (!mounted || _closing) return;
      final saved = await Navigator.of(context)
          .push<bool>(_finishPageRoute(session, review, rtl));
      if (saved != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(saved ? '已标记读完并保存书评' : '已标记读完，可稍后在书评页评分和写书评')),
        );
      }
    } catch (_) {
      if (mounted && !_closing) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('读完信息读取失败，请再向后翻页重试')));
      }
    } finally {
      _finishPageOpen = false;
      if (mounted) _syncReadingActivity();
    }
  }

  PageRoute<bool> _finishPageRoute(
    ReaderSession session,
    BookReview? review,
    bool rtl,
  ) => PageRouteBuilder<bool>(
    transitionDuration:
        MediaQuery.disableAnimationsOf(context) || _settings.inkMode
        ? Duration.zero
        : const Duration(milliseconds: 220),
    reverseTransitionDuration:
        MediaQuery.disableAnimationsOf(context) || _settings.inkMode
        ? Duration.zero
        : const Duration(milliseconds: 180),
    pageBuilder: (_, _, _) => _finishForm(session, review, rtl),
    transitionsBuilder: (context, animation, _, child) => SlideTransition(
      position: Tween(
        begin: Offset(rtl ? -1 : 1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );

  Widget _finishForm(ReaderSession session, BookReview? review, bool rtl) =>
      ReaderPanelTheme(
        theme: _pageTheme,
        child: FinishBookSheet(
          book:
              widget.book ??
              BookEntry(
                id: widget.bookId,
                title: widget.bookTitle,
                author: '',
                filePath: widget.sourcePath ?? '',
                addedAt: DateTime.now(),
              ),
          review: review,
          allowReview: widget.reviewStore != null,
          finished: session.progress?.finished ?? false,
          fullScreen: true,
          rtl: rtl,
          onCommit: (draft) => _finishBook(session, draft),
        ),
      );

  Future<void> _finishBook(
    ReaderSession session,
    FinishBookDraft? draft,
  ) async {
    final reviews = widget.reviewStore;
    final progress = widget.store;
    Future<void> saveReview() => reviews!.save(
      widget.bookId,
      rating: draft!.rating,
      content: draft.content,
    );
    if (draft != null && reviews != null && progress is DriftProgressStore) {
      await session.markFinished(
        saveWithReview: (value) =>
            progress.saveFinishedWithReview(widget.bookId, value, saveReview),
      );
    } else {
      await session.markFinished();
      if (draft != null && reviews != null) await saveReview();
    }
  }

  bool get _canEditBook =>
      widget.bookEditorRepository != null &&
      widget.sourcePath != null &&
      switch (defaultTargetPlatform) {
        TargetPlatform.macOS || TargetPlatform.windows => true,
        _ => false,
      };

  Future<void> _openEditor(ReaderEditTarget? target) async {
    if (!_canEditBook || _editorOpen) return;
    final repository = widget.bookEditorRepository;
    final path = widget.sourcePath;
    if (repository == null || path == null) return;
    _editorOpen = true;
    _syncReadingActivity();
    var contentUpdated = false;
    try {
      await _readerSession?.flushProgress();
      if (!mounted) return;
      final progress = _readerSession?.progress;
      final location =
          target ??
          (progress?.cfi == null
              ? null
              : ReaderEditTarget(
                  spineIndex: progress!.spineIndex,
                  cfi: progress.cfi!,
                  contentRevision: _contentRevision,
                ));
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => BookEditorRoute(
            repository: repository,
            bookId: widget.bookId,
            sourcePath: path,
            contentRevision: _contentRevision,
            title: widget.bookTitle,
            target: location,
            readingSettings: _settings,
            editInitialTarget: target != null,
          ),
        ),
      );
      if (saved == true && mounted) {
        contentUpdated = true;
        Navigator.of(context).pop(EpubReaderExit.contentUpdated);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('打开编辑器失败：$error')));
      }
    } finally {
      // 旧版本退出动画期间继续暂停统计；新会话就绪后自行恢复。
      if (!contentUpdated) {
        _editorOpen = false;
        if (mounted) _syncReadingActivity();
      }
    }
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

  // 背景封面可能没有正文锚点，进度为空不影响已经准备好的首屏。
  bool _hasPreparedFrame(ReaderSession? session) =>
      session != null && !session.loading && session.hasContent;

  void _syncReadingActivity() {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    final foreground =
        lifecycle == null || lifecycle == AppLifecycleState.resumed;
    if (_readable &&
        widget.readingActive &&
        foreground &&
        !_closing &&
        !_editorOpen &&
        !_finishPageOpen) {
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

/// 路径兼容与归档解压统一交给书籍资源，解压不再占用阅读界面线程。
Future<Uint8List?> _loadImageBytes(EpubChapterSource source, String url) =>
    source.readImageBytes(url);
