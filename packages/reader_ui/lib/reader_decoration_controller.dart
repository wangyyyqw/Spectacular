part of 'reader_page.dart';

extension _ReaderDecorationController on _ReaderPageState {
  bool get _hasEnabledDecorationRules =>
      ReaderDecorationRuleEngine.orderedRules(
        groups: _decorationGroups,
        rules: _decorationRules,
        bookId: widget.bookId,
      ).isNotEmpty;

  List<ReaderDecoration> get _orderedManualDecorations =>
      List.of(_resolvedDecorations)..sort(_compareManualDecorations);

  int _compareManualDecorations(ReaderDecoration left, ReaderDecoration right) {
    final creation = left.createdAt.compareTo(right.createdAt);
    return creation == 0 ? left.id.compareTo(right.id) : creation;
  }

  List<ReaderTextOverlay> get _textOverlays => [
    for (final matches in _chapterRuleMatches.values)
      for (final match in matches)
        ReaderTextOverlay(
          startCfi: match.startCfi,
          endCfi: match.endCfi,
          color: match.style.decorationStyle.textColor,
          colorOpacity: match.style.decorationStyle.textColorOpacity,
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

  ReaderTextOverlay _manualTextOverlay(
    ReaderDecoration decoration, {
    bool checkFontAvailability = true,
  }) {
    final style = decoration.style;
    return ReaderTextOverlay(
      startCfi: decoration.startCfi,
      endCfi: decoration.endCfi,
      fontFamily:
          checkFontAvailability &&
              _unavailableDecorationFonts.contains(style.fontFamily)
          ? null
          : style.fontFamily,
      fontSizeScale: style.fontSizeScale,
      fontWeight: style.fontWeight,
      italic: style.italic,
      letterSpacingEm: style.letterSpacingEm,
      color: style.textColor,
      colorOpacity: style.textColorOpacity,
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
    final boxes = ReaderDecorationGeometry.boxesFor(page, ranges, slice: slice);
    for (final box in boxes) {
      for (final rect in box.rects) {
        ReaderDecorationPainter.paintBox(
          canvas,
          rect,
          box.style,
          image: _decorationImages[box.style.backgroundImagePath],
          imageNineSlice: _decorationNineSlices[box.style.backgroundImagePath],
          imageAnchor: box.imageAnchorFor(rect),
          vertical: box.range.line.isVertical,
          clipRect:
              box.style.backgroundImageFit != ReaderDecorationImageFit.nineSlice
              ? null
              : box.imageClipFor(
                  rect,
                  Size(_paperContentWidth, page.pageHeight),
                ),
          inkMode: _inkMode,
        );
      }
    }
    ReaderDecorationPainter.paintHighlights(
      canvas,
      boxes,
      foreground: false,
      inkMode: _inkMode,
    );
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

  void _paintDecorationHighlights(Canvas canvas, PageContent page) {
    final ranges = _decorationRangesFor(page);
    if (!ranges.any((range) => range.style.highlight != null)) return;
    ReaderDecorationPainter.paintHighlights(
      canvas,
      ReaderDecorationGeometry.boxesFor(page, ranges),
      foreground: true,
      inkMode: _inkMode,
    );
  }

  bool _currentDecorationRequest(int generation) =>
      mounted && generation == _decorationGeneration;

  Future<bool> _reloadDecorations() async {
    final generation = ++_decorationGeneration;
    _decorationLoading = true;
    final anchor = _session.currentCfi;
    try {
      if (!await (_decorationStoresTask = _readDecorationStores(generation))) {
        return false;
      }
      if (widget.source is PreparedChapterSource) {
        return await _reloadPreparedDecorations(generation, anchor);
      }
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

  Future<bool> _reloadPreparedDecorations(
    int generation,
    String? anchor,
  ) async {
    final current = _session.page;
    var restored = true;
    if (current != null) {
      final changed = await _prepareDecorationsForLayout(current.spineIndex);
      restored = await _restoreDecorationPosition(changed, anchor, generation);
      if (!_currentDecorationRequest(generation)) return false;
      await _prepareDecorationChapter(generation: generation);
    }
    await _loadDecorationImages(generation);
    return restored && _currentDecorationRequest(generation);
  }

  Future<void> _prepareChapterBeforeLayout(int spineIndex) async {
    int generation;
    do {
      generation = _decorationGeneration;
      await _prepareDecorationsForLayout(spineIndex);
      if (!mounted) throw const ChapterLoadCancelled();
    } while (generation != _decorationGeneration);
  }

  Future<void> _waitForDecorationStores() async {
    Future<bool>? task;
    do {
      task = _decorationStoresTask;
      try {
        await task;
      } catch (_) {
        // 读取失败由装饰控制器提示，正文保留最后一份已核验装饰。
      }
    } while (mounted && !identical(task, _decorationStoresTask));
  }

  /// 原文核验和字体准备在章节源冻结输入前完成；不等待首屏分页。
  Future<bool> _prepareDecorationsForLayout(int spineIndex) async {
    await _waitForDecorationStores();
    final generation = _decorationGeneration;
    if (!_currentDecorationRequest(generation)) return false;
    final key = (generation, spineIndex);
    final pending = _chapterDecorationPreparations[key];
    if (pending != null) {
      await pending;
      return false;
    }
    final task = _prepareChapterDecorations(spineIndex, generation);
    _chapterDecorationPreparations[key] = task;
    try {
      return await task;
    } catch (_) {
      if (identical(_chapterDecorationPreparations[key], task)) {
        unawaited(_chapterDecorationPreparations.remove(key));
      }
      rethrow;
    }
  }

  Future<bool> _prepareChapterDecorations(
    int spineIndex,
    int generation,
  ) async {
    if (!await _verifyManualDecorations(generation, spineIndex: spineIndex)) {
      return false;
    }
    await _loadDecorationFonts(generation, spineIndex: spineIndex);
    if (!_currentDecorationRequest(generation)) return false;
    final source = widget.source;
    final changed =
        source is ReaderTextOverlaySource &&
        await (source as ReaderTextOverlaySource).applyTextOverlays(
          _textOverlays,
        );
    if (_currentDecorationRequest(generation)) {
      _changeReaderState(() => _painter = _buildPainter());
    }
    return changed;
  }

  Future<bool> _readDecorationStores(int generation) async {
    final itemsTask = widget.decorations?.list();
    final groupsTask = widget.decorationRules?.listGroups();
    final rulesTask = widget.decorationRules?.listRules();
    final items = await itemsTask ?? const <ReaderDecoration>[];
    final groups = await groupsTask ?? const <ReaderDecorationRuleGroup>[];
    final rules = await rulesTask ?? const <ReaderDecorationRule>[];
    if (!_currentDecorationRequest(generation)) return false;
    _changeReaderState(() {
      _decorations = items;
      _decorationGroups = groups;
      _decorationRules = rules;
      _manualDecorationsByChapter.clear();
      _chapterDecorationPreparations.clear();
      _chapterRuleMatches.clear();
      _decorationScheduledChapters.clear();
    });
    final source = widget.source;
    if (source case BookTypographyFontSource fonts) {
      fonts.setBookTypographyFamilies({
        for (final item in items) ?item.style.fontFamily,
      });
    }
    if (source is PreparedChapterSource) {
      final ordered = List.of(items)..sort(_compareManualDecorations);
      source.setBookTypographyFingerprint(
        ReaderTextOverlayResolver([
          for (final item in ordered)
            _manualTextOverlay(item, checkFontAvailability: false),
        ], colors: false).typographyFingerprint,
      );
    }
    return true;
  }

  Future<bool> _verifyManualDecorations(
    int generation, {
    int? spineIndex,
  }) async {
    final source = widget.source;
    if (spineIndex != null && source is AnchorChapterSource) {
      return _verifyDecorationAnchors(source, spineIndex, generation);
    }
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

  Future<bool> _verifyDecorationAnchors(
    AnchorChapterSource source,
    int spine,
    int generation,
  ) async {
    if (_manualDecorationsByChapter.containsKey(spine)) return true;
    final items = _decorations.where((decoration) {
      if (decoration.needsRelocation) return false;
      final parsedFirst = EpubCfi.parse(decoration.startCfi);
      final parsedLast = EpubCfi.parse(decoration.endCfi);
      final first = parsedFirst == null ? null : spineIndexOfCfi(parsedFirst);
      final last = parsedLast == null ? null : spineIndexOfCfi(parsedLast);
      return first != null && last != null && first <= spine && spine <= last;
    }).toList();
    final verified = items.isEmpty
        ? const <ReaderDecoration>[]
        : ReaderDecorationRelocator.resolveAnchors(
            decorations: items,
            book: AnchorBook(
              revision: widget.contentRevision ?? 'reader-layout',
              chapters: [await source.loadAnchorChapter(spine)],
            ),
          );
    if (!_currentDecorationRequest(generation)) return false;
    _changeReaderState(() {
      _manualDecorationsByChapter[spine] = verified;
      final unique = <String, ReaderDecoration>{
        for (final chapter in _manualDecorationsByChapter.values)
          for (final decoration in chapter) decoration.id: decoration,
      };
      _resolvedDecorations = unique.values.toList();
    });
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
    return ReaderTextRangeGeometry.containsPoint(page, cfi);
  }

  Future<void> _loadDecorationFonts(int generation, {int? spineIndex}) async {
    final loader = widget.onLoadFont;
    if (loader == null) return;
    final fonts = {
      for (final decoration
          in spineIndex == null
              ? _orderedManualDecorations
              : _manualDecorationsByChapter[spineIndex] ??
                    const <ReaderDecoration>[])
        if (decoration.style.fontFamily != null) decoration.style.fontFamily!,
    };
    for (final family in fonts) {
      try {
        await _ensureDecorationFont(family, loader);
        if (!_currentDecorationRequest(generation)) return;
        _unavailableDecorationFonts.remove(family);
        _reportDecorationFontAvailability(family, true);
      } catch (_) {
        if (!_currentDecorationRequest(generation)) return;
        final newlyUnavailable = _unavailableDecorationFonts.add(family);
        _reportDecorationFontAvailability(family, false);
        if (newlyUnavailable) {
          _showToast('装饰字体加载失败，已跟随正文');
        }
      }
    }
  }

  void _reportDecorationFontAvailability(String family, bool available) {
    if (widget.source case BookTypographyFontSource source) {
      source.setBookTypographyFontAvailability(family, available);
    }
  }

  Future<void> _ensureDecorationFont(
    String family,
    Future<void> Function(String) loader,
  ) async {
    if (_loadedDecorationFonts.contains(family)) return;
    final task = _decorationFontLoads.putIfAbsent(family, () => loader(family));
    try {
      await task;
      if (mounted) _loadedDecorationFonts.add(family);
    } finally {
      if (identical(_decorationFontLoads[family], task)) {
        unawaited(_decorationFontLoads.remove(family));
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
      for (final rule in ReaderDecorationRuleEngine.orderedRules(
        groups: _decorationGroups,
        rules: _decorationRules,
        bookId: widget.bookId,
      ))
        ?rule.style.backgroundImagePath,
    };
    for (final path in _decorationImages.keys.toList()) {
      if (!paths.contains(path)) {
        _decorationImages.remove(path)?.dispose();
        _decorationNineSlices.remove(path);
      }
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
    try {
      final decoded = await ReaderDecorationImageCodec.decode(
        await store.loadImage(path),
      );
      if (!_currentDecorationRequest(generation)) {
        decoded.image.dispose();
        return;
      }
      _decorationImages[path] = decoded.image;
      if (decoded.nineSlice case final nineSlice?) {
        _decorationNineSlices[path] = nineSlice;
      }
    } catch (_) {
      if (_currentDecorationRequest(generation)) {
        _missingDecorationImages.add(path);
      }
    }
  }
}
