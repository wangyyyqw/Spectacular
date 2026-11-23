import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/source/chapter_source.dart'
    show ChapterLoadCancelled;
import 'package:reader_ui/reader_session.dart';

import '../book_source/book_source_models.dart';
import '../book_source/online_book_controller.dart';
import '../book_source/online_reading_book.dart';
import '../book_source/online_reading_catalog_store.dart';
import '../diagnostics/reader_log.dart';
import '../dictionary/dictionary_store.dart';
import '../library/library_store.dart';
import '../editing/book_edit_repository.dart';
import '../rea_micro/rea_micro_models.dart';
import 'book_opening_reader.dart';
import 'epub_reader_page.dart';
import 'reader_settings.dart';
import 'reader_background_store.dart';
import 'reader_decoration_image_store.dart';
import 'reader_font_store.dart';

/// 统一处理打开图书的读盘、转场、设置持久化与最近阅读更新时间。
class BookOpener {
  /// 创建打开器。
  BookOpener({
    required this.library,
    required this.progressStore,
    this.onlineBooks,
    this.onReadingFinished,
    this.loadTtsVoices,
  });

  /// 书架存储。
  final LibraryStore library;

  /// 阅读进度存储。
  final ReaderProgressStore progressStore;

  /// 已同步或导入的按需 EPUB 通过原书架身份进入在线阅读。
  final OnlineBookController? onlineBooks;

  /// 阅读会话落盘并关闭阅读页后通知宿主，供后台同步使用。
  final VoidCallback? onReadingFinished;

  /// 读取阅微远端离线音色目录。
  final Future<List<ReaMicroTtsVoice>> Function()? loadTtsVoices;

  ReaderSettings? _settings;
  Future<void> _settingsSave = Future<void>.value();
  bool _opening = false;

  /// 以目录和单章正文加载器进入常规阅读页。
  Future<void> openOnline(
    BuildContext context,
    OnlineReadingBook book, {
    int? startChapter,
  }) async {
    if (_opening) return;
    _opening = true;
    try {
      if (!context.mounted) return;
      await _openOnlineReader(
        Navigator.of(context),
        Future.value(book),
        bookId: book.id,
        title: book.book.name,
        startChapter: startChapter,
      );
    } finally {
      _opening = false;
    }
  }

  /// 打开图书；重复点击期间忽略后续请求。
  Future<void> open(BuildContext context, BookEntry entry) async {
    if (_opening) {
      return;
    }
    _opening = true;
    final navigator = Navigator.of(context);
    try {
      var current = entry;
      while (context.mounted) {
        final controller = onlineBooks;
        final online = controller == null
            ? null
            : await controller.prepareImportedReading(current, progressStore);
        if (!context.mounted) break;
        if (online != null) {
          await _openOnlineReader(
            navigator,
            online.book,
            bookId: current.id,
            title: current.title,
            entry: current,
          );
          break;
        }
        final result = await _openReader(navigator, current);
        if (result != EpubReaderExit.contentUpdated || !context.mounted) break;
        final updated = await library.bookById(current.id);
        if (updated == null) throw StateError('保存后的书籍已不在书库中');
        current = updated;
      }
    } catch (error, stackTrace) {
      recordAppError('book_open_failed', error, stackTrace: stackTrace);
      if (error is BookSourceException && context.mounted) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      _opening = false;
    }
  }

  Future<void> _openOnlineReader(
    NavigatorState navigator,
    Future<OnlineReadingBook> reading, {
    required String bookId,
    required String title,
    BookEntry? entry,
    int? startChapter,
  }) async {
    final closed = Completer<void>();
    var created = false;
    var ready = false;
    var cancelled = false;
    var sourceCreated = false;
    final cancellation = entry == null ? null : Completer<OnlineReadingBook>();
    final remembered = reading.then((book) async {
      if (cancelled) throw const ChapterLoadCancelled();
      await OnlineReadingCatalogStore(library).remember(
        book.source,
        book.book,
        book.chapters,
        preserveSavedCatalog: true,
      );
      if (cancelled) throw const ChapterLoadCancelled();
      return book;
    });
    remembered.ignore();
    final prepared = cancellation == null
        ? remembered
        : Future.any<OnlineReadingBook>([remembered, cancellation.future]);
    prepared.ignore();
    final progressReady = prepared.then<ReaderProgressStore>(
      (book) =>
          OnlineReadingProgress(library, book, startChapter: startChapter),
    );
    // 目录失败时尚未创建 ReaderSession，派生存储也需立即接住异常。
    progressReady.ignore();
    final store = _DeferredOnlineProgress(progressReady);
    final fontStore = ReaderFontStore(library);
    final settings = _loadSettings()..ignore();
    final revision = prepared.then((book) => book.revision)..ignore();
    Future<EpubChapterSource>? source;
    final route = _OnlineReaderRoute(
      builder: (_) {
        created = true;
        return EpubReaderPage(
          dictionaryStore: DictionaryStore(library),
          onlineReading: prepared,
          sourceFuture: source ??= prepared.then((book) {
            if (cancelled) throw const ChapterLoadCancelled();
            final openedSource = book.open();
            sourceCreated = true;
            return openedSource;
          })..ignore(),
          bookId: bookId,
          bookTitle: title,
          book: entry,
          contentRevisionFuture: revision,
          store: store,
          readingSessions: entry == null ? null : library.readingSessionStore(),
          reviewStore: entry == null ? null : library.reviewStore(),
          settingsFuture: settings,
          fontStore: fontStore,
          onSettingsChanged: _saveSettings,
          loadTtsVoices: loadTtsVoices,
          enableFullTextSearch: false,
          persistInitialPosition: startChapter != null,
          onReady: () => ready = !cancelled && sourceCreated,
          onClosed: () {
            if (!closed.isCompleted) closed.complete();
          },
        );
      },
    );
    try {
      await navigator.push(route);
    } finally {
      if (cancellation != null) {
        // 先结束页面的目录等待，再按原关闭链路保存数据并释放源。
        cancelled = true;
        if (!cancellation.isCompleted) {
          cancellation.completeError(const ChapterLoadCancelled());
        }
      }
    }
    await route.completed;
    if (created) await closed.future;
    if (entry != null) {
      if (created) onReadingFinished?.call();
      if (ready) await library.touchLastRead(entry.id);
    }
  }

  Future<EpubReaderExit?> _openReader(
    NavigatorState navigator,
    BookEntry entry,
  ) async {
    final opening = _prepareOpening(entry);
    final route = _readerRoute(entry, opening);
    final result = await navigator.push<EpubReaderExit>(route);
    opening.cancelled = true;
    await route.completed;
    // 旧进度落盘及章节源释放完毕，才能为新修订绑定源并恢复位置。
    if (opening.created) await opening.closed.future;
    if (opening.created) onReadingFinished?.call();
    if (opening.revealed) await library.touchLastRead(entry.id);
    return result;
  }

  _OpeningPreparation _prepareOpening(BookEntry entry) {
    final settings = _loadSettings();
    // 文件由阅读页直接打开；内存库只读一次，共享给源和版本摘要。
    final bytes = entry.filePath.isEmpty ? library.readBytes(entry) : null;
    final opening = _OpeningPreparation(bytes, settings);
    final revision = opening.revision = _loadContentRevision(
      entry,
      isCancelled: () => opening.cancelled,
    );
    // 路由可能在首帧前取消，仍接住准备任务的异常。
    settings.ignore();
    bytes?.ignore();
    revision.ignore();
    unawaited(_logRead(entry, bytes));
    return opening;
  }

  Future<ReaderSettings> _loadSettings() async {
    // 外观页可修改全局阅读偏好，每次打开重新读取，保存队列先完成。
    await _settingsSave;
    return _settings = await ReaderSettingsStore(library).load();
  }

  Future<String> _loadContentRevision(
    BookEntry entry, {
    required bool Function() isCancelled,
  }) async {
    var known = entry.contentRevision;
    if (known == null || known.isEmpty) {
      final stored = await library.bookById(entry.id);
      if (stored?.filePath == entry.filePath) known = stored?.contentRevision;
    }
    if (known != null && known.isNotEmpty) return known;
    if (isCancelled()) throw StateError('打开已取消');
    throw StateError('书籍内容版本缺失，请重新导入书籍');
  }

  Future<void> _logRead(BookEntry entry, Future<Uint8List>? bytes) async {
    final watch = Stopwatch()..start();
    try {
      final length = bytes == null
          ? await File(entry.filePath).length()
          : (await bytes).length;
      await ReaderLog.instance.log(
        'user_open_book',
        fields: {
          'book_id': entry.id,
          'bytes': length,
          'source': bytes == null ? 'file' : 'memory',
          'read_ms': watch.elapsedMilliseconds,
        },
      );
    } catch (_) {
      // 来源失败由阅读页展示，不让诊断任务影响路由生命周期。
    }
  }

  void _saveSettings(ReaderSettings settings) {
    _settings = settings;
    unawaited(
      ReaderLog.instance.log(
        'user_settings',
        fields: <String, Object?>{
          'font_size': settings.fontSize,
          'line_height': settings.lineHeight,
          'paragraph_spacing': settings.paragraphSpacing,
          'theme': settings.themeId,
          'background': settings.backgroundId,
          'ink_mode': settings.inkMode,
        },
      ),
    );
    _settingsSave = _settingsSave
        .then((_) async {
          await ReaderSettingsStore(library).save(settings);
          await ReaderBackgroundStore().cleanUnused(
            settings.backgroundId,
            pendingId: _settings!.backgroundId,
          );
        })
        .catchError((Object error) async {
          await ReaderLog.instance.log(
            'settings_save_error',
            fields: {'error': error},
          );
        });
  }

  /// 封面和阅读页共用路由，准备任务与开场动画同时开始。
  /// 设置和存储参数集中桥接，保持服务身份稳定，避免揭开封面触发重复装饰准备。
  PageRoute<EpubReaderExit> _readerRoute(
    BookEntry entry,
    _OpeningPreparation opening,
  ) {
    final readerBuilder = _readerBuilder(entry, opening);
    return PageRouteBuilder<EpubReaderExit>(
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, _, _) {
        opening.created = true;
        return BookOpeningReader(
          book: entry,
          onRevealed: () => opening.revealed = true,
          readerBuilder: readerBuilder,
        );
      },
      transitionsBuilder: (_, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(opacity: curved, child: child);
      },
    );
  }

  Widget Function(VoidCallback, bool) _readerBuilder(
    BookEntry entry,
    _OpeningPreparation opening,
  ) {
    final decorationImages = ReaderDecorationImages();
    final bookmarks = library.bookmarkStore(entry.id);
    final annotations = library.annotationStore(entry.id);
    final decorations = library.decorationStore(
      entry.id,
      images: decorationImages,
    );
    final decorationRules = library.decorationRuleStore(entry.id);
    final readingSessions = library.readingSessionStore();
    final reviews = library.reviewStore();
    final fontStore = ReaderFontStore(library);
    return (onReady, readingActive) => EpubReaderPage(
      dictionaryStore: DictionaryStore(library),
      bytesFuture: opening.bytes,
      sourcePath: entry.filePath.isEmpty ? null : entry.filePath,
      bookId: entry.id,
      bookEditorRepository: BookEditRepository(library),
      store: progressStore,
      bookmarks: bookmarks,
      annotations: annotations,
      decorations: decorations,
      decorationRules: decorationRules,
      decorationImages: decorationImages,
      readingSessions: readingSessions,
      settingsFuture: opening.settings,
      fontStore: fontStore,
      onSettingsChanged: _saveSettings,
      loadTtsVoices: loadTtsVoices,
      bookTitle: entry.title,
      contentRevisionFuture: opening.revision,
      contentRevision: entry.contentRevision,
      readingActive: readingActive,
      onReady: onReady,
      onClosed: opening.finishClose,
      book: entry,
      reviewStore: reviews,
    );
  }
}

/// 在线阅读沿用平台入场动画，退出时直接交回原页面。
class _OnlineReaderRoute extends MaterialPageRoute<void> {
  _OnlineReaderRoute({required super.builder});

  @override
  Duration get reverseTransitionDuration => Duration.zero;
}

/// 目录仍在加载时先显示常规阅读页，位置读写等待同一份在线目录快照。
class _DeferredOnlineProgress implements ReaderProgressStore {
  const _DeferredOnlineProgress(this.store);

  final Future<ReaderProgressStore> store;

  @override
  Future<ReaderProgress?> load(String bookId) async =>
      (await store).load(bookId);

  @override
  Future<void> save(String bookId, ReaderProgress progress) async =>
      (await store).save(bookId, progress);

  @override
  Future<void> clear(String bookId) async => (await store).clear(bookId);

  @override
  Future<Map<String, ReaderProgress>> snapshot() async =>
      (await store).snapshot();
}

class _OpeningPreparation {
  _OpeningPreparation(this.bytes, this.settings);

  final Future<Uint8List>? bytes;
  final Future<ReaderSettings> settings;
  late final Future<String> revision;
  final closed = Completer<void>();
  bool created = false;
  bool revealed = false;
  bool cancelled = false;

  void finishClose() {
    if (!closed.isCompleted) closed.complete();
  }
}
