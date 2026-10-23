import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../css/computed_style.dart';
import '../layout/paginator.dart';
import '../layout/text_layout.dart';

/// 按页绘制文本与背景。
class PagePainter {
  /// 创建绘制器。
  const PagePainter({this.background = const Color(0xFFFFFFFF)});

  /// 页面背景色。
  final Color background;

  /// 绘制一页。
  ///
  /// [contentWidth] 用于 text-align 的水平定位；不传时取页面宽。
  void paint(
    Canvas canvas,
    PageContent page, {
    required Size pageSize,
    double? contentWidth,
  }) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, pageSize.width, pageSize.height),
      Paint()..color = background,
    );

    final width = contentWidth ?? pageSize.width;
    var y = page.topPadding;
    for (final slice in page.slices) {
      final style = slice.block.style ?? ComputedStyle(<String, String>{});
      final textStyle = TextLayoutEngine.textStyleFor(style);
      if (slice.startLine == 0) {
        y += slice.block.spaceBefore;
      }
      for (
        var lineIndex = slice.startLine;
        lineIndex < slice.endLine;
        lineIndex++
      ) {
        final line = slice.block.layout.lines[lineIndex];
        final lineText = slice.block.layout.text.substring(
          line.start,
          line.end,
        );
        if (lineText.isNotEmpty) {
          final painter = TextPainter(
            text: TextSpan(text: lineText, style: textStyle),
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.left,
          )..layout();
          final indent = math.max(0.0, line.indent);
          final available = math.max(0.0, width - indent);
          final x = switch (style.textAlign) {
            CssTextAlign.center => indent + (available - line.width) / 2,
            CssTextAlign.right || CssTextAlign.end => width - line.width,
            _ => indent,
          };
          painter.paint(canvas, Offset(x, y));
        }
        y += line.height;
      }
      if (slice.endLine == slice.block.layout.lineCount) {
        y += slice.block.spaceAfter;
      }
    }
  }
}
