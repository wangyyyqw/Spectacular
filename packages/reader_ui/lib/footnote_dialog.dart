import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/image_cache.dart';

import 'icons/app_icon.dart';
import 'theme/reader_frosted_surface.dart';

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = footnote.text;
    final images = footnote.imageUrls;
    final copyText = text?.trim();
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
              Flexible(
                child: Scrollbar(
                  key: const ValueKey('reader-footnote-scrollbar'),
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
                                        if (index > 0)
                                          const SizedBox(height: 14),
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
              if (copyText != null && copyText.isNotEmpty) ...[
                const Divider(height: 1),
                _CopyFootnoteAction(text: copyText),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CopyFootnoteAction extends StatefulWidget {
  const _CopyFootnoteAction({required this.text});

  final String text;

  @override
  State<_CopyFootnoteAction> createState() => _CopyFootnoteActionState();
}

class _CopyFootnoteActionState extends State<_CopyFootnoteAction> {
  Timer? _resetTimer;
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) {
      return;
    }
    setState(() => _copied = true);
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _copied = false);
      }
    });
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          key: const ValueKey('reader-footnote-copy'),
          onPressed: _copy,
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            child: AppIcon(
              _copied ? AppGlyph.check : AppGlyph.copy,
              key: ValueKey(_copied),
              size: 18,
            ),
          ),
          label: Text(_copied ? '已复制' : '复制注释'),
          style: TextButton.styleFrom(
            foregroundColor: _copied
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 12),
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
