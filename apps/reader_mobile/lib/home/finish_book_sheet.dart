import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';
import 'package:reader_ui/theme/reader_frosted_surface.dart';

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
    this.fullScreen = false,
    this.finished = false,
    this.rtl = false,
  });

  final BookEntry book;
  final BookReview? review;
  final Future<void> Function(FinishBookDraft? draft) onCommit;
  final bool allowReview;
  final bool fullScreen;
  final bool finished;
  final bool rtl;

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
  double _dragDistance = 0;
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

  void _dismiss([bool? savedReview]) {
    if (_closing || !mounted) return;
    _closing = true;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(savedReview);
    });
  }

  Future<bool> _confirmDiscard() async {
    if (_confirming) return false;
    _confirming = true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ReaderFrostedAlertDialog(
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

  Future<void> _submit({bool review = false}) async {
    if (_saving || _closing) return;
    if (!review && _dirty && !await _confirmDiscard()) return;
    if (!mounted || _closing) return;
    final draft = review
        ? FinishBookDraft(rating: _rating, content: _controller.text.trim())
        : null;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onCommit(draft);
      if (mounted) {
        _saving = false;
        _dismiss(review);
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
      if (!widget.fullScreen)
        Row(
          children: [
            Expanded(child: Text('读完信息', style: theme.textTheme.titleLarge)),
            IconButton(
              key: const ValueKey('book-detail-finish-close'),
              tooltip: '关闭读完信息',
              onPressed: _saving ? null : _close,
              icon: const AppIcon(AppGlyph.close),
            ),
          ],
        ),
      Text(
        widget.book.title,
        maxLines: widget.fullScreen ? 3 : 1,
        overflow: TextOverflow.ellipsis,
        style: widget.fullScreen
            ? theme.textTheme.titleSmall
            : theme.textTheme.bodySmall?.copyWith(
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
      Wrap(
        spacing: 2,
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
                icon: AppIcon(AppGlyph.star, filled: star <= (_rating ?? 0)),
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
          if (widget.fullScreen) ...[
            const SizedBox(height: 12),
            Text(
              widget.finished
                  ? '已经读完这本书，可以在这里补充评分和书评。'
                  : '正文已结束。标记读完后，也可以稍后到书评页评分和写书评。',
              style: theme.textTheme.bodyMedium,
            ),
          ],
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
            if (!widget.fullScreen)
              TextButton(
                key: const ValueKey('book-detail-finish-cancel'),
                onPressed: _saving ? null : _close,
                child: const Text('取消'),
              ),
            if (!widget.finished)
              OutlinedButton(
                key: const ValueKey<String>('finish-book-only'),
                onPressed: _saving ? null : _submit,
                child: Text(widget.allowReview ? '仅标记读完' : '标记读完'),
              ),
            if (widget.allowReview)
              FilledButton.icon(
                key: const ValueKey<String>('book-detail-finish-save'),
                onPressed: _saving || !_dirty
                    ? null
                    : () => _submit(review: true),
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const AppIcon(AppGlyph.check),
                label: Text(widget.finished ? '保存书评' : '保存书评并标记读完'),
              ),
          ],
        ),
      ],
    ),
  );

  Widget _form(BuildContext context) => Column(
    mainAxisSize: widget.fullScreen ? MainAxisSize.max : MainAxisSize.min,
    children: [
      if (widget.fullScreen)
        Expanded(child: _content(context))
      else
        Flexible(child: _content(context)),
      const Divider(height: 1),
      _actions(context),
    ],
  );

  Widget _fullPage(BuildContext context) => GestureDetector(
    onHorizontalDragStart: (_) => _dragDistance = 0,
    onHorizontalDragUpdate: (details) => _dragDistance += details.delta.dx,
    onHorizontalDragEnd: (details) {
      final direction = widget.rtl ? -1 : 1;
      if (_dragDistance * direction > 56 ||
          (details.primaryVelocity ?? 0) * direction > 450) {
        _close();
      }
    },
    child: Scaffold(
      key: const ValueKey('reader-finish-page'),
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回正文末页',
          onPressed: _saving ? null : _close,
          icon: const AppIcon(AppGlyph.arrowBack),
        ),
        title: Text(widget.finished ? '已读完' : '标记读完'),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: _form(context),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving && (!_dirty || _allowPop),
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _close();
    },
    child: widget.fullScreen
        ? _fullPage(context)
        : Material(
            key: const ValueKey<String>('book-detail-finish-sheet'),
            color: ReaderFrostedSurface.panelColorOf(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            clipBehavior: Clip.antiAlias,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: _form(context),
              ),
            ),
          ),
  );
}
