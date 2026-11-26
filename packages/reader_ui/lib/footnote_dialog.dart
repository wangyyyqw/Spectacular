import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/image_cache.dart';

import 'icons/app_icon.dart';
import 'theme/reader_panel_theme.dart';
import 'theme/reader_frosted_surface.dart';
import 'theme/reader_theme.dart';

/// 阅读页注释的展示样式。
enum ReaderFootnoteStyle {
  /// 底部弹窗。
  dialog('弹窗'),

  /// 指向注号的圆角气泡。
  bubble('气泡'),

  /// 右侧带撕边的纸条。
  paper('纸条');

  const ReaderFootnoteStyle(this.label);

  final String label;

  /// 从持久化值解析；未知值使用兼容默认样式。
  static ReaderFootnoteStyle fromId(String? value) =>
      ReaderFootnoteStyle.values.firstWhere(
        (style) => style.name == value,
        orElse: () => ReaderFootnoteStyle.dialog,
      );
}

/// 阅读页注释弹窗：展示多段文字与书内图片，不进入正文排版。
class ReaderFootnoteDialog extends StatelessWidget {
  /// 创建注释弹窗。
  const ReaderFootnoteDialog({
    super.key,
    required this.footnote,
    this.imageCache,
    this.style = ReaderFootnoteStyle.dialog,
    this.anchor,
    this.contentWidth,
  });

  /// 当前点击的注释。
  final PageFootnote footnote;

  /// 书内图片解码缓存。
  final DecodedImageCache? imageCache;

  /// 当前展示样式。
  final ReaderFootnoteStyle style;

  /// 正文中被点击注号的屏幕坐标；弹窗样式不使用。
  final Offset? anchor;

  /// 正文排版区域宽度；气泡居中并与正文等宽。
  final double? contentWidth;

  @override
  Widget build(BuildContext context) {
    if (style != ReaderFootnoteStyle.dialog) {
      return _buildCallout(context);
    }
    return _buildDialog(context);
  }

  Widget _buildDialog(BuildContext context) {
    final theme = Theme.of(context);
    final text = footnote.text;
    final images = footnote.imageUrls;
    final paragraphs = <String>[
      for (final paragraph in (text ?? '').split(RegExp(r'\n+')))
        if (paragraph.trim().isNotEmpty) paragraph.trim(),
    ];
    return Material(
      key: const ValueKey('reader-footnote-dialog'),
      color: ReaderFrostedSurface.panelColorOf(context),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.40,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Scrollbar(
                  key: const ValueKey('reader-footnote-scrollbar'),
                  child: SingleChildScrollView(
                    key: const ValueKey('reader-footnote-scroll'),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 2, 20, 24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (paragraphs.isNotEmpty)
                                SelectionArea(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      for (
                                        var index = 0;
                                        index < paragraphs.length;
                                        index++
                                      ) ...[
                                        if (index > 0)
                                          const SizedBox(height: 14),
                                        Text(
                                          paragraphs[index],
                                          key: ValueKey(
                                            'reader-footnote-paragraph-$index',
                                          ),
                                          textAlign: TextAlign.justify,
                                          style: theme.textTheme.bodyLarge
                                              ?.copyWith(height: 1.75),
                                        ),
                                      ],
                                    ],
                                  ),
                                )
                              else if (images.isEmpty)
                                _EmptyFootnote(theme: theme),
                              for (
                                var index = 0;
                                index < images.length;
                                index++
                              ) ...[
                                if (paragraphs.isNotEmpty || index > 0)
                                  const SizedBox(height: 18),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: _FootnoteImage(
                                    url: images[index],
                                    imageCache: imageCache,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCallout(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final safe = MediaQuery.viewPaddingOf(context);
    final point = anchor ?? Offset(screen.width / 2, screen.height / 2);
    final bubble = style == ReaderFootnoteStyle.bubble;
    final width = bubble
        ? (contentWidth ?? screen.width - 24).clamp(0.0, screen.width)
        : screen.width * 0.85;
    final belowSpace = screen.height - point.dy - safe.bottom - 18;
    final aboveSpace = point.dy - safe.top - 18;
    final below = belowSpace >= 150 || belowSpace >= aboveSpace;
    final availableHeight = math
        .min(
          screen.height * (bubble ? 0.40 : 0.15),
          math.max(0.0, below ? belowSpace : aboveSpace),
        )
        .toDouble();
    final top = below
        ? (point.dy + 10)
              .clamp(
                safe.top + 4,
                math.max(
                  safe.top + 4,
                  screen.height - safe.bottom - availableHeight,
                ),
              )
              .toDouble()
        : (point.dy - availableHeight - 10)
              .clamp(
                safe.top + 4,
                math.max(
                  safe.top + 4,
                  screen.height - safe.bottom - availableHeight,
                ),
              )
              .toDouble();
    final left = bubble ? (screen.width - width) / 2 : 0.0;
    final paragraphs = <String>[
      for (final paragraph in (footnote.text ?? '').split(RegExp(r'\n+')))
        if (paragraph.trim().isNotEmpty) paragraph.trim(),
    ];
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: left,
          top: top,
          width: width,
          height: availableHeight,
          // 短注释贴住靠近注号的一侧，最大高度只限制长内容，不参与实际间距。
          child: Align(
            alignment: below ? Alignment.topCenter : Alignment.bottomCenter,
            child: _FootnoteCallout(
              bubble: bubble,
              pointerLeft: (point.dx - left - 8)
                  .clamp(14.0, math.max(14.0, width - 30))
                  .toDouble(),
              pointerAtBottom: !below,
              maxHeight: availableHeight,
              paragraphs: paragraphs,
              images: footnote.imageUrls,
              imageCache: imageCache,
            ),
          ),
        ),
      ],
    );
  }
}

/// 在正文上方打开气泡或纸条样式的注释。
Future<void> showReaderFootnotePopup({
  required BuildContext context,
  required PageFootnote footnote,
  required ReaderFootnoteStyle style,
  required Offset anchor,
  required double contentWidth,
  DecodedImageCache? imageCache,
  ReaderTheme? readerTheme,
}) async {
  final reduceMotion =
      ReaderFrostedScope.inkModeOf(context) ||
      readerTheme?.id == 'ink' ||
      MediaQuery.disableAnimationsOf(context);
  final themes = InheritedTheme.capture(
    from: context,
    to: Navigator.of(context, rootNavigator: true).context,
  );
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭注释',
    // 与底部弹窗注释一致：使用底部弹层遮罩色压暗阅读页。
    barrierColor:
        Theme.of(context).bottomSheetTheme.modalBarrierColor ?? Colors.black54,
    pageBuilder: (context, animation, _) {
      Widget dialog = ReaderFootnoteDialog(
        footnote: footnote,
        style: style,
        anchor: anchor,
        contentWidth: contentWidth,
        imageCache: imageCache,
      );
      if (style == ReaderFootnoteStyle.paper && !reduceMotion) {
        dialog = SlideTransition(
          position: animation.drive(
            Tween<Offset>(
              begin: const Offset(-1, 0),
              end: Offset.zero,
            ).chain(CurveTween(curve: Curves.easeOutCubic)),
          ),
          child: dialog,
        );
      }
      Widget child = Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
          Positioned.fill(child: dialog),
        ],
      );
      if (readerTheme != null) {
        child = ReaderPanelTheme(theme: readerTheme, child: child);
      }
      return themes.wrap(child);
    },
    transitionDuration: reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 220),
    transitionBuilder: (context, animation, _, child) {
      if (style == ReaderFootnoteStyle.paper || reduceMotion) {
        return child;
      }
      return FadeTransition(opacity: animation, child: child);
    },
  );
}

class _FootnoteCallout extends StatelessWidget {
  const _FootnoteCallout({
    required this.bubble,
    required this.pointerLeft,
    required this.pointerAtBottom,
    required this.maxHeight,
    required this.paragraphs,
    required this.images,
    required this.imageCache,
  });

  final bool bubble;
  final double pointerLeft;
  final bool pointerAtBottom;
  final double maxHeight;
  final List<String> paragraphs;
  final List<String> images;
  final DecodedImageCache? imageCache;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final background = colors.surfaceContainerLow;
    final content = Padding(
      // 上下留白放在滚动视口外，滚动时文字也不会贴到气泡/纸条边缘。
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (paragraphs.isNotEmpty)
                SelectionArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (
                        var index = 0;
                        index < paragraphs.length;
                        index++
                      ) ...[
                        if (index > 0) const SizedBox(height: 8),
                        Text(
                          paragraphs[index],
                          textAlign: TextAlign.justify,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(color: colors.onSurface, height: 1.5),
                        ),
                      ],
                    ],
                  ),
                )
              else if (images.isEmpty)
                Text(
                  '这条注释暂无内容',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              for (final image in images) ...[
                if (paragraphs.isNotEmpty) const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: _FootnoteImage(url: image, imageCache: imageCache),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (!bubble) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: PhysicalShape(
          key: const ValueKey<String>('reader-footnote-callout-paper'),
          clipper: const _TornPaperClipper(),
          color: background,
          elevation: 5,
          shadowColor: Colors.black26,
          child: content,
        ),
      );
    }
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: EdgeInsets.only(
              top: pointerAtBottom ? 0 : 8,
              bottom: pointerAtBottom ? 8 : 0,
            ),
            child: Material(
              key: const ValueKey<String>('reader-footnote-callout-bubble'),
              color: background,
              elevation: 5,
              shadowColor: Colors.black26,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(5),
                side: BorderSide(color: colors.outlineVariant),
              ),
              clipBehavior: Clip.antiAlias,
              child: content,
            ),
          ),
          Positioned(
            left: pointerLeft,
            top: pointerAtBottom ? null : 0,
            bottom: pointerAtBottom ? 0 : null,
            child: Transform.rotate(
              angle: pointerAtBottom ? math.pi : 0,
              child: CustomPaint(
                size: const Size(16, 9),
                painter: _BubblePointerPainter(color: background),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BubblePointerPainter extends CustomPainter {
  const _BubblePointerPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_BubblePointerPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _TornPaperClipper extends CustomClipper<Path> {
  const _TornPaperClipper();

  @override
  Path getClip(Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0);
    const step = 9.0;
    var y = step;
    var inset = 5.0;
    while (y < size.height) {
      path.lineTo(size.width - inset, y);
      inset = inset == 5 ? 1 : 5;
      y += step;
    }
    path
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    return path;
  }

  @override
  bool shouldReclip(_TornPaperClipper oldClipper) => false;
}

class _EmptyFootnote extends StatelessWidget {
  const _EmptyFootnote({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: [
          AppIcon(
            AppGlyph.article,
            size: 28,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 8),
          Text(
            '这条注释暂无内容',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _FootnoteImage extends StatefulWidget {
  const _FootnoteImage({required this.url, required this.imageCache});

  final String url;
  final DecodedImageCache? imageCache;

  @override
  State<_FootnoteImage> createState() => _FootnoteImageState();
}

class _FootnoteImageState extends State<_FootnoteImage> {
  Future<ui.Image?>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  @override
  void didUpdateWidget(covariant _FootnoteImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.imageCache != widget.imageCache) {
      _future = _load();
    }
  }

  Future<ui.Image?> _load() {
    final cache = widget.imageCache;
    if (cache == null) {
      return Future<ui.Image?>.value();
    }
    final width = MediaQuery.sizeOf(context).width.clamp(160.0, 420.0);
    return cache.load(
      widget.url,
      displayWidth: width,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ui.Image?>(
      future: _future,
      builder: (context, snapshot) {
        final image = snapshot.data;
        if (image != null) {
          return AspectRatio(
            aspectRatio: image.width / image.height,
            child: RawImage(
              image: image,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
            ),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        return Text(
          '图片加载失败',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        );
      },
    );
  }
}
