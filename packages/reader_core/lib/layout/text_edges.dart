import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../css/computed_style.dart';
import '../paint/line_spans.dart';

import 'package:reader_core/layout/line_breaker.dart';

/// 行高在文字与行内图片真实盒之外增加的上下留白；不包含字形自身的空白。
class PageTextEdges {
  const PageTextEdges({this.top = 0, this.bottom = 0, this.bottomOverflow = 0});

  final double top;
  final double bottom;

  /// 字形超出行盒下沿的实测距离；用于装饰线避让。
  final double bottomOverflow;
}

final _edgeCache = Expando<Map<(LineBox, String), PageTextEdges>>();

/// 几何缓存只替换绘制 runs 时，保留已经实测的行高留白。
///
/// 调用方须先确认文本、字体依赖和 run 度量键相同；不同布局不共享此表。
void reuseTextLineEdges(TextLayoutResult source, TextLayoutResult target) {
  if (identical(source, target) || !identical(source.lines, target.lines)) {
    return;
  }
  final cache = _edgeCache[source];
  if (cache != null) _edgeCache[target] = cache;
}

/// 与绘制使用相同的文字和字体回退，只关闭单行首尾的行高扩展。
PageTextEdges textLineEdges(
  TextLayoutResult layout,
  LineBox line,
  ComputedStyle style,
) {
  final cache = _edgeCache[layout] ??= {};
  final fingerprint = style.layoutFingerprint;
  final key = (line, fingerprint);
  final cached = cache[key];
  if (cached != null) return cached;
  return cache[key] = _measureSingle(layout, line, style);
}

PageTextEdges _measureSingle(
  TextLayoutResult layout,
  LineBox line,
  ComputedStyle style,
) {
  final painter = TextPainter(
    text: _lineSpan(layout, line, style),
    textDirection: layout.isRtl ? TextDirection.rtl : TextDirection.ltr,
    textHeightBehavior: const TextHeightBehavior(
      applyHeightToFirstAscent: false,
      applyHeightToLastDescent: false,
    ),
  )..layout();
  try {
    final ascent = painter.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    return _edges(line, ascent, painter.height - ascent);
  } finally {
    painter.dispose();
  }
}

InlineSpan _lineSpan(
  TextLayoutResult layout,
  LineBox line,
  ComputedStyle style,
) => buildLineSpan(
  layout: layout,
  line: line,
  baseStyle: TextLayoutEngine.textStyleFor(style),
  punctCompression: style.textSpacingTrim == CssTextSpacingTrim.trimAdjacent,
  textAutospace: style.textAutospace == CssTextAutospace.normal,
);

PageTextEdges _edges(LineBox line, double ascent, double descent) {
  final baseline = line.baseline - line.top;
  final top = baseline - ascent;
  final bottom = line.height - baseline - descent;
  var topCredit = math.max(0.0, top);
  var bottomCredit = math.max(0.0, bottom);
  for (final box in line.inlineBoxes) {
    topCredit = math.min(topCredit, math.max(0.0, box.topIn(baseline)));
    bottomCredit = math.min(
      bottomCredit,
      math.max(0.0, line.height - baseline - box.descent),
    );
  }
  return PageTextEdges(
    top: topCredit,
    bottom: bottomCredit,
    bottomOverflow: math.max(0, -bottom),
  );
}
