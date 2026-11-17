import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';

import '../library/library_store.dart';

const _coverRadius = BorderRadius.all(Radius.circular(4));

/// 打开图书时的封面展开动画。
///
/// 独立成路由页，保证读盘期间有明确反馈，同时允许系统返回取消打开。
class BookOpeningView extends StatefulWidget {
  const BookOpeningView({super.key, required this.book});

  /// 封面完整展开所需时长；打开器据此避免快速读盘时提前切页。
  static const Duration revealDuration = Duration(milliseconds: 560);

  final BookEntry book;

  @override
  State<BookOpeningView> createState() => _BookOpeningViewState();
}

class _BookOpeningViewState extends State<BookOpeningView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: BookOpeningView.revealDuration,
  );
  late final Animation<double> _reveal = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) {
      return;
    }
    _started = true;
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
    key: const ValueKey<String>('book-opening-view'),
    color: Theme.of(context).scaffoldBackgroundColor,
    child: Semantics(
      container: true,
      liveRegion: true,
      label: '正在打开《${widget.book.title}》',
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          SafeArea(child: LayoutBuilder(builder: _layout)),
          Positioned(
            left: 0,
            top: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: IconButton(
                  key: const ValueKey<String>('book-opening-close'),
                  tooltip: '取消打开',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const AppIcon(AppGlyph.close),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _layout(BuildContext context, BoxConstraints constraints) {
    final coverWidth = math.min(
      math.min(
        constraints.maxWidth * 0.46,
        constraints.maxHeight * 0.5 * 3 / 4,
      ),
      228.0,
    );
    return Column(
      children: <Widget>[
        const Spacer(flex: 3),
        _animatedCover(coverWidth),
        const SizedBox(height: 30),
        AnimatedBuilder(
          animation: _reveal,
          builder: (context, child) => Opacity(
            opacity: ((_reveal.value - 0.3) / 0.7).clamp(0.0, 1.0).toDouble(),
            child: child,
          ),
          child: _OpeningStatus(book: widget.book),
        ),
        const Spacer(flex: 4),
      ],
    );
  }

  Widget _animatedCover(double width) => AnimatedBuilder(
    animation: _reveal,
    builder: (context, child) {
      final t = _reveal.value;
      final scale = 0.94 + 0.06 * t;
      return Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 28 * (1 - t)),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0015)
              ..rotateY(-0.22 * (1 - t))
              ..multiply(Matrix4.diagonal3Values(scale, scale, 1)),
            child: child,
          ),
        ),
      );
    },
    child: _OpeningCover(book: widget.book, width: width),
  );
}

class _OpeningStatus extends StatelessWidget {
  const _OpeningStatus({required this.book});

  final BookEntry book;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 44),
      child: Column(
        children: <Widget>[
          Text(
            book.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '正在打开',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          const SizedBox(
            width: 88,
            child: LinearProgressIndicator(minHeight: 2),
          ),
        ],
      ),
    );
  }
}

class _OpeningCover extends StatelessWidget {
  const _OpeningCover({required this.book, required this.width});

  final BookEntry book;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: width * 4 / 3,
    child: Hero(
      tag: bookCoverHeroTag(book.id),
      transitionOnUserGestures: true,
      child: ClipRRect(
        borderRadius: _coverRadius,
        child: _coverContent(context),
      ),
    ),
  );

  Widget _coverContent(BuildContext context) {
    final coverPath = book.coverPath;
    final fallback = _CoverFallback(book: book);
    if (coverPath == null) {
      return fallback;
    }
    return Image.file(
      File(coverPath),
      fit: BoxFit.cover,
      cacheWidth: 720,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => fallback,
    );
  }
}

class _CoverFallback extends StatelessWidget {
  const _CoverFallback({required this.book});

  final BookEntry book;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: _coverRadius,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Center(
        child: Text(
          book.title.characters.isEmpty ? '书' : book.title.characters.first,
          style: theme.textTheme.displayMedium,
        ),
      ),
    );
  }
}
