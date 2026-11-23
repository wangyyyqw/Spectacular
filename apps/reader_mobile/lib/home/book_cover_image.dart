import 'dart:io';

import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';

import '../library/library_store.dart';

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
    this.httpHeaders = const {},
  });

  final BookEntry book;
  final double? width;
  final double? height;
  final bool showReadabilityBadge;
  final bool showShadow;
  final double shadowOpacity;

  /// 来源图片的必要请求头，例如豆瓣的封面 Referer。
  final Map<String, String> httpHeaders;

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
    final decodeWidth = (logicalWidth * MediaQuery.devicePixelRatioOf(context))
        .ceil()
        .clamp(96, 1200);
    if (book.coverPath != null) {
      return Image.file(
        File(book.coverPath!),
        key: ValueKey('cover-${book.coverPath}'),
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        cacheWidth: decodeWidth,
        gaplessPlayback: true,
        excludeFromSemantics: true,
        frameBuilder: (_, child, frame, loaded) =>
            loaded || frame != null ? child : placeholder,
        errorBuilder: (_, _, _) => placeholder,
      );
    }
    final remote = normalizeBookCoverUrl(book.remoteCoverUrl);
    if (remote == null) return placeholder;
    final sourceHeaders = {
      if (Uri.parse(remote).host.endsWith('.doubanio.com')) ...const {
        'Referer': 'https://book.douban.com/',
        'User-Agent': 'Mozilla/5.0',
      },
      ...httpHeaders,
    };
    return Image.network(
      remote,
      headers: sourceHeaders,
      key: ValueKey('cover-$remote'),
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.cover,
      cacheWidth: decodeWidth,
      gaplessPlayback: true,
      excludeFromSemantics: true,
      frameBuilder: (_, child, frame, loaded) =>
          loaded || frame != null ? child : placeholder,
      errorBuilder: (_, _, _) => placeholder,
    );
  }
}

/// 兼容协议省略、豆瓣图片节点及过期的番茄签名封面。
String? normalizeBookCoverUrl(String? value, {DateTime? now}) {
  var url = value?.trim() ?? '';
  if (url.startsWith('//')) url = 'https:$url';
  final uri = Uri.tryParse(url);
  if (uri == null ||
      !['https', 'http'].contains(uri.scheme) ||
      uri.host.isEmpty) {
    return null;
  }
  if (RegExp(r'^img\d+\.doubanio\.com$').hasMatch(uri.host)) {
    return uri.replace(scheme: 'https', host: 'img1.doubanio.com').toString();
  }
  if (uri.host.endsWith('.fqnovelpic.com') &&
      uri.path.startsWith('/novel-pic/')) {
    final expires = int.tryParse(uri.queryParameters['x-expires'] ?? '');
    if (expires != null &&
        expires <= (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000) {
      final image = uri.path.substring('/novel-pic/'.length).split('~').first;
      if (image.isNotEmpty && !image.contains('/')) {
        return 'https://p3-novel.byteimg.com/origin/novel-pic/$image';
      }
    }
  }
  return url;
}

/// 把阅微封面地址附加到本地书目；本地已有封面时不替换。
List<BookEntry> withRemoteCovers(
  List<BookEntry> books,
  Map<String, String> covers,
) => <BookEntry>[
  for (final book in books)
    if (covers[book.id] case final cover?)
      book.withRemoteCover(cover)
    else
      book,
];

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
