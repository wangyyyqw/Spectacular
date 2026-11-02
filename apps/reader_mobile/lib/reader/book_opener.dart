import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:reader_ui/reader_session.dart';

import '../diagnostics/reader_log.dart';
import '../library/library_store.dart';
import 'book_opening_view.dart';
import 'epub_reader_page.dart';
import 'reader_settings.dart';

/// 统一处理打开图书的读盘、转场、设置持久化与最近阅读更新时间。
class BookOpener {
  /// 创建打开器。
  BookOpener({required this.library, required this.progressStore});

  /// 书架存储。
  final LibraryStore library;

  /// 阅读进度存储。
  final ReaderProgressStore progressStore;

  ReaderSettings? _settings;
  bool _opening = false;

  /// 打开图书；重复点击期间忽略后续请求。
  Future<void> open(BuildContext context, BookEntry entry) async {
    if (_opening) {
      return;
    }
    _opening = true;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final minimumReveal = MediaQuery.maybeOf(context)?.disableAnimations ?? false
        ? Duration.zero
        : BookOpeningView.revealDuration;
    var openingVisible = false;
    void closeOpening() {
      if (!openingVisible) {
        return;
      }
      openingVisible = false;
      if (navigator.mounted) {
        navigator.pop();
      }
    }

    try {
      unawaited(
        navigator.push<void>(_openingRoute(entry)).then((_) {
          openingVisible = false;
        }),
      );
      openingVisible = true;
      _settings ??= await ReaderSettingsStore(library).load();
      if (!context.mounted || !openingVisible) {
        return;
      }
      final readWatch = Stopwatch()..start();
      final bytes = await library.readBytes(entry);
      readWatch.stop();
      unawaited(
        ReaderLog.instance.log(
          'user_open_book',
          fields: <String, Object?>{
            'book': entry.title,
            'bytes': bytes.length,
            'read_ms': readWatch.elapsedMilliseconds,
          },
        ),
      );
      // 小文件读盘几乎瞬时完成；等封面完整展开后再切入正文。
      final remaining = minimumReveal - readWatch.elapsed;
      if (remaining > Duration.zero) {
        await Future<void>.delayed(remaining);
      }
      if (!context.mounted || !openingVisible) {
        return;
      }
      await navigator.pushReplacement<void, void>(_readerRoute(entry, bytes));
      await library.touchLastRead(entry.id);
    } catch (error) {
      if (context.mounted) {
        closeOpening();
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(content: Text('打开《${entry.title}》失败：$error')),
        );
      }
    } finally {
      closeOpening();
      _opening = false;
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
    unawaited(ReaderSettingsStore(library).save(settings));
  }

  /// 开场页入场：从书架柔和淡入，随后由封面动画接管。
  Route<void> _openingRoute(BookEntry entry) {
    return PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, _, _) => BookOpeningView(book: entry),
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

  /// 阅读页入场：淡入、轻微放大和上浮，承接封面展开动画。
  Route<void> _readerRoute(BookEntry entry, Uint8List bytes) {
    return PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 360),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, _, _) => EpubReaderPage(
        bytes: bytes,
        bookId: entry.id,
        store: progressStore,
        bookmarks: library.bookmarkStore(entry.id),
        annotations: library.annotationStore(entry.id),
        settings: _settings ?? ReaderSettings.defaults,
        onSettingsChanged: _saveSettings,
        bookTitle: entry.title,
        onMarginsChanged: (margins) {
          final current = _settings ?? ReaderSettings.defaults;
          _saveSettings(current.copyWithMargins(margins));
        },
      ),
      transitionsBuilder: (_, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.018),
              end: Offset.zero,
            ).animate(curved),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.985, end: 1).animate(curved),
              alignment: Alignment.center,
              child: child,
            ),
          ),
        );
      },
    );
  }
}
