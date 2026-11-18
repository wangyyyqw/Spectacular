import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/paint/image_cache.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';

import '../reader/reader_settings.dart';
import '../reader/reader_background_store.dart';

/// 正式阅读引擎预览；所有翻页状态只写入本组件的内存存储。
class BookEditorPreview extends StatefulWidget {
  const BookEditorPreview({
    super.key,
    required this.source,
    required this.revision,
    required this.onEditTarget,
    this.target,
    this.settings,
    this.onLocationChanged,
    this.navigation = 0,
    this.onSessionReady,
    this.bookTitle = '点击段落编辑原文',
  });
  final EpubChapterSource source;
  final int revision;
  final ReaderEditTarget? target;
  final ValueChanged<ReaderEditTarget> onEditTarget;
  final ReaderSettings? settings;
  final ValueChanged<ReaderEditTarget>? onLocationChanged;
  final int navigation;
  final ValueChanged<ReaderSession>? onSessionReady;
  final String bookTitle;

  @override
  State<BookEditorPreview> createState() => _BookEditorPreviewState();
}

class _BookEditorPreviewState extends State<BookEditorPreview> {
  final _progress = MemoryReaderProgressStore();
  final _backgrounds = ReaderBackgroundStore();
  ReaderSession? _session;
  late final _images = DecodedImageCache(
    maxEntries: 12,
    maxBytes: 24 << 20,
    loadBytes: widget.source.readImageBytes,
  );

  void _ready(ReaderSession session) {
    _session?.removeListener(_rememberLocation);
    _session = session;
    widget.onSessionReady?.call(session);
    session.addListener(_rememberLocation);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {});
      if (widget.target case final target?) {
        unawaited(session.jumpToCfi(target.cfi));
      }
    });
  }

  void _rememberLocation() {
    final progress = _session?.progress;
    if (progress?.cfi case final cfi?) {
      widget.onLocationChanged?.call(
        ReaderEditTarget(spineIndex: progress!.spineIndex, cfi: cfi),
      );
    }
  }

  @override
  void didUpdateWidget(covariant BookEditorPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.navigation == oldWidget.navigation) return;
    final target = widget.target;
    final session = _session;
    if (target != null && session != null) {
      unawaited(session.jumpToCfi(target.cfi));
    }
  }

  @override
  void dispose() {
    _session?.removeListener(_rememberLocation);
    _images.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(child: _PreviewPhone(child: _reader())),
      _pageControls(),
    ],
  );

  Widget _reader() => ReaderPage(
    key: ValueKey('edit-reader-${widget.revision}'),
    source: widget.source,
    store: _progress,
    bookId: 'editor-preview',
    contentRevision: 'editor-${widget.revision}',
    imageCache: _images,
    overrides: widget.settings?.overrides ?? const ReaderOverrides(),
    theme: widget.settings?.theme,
    margins: widget.settings?.margins,
    backgroundId: widget.settings?.backgroundId ?? 'none',
    backgroundImageLoader: _backgrounds.load,
    inkMode: widget.settings?.inkMode ?? false,
    bookTitle: widget.bookTitle,
    editMode: true,
    onEditTarget: widget.onEditTarget,
    onSessionReady: _ready,
    pageTurnMode: PageTurnMode.slideHorizontal,
    showPageFooter: false,
  );

  Widget _pageControls() {
    final session = _session;
    if (session == null) return const SizedBox(height: 40);
    return SizedBox(
      height: 40,
      child: ListenableBuilder(
        listenable: session,
        builder: (_, _) => _pagingRow(session),
      ),
    );
  }

  Widget _pagingRow(ReaderSession session) {
    final page = session.page;
    final ready = page != null && !session.loading;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: '上一页',
          onPressed: ready && (page.spineIndex > 0 || page.pageIndex > 0)
              ? () => unawaited(session.previous())
              : null,
          icon: const AppIcon(AppGlyph.chevronLeft, size: 20),
        ),
        Flexible(
          child: Text(
            page == null
                ? '正在排版…'
                : '第 ${page.spineIndex + 1} 章 · ${session.pageLabelOf(page)}',
            key: const ValueKey('editor-preview-page'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        IconButton(
          tooltip: '下一页',
          onPressed: ready ? () => unawaited(session.next()) : null,
          icon: const AppIcon(AppGlyph.chevronRight, size: 20),
        ),
      ],
    );
  }
}

class _PreviewPhone extends StatelessWidget {
  const _PreviewPhone({required this.child});

  final Widget child;
  static const _screenSize = Size(360, 800);
  static const _safeInsets = EdgeInsets.only(top: 24, bottom: 16);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      minimum: const EdgeInsets.all(8),
      child: FittedBox(
        fit: BoxFit.contain,
        child: Container(
          key: const ValueKey('editor-phone-frame'),
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 12),
          decoration: BoxDecoration(
            color: colors.inverseSurface,
            border: Border.all(color: colors.outline),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _hardware(colors),
              const SizedBox(height: 7),
              _screen(context),
              const SizedBox(height: 8),
              _bar(88, colors),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hardware(ColorScheme colors) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _bar(32, colors),
      const SizedBox(width: 6),
      Container(
        width: 4,
        height: 4,
        decoration: BoxDecoration(
          color: colors.outline,
          shape: BoxShape.circle,
        ),
      ),
    ],
  );

  Widget _bar(double width, ColorScheme colors) => Container(
    width: width,
    height: 3,
    decoration: BoxDecoration(
      color: colors.outline,
      borderRadius: BorderRadius.circular(2),
    ),
  );

  Widget _screen(BuildContext context) => SizedBox.fromSize(
    size: _screenSize,
    child: MediaQuery(
      data: MediaQuery.of(context).copyWith(
        size: _screenSize,
        devicePixelRatio: 3,
        padding: _safeInsets,
        viewPadding: _safeInsets,
        viewInsets: EdgeInsets.zero,
        systemGestureInsets: EdgeInsets.zero,
        displayFeatures: const [],
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(18), child: child),
    ),
  );
}
