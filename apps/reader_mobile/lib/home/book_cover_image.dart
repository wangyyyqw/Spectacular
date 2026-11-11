import 'dart:io';

import 'package:flutter/material.dart';

import '../library/library_store.dart';

/// 书架、详情、统计与书评共用封面；完整保留原图比例和边缘。
class BookCoverImage extends StatelessWidget {
  const BookCoverImage({
    super.key,
    required this.book,
    this.width,
    this.height,
    this.showReadabilityBadge = false,
  });

  final BookEntry book;
  final double? width;
  final double? height;
  final bool showReadabilityBadge;

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
    final decodeWidth = (logicalWidth * MediaQuery.devicePixelRatioOf(context))
        .ceil()
        .clamp(96, 1200);
    return Image.file(
      File(book.coverPath!),
      key: ValueKey('cover-${book.coverPath}'),
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.contain,
      cacheWidth: decodeWidth,
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
          child: Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: scheme.onErrorContainer,
          ),
        ),
      ),
    );
  }
}
