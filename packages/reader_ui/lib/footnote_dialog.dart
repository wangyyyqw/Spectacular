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
    final text = footnote.text;
    final images = footnote.imageUrls;
    return AlertDialog(
      key: const ValueKey('reader-footnote-dialog'),
      title: Row(
        children: [
          const Icon(Icons.sticky_note_2_outlined, size: 20),
          const SizedBox(width: 8),
          Text(_title),
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 420,
          maxHeight: MediaQuery.sizeOf(context).height * 0.55,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (text != null && text.isNotEmpty)
                SelectableText(
                  text,
                  key: const ValueKey('reader-footnote-text'),
                  style: const TextStyle(height: 1.65),
                ),
              for (var index = 0; index < images.length; index++) ...[
                if (text != null && text.isNotEmpty || index > 0)
                  const SizedBox(height: 12),
                _FootnoteImage(url: images[index], imageCache: imageCache),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
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
