import 'package:flutter/painting.dart';

import '../layout/cjk_justify.dart';
import '../layout/line_breaker.dart';
import '../layout/text_layout.dart';

/// 组装一行的 span：行内样式区间 + justify 间隙字距（P2-20）。
///
/// justify 行把余量 `extra` 均分到每个可分配 gap（`ls = extra / gaps.length`），
/// 只给「间隙左侧字符」加单字符 `SpanStyle` 并保留原 `letterSpacing`；末字之后
/// 不加字距，因此不会在右缘留下多余间距（S3 结论）。
///
/// 与阅微 `adaptiveJustify` 同构；差异只在 gap 判定（见 `cjk_justify.dart`）。
InlineSpan buildLineSpan({
  required TextLayoutResult layout,
  required LineBox line,
  required TextStyle baseStyle,
  Color? textColor,
}) {
  // 主题覆盖文字色：不改样式表，只在绘制时替换颜色，避免重新分页（P2-23）。
  final effectiveBase = textColor == null
      ? baseStyle
      : baseStyle.copyWith(color: textColor);
  final lineText = layout.text.substring(line.start, line.end);
  final runs = layout.runs;
  final gaps = line.justifyExtra > 0
      ? cjkJustifyGapOffsets(lineText)
      : const <int>[];
  if (runs.isEmpty && gaps.isEmpty) {
    return TextSpan(text: lineText, style: effectiveBase);
  }
  if (gaps.isEmpty) {
    return TextSpan(
      style: effectiveBase,
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
  final spacing = justifyGapSpacing(line.justifyExtra, gaps.length);
  final gapStarts = gaps.toSet();
  final resolved = <int, TextStyle>{};
  TextStyle styleAt(int offset) {
    for (var i = 0; i < runs.length; i++) {
      final run = runs[i];
      if (offset >= run.start && offset < run.end) {
        return resolved[i] ??= textColor == null
            ? TextLayoutEngine.textStyleFor(run.style)
            : TextLayoutEngine.textStyleFor(run.style)
                  .copyWith(color: textColor);
      }
    }
    return effectiveBase;
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
  return TextSpan(style: effectiveBase, children: children);
}
