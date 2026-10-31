import 'package:flutter/painting.dart';

import '../css/computed_style.dart';
import '../layout/autospace.dart';
import '../layout/cjk_justify.dart';
import '../layout/line_breaker.dart';
import '../layout/punct_trim.dart';
import '../layout/text_layout.dart';

/// 拆行后按已排好的基线定位混排文字，不让小字号行自行贴到行顶。
/// 显式上下标继续走既有分段位移路径，避免重复补偿。
double textLineBaselineOffset(
  TextLayoutResult layout,
  LineBox line,
  TextPainter painter,
) {
  if ((layout.runs.isEmpty || layout.plainTextLayout) ||
      layout.runs.any(
        (run) =>
            run.start < line.end &&
            run.end > line.start &&
            run.baselineShift != 0,
      )) {
    return 0;
  }
  return line.baseline -
      line.top -
      painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
}

/// 原文位置之前的行内盒占宽；同位置多个盒累加，不向原文插入字符。
/// 起点贴盒后（downstream），终点贴盒前（upstream）。
double inlineBoxAdvanceAt(LineBox line, TextPosition position) {
  var advance = 0.0;
  for (final box in line.inlineBoxes) {
    final offset = box.offset - line.start;
    if (offset < position.offset ||
        (offset == position.offset &&
            position.affinity == TextAffinity.downstream)) {
      advance += box.spec.outerWidth;
    }
  }
  return advance;
}

/// 按插入盒拆分行内原文区间，位移与绘制端一致，包含盒的左右外边距。
/// [start]、[end] 为行内偏移；end 处的盒不属于当前半开选区。
Iterable<({int start, int end, double advance})> lineTextFragments(
  LineBox line, {
  int start = 0,
  int? end,
}) sync* {
  final length = line.end - line.start;
  final from = start.clamp(0, length);
  final until = (end ?? length).clamp(from, length);
  final boundaries = {
    from,
    until,
    for (final box in line.inlineBoxes)
      (box.offset - line.start).clamp(from, until),
  }.toList()..sort();
  for (var index = 0; index < boundaries.length - 1; index++) {
    final offset = boundaries[index];
    yield (
      start: offset,
      end: boundaries[index + 1],
      advance: inlineBoxAdvanceAt(line, TextPosition(offset: offset)),
    );
  }
}

/// 组装一行的 span：行内样式区间 + justify 间隙字距（P2-20）+ 标点
/// 挤压（P7-19）。
///
/// justify 行把余量 `extra` 均分到每个可分配 gap（`ls = extra / gaps.length`），
/// 只给「间隙左侧字符」加单字符 `SpanStyle` 并保留原 `letterSpacing`；末字之后
/// 不加字距，因此不会在右缘留下多余间距（S3 结论）。
///
/// 挤压（[punctCompression]）只作用于排版等价的纯文本行，与测量期
/// （`_measureSegment`）同规则：相邻全角标点的前标点加 -0.5em 字距；
/// 与 justify 同字符叠加时字距代数相加。
///
/// 与阅微 `adaptiveJustify` 同构；差异只在 gap 判定（见 `cjk_justify.dart`）。
InlineSpan buildLineSpan({
  required TextLayoutResult layout,
  required LineBox line,
  required TextStyle baseStyle,
  Color? textColor,
  TextStyle Function(ComputedStyle style)? styleOf,
  bool punctCompression = false,
  bool textAutospace = false,
}) {
  // 主题覆盖文字色：不改样式表，只在绘制时替换颜色，避免重新分页（P2-23）。
  final effectiveBase = textColor == null
      ? baseStyle
      : baseStyle.copyWith(color: textColor);
  final lineText = layout.text.substring(line.start, line.end);
  final trailingBidiMark = _rtlTrailingBidiMark(layout, line);
  final runs = layout.runs;
  // 与测量期同模式取 gap（P7-21：text-justify 模式随行携带）。
  final gaps = line.justifyExtra > 0
      ? cjkJustifyGapOffsets(lineText, mode: line.justifyMode)
      : const <int>[];
  // 挤压/自动间距与测量同条件：runs 可以存在，但不能改变文本测量。
  final plain =
      (runs.isEmpty || layout.plainTextLayout) && lineText.length >= 2;
  final compressionOffsets = punctCompression && plain
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
    final caps = syntheticSmallCapsFromTextStyle(effectiveBase);
    if (caps != null) {
      return buildSyntheticSmallCapsSpan(
        text: '$lineText$trailingBidiMark',
        style: effectiveBase,
        caps: caps,
      );
    }
    return TextSpan(text: '$lineText$trailingBidiMark', style: effectiveBase);
  }
  if (!hasPlaceholder &&
      gaps.isEmpty &&
      compressionOffsets.isEmpty &&
      autospace.isEmpty) {
    return applySyntheticSmallCaps(
      TextSpan(
        style: effectiveBase,
        children: <InlineSpan>[
          ...buildStyledSpans(
            text: layout.text,
            start: line.start,
            end: line.end,
            runs: runs,
            // 非 run 段必须用 effectiveBase：用 baseStyle 会让同一行出现
            // “主题色 + 书籍色”混杂（P9-02 修复）。
            baseStyle: effectiveBase,
            styleOf: styleOf ?? TextLayoutEngine.textStyleFor,
          ),
          if (trailingBidiMark.isNotEmpty)
            TextSpan(text: trailingBidiMark, style: effectiveBase),
        ],
      ),
    );
  }
  // justify / 挤压 / 自动间距行逐字符铺开，三类字距代数叠加。
  final spacing = justifyGapSpacing(line.justifyExtra, gaps.length);
  final compressionSpacing = compressionOffsets.isEmpty
      ? 0.0
      : punctCompressionSpacing(baseStyle.fontSize ?? 0);
  final boundarySpacing = autospace.isEmpty
      ? 0.0
      : autospaceSpacing(baseStyle.fontSize ?? 0);
  final gapStarts = gaps.toSet();
  final compressStarts = compressionOffsets.toSet();
  final autospaceStarts = autospace.toSet();
  final resolved = <int, TextStyle>{};
  TextStyle styleAt(int offset) {
    for (var i = 0; i < runs.length; i++) {
      final run = runs[i];
      if (offset >= run.start && offset < run.end) {
        // 行内颜色按自身样式处理，父段落的主题色不应抹掉作者高亮。
        return resolved[i] ??= (styleOf ?? TextLayoutEngine.textStyleFor)(
          run.style,
        );
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
  if (trailingBidiMark.isNotEmpty) {
    children.add(TextSpan(text: trailingBidiMark, style: effectiveBase));
  }
  return TextSpan(style: effectiveBase, children: children);
}

/// RTL 段落逐行绘制时，行尾中性标点需要看到下一行的强文字方向。
///
/// TextPainter 只拿到当前行，会把行尾顿号误判为段落边界而排到视觉左侧；
/// 浏览器使用整段双向上下文。后续强 LTR 文字存在时追加零宽 LRM 保留该
/// 上下文；段落末尾或后续为 RTL 文字时不加。
String _rtlTrailingBidiMark(TextLayoutResult layout, LineBox line) {
  if (!layout.isRtl ||
      line.end <= line.start ||
      line.end >= layout.text.length) {
    return '';
  }
  final lastRune = layout.text.substring(line.start, line.end).runes.last;
  if (_isStrongLtrRune(lastRune) || _isStrongRtlRune(lastRune)) {
    return '';
  }
  final tail = layout.text.substring(line.end);
  for (final rune in tail.runes) {
    if (rune == 0x0A || rune == 0x0D) {
      return '';
    }
    if (_isStrongLtrRune(rune)) {
      return '\u200E';
    }
    if (_isStrongRtlRune(rune)) {
      return '';
    }
  }
  return '';
}

bool _isStrongLtrRune(int rune) {
  return isJustifyWordCodePoint(rune) ||
      (rune >= 0x3400 && rune <= 0x4DBF) ||
      (rune >= 0x4E00 && rune <= 0x9FFF) ||
      (rune >= 0xF900 && rune <= 0xFAFF) ||
      (rune >= 0x20000 && rune <= 0x2FA1F) ||
      (rune >= 0x3040 && rune <= 0x30FF) ||
      (rune >= 0xAC00 && rune <= 0xD7AF);
}

bool _isStrongRtlRune(int rune) {
  return (rune >= 0x0590 && rune <= 0x08FF) ||
      (rune >= 0xFB1D && rune <= 0xFDFF) ||
      (rune >= 0xFE70 && rune <= 0xFEFF);
}
