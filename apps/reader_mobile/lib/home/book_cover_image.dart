import 'dart:io';

import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';

import '../library/library_store.dart';
import '../book_source/book_cover_url.dart';
import '../diagnostics/reader_log.dart';
export '../book_source/book_cover_url.dart';

/// 共用封面的圆角，书目卡片外框沿用同一尺寸。
const bookCoverRadius = BorderRadius.all(Radius.circular(4));

/// 拖动窗口时按 64 像素档位稳定解码尺寸，避免逐像素重建图像源。
int _coverDecodeBucket(int value) =>
    (((value + 63) ~/ 64) * 64).clamp(96, 1200);

/// 封面解码宽度；预解码与显示必须用同一个宽度才会命中同一份缓存。
int coverDecodeWidth(double logicalWidth, double devicePixelRatio) =>
    _coverDecodeBucket((logicalWidth * devicePixelRatio).ceil());

/// 与显示尺寸匹配的解码高度，避免只按宽度解码造成长封面占用过多内存。
int coverDecodeHeight(double logicalHeight, double devicePixelRatio) =>
    _coverDecodeBucket((logicalHeight * devicePixelRatio).ceil());

/// 首屏预解码与按需显示使用相同尺寸键，共享 Flutter 的内存图像缓存。
ImageProvider coverImageProvider(
  String path,
  int decodeWidth, {
  int? decodeHeight,
}) => ResizeImage.resizeIfNeeded(
  decodeWidth,
  decodeHeight,
  FileImage(File(path)),
);

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
            borderRadius: bookCoverRadius,
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: bookCoverRadius,
              ),
              foregroundDecoration: BoxDecoration(
                border: Border.all(color: scheme.outlineVariant),
                borderRadius: bookCoverRadius,
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
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final decodeWidth = coverDecodeWidth(logicalWidth, devicePixelRatio);
    if (book.coverPath != null) {
      return _CoverImage(
        book: book,
        constraints: constraints,
        placeholder: placeholder,
      );
    }
    final remote = normalizeBookCoverUrl(book.remoteCoverUrl);
    if (remote == null) return placeholder;
    return _RemoteCover(
      key: ValueKey(remote),
      url: remote,
      headers: httpHeaders,
      decodeWidth: decodeWidth,
      placeholder: placeholder,
    );
  }
}

/// 解码新尺寸期间保留上一帧封面，只在首次加载或失败时露出占位。
class _CoverImage extends StatefulWidget {
  const _CoverImage({
    required this.book,
    required this.constraints,
    required this.placeholder,
  });

  final BookEntry book;
  final BoxConstraints constraints;
  final Widget placeholder;

  @override
  State<_CoverImage> createState() => _CoverImageState();
}

class _CoverImageState extends State<_CoverImage> {
  bool _loaded = false;

  @override
  void didUpdateWidget(covariant _CoverImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.book.coverPath != widget.book.coverPath) _loaded = false;
  }

  @override
  Widget build(BuildContext context) {
    final logicalWidth = widget.constraints.maxWidth.isFinite
        ? widget.constraints.maxWidth
        : 160.0;
    final logicalHeight = widget.constraints.maxHeight.isFinite
        ? widget.constraints.maxHeight
        : logicalWidth * 4 / 3;
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (!_loaded) widget.placeholder,
        Image(
          image: coverImageProvider(
            widget.book.coverPath!,
            coverDecodeWidth(logicalWidth, devicePixelRatio),
            decodeHeight: coverDecodeHeight(logicalHeight, devicePixelRatio),
          ),
          key: ValueKey('cover-${widget.book.coverPath}'),
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          excludeFromSemantics: true,
          frameBuilder: (_, child, frame, synchronous) {
            final ready = synchronous || frame != null;
            if (ready && !_loaded) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && !_loaded) setState(() => _loaded = true);
              });
            }
            return _loaded || ready ? child : const SizedBox.shrink();
          },
          errorBuilder: (_, _, _) {
            if (_loaded) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _loaded) setState(() => _loaded = false);
              });
            }
            return const SizedBox.shrink();
          },
        ),
      ],
    );
  }
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

/// 网络或解码失败后换豆瓣节点；保留图片身份、比例和书名占位。
class _RemoteCover extends StatefulWidget {
  const _RemoteCover({
    super.key,
    required this.url,
    required this.headers,
    required this.decodeWidth,
    required this.placeholder,
  });
  final String url;
  final Map<String, String> headers;
  final int decodeWidth;
  final Widget placeholder;
  @override
  State<_RemoteCover> createState() => _RemoteCoverState();
}

class _RemoteCoverState extends State<_RemoteCover> {
  late final _urls = bookCoverCandidates(widget.url);
  int _attempt = 0;
  bool _retryQueued = false;
  void _retry() {
    if (_retryQueued || _attempt + 1 >= _urls.length) return;
    _retryQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _attempt++;
        _retryQueued = false;
      });
    });
    // 异步图片错误不一定发生在帧内，单独注册回调不会启动下一帧。
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) {
    final url = _urls[_attempt];
    return Image.network(
      url,
      headers: {...bookCoverHeaders(url), ...widget.headers},
      key: ValueKey('cover-$url'),
      width: double.infinity,
      height: double.infinity,
      fit: BoxFit.cover,
      cacheWidth: widget.decodeWidth,
      gaplessPlayback: true,
      excludeFromSemantics: true,
      frameBuilder: (_, child, frame, loaded) =>
          loaded || frame != null ? child : widget.placeholder,
      errorBuilder: (_, error, _) {
        recordAppEvent(
          'book_cover_failed',
          fields: {
            'douban': Uri.parse(url).host.endsWith('.doubanio.com'),
            'attempt': _attempt + 1,
            'status_code': error is NetworkImageLoadException
                ? error.statusCode
                : 0,
            'error': error,
          },
        );
        _retry();
        return widget.placeholder;
      },
    );
  }
}
