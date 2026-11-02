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
    NoteKind.footnote => '脚注',
    NoteKind.link => '注释',
  };

  IconData get _icon => switch (footnote.kind) {
    NoteKind.endnote => Icons.article_outlined,
    NoteKind.footnote => Icons.sticky_note_2_outlined,
    NoteKind.link => Icons.link,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = footnote.text;
    final images = footnote.imageUrls;
    final paragraphs = <String>[
      for (final paragraph in (text ?? '').split(RegExp(r'\n+')))
        if (paragraph.trim().isNotEmpty) paragraph.trim(),
    ];
    final characterCount = paragraphs
        .join()
        .replaceAll(RegExp(r'\s+'), '')
        .length;
    final details = <String>[
      if (characterCount > 0) '$characterCount 字',
      if (images.isNotEmpty) '${images.length} 张图片',
    ];
    final label = footnote.label.trim();
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
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: Icon(
                            _icon,
                            size: 21,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    _title,
                                    style: theme.textTheme.titleMedium,
                                  ),
                                  if (label.isNotEmpty)
                                    Container(
                                      key: const ValueKey(
                                        'reader-footnote-label',
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            theme.colorScheme.surfaceContainer,
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                        border: Border.all(
                                          color:
                                              theme.colorScheme.outlineVariant,
                                        ),
                                      ),
                                      child: Text(
                                        label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                details.isEmpty
                                    ? '正文注释引用'
                                    : '正文注释引用 · ${details.join(' · ')}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
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
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  key: const ValueKey('reader-footnote-scroll'),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
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
                                      if (index > 0) const SizedBox(height: 14),
                                      Text(
                                        paragraphs[index],
                                        key: ValueKey(
                                          'reader-footnote-paragraph-$index',
                                        ),
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

class _EmptyFootnote extends StatelessWidget {
  const _EmptyFootnote({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(
            Icons.notes_outlined,
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
