import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:reader_ui/reader_session.dart';

import '../diagnostics/reader_log.dart';
import '../library/library_store.dart';
import 'book_opening_reader.dart';
import 'epub_reader_page.dart';
import 'reader_settings.dart';
import 'reader_background_store.dart';
import 'reader_decoration_image_store.dart';
import 'reader_font_store.dart';

/// 统一处理打开图书的读盘、转场、设置持久化与最近阅读更新时间。
class BookOpener {
  /// 创建打开器。
  BookOpener({required this.library, required this.progressStore});

  /// 书架存储。
  final LibraryStore library;

  /// 阅读进度存储。
  final ReaderProgressStore progressStore;

  ReaderSettings? _settings;
  Future<void> _settingsSave = Future<void>.value();
  bool _opening = false;

  /// 打开图书；重复点击期间忽略后续请求。
  Future<void> open(BuildContext context, BookEntry entry) async {
    if (_opening) {
      return;
    }
    _opening = true;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final opening = _prepareOpening(entry);
      final route = _readerRoute(entry, opening);
      await navigator.push<void>(route);
      opening.cancelled = true;
      await route.completed;
      if (opening.created) await opening.closed.future;
      if (opening.revealed) await library.touchLastRead(entry.id);
    } catch (error) {
      if (context.mounted) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(content: Text('打开《${entry.title}》失败：$error')),
        );
      }
    } finally {
      _opening = false;
    }
  }

  _OpeningPreparation _prepareOpening(BookEntry entry) {
    final settings = _loadSettings();
    // 文件由阅读页直接打开；内存库只读一次，共享给源和版本摘要。
    final bytes = entry.filePath.isEmpty ? library.readBytes(entry) : null;
    final opening = _OpeningPreparation(bytes, settings);
    final revision = opening.revision = _loadContentRevision(
      entry,
      bytes,
      isCancelled: () => opening.cancelled,
    );
    // 路由可能在首帧前取消，仍接住准备任务的异常。
    settings.ignore();
    bytes?.ignore();
    revision.ignore();
    unawaited(_logRead(entry, bytes));
    return opening;
  }

  Future<ReaderSettings> _loadSettings() async =>
      _settings ??= await ReaderSettingsStore(library).load();

  Future<String> _loadContentRevision(
    BookEntry entry,
    Future<Uint8List>? bytes, {
    required bool Function() isCancelled,
  }) async {
    var known = entry.contentRevision;
    if (known == null || known.isEmpty) {
      final stored = await library.bookById(entry.id);
      if (stored?.filePath == entry.filePath) known = stored?.contentRevision;
    }
    if (known != null && known.isNotEmpty) return known;
    if (isCancelled()) throw StateError('打开已取消');
    final revision = bytes == null
        ? (await sha256
                  .bind(
                    File(entry.filePath)
                        .openRead()
                        .takeWhile((_) => !isCancelled()),
                  )
                  .first)
              .toString()
        : await _hashBytes(bytes, isCancelled);
    // 中途返回会取消文件流；部分摘要绝不能绑定 CFI 或写成原书版本。
    if (isCancelled()) throw StateError('打开已取消');
    try {
      await library.rememberContentRevision(entry.id, revision);
    } catch (_) {
      // 补写失败不影响本次版本校验，下次打开再补写。
    }
    return revision;
  }

  Future<String> _hashBytes(
    Future<Uint8List> bytes,
    bool Function() isCancelled,
  ) async {
    final payload = await bytes;
    if (isCancelled()) throw StateError('打开已取消');
    return compute(_revisionOfBytes, payload);
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
          'book': entry.title,
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
            fields: {'error': '$error'},
          );
        });
  }

  /// 封面和阅读页共用路由，准备任务与开场动画同时开始。
  /// 设置和存储参数集中桥接，保持服务身份稳定，避免揭开封面触发重复装饰准备。
  PageRoute<void> _readerRoute(BookEntry entry, _OpeningPreparation opening) {
    final readerBuilder = _readerBuilder(entry, opening);
    return PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 220),
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
    final fontStore = ReaderFontStore(library);
    return (onReady, readingActive) => EpubReaderPage(
      bytesFuture: opening.bytes,
      sourcePath: entry.filePath.isEmpty ? null : entry.filePath,
      bookId: entry.id,
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
      bookTitle: entry.title,
      contentRevisionFuture: opening.revision,
      contentRevision: entry.contentRevision,
      readingActive: readingActive,
      onReady: onReady,
      onClosed: opening.finishClose,
    );
  }
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

String _revisionOfBytes(Uint8List bytes) => sha256.convert(bytes).toString();
