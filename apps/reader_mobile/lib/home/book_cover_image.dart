import 'dart:io';

import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';

import '../library/library_store.dart';

/// 封面解码宽度；预解码与显示必须用同一个宽度才会命中同一份缓存。
int coverDecodeWidth(double logicalWidth, double devicePixelRatio) =>
    (logicalWidth * devicePixelRatio).ceil().clamp(96, 1200);

/// 封面图像源；首屏预解码与书架显示共用，键一致才能避免再次解码。
ImageProvider coverImageProvider(String path, int decodeWidth) =>
    ResizeImage.resizeIfNeeded(decodeWidth, null, FileImage(File(path)));

/// 书架、详情、统计与书评共用封面；等比缩放并居中裁切铺满容器。
class BookCoverImage extends StatelessWidget {
  const BookCoverImage({
    super.key,
    required this.book,
    this.width,
    this.height,
    this.showReadabilityBadge = false,
    this.showShadow = false,
    this.shadowOpacity = .12,
  });

  final BookEntry book;
  final double? width;
  final double? height;
  final bool showReadabilityBadge;
  final bool showShadow;
  final double shadowOpacity;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final scheme = Theme.of(context).colorScheme;
        final placeholder = _CoverPlaceholder(
          book: book,
          compact: constraints.maxWidth < 100 || constraints.maxHeight < 140,
        );
        return Semantics(
          label: '${book.title}封面',
          image: true,
          child: Material(
            color: scheme.surface,
            elevation: showShadow ? 2 : 0,
            shadowColor: scheme.shadow.withValues(alpha: shadowOpacity),
            borderRadius: BorderRadius.circular(4),
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(4),
              ),
              foregroundDecoration: BoxDecoration(
                border: Border.all(color: scheme.outlineVariant),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (book.coverPath == null)
                    placeholder
                  else
                    _image(context, constraints, placeholder),
                  if (showReadabilityBadge && book.readabilityLevel >= 2)
                    _ReadabilityBadge(book: book),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );

  Widget _image(
    BuildContext context,
    BoxConstraints constraints,
    Widget placeholder,
  ) {
    final logicalWidth = constraints.maxWidth.isFinite
        ? constraints.maxWidth
        : 160.0;
    final decodeWidth = coverDecodeWidth(
      logicalWidth,
      MediaQuery.devicePixelRatioOf(context),
    );
    return Image(
      image: coverImageProvider(book.coverPath!, decodeWidth),
      key: ValueKey('cover-${book.coverPath}'),
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      excludeFromSemantics: true,
      frameBuilder: (_, child, frame, loaded) =>
          loaded || frame != null ? child : placeholder,
      errorBuilder: (_, _, _) => placeholder,
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder({required this.book, required this.compact});

  final BookEntry book;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = book.title.trim();
    return ExcludeSemantics(
      child: Container(
        key: ValueKey('cover-placeholder-${book.id}'),
        padding: EdgeInsets.all(compact ? 4 : 12),
        color: theme.colorScheme.surfaceContainerLow,
        alignment: Alignment.center,
        child: Text(
          title.isEmpty
              ? '书'
              : compact
              ? title.characters.first
              : title,
          maxLines: compact ? 1 : 3,
          // 封面内文字按图像处理，完整书名由外层语义和书架标题提供。
          textScaler: TextScaler.noScaling,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: compact ? 18 : 16,
            fontWeight: FontWeight.w600,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}

class _ReadabilityBadge extends StatelessWidget {
  const _ReadabilityBadge({required this.book});

  final BookEntry book;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Positioned(
      top: 6,
      right: 6,
      child: Tooltip(
        message: book.readabilityLevel >= 3
            ? '结构异常：进度与目录可能不可靠'
            : '部分内容降级：目录或资源缺失',
        child: Container(
          key: const ValueKey('book-damaged-badge'),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: scheme.errorContainer,
            borderRadius: BorderRadius.circular(4),
          ),
          child: AppIcon(
            AppGlyph.info,
            size: 16,
            color: scheme.onErrorContainer,
          ),
        ),
      ),
    );
  }
}
