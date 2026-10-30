import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../css/computed_style.dart';
import '../paint/line_spans.dart';
import 'text_layout.dart';

/// 行高在真实字体盒之外增加的上下留白；不包含字形自身的空白。
class PageTextEdges {
  const PageTextEdges({this.top = 0, this.bottom = 0});

  final double top;
  final double bottom;
}

final _edgeCache = Expando<Map<(LineBox, ComputedStyle), PageTextEdges>>();

/// 与绘制使用相同的文字和字体回退，只关闭单行首尾的行高扩展。
PageTextEdges textLineEdges(
  TextLayoutResult layout,
  LineBox line,
  ComputedStyle style,
) {
  final cache = _edgeCache[layout] ??= {};
  return cache.putIfAbsent((line, style), () {
    final painter = TextPainter(
      text: buildLineSpan(
        layout: layout,
        line: line,
        baseStyle: TextLayoutEngine.textStyleFor(style),
        punctCompression:
            style.textSpacingTrim == CssTextSpacingTrim.trimAdjacent,
        textAutospace: style.textAutospace == CssTextAutospace.normal,
      ),
      textDirection: layout.isRtl ? TextDirection.rtl : TextDirection.ltr,
      textHeightBehavior: const TextHeightBehavior(
        applyHeightToFirstAscent: false,
        applyHeightToLastDescent: false,
      ),
    )..layout();
    final ascent = painter.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    final descent = painter.height - ascent;
    painter.dispose();
    final baseline = line.baseline - line.top;
    return PageTextEdges(
      top: math.max(0, baseline - ascent),
      bottom: math.max(0, line.height - baseline - descent),
    );
  });
}
