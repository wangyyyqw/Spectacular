import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../library/library_store.dart';

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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final book = widget.book;
    final accent = HSLColor.fromAHSL(
      1,
      book.coverHue.toDouble(),
      0.46,
      0.36,
    ).toColor();
    return Material(
      key: const ValueKey<String>('book-opening-view'),
      color: theme.colorScheme.surface,
      child: Semantics(
        container: true,
        liveRegion: true,
        label: '正在打开《${book.title}》',
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.18),
                  radius: 0.9,
                  colors: <Color>[
                    Color.alphaBlend(
                      accent.withValues(alpha: 0.16),
                      theme.colorScheme.surface,
                    ),
                    theme.colorScheme.surface,
                  ],
                ),
              ),
            ),
            Positioned(
              left: -120,
              top: 80,
              child: _AtmosphereOrb(color: accent, size: 280),
            ),
            Positioned(
              right: -90,
              bottom: 60,
              child: _AtmosphereOrb(
                color: theme.colorScheme.primary,
                size: 220,
              ),
            ),
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
                    icon: const Icon(Icons.close),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
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
                      AnimatedBuilder(
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
                                  ..multiply(
                                    Matrix4.diagonal3Values(scale, scale, 1),
                                  ),
                                child: child,
                              ),
                            ),
                          );
                        },
                        child: _OpeningCover(
                          book: book,
                          width: coverWidth,
                          accent: accent,
                        ),
                      ),
                      const SizedBox(height: 30),
                      AnimatedBuilder(
                        animation: _reveal,
                        builder: (context, child) => Opacity(
                          opacity: ((_reveal.value - 0.3) / 0.7)
                              .clamp(0.0, 1.0)
                              .toDouble(),
                          child: child,
                        ),
                        child: Column(
                          children: <Widget>[
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 44,
                              ),
                              child: Text(
                                book.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '正在展开',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                letterSpacing: 2.4,
                              ),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: 88,
                              child: LinearProgressIndicator(
                                minHeight: 2,
                                borderRadius: BorderRadius.circular(2),
                                color: accent,
                                backgroundColor: accent.withValues(alpha: 0.16),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(flex: 4),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpeningCover extends StatelessWidget {
  const _OpeningCover({
    required this.book,
    required this.width,
    required this.accent,
  });

  final BookEntry book;
  final double width;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final height = width * 4 / 3;
    return SizedBox(
      width: width + 16,
      height: height + 16,
      child: Stack(
        children: <Widget>[
          Positioned(
            left: 16,
            top: 8,
            right: 0,
            bottom: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant
                      .withValues(alpha: 0.7),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            width: width,
            height: height,
            child: Hero(
              tag: bookCoverHeroTag(book.id),
              transitionOnUserGestures: true,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 30,
                      offset: const Offset(0, 18),
                    ),
                    BoxShadow(
                      color: accent.withValues(alpha: 0.18),
                      blurRadius: 42,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      _coverContent(context),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: 0.018,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: <Color>[
                                  Color(0x33000000),
                                  Color(0x08000000),
                                  Color(0x00000000),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.all(Radius.circular(10)),
                          border: Border.fromBorderSide(
                            BorderSide(color: Color(0x22FFFFFF)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _coverContent(BuildContext context) {
    final coverPath = book.coverPath;
    final fallback = _CoverFallback(book: book, accent: accent);
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
  const _CoverFallback({required this.book, required this.accent});

  final BookEntry book;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[accent, Color.lerp(accent, Colors.black, 0.34)!],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              book.title.characters.isEmpty
                  ? '书'
                  : book.title.characters.first.toString(),
              style: Theme.of(context).textTheme.displayMedium
                  ?.copyWith(color: Colors.white, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 14),
            Text(
              book.title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

class _AtmosphereOrb extends StatelessWidget {
  const _AtmosphereOrb({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: <Color>[
              color.withValues(alpha: 0.09),
              color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}
