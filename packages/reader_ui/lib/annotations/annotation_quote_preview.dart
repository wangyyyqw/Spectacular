import 'package:flutter/material.dart';

import 'annotation.dart';
import 'annotation_style_painter.dart';

/// 逐行展示原文标记，想法图标独立放在文字外侧。
class AnnotationQuotePreview extends StatelessWidget {
  /// 创建原文预览。
  const AnnotationQuotePreview({
    super.key,
    required this.quote,
    required this.color,
    required this.style,
    required this.opacity,
    this.strokeWidth = 1.8,
    this.inkMode = false,
    this.thought = false,
  });

  /// 原文。
  final String quote;

  /// 标记颜色。
  final int color;

  /// 标记样式。
  final ReaderAnnotationStyle style;

  /// 可见强度。
  final double opacity;

  /// 线宽。
  final double strokeWidth;

  /// 黑白预览。
  final bool inkMode;

  /// 想法预览增加独立便签图标。
  final bool thought;

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.bodyMedium!.copyWith(
      height: 1.55,
      color: inkMode
          ? Colors.black
          : style == ReaderAnnotationStyle.tint
          ? Color(color).withValues(alpha: opacity)
          : null,
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final text = TextPainter(
                  text: TextSpan(text: quote, style: textStyle),
                  maxLines: 4,
                  ellipsis: '…',
                  textDirection: Directionality.of(context),
                )..layout(maxWidth: constraints.maxWidth);
                return CustomPaint(
                  size: Size(constraints.maxWidth, text.height + 3),
                  painter: _QuotePainter(
                    text,
                    Color(inkMode ? 0xFF000000 : color),
                    inkMode ? style.inkStyle : style,
                    inkMode ? 1 : opacity,
                    inkMode ? 2 : strokeWidth,
                  ),
                );
              },
            ),
          ),
          if (thought) ...[
            const SizedBox(width: 8),
            Icon(
              Icons.sticky_note_2_outlined,
              size: 16,
              color: Color(inkMode ? 0xFF000000 : color),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuotePainter extends CustomPainter {
  _QuotePainter(
    this.text,
    this.color,
    this.style,
    this.opacity,
    this.strokeWidth,
  );
  final TextPainter text;
  final Color color;
  final ReaderAnnotationStyle style;
  final double opacity;
  final double strokeWidth;
  @override
  void paint(Canvas canvas, Size size) {
    for (final line in text.computeLineMetrics()) {
      AnnotationStylePainter.paint(
        canvas,
        Rect.fromLTWH(
          line.left,
          line.baseline - line.ascent,
          line.width,
          line.height,
        ),
        color: color,
        style: style,
        fillAlpha: opacity,
        strokeAlpha: opacity,
        strokeWidth: strokeWidth,
      );
    }
    text.paint(canvas, Offset.zero);
  }

  @override
  bool shouldRepaint(_QuotePainter oldDelegate) => true;
}
