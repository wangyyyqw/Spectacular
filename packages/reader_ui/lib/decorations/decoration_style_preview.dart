import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../annotations/annotation.dart';
import 'decoration_image_store.dart';
import 'decoration_image_codec.dart';
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
    this.maxLines = 4,
  });

  /// 预览原文。
  final String text;

  /// 当前样式草稿。
  final ReaderDecorationStyle style;

  /// 本地图片读取器。
  final ReaderDecorationImageStore? images;

  /// 黑白预览。
  final bool inkMode;
  final int maxLines;
  @override
  State<ReaderDecorationStylePreview> createState() =>
      _ReaderDecorationStylePreviewState();
}

class _ReaderDecorationStylePreviewState
    extends State<ReaderDecorationStylePreview> {
  ui.Image? _image;
  ReaderDecorationNineSlice? _imageNineSlice;
  int _generation = 0;
  bool _missing = false;
  TextPainter? _text;

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
    _text?.dispose();
    super.dispose();
  }

  Future<void> _loadImage() async {
    final generation = ++_generation;
    final path = widget.style.backgroundImagePath;
    _image?.dispose();
    _image = null;
    _imageNineSlice = null;
    _missing = false;
    if (path == null || widget.images == null) return;
    try {
      final bytes = await widget.images!.loadImage(path);
      final decoded = await ReaderDecorationImageCodec.decode(bytes);
      if (!mounted || generation != _generation) {
        decoded.image.dispose();
        return;
      }
      setState(() {
        _image = decoded.image;
        _imageNineSlice = decoded.nineSlice;
      });
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _missing = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).textTheme.bodyMedium!;
    final fontSize = base.fontSize! * widget.style.fontSizeScale;
    final previewText = widget.text.isEmpty ? '装饰预览' : widget.text;
    final textScaler = MediaQuery.textScalerOf(context);
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
              _text?.dispose();
              final text = _text = TextPainter(
                text: TextSpan(text: previewText, style: textStyle),
                maxLines: widget.maxLines,
                ellipsis: '…',
                textDirection: Directionality.of(context),
                textScaler: textScaler,
              )..layout(maxWidth: constraints.maxWidth);
              var offset = Offset.zero;
              var extraHeight = 8.0;
              final nineSlice =
                  widget.style.backgroundImageFit ==
                      ReaderDecorationImageFit.nineSlice
                  ? widget.style.backgroundImageNineSlice ??
                        _imageNineSlice ??
                        const ReaderDecorationNineSlice()
                  : null;
              if (_image != null && nineSlice != null && !widget.inkMode) {
                final first = text
                    .getBoxesForSelection(
                      const TextSelection(baseOffset: 0, extentOffset: 1),
                    )
                    .firstOrNull
                    ?.toRect();
                final glyphHeight = first?.height ?? text.preferredLineHeight;
                final bounds = nineSlice.imageRectFor(
                  Rect.fromLTWH(0, 0, 1, glyphHeight),
                  Size(_image!.width.toDouble(), _image!.height.toDouble()),
                );
                final left = (-bounds.left).clamp(
                  0.0,
                  constraints.maxWidth / 3,
                );
                final right = (bounds.right - 1).clamp(
                  0.0,
                  constraints.maxWidth / 3,
                );
                final top = (-bounds.top).clamp(0.0, 16.0);
                final bottom = (bounds.bottom - glyphHeight).clamp(0.0, 16.0);
                offset = Offset(left, top);
                extraHeight += top + bottom;
                text.text = TextSpan(
                  text: previewText,
                  style: textStyle.copyWith(
                    height: math.max(
                      textStyle.height!,
                      (glyphHeight + 2 * math.max(top, bottom) + 4) /
                          textScaler.scale(fontSize),
                    ),
                  ),
                );
                text.layout(
                  maxWidth: math.max(1, constraints.maxWidth - left - right),
                );
              }
              return CustomPaint(
                size: Size(constraints.maxWidth, text.height + extraHeight),
                painter: _DecorationPreviewPainter(
                  text,
                  widget.style,
                  _image,
                  _imageNineSlice,
                  widget.inkMode,
                  offset,
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
  _DecorationPreviewPainter(
    this.text,
    this.style,
    this.image,
    this.imageNineSlice,
    this.inkMode,
    this.offset,
  );
  final TextPainter text;
  final ReaderDecorationStyle style;
  final ui.Image? image;
  final ReaderDecorationNineSlice? imageNineSlice;
  final bool inkMode;
  final Offset offset;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(offset.dx, offset.dy);
    final lines = _lines();
    for (final (line, rects) in lines) {
      for (final rect in rects) {
        final expanded = Rect.fromLTRB(
          rect.left - style.paddingLeft,
          rect.top -
              style.paddingTop.clamp(
                0.0,
                (rect.top - line.baseline + line.ascent).clamp(0.0, 8.0),
              ),
          rect.right + style.paddingRight,
          rect.bottom +
              style.paddingBottom.clamp(
                0.0,
                (line.baseline + line.descent - rect.bottom).clamp(0.0, 8.0),
              ),
        );
        ReaderDecorationPainter.paintBox(
          canvas,
          expanded,
          style,
          image: image,
          imageNineSlice: imageNineSlice,
          clipRect:
              style.backgroundImageFit == ReaderDecorationImageFit.nineSlice
              ? Rect.fromLTWH(
                  -offset.dx,
                  line.baseline - line.ascent,
                  size.width,
                  line.height,
                )
              : null,
          inkMode: inkMode,
        );
      }
    }
    _paintHighlights(canvas, lines, foreground: false);
    text.paint(canvas, Offset.zero);
    _paintHighlights(canvas, lines, foreground: true);
    canvas.restore();
  }

  List<(ui.LineMetrics, List<Rect>)> _lines() => [
    for (final line in text.computeLineMetrics())
      (
        line,
        [
          for (final box in text.getBoxesForSelection(_lineSelection(line)))
            if (!box.toRect().isEmpty) box.toRect(),
        ],
      ),
  ];

  TextSelection _lineSelection(ui.LineMetrics line) {
    final position = text.getPositionForOffset(
      Offset(line.left + line.width / 2, line.baseline - line.ascent / 2),
    );
    final boundary = text.getLineBoundary(position);
    return TextSelection(
      baseOffset: boundary.start,
      extentOffset: boundary.end,
    );
  }

  void _paintHighlights(
    Canvas canvas,
    List<(ui.LineMetrics, List<Rect>)> lines, {
    required bool foreground,
  }) {
    final highlight = style.highlight;
    if (highlight == null) return;
    if (!foreground &&
        !inkMode &&
        [
          ReaderAnnotationStyle.background,
          ReaderAnnotationStyle.halfBackground,
        ].contains(highlight.style)) {
      ReaderDecorationPainter.paintHighlightBackground(canvas, [
        for (final (line, rects) in lines) ...[
          rects,
          if (line.hardBreak) const <Rect>[],
        ],
      ], highlight);
      return;
    }
    for (final (line, rects) in lines) {
      for (final rect in rects) {
        ReaderDecorationPainter.paintHighlight(
          canvas,
          rect,
          highlight,
          foreground: foreground,
          inkMode: inkMode,
          baseline: line.baseline + (inkMode ? 2 : highlight.strokeWidth),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_DecorationPreviewPainter oldDelegate) =>
      oldDelegate.text != text ||
      oldDelegate.style != style ||
      oldDelegate.image != image ||
      oldDelegate.imageNineSlice != imageNineSlice ||
      oldDelegate.offset != offset ||
      oldDelegate.inkMode != inkMode;
}
