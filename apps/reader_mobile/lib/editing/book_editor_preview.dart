import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/paint/image_cache.dart';
import 'package:reader_core/css/reader_overrides.dart';
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
  });
  final EpubChapterSource source;
  final int revision;
  final ReaderEditTarget? target;
  final ValueChanged<ReaderEditTarget> onEditTarget;
  final ReaderSettings? settings;
  final ValueChanged<ReaderEditTarget>? onLocationChanged;

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
    _session = session;
    session.addListener(_rememberLocation);
    final target = widget.target;
    if (target == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(session.jumpToCfi(target.cfi));
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
  void dispose() {
    _session?.removeListener(_rememberLocation);
    _images.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ReaderPage(
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
    bookTitle: '点击段落编辑原文',
    editMode: true,
    onEditTarget: widget.onEditTarget,
    onSessionReady: _ready,
    pageTurnMode: PageTurnMode.scroll,
    showPageFooter: false,
  );
}
