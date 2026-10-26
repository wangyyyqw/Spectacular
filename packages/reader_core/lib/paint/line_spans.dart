import 'package:flutter/painting.dart';

import '../layout/autospace.dart';
import '../layout/cjk_justify.dart';
import '../layout/line_breaker.dart';
import '../layout/punct_trim.dart';
import '../layout/text_layout.dart';

/// 组装一行的 span：行内样式区间 + justify 间隙字距（P2-20）+ 标点
/// 挤压（P7-19）。
///
/// justify 行把余量 `extra` 均分到每个可分配 gap（`ls = extra / gaps.length`），
/// 只给「间隙左侧字符」加单字符 `SpanStyle` 并保留原 `letterSpacing`；末字之后
/// 不加字距，因此不会在右缘留下多余间距（S3 结论）。
///
/// 挤压（[punctCompression]）只作用于无行内样式区间的纯文本行，与测量
/// 期（`_measureSegment`）同规则：相邻全角标点的前标点加 -0.5em 字距；
/// 与 justify 同字符叠加时字距代数相加。
///
/// 与阅微 `adaptiveJustify` 同构；差异只在 gap 判定（见 `cjk_justify.dart`）。
InlineSpan buildLineSpan({
  required TextLayoutResult layout,
  required LineBox line,
  required TextStyle baseStyle,
  Color? textColor,
  bool punctCompression = false,
  bool textAutospace = false,
}) {
  // 主题覆盖文字色：不改样式表，只在绘制时替换颜色，避免重新分页（P2-23）。
  final effectiveBase = textColor == null
      ? baseStyle
      : baseStyle.copyWith(color: textColor);
  final lineText = layout.text.substring(line.start, line.end);
  final runs = layout.runs;
  // 与测量期同模式取 gap（P7-21：text-justify 模式随行携带）。
  final gaps = line.justifyExtra > 0
      ? cjkJustifyGapOffsets(lineText, mode: line.justifyMode)
      : const <int>[];
  // 挤压/自动间距与测量同条件：仅纯文本行（runs 为空）。
  final plain = runs.isEmpty && lineText.length >= 2;
  final compressionOffsets =
      punctCompression && plain
      ? punctCompressionOffsets(
          lineText,
          em: baseStyle.fontSize ?? 0,
          advanceOf: punctAdvanceMeasurer(baseStyle, 1),
        )
      : const <int>[];
  final autospace = textAutospace && plain
      ? autospaceOffsets(lineText)
      : const <int>[];
  // 行内图片占位符（P9-06）：占位字形本身要透明，图片由绘制层画在
  // 同一位置，否则会看到豆腐块叠在图片上。
  final hasPlaceholder = lineText.contains('\uFFFC');
  if (!hasPlaceholder &&
      runs.isEmpty &&
      gaps.isEmpty &&
      compressionOffsets.isEmpty &&
      autospace.isEmpty) {
    return TextSpan(text: lineText, style: effectiveBase);
  }
  if (!hasPlaceholder &&
      gaps.isEmpty &&
      compressionOffsets.isEmpty &&
      autospace.isEmpty) {
    return TextSpan(
      style: effectiveBase,
      children: buildStyledSpans(
        text: layout.text,
        start: line.start,
        end: line.end,
        runs: runs,
        // 非 run 段必须用 effectiveBase：用 baseStyle 会让同一行出现
        // “主题色 + 书籍色”混杂（P9-02 修复）。
        baseStyle: effectiveBase,
        styleOf: (runStyle) => TextLayoutEngine.textStyleFor(runStyle),
      ),
    );
  }
  // justify / 挤压 / 自动间距行逐字符铺开，三类字距代数叠加。
  final spacing = justifyGapSpacing(line.justifyExtra, gaps.length);
  final compressionSpacing =
      compressionOffsets.isEmpty
          ? 0.0
          : punctCompressionSpacing(baseStyle.fontSize ?? 0);
  final boundarySpacing =
      autospace.isEmpty ? 0.0 : autospaceSpacing(baseStyle.fontSize ?? 0);
  final gapStarts = gaps.toSet();
  final compressStarts = compressionOffsets.toSet();
  final autospaceStarts = autospace.toSet();
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
    final base = styleAt(line.start + offset);
    final style = char == '\uFFFC'
        ? base.copyWith(color: const Color(0x00000000))
        : base;
    final extraSpacing =
        (gapStarts.contains(offset) ? spacing : 0.0) +
        (compressStarts.contains(offset) ? compressionSpacing : 0.0) +
        (autospaceStarts.contains(offset) ? boundarySpacing : 0.0);
    children.add(
      TextSpan(
        text: char,
        style: extraSpacing == 0
            ? style
            : style.copyWith(
                letterSpacing: (style.letterSpacing ?? 0) + extraSpacing,
              ),
      ),
    );
    offset += char.length;
  }
  return TextSpan(style: effectiveBase, children: children);
}
