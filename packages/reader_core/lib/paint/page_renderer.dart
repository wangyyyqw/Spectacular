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
            text: _lineSpan(lineText, textStyle, line),
            textDirection: TextDirection.ltr,
          )..layout();
          painter.paint(canvas, Offset(line.offsetX, y));
        }
        y += line.height;
      }
      if (slice.endLine == slice.block.layout.lineCount) {
        y += slice.block.spaceAfter;
      }
    }
  }

  /// justify 行按间隙分摊余量：只给“间隙左侧字符”加字距，末字后不加。
  InlineSpan _lineSpan(String text, TextStyle textStyle, LineBox line) {
    final gaps = line.justifyExtra > 0
        ? justifyGapOffsets(text)
        : const <int>[];
    if (gaps.isEmpty) {
      return TextSpan(text: text, style: textStyle);
    }
    final spacing =
        (textStyle.letterSpacing ?? 0) + line.justifyExtra / gaps.length;
    final stretched = textStyle.copyWith(letterSpacing: spacing);
    final gapStarts = gaps.toSet();
    final children = <InlineSpan>[];
    var offset = 0;
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      children.add(
        TextSpan(
          text: char,
          style: gapStarts.contains(offset) ? stretched : null,
        ),
      );
      offset += char.length;
    }
    return TextSpan(style: textStyle, children: children);
  }
}
