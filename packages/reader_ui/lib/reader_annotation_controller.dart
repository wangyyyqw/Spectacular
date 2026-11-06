part of 'reader_page.dart';

extension _ReaderAnnotationController on _ReaderPageState {
  Future<void> _resolveAnnotationChapter(int spine, int generation) async {
    final items = _annotations.where((annotation) {
      final start = EpubCfi.parse(annotation.startCfi);
      final end = EpubCfi.parse(annotation.endCfi);
      final first = start == null ? null : spineIndexOfCfi(start);
      final last = end == null ? first : spineIndexOfCfi(end);
      return first != null && last != null && first <= spine && last >= spine;
    }).toList();
    final pages = items.isEmpty
        ? const <PageContent>[]
        : spine == _session.page?.spineIndex
        ? await _session.chapterPages()
        : await widget.source.loadChapter(spine);
    if (!mounted || generation != _annotationGeneration) return;
    final relocations = AnnotationRelocator.relocate(
      annotations: items,
      pages: pages,
      contentRevision: widget.contentRevision,
    );
    _changeReaderState(() {
      _annotationsByChapter[spine] = [
        for (final item in relocations)
          if (item.isResolved) item.resolved,
      ];
      while (_annotationsByChapter.length > 8) {
        _annotationsByChapter.remove(_annotationsByChapter.keys.first);
      }
      final unique = <String, ReaderAnnotation>{
        for (final chapter in _annotationsByChapter.values)
          for (final annotation in chapter) annotation.id: annotation,
      };
      _resolvedAnnotations = unique.values.toList();
      _painter = _buildPainter();
    });
  }

  void _scheduleAnnotationChapter(PageContent page) {
    final spine = page.spineIndex;
    final generation = _annotationGeneration;
    if (_annotations.isEmpty ||
        _annotationsByChapter.containsKey(spine) ||
        _annotationScheduledChapters[spine] == generation) {
      return;
    }
    _annotationScheduledChapters[spine] = generation;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || generation != _annotationGeneration) return;
      try {
        await _resolveAnnotationChapter(spine, generation);
      } catch (_) {
        if (mounted && generation == _annotationGeneration) {
          _annotationsByChapter[spine] = const [];
          _showToast('标注读取失败，请重试');
        }
      } finally {
        if (_annotationScheduledChapters[spine] == generation) {
          _annotationScheduledChapters.remove(spine);
        }
      }
    });
  }

  Future<void> _applyAnnotationEdit(
    ReaderAnnotation annotation,
    AnnotationEditAction action,
  ) async {
    final store = widget.annotations;
    final note = action.note?.trim();
    if (store == null || (note != null && note.isEmpty)) return;
    try {
      await _writeAnnotationEdit(store, annotation, action, note);
      if (!mounted) return;
      if (action.markSettings case final settings?) {
        _applyMarkSettings(settings);
      }
      await _reloadAnnotations();
      if (!mounted) return;
      final removable = action.type != AnnotationEditActionType.save;
      _showToast(
        _annotationEditMessage(annotation, action),
        duration: Duration(seconds: removable ? 5 : 2),
        action: !removable
            ? null
            : SnackBarAction(
                label: '撤销',
                onPressed: () => unawaited(
                  _restoreAnnotationState(
                    annotation,
                    replacedId:
                        action.type == AnnotationEditActionType.removeNote
                        ? annotation.id
                        : null,
                  ),
                ),
              ),
      );
    } catch (_) {
      if (mounted) _showToast('标注保存失败，请重试');
    }
  }

  Future<void> _writeAnnotationEdit(
    ReaderAnnotationStore store,
    ReaderAnnotation annotation,
    AnnotationEditAction action,
    String? note,
  ) async {
    switch (action.type) {
      case AnnotationEditActionType.save:
        await store.update(
          annotation.id,
          type: note == null ? null : ReaderAnnotationType.thought,
          color: action.color,
          style: action.style,
          opacity: action.opacity,
          note: note,
        );
      case AnnotationEditActionType.removeNote:
        await store.update(
          annotation.id,
          type: ReaderAnnotationType.mark,
          color: action.color,
          style: action.style,
          opacity: action.opacity,
          clearNote: true,
        );
      case AnnotationEditActionType.remove:
        await store.remove(annotation.id);
    }
  }

  String _annotationEditMessage(
    ReaderAnnotation annotation,
    AnnotationEditAction action,
  ) => switch (action.type) {
    AnnotationEditActionType.save =>
      action.note == null
          ? '已更新划线'
          : annotation.type == ReaderAnnotationType.mark
          ? '已添加想法'
          : '想法已更新',
    AnnotationEditActionType.removeNote => '已删除想法，保留划线',
    AnnotationEditActionType.remove =>
      annotation.type == ReaderAnnotationType.thought ? '已删除想法及划线' : '已删除划线',
  };

  Future<void> _restoreAnnotationState(
    ReaderAnnotation annotation, {
    String? replacedId,
  }) async {
    final store = widget.annotations;
    if (store == null) return;
    try {
      await _writeAnnotationSnapshot(store, annotation, replacedId);
      await _reloadAnnotations();
      if (mounted) {
        _showToast(
          annotation.type == ReaderAnnotationType.thought ? '已恢复想法' : '已恢复划线',
        );
      }
    } catch (_) {
      if (mounted) _showToast('恢复失败，请重试');
    }
  }

  Future<void> _writeAnnotationSnapshot(
    ReaderAnnotationStore store,
    ReaderAnnotation annotation,
    String? replacedId,
  ) async {
    if (replacedId != null) {
      await store.update(
        replacedId,
        type: annotation.type,
        color: annotation.color ?? defaultHighlightColor,
        style: annotation.style,
        opacity: annotation.effectiveOpacity,
        note: annotation.note,
        clearNote: annotation.note == null,
      );
      return;
    }
    final restored = await store.add(
      type: annotation.type,
      startCfi: annotation.startCfi,
      endCfi: annotation.endCfi,
      quote: annotation.quote,
      contextBefore: annotation.contextBefore,
      contextAfter: annotation.contextAfter,
      color: annotation.color,
      style: annotation.style,
      opacity: annotation.opacity,
      note: annotation.note,
    );
    if (restored == null) throw const FormatException('当前位置不支持标注');
  }

  List<SelectionAction> _selectionActions(
    PageContent page,
    ReaderSelection selection,
  ) {
    if (_relocatingAnnotation != null || _relocatingDecoration != null) {
      return [
        _selectionAction(
          'relocate',
          '关联此处',
          () => unawaited(
            _relocatingDecoration == null
                ? _relocateSelectedAnnotation(page, selection)
                : _relocateSelectedDecoration(page, selection),
          ),
        ),
        _selectionAction('dismiss', '取消选区', _clearSelection),
      ];
    }
    return [
      _selectionAction(
        'mark',
        '划线',
        () => unawaited(
          _saveAnnotation(page, selection, ReaderAnnotationType.mark),
        ),
      ),
      _selectionAction(
        'thought',
        '想法',
        () => unawaited(_addNote(page, selection)),
      ),
      _selectionAction(
        'decoration',
        '装饰',
        () => unawaited(_addDecoration(page, selection)),
      ),
      _selectionAction(
        'copy',
        '复制',
        () => unawaited(_copySelection(page, selection)),
      ),
      _selectionAction('dictionary', '词典', () => _showToast('词典功能开发中')),
      _selectionAction(
        'more',
        '更多',
        () => _changeReaderState(() => _selectionMore = !_selectionMore),
      ),
      if (_selectionMore) ...[
        _selectionAction('select-all', '全选', () => _selectAll(page)),
        _selectionAction('dismiss', '取消选区', _clearSelection),
      ],
    ];
  }

  SelectionAction _selectionAction(
    String id,
    String label,
    VoidCallback action,
  ) => SelectionAction(id: id, label: label, onTap: action);

  Future<void> _saveAnnotation(
    PageContent page,
    ReaderSelection selection,
    ReaderAnnotationType type, {
    AnnotationEditAction? appearance,
    ReaderSupportedSelection? supported,
  }) async {
    final store = widget.annotations;
    if (store == null) {
      _showToast('当前位置不支持标注');
      return;
    }
    try {
      final range = supported ?? await _supportedSelection(page, selection);
      if (!mounted || range == null) return;
      final previous = await _existingAnnotation(range);
      final saved = await _persistSelectedAnnotation(
        store,
        range,
        type,
        appearance,
      );
      if (!mounted) return;
      if (saved == null) {
        _showToast('当前位置不支持标注');
        return;
      }
      if (appearance?.markSettings case final settings?) {
        _applyMarkSettings(settings);
      }
      await _reloadAnnotations();
      if (!mounted) return;
      _clearSelection();
      _showToast(
        type == ReaderAnnotationType.thought ? '想法已保存' : '已划线',
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () => unawaited(_undoSavedAnnotation(saved, previous)),
        ),
      );
    } on FormatException {
      if (mounted) _showToast('当前位置不支持标注');
    } catch (_) {
      if (mounted) _showToast('标注保存失败，请重试');
    }
  }

  Future<ReaderAnnotation?> _persistSelectedAnnotation(
    ReaderAnnotationStore store,
    ReaderSupportedSelection range,
    ReaderAnnotationType type,
    AnnotationEditAction? appearance,
  ) => store.add(
    type: type,
    startCfi: range.startCfi,
    endCfi: range.endCfi,
    quote: range.quote,
    contextBefore: range.contextBefore,
    contextAfter: range.contextAfter,
    color: appearance?.color ?? _markSettings.lastColor,
    style: appearance?.style ?? _markSettings.lastStyle,
    opacity: appearance?.opacity,
    note: appearance?.note?.trim(),
  );

  Future<ReaderAnnotation?> _existingAnnotation(
    ReaderSupportedSelection range,
  ) async {
    final items = (await widget.annotations!.list())
        .where(
          (annotation) =>
              annotation.startCfi == range.startCfi &&
              annotation.endCfi == range.endCfi,
        )
        .toList();
    items.sort((left, right) {
      final type = right.type.storageValue.compareTo(left.type.storageValue);
      return type != 0 ? type : right.updatedAt.compareTo(left.updatedAt);
    });
    return items.firstOrNull;
  }

  Future<void> _undoSavedAnnotation(
    ReaderAnnotation saved,
    ReaderAnnotation? previous,
  ) async {
    final store = widget.annotations;
    if (store == null) return;
    try {
      if (previous == null) {
        await store.remove(saved.id);
      } else {
        await _writeAnnotationSnapshot(store, previous, saved.id);
      }
      await _reloadAnnotations();
      if (mounted) _showToast('已撤销');
    } catch (_) {
      if (mounted) _showToast('撤销失败，请重试');
    }
  }

  Future<void> _addNote(PageContent page, ReaderSelection selection) async {
    if (widget.annotations == null) {
      _showToast('当前位置不支持标注');
      return;
    }
    try {
      final supported = await _supportedSelection(page, selection);
      if (!mounted || supported == null) return;
      final existing = await _existingAnnotation(supported);
      if (!mounted) return;
      if (existing?.type == ReaderAnnotationType.thought) {
        _clearSelection();
        await _editAnnotation(existing!);
        return;
      }
      _changeReaderState(() => _hideSelectionMenu = true);
      final appearance = await _composeThought(supported, existing);
      if (!mounted ||
          appearance == null ||
          (appearance.note?.trim().isEmpty ?? true)) {
        return;
      }
      await _saveAnnotation(
        page,
        selection,
        ReaderAnnotationType.thought,
        appearance: appearance,
        supported: supported,
      );
    } catch (_) {
      if (mounted) _showToast('想法编辑失败，请重试');
    } finally {
      if (mounted) _changeReaderState(() => _hideSelectionMenu = false);
    }
  }

  Future<AnnotationEditAction?> _composeThought(
    ReaderSupportedSelection range,
    ReaderAnnotation? existing,
  ) => showModalBottomSheet<AnnotationEditAction>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => ReaderPanelTheme(
      theme: _effectiveTheme ?? ReaderTheme.white,
      child: ReaderNoteComposerSheet(
        quote: range.quote,
        inkMode: _inkMode,
        initialOpacity: existing?.opacity,
        markSettings: existing == null
            ? _markSettings
            : _markSettings.copyWith(
                lastColor: existing.color ?? defaultHighlightColor,
                lastStyle: existing.style,
              ),
      ),
    ),
  );
}
