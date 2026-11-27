import 'dart:async';

import 'package:flutter/material.dart';

import 'book_opening_view.dart';

/// 正文先在同一路由内准备，封面展开和首屏绘制均完成后再揭开。
class BookOpeningReader extends StatefulWidget {
  const BookOpeningReader({
    super.key,
    required this.openingView,
    required this.readerBuilder,
    this.onRevealed,
  });

  final BookOpeningView openingView;

  /// 第二个参数为正文是否已经可交互，用于前台阅读计时。
  final Widget Function(VoidCallback onReady, bool readingActive) readerBuilder;
  final VoidCallback? onRevealed;

  @override
  State<BookOpeningReader> createState() => _BookOpeningReaderState();
}

class _BookOpeningReaderState extends State<BookOpeningReader> {
  Timer? _coverTimer;
  bool _started = false;
  bool _coverFinished = false;
  bool _readerReady = false;
  bool _revealing = false;
  bool _revealed = false;
  bool _disableAnimations = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_started) return;
    _started = true;
    if (_disableAnimations) {
      _coverFinished = true;
    } else {
      _coverTimer = Timer(BookOpeningView.revealDuration, () {
        _coverFinished = true;
        _revealIfReady();
      });
    }
  }

  void _readerDidPrepare() {
    _readerReady = true;
    _revealIfReady();
  }

  void _revealIfReady() {
    if (!mounted || _revealing || !_coverFinished || !_readerReady) return;
    setState(() => _revealing = true);
    if (_disableAnimations) _finishReveal();
  }

  void _finishReveal() {
    if (!mounted || !_revealing || _revealed) return;
    setState(() => _revealed = true);
    widget.onRevealed?.call();
  }

  @override
  void dispose() {
    _coverTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      ExcludeSemantics(
        excluding: !_revealed,
        child: ExcludeFocus(
          excluding: !_revealed,
          child: IgnorePointer(
            ignoring: !_revealed,
            child: widget.readerBuilder(_readerDidPrepare, _revealed),
          ),
        ),
      ),
      if (!_revealed)
        AnimatedOpacity(
          opacity: _revealing ? 0 : 1,
          duration: _disableAnimations
              ? Duration.zero
              : const Duration(milliseconds: 220),
          onEnd: _finishReveal,
          child: widget.openingView,
        ),
    ],
  );
}
