part of 'reader_page.dart';

extension _ReaderDecorationActions on _ReaderPageState {
  void _applyMarkSettings(ReaderMarkSettings settings) {
    if (!mounted || settings == _markSettings) return;
    _changeReaderState(() {
      _markSettings = settings;
      _painter = _buildPainter();
    });
    widget.onMarkSettingsChanged?.call(settings);
  }

  Future<void> _openMarkSettings() async {
    final settings = await showReaderBottomSheet<ReaderMarkSettings>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      readerTheme: _effectiveTheme ?? ReaderTheme.white,
      builder: (context) =>
          ReaderMarkSettingsSheet(settings: _markSettings, inkMode: _inkMode),
    );
    if (mounted && settings != null) _applyMarkSettings(settings);
  }

  Future<ReaderSupportedSelection?> _supportedSelection(
    PageContent page,
    ReaderSelection selection,
  ) async {
    final pages = selection.isMultiPage
        ? await _session.chapterPages()
        : [page];
    final supported = ReaderSelectionSupport.capture(pages, selection);
    if (mounted && supported == null) _showToast('当前位置不支持标注');
    return supported;
  }

  Future<ReaderDecorationStyle?> _decorationEditor(
    String quote,
    ReaderDecorationStyle initialStyle,
  ) => showReaderBottomSheet<ReaderDecorationStyle>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    readerTheme: _effectiveTheme ?? ReaderTheme.white,
    builder: (context) => ReaderDecorationEditorSheet(
      quote: quote,
      initialStyle: initialStyle,
      fonts: _customFonts,
      onLoadFont: widget.onLoadFont,
      images: widget.decorationImages,
      inkMode: _inkMode,
    ),
  );

  Future<void> _addDecoration(
    PageContent page,
    ReaderSelection selection,
  ) async {
    final store = widget.decorations;
    if (store == null) {
      _showToast('当前位置不支持标注');
      return;
    }
    final supported = await _supportedSelection(page, selection);
    if (!mounted || supported == null) return;
    final existing = _decorations
        .where(
          (item) =>
              item.startCfi == supported.startCfi &&
              item.endCfi == supported.endCfi,
        )
        .firstOrNull;
    _changeReaderState(() => _hideSelectionMenu = true);
    try {
      final style = await _decorationEditor(
        supported.quote,
        existing?.style ?? ReaderDecorationPreset.highlight.style,
      );
      if (!mounted || style == null) return;
      final saved = await store.add(
        startCfi: supported.startCfi,
        endCfi: supported.endCfi,
        quote: supported.quote,
        style: style,
        contextBefore: supported.contextBefore,
        contextAfter: supported.contextAfter,
      );
      if (!mounted) return;
      if (saved == null) {
        _showToast('当前位置不支持标注');
        return;
      }
      _clearSelection();
      final restored = await _reloadDecorations();
      if (mounted) _showToast(restored ? '装饰已保存' : '装饰已保存，排版位置可能变化');
    } on FormatException {
      if (mounted) _showToast('当前位置不支持标注');
    } catch (_) {
      if (mounted) _showToast('装饰保存失败，请重试');
    } finally {
      if (mounted) _changeReaderState(() => _hideSelectionMenu = false);
    }
  }

  Future<void> _editDecoration(ReaderDecoration decoration) async {
    final style = await _decorationEditor(decoration.quote, decoration.style);
    if (!mounted || style == null) return;
    try {
      await widget.decorations?.update(decoration.id, style: style);
      final restored = await _reloadDecorations();
      if (mounted) _showToast(restored ? '装饰已保存' : '装饰已保存，排版位置可能变化');
    } catch (_) {
      if (mounted) _showToast('装饰保存失败，请重试');
    }
  }

  Future<void> _removeDecoration(ReaderDecoration decoration) async {
    final confirmed = await showReaderDialog<bool>(
      context: context,
      builder: (context) => ReaderPanelTheme(
        theme: _effectiveTheme ?? ReaderTheme.white,
        child: ReaderFrostedAlertDialog(
          title: const Text('删除这条装饰？'),
          content: Text(decoration.quote),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || confirmed != true) return;
    try {
      await widget.decorations?.remove(decoration.id);
      await _reloadDecorations();
      if (mounted) _showToast('已删除装饰');
    } catch (_) {
      if (mounted) _showToast('装饰删除失败，请重试');
    }
  }

  Future<void> _openDecorationRules() async {
    final store = widget.decorationRules;
    if (store == null) {
      _showToast('当前书籍暂不支持自动装饰');
      return;
    }
    final navigator = Navigator.of(context);
    final themes = InheritedTheme.capture(from: context, to: navigator.context);
    await navigator.push<void>(
      MaterialPageRoute(
        builder: (context) => themes.wrap(
          ReaderPanelTheme(
            theme: _effectiveTheme ?? ReaderTheme.white,
            child: AnimatedBuilder(
              animation: _ruleEngine,
              builder: (context, _) => ReaderDecorationRulePage(
                store: store,
                bookId: widget.bookId,
                errors: _ruleEngine.errors,
                images: widget.decorationImages,
                inkMode: _inkMode,
                fonts: _customFonts,
                onPreview: (rule) async => _ruleEngine.preview(
                  rule,
                  await _session.chapterPages(),
                  sourceBlocks: widget.source is AnchorChapterSource
                      ? ReaderDecorationRuleEngine.anchorBlocks(
                          await (widget.source as AnchorChapterSource)
                              .loadAnchorChapter(_session.page!.spineIndex),
                        )
                      : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (!mounted) return;
    await _reloadDecorations();
  }

  Future<void> _selectDecoration(ReaderDecoration decoration) async {
    if (!decoration.needsRelocation) {
      final cfi = EpubCfi.parse(decoration.startCfi);
      final spine = cfi == null ? null : spineIndexOfCfi(cfi);
      if (spine != null && spine >= 0 && spine < widget.source.chapterCount) {
        final pages = await widget.source.loadChapter(spine);
        final resolved = ReaderDecorationRelocator.resolve(
          decorations: [decoration],
          pages: pages,
          contentRevision: widget.contentRevision,
        );
        if (!mounted) return;
        if (resolved.isNotEmpty) {
          await _session.jumpToCfi(
            resolved.first.startCfi,
            title: decoration.quote,
            continuous: _effectiveTurnMode == PageTurnMode.scroll,
          );
          return;
        }
      }
    }
    final accepted = await _showRelocationDialog(
      '重新定位装饰',
      decoration.quote,
      decoration.relocationReason,
    );
    if (!mounted || !accepted) return;
    _clearSelection();
    _changeReaderState(() {
      _relocatingAnnotation = null;
      _relocatingBookmark = null;
      _relocatingDecoration = decoration;
    });
  }

  Future<void> _relocateSelectedDecoration(
    PageContent page,
    ReaderSelection selection,
  ) async {
    final decoration = _relocatingDecoration;
    final store = widget.decorations;
    if (_relocationBusy || decoration == null || store == null) return;
    final supported = await _supportedSelection(page, selection);
    if (!mounted || supported == null) return;
    final accepted = await _showRelocationDialog(
      '确认关联装饰',
      decoration.quote,
      null,
      replacement: supported.quote,
    );
    if (!mounted || !accepted || _relocatingDecoration != decoration) return;
    await _saveRelocation(() async {
      await store.relocate(
        decoration.id,
        startCfi: supported.startCfi,
        endCfi: supported.endCfi,
      );
      if (mounted) await _reloadDecorations();
    }, '装饰已重新定位');
  }
}
