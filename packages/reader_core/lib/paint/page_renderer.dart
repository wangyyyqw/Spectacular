import 'package:flutter/painting.dart';

import '../css/computed_style.dart';
import '../layout/paginator.dart';
import '../layout/text_layout.dart';
import '../text/justify.dart';

/// 按页绘制文本与背景。
class PagePainter {
  /// 创建绘制器。
  const PagePainter({this.background = const Color(0xFFFFFFFF)});

  /// 页面背景色。
  final Color background;

  /// 绘制一页。
  ///
  /// 行的水平位置由布局阶段按 text-align 算好（[LineBox.offsetX]）；
  /// 行内样式取自 [TextLayoutResult.runs]（混排字号、行内元素）；
  /// justify 行把余量按间隙分摊到左侧字符的字距上（§8.4）。
  void paint(Canvas canvas, PageContent page, {required Size pageSize}) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, pageSize.width, pageSize.height),
      Paint()..color = background,
    );

    var y = page.topPadding;
    for (final slice in page.slices) {
      final style = slice.block.style ?? ComputedStyle(<String, String>{});
      final textStyle = TextLayoutEngine.textStyleFor(style);
      if (slice.startLine == 0) {
        y += slice.block.spaceBefore;
      }
      // 跨页块只画本页可见的行（§60.8）：裁剪后即使字号/行高有浮点误差，
      // 墨迹也不会越到下一块或下一页。
      canvas.save();
      canvas.clipRect(slice.clipRect(y, pageSize.width));
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
            text: _lineSpan(slice.block.layout, line, textStyle),
            textDirection: TextDirection.ltr,
          )..layout();
          painter.paint(canvas, Offset(line.offsetX, y));
        }
        y += line.height;
      }
      canvas.restore();
      if (slice.endLine == slice.block.layout.lineCount) {
        y += slice.block.spaceAfter;
      }
    }
  }

  /// 组装一行的 span：行内样式区间 + justify 间隙字距。
  InlineSpan _lineSpan(
    TextLayoutResult layout,
    LineBox line,
    TextStyle baseStyle,
  ) {
    final lineText = layout.text.substring(line.start, line.end);
    final runs = layout.runs;
    final gaps = line.justifyExtra > 0
        ? justifyGapOffsets(lineText)
        : const <int>[];
    if (runs.isEmpty && gaps.isEmpty) {
      return TextSpan(text: lineText, style: baseStyle);
    }
    if (gaps.isEmpty) {
      return TextSpan(
        style: baseStyle,
        children: buildStyledSpans(
          text: layout.text,
          start: line.start,
          end: line.end,
          runs: runs,
          baseStyle: baseStyle,
          styleOf: (runStyle) => TextLayoutEngine.textStyleFor(runStyle),
        ),
      );
    }
    // justify 行逐字符铺开，样式区间与间隙字距一起处理。
    final spacing = line.justifyExtra / gaps.length;
    final gapStarts = gaps.toSet();
    final resolved = <int, TextStyle>{};
    TextStyle styleAt(int offset) {
      for (var i = 0; i < runs.length; i++) {
        final run = runs[i];
        if (offset >= run.start && offset < run.end) {
          return resolved[i] ??= TextLayoutEngine.textStyleFor(run.style);
        }
      }
      return baseStyle;
    }

    final children = <InlineSpan>[];
    var offset = 0;
    for (final rune in lineText.runes) {
      final char = String.fromCharCode(rune);
      final style = styleAt(line.start + offset);
      children.add(
        TextSpan(
          text: char,
          style: gapStarts.contains(offset)
              ? style.copyWith(
                  letterSpacing: (style.letterSpacing ?? 0) + spacing,
                )
              : style,
        ),
      );
      offset += char.length;
    }
    return TextSpan(style: baseStyle, children: children);
  }
}
