import 'package:flutter/material.dart';

import '../library/library_store.dart';
import '../storage/book_review_store.dart';

/// 读完时提交的评分与书评，不把未保存输入写入书籍资料。
class FinishBookDraft {
  const FinishBookDraft({required this.rating, required this.content});

  final int? rating;
  final String content;
}

/// 读完信息编辑器；写入成功后关闭，失败与返回操作均保留草稿。
class FinishBookSheet extends StatefulWidget {
  const FinishBookSheet({
    super.key,
    required this.book,
    required this.review,
    required this.onCommit,
    this.allowReview = true,
  });

  final BookEntry book;
  final BookReview? review;
  final Future<void> Function(FinishBookDraft draft) onCommit;
  final bool allowReview;

  @override
  State<FinishBookSheet> createState() => _FinishBookSheetState();
}

class _FinishBookSheetState extends State<FinishBookSheet> {
  late final _controller = TextEditingController(
    text: widget.review?.content ?? '',
  )..addListener(_changed);
  late int? _rating = widget.review?.rating;
  bool _saving = false;
  bool _allowPop = false;
  bool _closing = false;
  bool _confirming = false;
  String? _error;

  bool get _dirty =>
      widget.allowReview &&
      (_rating != widget.review?.rating ||
          _controller.text.trim() != (widget.review?.content ?? '').trim());

  void _changed() => setState(() => _error = null);

  @override
  void dispose() {
    _controller
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  void _dismiss([FinishBookDraft? draft]) {
    if (_closing || !mounted) return;
    _closing = true;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(draft);
    });
  }

  Future<bool> _confirmDiscard() async {
    if (_confirming) return false;
    _confirming = true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('放弃未保存的书评？'),
        content: const Text('离开后本次尚未保存的修改会丢失。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('继续编辑'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('放弃修改'),
          ),
        ],
      ),
    );
    _confirming = false;
    return confirmed == true;
  }

  Future<void> _close() async {
    if (_saving || _closing) return;
    if (!_dirty || await _confirmDiscard()) _dismiss();
  }

  Future<void> _submit() async {
    if (_saving || _closing) return;
    final draft = FinishBookDraft(
      rating: _rating,
      content: _controller.text.trim(),
    );
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onCommit(draft);
      if (mounted) {
        _saving = false;
        _dismiss(draft);
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FormatException
              ? error.message
              : '保存失败，草稿已保留，请重试',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _heading(ThemeData theme) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(child: Text('读完信息', style: theme.textTheme.titleLarge)),
          IconButton(
            key: const ValueKey('book-detail-finish-close'),
            tooltip: '关闭读完信息',
            onPressed: _saving ? null : _close,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
      Text(
        widget.book.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );

  void _setRating(int star) => setState(() {
    _rating = _rating == star ? null : star;
    _error = null;
  });

  Widget _ratingPicker(ThemeData theme) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('评分（可选）', style: theme.textTheme.labelLarge),
      const SizedBox(height: 6),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var star = 1; star <= 5; star++)
            Semantics(
              selected: _rating == star,
              child: IconButton(
                key: ValueKey<String>('book-detail-finish-rating-$star'),
                tooltip: '$star 星',
                onPressed: _saving ? null : () => _setRating(star),
                iconSize: 34,
                color: const Color(0xFFE0A327),
                icon: Icon(
                  star <= (_rating ?? 0)
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                ),
              ),
            ),
        ],
      ),
    ],
  );

  Widget _reviewInput(ThemeData theme) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('书评（可选）', style: theme.textTheme.labelLarge),
      const SizedBox(height: 8),
      TextField(
        key: const ValueKey<String>('book-detail-finish-review'),
        controller: _controller,
        readOnly: _saving,
        minLines: 4,
        maxLines: 7,
        maxLength: BookReview.maxContentLength,
        textInputAction: TextInputAction.newline,
        decoration: const InputDecoration(
          hintText: '写下这本书带给你的感受…',
          alignLabelWithHint: true,
        ),
      ),
    ],
  );

  Widget _content(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(theme),
          const SizedBox(height: 18),
          if (widget.allowReview) ...[
            _ratingPicker(theme),
            const SizedBox(height: 14),
            _reviewInput(theme),
          ] else
            const Text('当前无法保存书评，仅标记读完。'),
        ],
      ),
    );
  }

  Widget _actions(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                key: const ValueKey('book-detail-finish-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
        OverflowBar(
          alignment: MainAxisAlignment.end,
          spacing: 8,
          overflowSpacing: 8,
          children: [
            TextButton(
              key: const ValueKey<String>('book-detail-finish-cancel'),
              onPressed: _saving ? null : _close,
              child: const Text('取消'),
            ),
            FilledButton.icon(
              key: const ValueKey<String>('book-detail-finish-save'),
              onPressed: _saving ? null : _submit,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(_saving ? '正在保存…' : '保存并标记读完'),
            ),
          ],
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving && (!_dirty || _allowPop),
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _close();
    },
    child: Material(
      key: const ValueKey<String>('book-detail-finish-sheet'),
      color: Theme.of(context).colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: _content(context)),
              const Divider(height: 1),
              _actions(context),
            ],
          ),
        ),
      ),
    ),
  );
}
