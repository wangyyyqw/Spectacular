part of 'reader_page.dart';

extension _ReaderSelectionText on _ReaderPageState {
  Future<String?> _selectionText(
    PageContent page,
    ReaderSelection selection,
  ) async {
    if (!widget.ocrRequired) {
      return selection.isMultiPage
          ? SelectionOps.textAcrossPages(
              await _session.chapterPages(),
              selection,
            )
          : SelectionOps.textOf(page, selection);
    }
    if (_selectionTextBusy) return null;
    final recognize = widget.onRecognizeSelection;
    if (recognize == null) {
      await _showOcrFailure('本书需要文字识别，当前无法使用 OCR');
      return null;
    }
    final originalSelection = _selection;
    final revision = _session.layoutRevision;
    bool current() =>
        mounted &&
        identical(originalSelection, _selection) &&
        revision == _session.layoutRevision;
    _changeReaderState(() {
      _selectionTextBusy = true;
      _hideSelectionMenu = true;
    });
    try {
      final pages = selection.isMultiPage
          ? await _session.chapterPages()
          : [page];
      final text = StringBuffer();
      for (final selectedPage in pages) {
        if (!current()) return null;
        final local = SelectionOps.localSelectionOf(
          selectedPage,
          selectedPage.pageIndex,
          selection,
        );
        if (local == null) continue;
        await for (final image in SelectionImage.captureLines(
          selectedPage,
          local,
        )) {
          if (!current()) return null;
          text.write(await recognize(image));
        }
      }
      if (!current()) return null;
      if (text.isEmpty) throw const FormatException('未识别到文字，请重新选择');
      return text.toString();
    } catch (error) {
      if (current()) {
        await _showOcrFailure(
          error is FormatException ? error.message : '文字识别失败，请重试',
        );
      }
      return null;
    } finally {
      if (mounted) {
        _changeReaderState(() {
          _selectionTextBusy = false;
          _hideSelectionMenu = false;
        });
      }
    }
  }

  Future<void> _showOcrFailure(String message) => showReaderDialog<void>(
    context: context,
    builder: (context) => ReaderFrostedAlertDialog(
      title: const Text('未完成文字操作'),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('知道了'),
        ),
      ],
    ),
  );

  Future<void> _editSelection(
    PageContent page,
    ReaderSelection selection,
  ) async {
    final edit = widget.onEditTarget;
    final range = SelectionOps.cfiOf(selection);
    if (edit == null || range == null) return;
    final supported = widget.ocrRequired
        ? await _supportedSelection(page, selection)
        : null;
    if (!mounted || widget.ocrRequired && supported == null) return;
    _clearSelection();
    edit(
      ReaderEditTarget(
        spineIndex: page.spineIndex,
        cfi: range.start,
        endCfi: range.end,
        contentRevision: widget.contentRevision,
        recognizedText: supported?.quote,
        sourceText: supported?.sourceQuote,
      ),
    );
  }
}
