part of 'reader_page.dart';

/// 只保留近期画廊的帧序号；不持有章节、解码图或永久阅读位置。
extension _ReaderGalleryController on _ReaderPageState {
  int _galleryFrameOf(PageGallery gallery) {
    if (gallery.frames.isEmpty) return 0;
    final anchor = _session.readingCfi;
    final selected = _gallerySelections[gallery.cfi];
    if (selected != null &&
        selected.anchor == anchor &&
        selected.generation == _session.generation) {
      return selected.index.clamp(0, gallery.frames.length - 1);
    }
    return gallery.frameIndexForCfi(anchor) ??
        (selected?.index ?? 0).clamp(0, gallery.frames.length - 1);
  }

  void _rememberGalleryFrame(PageGallery gallery, int index) {
    _gallerySelections.remove(gallery.cfi);
    _gallerySelections[gallery.cfi] = (
      index: index,
      anchor: _session.readingCfi,
      generation: _session.generation,
    );
    if (_gallerySelections.length > 64) {
      _gallerySelections.remove(_gallerySelections.keys.first);
    }
  }

  /// 同页 CFI 跳转也更新绘制器，使纸面和已预热快照显示同一帧。
  void _syncGalleryFrames(PageContent page) {
    var changed = false;
    for (final region in galleryRegionsOf(page)) {
      final gallery = region.gallery;
      final selected = _gallerySelections[gallery.cfi];
      final index = _galleryFrameOf(gallery);
      if (index != (selected?.index ?? 0)) changed = true;
      _rememberGalleryFrame(gallery, index);
    }
    if (changed) _painter = _buildPainter();
  }

  void _selectGalleryFrame(PageContent page, PageGallery gallery, int index) {
    if (index == _galleryFrameOf(gallery) ||
        _pageTurnKey.currentState?.controller.active == true) {
      return;
    }
    _clearSelection();
    _changeReaderState(() {
      _rememberGalleryFrame(gallery, index);
      // 新绘制器身份同时使翻页快照失效，避免回翻时恢复旧帧画面。
      _painter = _buildPainter();
    });
    unawaited(_prefetchPageImages(page, _paperContentWidth));
  }

  void _setGalleryPosition(PageGallery gallery, double? position) {
    if (!mounted || _galleryPositions[gallery.cfi] == position) return;
    if (position == null) {
      _galleryPositions.remove(gallery.cfi);
      // 松手后使翻页快照失效，不保留拖动过程中的半帧画面。
      _changeReaderState(() => _painter = _buildPainter());
    } else {
      _galleryPositions[gallery.cfi] = position;
    }
    _galleryRepaint.value++;
  }

  List<Widget> _galleryLayers(
    PageContent page, {
    EdgeInsets padding = EdgeInsets.zero,
  }) => [
    for (final region in galleryRegionsOf(page))
      Positioned(
        left: padding.left + region.rect.left,
        top: padding.top + region.rect.top,
        width: region.rect.width,
        height: region.rect.height,
        child: ReaderGalleryControls(
          key: ValueKey('gallery-${region.gallery.cfi}'),
          gallery: region.gallery,
          index: _galleryFrameOf(region.gallery),
          foreground:
              _effectiveTheme?.text ?? Theme.of(context).colorScheme.onSurface,
          onChanged: (index) =>
              _selectGalleryFrame(page, region.gallery, index),
          onPositionChanged: (position) =>
              _setGalleryPosition(region.gallery, position),
          animate: !_inkMode,
          onPreview: _canPreviewGallery(region.gallery)
              ? () => unawaited(_previewGallery(page, region.gallery))
              : null,
        ),
      ),
  ];

  bool _canPreviewGallery(PageGallery gallery) =>
      widget.imageCache != null &&
      gallery.frames.isNotEmpty &&
      gallery.frames[_galleryFrameOf(gallery)].imageUrl != null;

  bool _handleGalleryTap(PageContent page, Offset position) {
    for (final region in galleryRegionsOf(page)) {
      final gallery = region.gallery;
      if (!_canPreviewGallery(gallery)) continue;
      final imageRect = galleryImageRectOf(
        gallery,
        _galleryFrameOf(gallery),
        contentOrigin: region.rect.topLeft,
        containingWidth: _paperContentWidth,
      );
      if (imageRect == null || !imageRect.contains(position)) continue;
      _clearSelection();
      unawaited(_previewGallery(page, gallery));
      return true;
    }
    return false;
  }

  Future<void> _previewGallery(PageContent page, PageGallery gallery) async {
    if (gallery.frames.isEmpty) return;
    final cache = widget.imageCache;
    if (cache == null || !mounted) return;
    var index = _galleryFrameOf(gallery);
    final generation = _session.generation;
    final originals = DecodedImageCache(
      loadBytes: cache.loadBytes,
      maxEntries: 1,
    );
    final items = _galleryPreviewItems(gallery, cache, originals);
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ImagePreviewPage.gallery(
            items: items,
            initialIndex: index,
            animate: !_inkMode,
            onChanged: (selected) {
              index = selected;
              // 旧请求失效，当前帧由预览克隆持有；不在原图缓存里累积帧。
              originals.clear();
            },
          ),
        ),
      );
    } finally {
      originals.clear();
    }
    if (mounted && _session.generation == generation) {
      _selectGalleryFrame(page, gallery, index);
    }
  }

  List<ImagePreviewItem> _galleryPreviewItems(
    PageGallery gallery,
    DecodedImageCache thumbnails,
    DecodedImageCache originals,
  ) => [
    for (final frame in gallery.frames)
      ImagePreviewItem(
        thumbnail: () =>
            frame.imageUrl == null ? null : thumbnails.lookup(frame.imageUrl!),
        loadThumbnail: () async => frame.imageUrl == null
            ? null
            : thumbnails.load(frame.imageUrl!, displayWidth: gallery.width),
        loadOriginal: () async => frame.imageUrl == null
            ? null
            : originals.load(
                frame.imageUrl!,
                displayWidth: gallery.width,
                fullResolution: true,
              ),
      ),
  ];
}
