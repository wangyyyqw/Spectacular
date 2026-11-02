import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:reader_core/epub/footnote.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/image_cache.dart';

/// 阅读页注释弹窗：展示多段文字与书内图片，不进入正文排版。
class ReaderFootnoteDialog extends StatelessWidget {
  /// 创建注释弹窗。
  const ReaderFootnoteDialog({
    super.key,
    required this.footnote,
    this.imageCache,
  });

  /// 当前点击的注释。
  final PageFootnote footnote;

  /// 书内图片解码缓存。
  final DecodedImageCache? imageCache;

  String get _title => switch (footnote.kind) {
    NoteKind.endnote => '尾注',
    _ => '脚注',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = footnote.text;
    final images = footnote.imageUrls;
    return Material(
      key: const ValueKey('reader-footnote-dialog'),
      color: theme.colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.78,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.sticky_note_2_outlined,
                        size: 20,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_title, style: theme.textTheme.titleMedium),
                          Text(
                            '正文注释引用',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('reader-footnote-close'),
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: '关闭注释',
                      icon: const Icon(Icons.close, size: 20),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (text != null && text.isNotEmpty)
                        SelectableText(
                          text,
                          key: const ValueKey('reader-footnote-text'),
                          style: theme.textTheme.bodyLarge?.copyWith(
                            height: 1.75,
                          ),
                        )
                      else if (images.isEmpty)
                        Text(
                          '这条注释暂无内容',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      for (var index = 0; index < images.length; index++) ...[
                        if (text != null && text.isNotEmpty || index > 0)
                          const SizedBox(height: 14),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
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
            ],
          ),
        ),
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
