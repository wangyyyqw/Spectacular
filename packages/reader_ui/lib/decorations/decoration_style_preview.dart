import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../annotations/annotation.dart';
import 'decoration_image_store.dart';
import 'decoration_painter.dart';
import 'decoration_style.dart';

/// 使用正文同一盒绘制器的逐行装饰预览。
class ReaderDecorationStylePreview extends StatefulWidget {
  /// 创建实时预览。
  const ReaderDecorationStylePreview({
    super.key,
    required this.text,
    required this.style,
    this.images,
    this.inkMode = false,
  });

  /// 预览原文。
  final String text;

  /// 当前样式草稿。
  final ReaderDecorationStyle style;

  /// 本地图片读取器。
  final ReaderDecorationImageStore? images;

  /// 黑白预览。
  final bool inkMode;
  @override
  State<ReaderDecorationStylePreview> createState() =>
      _ReaderDecorationStylePreviewState();
}

class _ReaderDecorationStylePreviewState
    extends State<ReaderDecorationStylePreview> {
  ui.Image? _image;
  int _generation = 0;
  bool _missing = false;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(covariant ReaderDecorationStylePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.style.backgroundImagePath !=
            widget.style.backgroundImagePath ||
        oldWidget.images != widget.images) {
      _loadImage();
    }
  }

  @override
  void dispose() {
    _generation++;
    _image?.dispose();
    super.dispose();
  }

  Future<void> _loadImage() async {
    final generation = ++_generation;
    final path = widget.style.backgroundImagePath;
    _image?.dispose();
    _image = null;
    _missing = false;
    if (path == null || widget.images == null) return;
    try {
      final bytes = await widget.images!.loadImage(path);
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted || generation != _generation) {
        frame.image.dispose();
        return;
      }
      setState(() => _image = frame.image);
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _missing = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).textTheme.bodyMedium!;
    final fontSize = base.fontSize! * widget.style.fontSizeScale;
    final textStyle = base.copyWith(
      fontFamily: widget.style.fontFamily,
      fontSize: fontSize,
      fontWeight: widget.style.fontWeight == null
          ? null
          : FontWeight.values[widget.style.fontWeight! ~/ 100 - 1],
      fontStyle: widget.style.italic == null
          ? null
          : widget.style.italic!
          ? FontStyle.italic
          : FontStyle.normal,
      letterSpacing:
          (base.letterSpacing ?? 0) +
          base.fontSize! * widget.style.letterSpacingEm,
      color: widget.inkMode
          ? Colors.black
          : widget.style.textColor == null
          ? null
          : Color(widget.style.textColor!).withValues(
              alpha:
                  Color(widget.style.textColor!).a *
                  widget.style.textColorOpacity,
            ),
      height: 1.65,
    );
    return Container(
      key: const ValueKey<String>('decoration-style-preview'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final text = TextPainter(
                text: TextSpan(
                  text: widget.text.isEmpty ? '装饰预览' : widget.text,
                  style: textStyle,
                ),
                maxLines: 4,
                ellipsis: '…',
                textDirection: Directionality.of(context),
              )..layout(maxWidth: constraints.maxWidth);
              return CustomPaint(
                size: Size(constraints.maxWidth, text.height + 8),
                painter: _DecorationPreviewPainter(
                  text,
                  widget.style,
                  _image,
                  widget.inkMode,
                ),
              );
            },
          ),
          if (_missing) const Text('图片不可用，已回退到背景色'),
        ],
      ),
    );
  }
}

class _DecorationPreviewPainter extends CustomPainter {
  _DecorationPreviewPainter(this.text, this.style, this.image, this.inkMode);
  final TextPainter text;
  final ReaderDecorationStyle style;
  final ui.Image? image;
  final bool inkMode;
  @override
  void paint(Canvas canvas, Size size) {
    for (final line in text.computeLineMetrics()) {
      final leading =
          (line.height - line.ascent - line.descent).clamp(0.0, 16.0) / 2;
      final rect = Rect.fromLTRB(
        line.left - style.paddingLeft,
        line.baseline - line.ascent - style.paddingTop.clamp(0.0, leading),
        line.left + line.width + style.paddingRight,
        line.baseline + line.descent + style.paddingBottom.clamp(0.0, leading),
      );
      ReaderDecorationPainter.paintBox(
        canvas,
        rect,
        style,
        image: image,
        inkMode: inkMode,
      );
    }
    _paintHighlights(canvas, foreground: false);
    text.paint(canvas, Offset.zero);
    _paintHighlights(canvas, foreground: true);
  }

  void _paintHighlights(Canvas canvas, {required bool foreground}) {
    final highlight = style.highlight;
    if (highlight == null) return;
    Rect? previous;
    for (final line in text.computeLineMetrics()) {
      final rect = Rect.fromLTRB(
        line.left,
        line.baseline - line.ascent,
        line.left + line.width,
        line.baseline + line.descent,
      );
      ReaderDecorationPainter.paintHighlight(
        canvas,
        rect,
        highlight,
        foreground: foreground,
        inkMode: inkMode,
        baseline: line.baseline + highlight.strokeWidth,
      );
      if (!foreground &&
          !inkMode &&
          highlight.style == ReaderAnnotationStyle.background &&
          highlight.joinLines &&
          previous != null) {
        ReaderDecorationPainter.paintHighlightGap(
          canvas,
          previous,
          rect,
          highlight,
        );
      }
      previous = rect;
    }
  }

  @override
  bool shouldRepaint(_DecorationPreviewPainter oldDelegate) => true;
}
