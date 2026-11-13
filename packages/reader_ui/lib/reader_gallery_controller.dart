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
          onPreview: _canPreviewGallery(region.gallery)
              ? () => unawaited(_previewGallery(region.gallery))
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
      unawaited(_previewGallery(gallery));
      return true;
    }
    return false;
  }

  Future<void> _previewGallery(PageGallery gallery) async {
    if (gallery.frames.isEmpty) return;
    final cache = widget.imageCache;
    final url = gallery.frames[_galleryFrameOf(gallery)].imageUrl;
    if (cache == null || url == null || !mounted) return;
    // 缩略图克隆句柄与独立原图缓存由本次预览释放，不受正文 LRU 淘汰影响。
    final thumbnail = cache.lookup(url)?.clone();
    final originals = DecodedImageCache(
      loadBytes: cache.loadBytes,
      maxEntries: 1,
    );
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ImagePreviewPage(
            thumbnail: thumbnail,
            loadOriginal: () => originals.load(
              url,
              displayWidth: gallery.width,
              fullResolution: true,
            ),
          ),
        ),
      );
    } finally {
      originals.clear();
      thumbnail?.dispose();
    }
  }
}
