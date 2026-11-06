part of 'reader_page.dart';

extension _ReaderDecorationController on _ReaderPageState {
  bool get _hasEnabledDecorationRules =>
      ReaderDecorationRuleEngine.orderedRules(
        groups: _decorationGroups,
        rules: _decorationRules,
        bookId: widget.bookId,
      ).isNotEmpty;

  List<ReaderDecoration> get _orderedManualDecorations =>
      List.of(_resolvedDecorations)
        ..sort((left, right) => left.createdAt.compareTo(right.createdAt));

  List<ReaderTextOverlay> get _textOverlays => [
    for (final matches in _chapterRuleMatches.values)
      for (final match in matches)
        ReaderTextOverlay(
          startCfi: match.startCfi,
          endCfi: match.endCfi,
          color: match.style.color,
        ),
    for (final decoration in _orderedManualDecorations)
      _manualTextOverlay(decoration),
    for (final annotation in _resolvedAnnotations)
      if (annotation.style == ReaderAnnotationStyle.tint)
        ReaderTextOverlay(
          startCfi: annotation.startCfi,
          endCfi: annotation.endCfi,
          color: annotation.color ?? defaultHighlightColor,
          colorOpacity: annotation.effectiveOpacity,
        ),
  ];

  ReaderTextOverlay _manualTextOverlay(ReaderDecoration decoration) {
    final style = decoration.style;
    return ReaderTextOverlay(
      startCfi: decoration.startCfi,
      endCfi: decoration.endCfi,
      fontFamily: _unavailableDecorationFonts.contains(style.fontFamily)
          ? null
          : style.fontFamily,
      fontSizeScale: style.fontSizeScale,
      fontWeight: style.fontWeight,
      italic: style.italic,
      letterSpacingEm: style.letterSpacingEm,
      color: style.color,
    );
  }

  List<ReaderDecorationRange> _decorationRangesFor(PageContent page) => [
    for (final match
        in _chapterRuleMatches[page.spineIndex] ??
            const <ReaderDecorationRuleMatch>[])
      ReaderDecorationRange(
        startCfi: match.startCfi,
        endCfi: match.endCfi,
        style: match.style.decorationStyle,
      ),
    for (final decoration in _orderedManualDecorations)
      ReaderDecorationRange(
        startCfi: decoration.startCfi,
        endCfi: decoration.endCfi,
        style: decoration.style,
      ),
  ];

  void _paintDecorationsBeforeText(
    Canvas canvas,
    PageContent page,
    PageBlockSlice slice,
  ) {
    final ranges = _decorationRangesFor(page);
    for (final box in ReaderDecorationGeometry.boxesFor(
      page,
      ranges,
      slice: slice,
    )) {
      for (final rect in box.rects) {
        ReaderDecorationPainter.paintBox(
          canvas,
          rect,
          box.style,
          image: _decorationImages[box.style.backgroundImagePath],
          inkMode: _inkMode,
        );
      }
    }
    if (!_inkMode) {
      ReaderAnnotationPainting.paintBackgrounds(
        canvas,
        page,
        [..._resolvedAnnotations, ?_tempHighlight],
        _markSettings,
        slice: slice,
      );
    }
  }

  bool _currentDecorationRequest(int generation) =>
      mounted && generation == _decorationGeneration;

  Future<bool> _reloadDecorations() async {
    final generation = ++_decorationGeneration;
    _decorationLoading = true;
    final anchor = _session.currentCfi;
    try {
      if (!await _readDecorationStores(generation)) return false;
      if (!await _verifyManualDecorations(generation)) return false;
      await _loadDecorationFonts(generation);
      if (!_currentDecorationRequest(generation)) return false;
      final source = widget.source;
      final changed =
          source is ReaderTextOverlaySource &&
          await (source as ReaderTextOverlaySource).applyTextOverlays(
            _textOverlays,
          );
      final restored = await _restoreDecorationPosition(
        changed,
        anchor,
        generation,
      );
      if (!_currentDecorationRequest(generation)) return false;
      await _prepareDecorationChapter(generation: generation);
      await _loadDecorationImages(generation);
      return restored;
    } catch (error) {
      if (_currentDecorationRequest(generation)) {
        _showToast(error is FormatException ? error.message : '装饰读取失败，请重试');
      }
      return false;
    } finally {
      if (_currentDecorationRequest(generation)) {
        _changeReaderState(() => _decorationLoading = false);
      }
    }
  }

  Future<bool> _readDecorationStores(int generation) async {
    final items =
        await widget.decorations?.list() ?? const <ReaderDecoration>[];
    final groups =
        await widget.decorationRules?.listGroups() ??
        const <ReaderDecorationRuleGroup>[];
    final rules =
        await widget.decorationRules?.listRules() ??
        const <ReaderDecorationRule>[];
    if (!_currentDecorationRequest(generation)) return false;
    _changeReaderState(() {
      _decorations = items;
      _decorationGroups = groups;
      _decorationRules = rules;
      _resolvedDecorations = const [];
      _chapterRuleMatches.clear();
      _decorationScheduledChapters.clear();
    });
    return true;
  }

  Future<bool> _verifyManualDecorations(int generation) async {
    final chapters = <int, List<ReaderDecoration>>{};
    for (final decoration in _decorations) {
      if (decoration.needsRelocation) continue;
      final cfi = EpubCfi.parse(decoration.startCfi);
      final spine = cfi == null ? null : spineIndexOfCfi(cfi);
      if (spine != null && spine >= 0 && spine < widget.source.chapterCount) {
        (chapters[spine] ??= []).add(decoration);
      }
    }
    final verified = <ReaderDecoration>[];
    for (final entry in chapters.entries) {
      final pages = await widget.source.loadChapter(entry.key);
      if (!_currentDecorationRequest(generation)) return false;
      verified.addAll(
        ReaderDecorationRelocator.resolve(
          decorations: entry.value,
          pages: pages,
          contentRevision: widget.contentRevision,
        ),
      );
    }
    _changeReaderState(() => _resolvedDecorations = verified);
    return true;
  }

  Future<bool> _restoreDecorationPosition(
    bool changed,
    String? cfi,
    int generation,
  ) async {
    if (!changed) return true;
    await _initialOpen;
    if (!_currentDecorationRequest(generation) || _session.page == null) {
      return false;
    }
    final anchor = cfi ?? _session.currentCfi;
    _paragraphCache.clear();
    final restored = await _session.refreshLayout(anchorCfi: anchor);
    if (!_currentDecorationRequest(generation) || !restored || anchor == null) {
      return restored;
    }
    await _session.jumpToCfi(
      anchor,
      continuous: _effectiveTurnMode == PageTurnMode.scroll,
    );
    return _currentDecorationRequest(generation) &&
        _currentPageContainsCfi(anchor);
  }

  bool _currentPageContainsCfi(String cfi) {
    final page = _session.page;
    if (page == null) return false;
    final offset = cfiCharOffset(cfi) ?? 0;
    return ReaderTextRangeGeometry.linesFor(
      page,
      startCfi: cfi,
      endCfi: cfiWithCharOffset(cfi, offset + 1),
    ).isNotEmpty;
  }

  Future<void> _loadDecorationFonts(int generation) async {
    final loader = widget.onLoadFont;
    if (loader == null) return;
    final fonts = {
      for (final decoration in _orderedManualDecorations)
        if (decoration.style.fontFamily != null) decoration.style.fontFamily!,
    };
    for (final family in fonts) {
      try {
        await loader(family);
        if (!_currentDecorationRequest(generation)) return;
        _unavailableDecorationFonts.remove(family);
      } catch (_) {
        if (!_currentDecorationRequest(generation)) return;
        if (_unavailableDecorationFonts.add(family)) {
          _showToast('装饰字体加载失败，已跟随正文');
        }
      }
    }
  }

  Future<void> _prepareDecorationChapter({
    int? generation,
    int? spineIndex,
  }) async {
    final spine = spineIndex ?? _session.page?.spineIndex;
    if (spine == null) return;
    final token = generation ?? _decorationGeneration;
    if (!_hasEnabledDecorationRules) return;
    final pages = spine == _session.page?.spineIndex
        ? await _session.chapterPages()
        : await widget.source.loadChapter(spine);
    if (!_currentDecorationRequest(token)) return;
    final matches = await _ruleEngine.matchChapter(
      pages: pages,
      groups: _decorationGroups,
      rules: _decorationRules,
      bookId: widget.bookId,
    );
    if (!_currentDecorationRequest(token)) return;
    _changeReaderState(() {
      _chapterRuleMatches[spine] = matches;
      while (_chapterRuleMatches.length > 8) {
        _chapterRuleMatches.remove(_chapterRuleMatches.keys.first);
      }
      _painter = _buildPainter();
    });
  }

  void _scheduleDecorationChapter(PageContent page) {
    final token = _decorationGeneration;
    final spine = page.spineIndex;
    if (_decorationLoading ||
        !_hasEnabledDecorationRules ||
        _chapterRuleMatches.containsKey(spine) ||
        _decorationScheduledChapters[spine] == token) {
      return;
    }
    _decorationScheduledChapters[spine] = token;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!_currentDecorationRequest(token)) return;
      try {
        await _prepareDecorationChapter(generation: token, spineIndex: spine);
      } catch (_) {
        if (_currentDecorationRequest(token)) {
          _chapterRuleMatches[spine] = const [];
          _showToast('自动装饰暂不可用，请重试');
        }
      } finally {
        if (_decorationScheduledChapters[spine] == token) {
          _decorationScheduledChapters.remove(spine);
        }
      }
    });
  }

  Future<void> _loadDecorationImages(int generation) async {
    final paths = {
      for (final decoration in _orderedManualDecorations)
        if (decoration.style.backgroundImagePath != null)
          decoration.style.backgroundImagePath!,
    };
    for (final path in _decorationImages.keys.toList()) {
      if (!paths.contains(path)) _decorationImages.remove(path)?.dispose();
    }
    _missingDecorationImages.retainAll(paths);
    for (final path in paths) {
      if (!_currentDecorationRequest(generation)) return;
      if (_decorationImages.containsKey(path) ||
          _missingDecorationImages.contains(path)) {
        continue;
      }
      await _decodeDecorationImage(path, generation);
    }
    if (_currentDecorationRequest(generation)) {
      _changeReaderState(() => _painter = _buildPainter());
    }
  }

  Future<void> _decodeDecorationImage(String path, int generation) async {
    final store = widget.decorationImages;
    if (store == null) return;
    ui.Codec? codec;
    try {
      codec = await ui.instantiateImageCodec(await store.loadImage(path));
      final frame = await codec.getNextFrame();
      if (!_currentDecorationRequest(generation)) {
        frame.image.dispose();
        return;
      }
      _decorationImages[path] = frame.image;
    } catch (_) {
      if (_currentDecorationRequest(generation)) {
        _missingDecorationImages.add(path);
      }
    } finally {
      codec?.dispose();
    }
  }
}
