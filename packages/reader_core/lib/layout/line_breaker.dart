import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../css/computed_style.dart';
import '../css/font_face.dart';
import '../src/api/models.dart' show TextLayout;
import 'cjk_justify.dart';
import 'autospace.dart';
import 'punct_trim.dart';
import '../text/script_fallback.dart';

/// 一行文本的布局结果。
class LineBox {
  /// 创建行框。
  const LineBox({
    required this.start,
    required this.end,
    required this.top,
    required this.height,
    required this.baseline,
    required this.width,
    this.indent = 0,
    this.isLastLine = false,
    this.isHardBreak = false,
    this.offsetX = 0,
    this.justifyExtra = 0,
    this.justifyMode = CssTextJustify.auto,
    this.ellipsized = false,
    this.ellipsisWidth = 0,
    this.hyphenated = false,
    this.hyphenWidth = 0,
    this.inlineBoxes = const <InlineBoxPlacement>[],
    this.columnIndex,
    this.columnX,
    this.vertical = false,
  });

  /// 行起始字符下标（半开区间，P1-23 精化）。
  final int start;

  /// 行结束字符下标（半开）。
  final int end;

  /// 行框顶部（相对文本块）。
  final double top;

  /// 行框高度。
  final double height;

  /// 基线（相对文本块）。
  final double baseline;

  /// 行实际宽度。
  final double width;

  /// 首行缩进（仅首行非 0）。
  final double indent;

  /// 是否为段落最后一行。
  final bool isLastLine;

  /// 是否以硬换行结束。
  final bool isHardBreak;

  /// 行在内容区内的水平偏移，由 text-align 计算（§61.5）。
  final double offsetX;

  /// justify 需要分摊到行内的额外宽度；末行与硬换行行为 0。
  final double justifyExtra;

  /// 本行的 justify 拉伸方式（P7-21）：绘制端按同一模式取 gap，
  /// 与测量期的 justifyExtra 一致。
  final CssTextJustify justifyMode;

  /// 本行是否被 `text-overflow: ellipsis` 截断（行尾需画省略号）。
  ///
  /// [start]/[end] 仍是原文坐标（CFI/选区不受影响），[width] 已含
  /// [ellipsisWidth]，因此截断行不会超出内容宽。
  final bool ellipsized;

  /// 省略号（`…`）的 advance 宽；[ellipsized] 为 false 时是 0。
  final double ellipsisWidth;

  /// 本行是否在词中断开并需要在行尾画连字符（`hyphens`）。
  ///
  /// [end] 仍是原文坐标（断点后一个字符），[width] 已含 [hyphenWidth]。
  final bool hyphenated;

  /// 连字符（`-`）的 advance 宽；[hyphenated] 为 false 时是 0。
  final double hyphenWidth;

  /// 竖排时本行对应的列序号（0 = 逻辑首列；`vertical` 为 false 时为 null）。
  final int? columnIndex;

  /// 竖排时该列的 x（页内/块内左缘；rl 时首列在最右）。
  final double? columnX;

  /// 是否为竖排列（`writing-mode: vertical-rl/vertical-lr`）。
  ///
  /// 竖排时 [start]/[end] 仍是该列的字符区间，[width] = 列宽（= 行高），
  /// [height] = 该列内容长度（横排时的行宽），[top] 恒为 0。
  final bool vertical;

  /// 本行内的行级盒（`display: inline-block`）：按行内 x 升序。
  ///
  /// 排版期已按盒宽预留、按盒高/基线撑高行盒；绘制层按 [InlineBoxPlacement]
  /// 画盒内容（尺寸、圆角、背景等由 payload 提供）。
  final List<InlineBoxPlacement> inlineBoxes;

  /// 行底。
  double get bottom => top + height;

  /// 行实际占据的宽度：自然行宽 + justify 分摊宽度。
  ///
  /// [width] 是测量宽（不含 justifyExtra），绘制端按 gap 均分 [justifyExtra]
  /// 后行尾正好落在版心右缘；对照浏览器时要用本值（浏览器量的是绘制宽）。
  double get advanceWidth => width + justifyExtra;

  /// 复制并更新标志。
  LineBox copyWith({
    int? start,
    int? end,
    double? top,
    double? indent,
    bool? isLastLine,
    bool? isHardBreak,
    double? offsetX,
    double? justifyExtra,
    CssTextJustify? justifyMode,
    double? width,
    bool? ellipsized,
    double? ellipsisWidth,
    bool? hyphenated,
    double? hyphenWidth,
    List<InlineBoxPlacement>? inlineBoxes,
    int? columnIndex,
    double? columnX,
    bool? vertical,
  }) => LineBox(
    start: start ?? this.start,
    end: end ?? this.end,
    top: top ?? this.top,
    height: height,
    baseline: baseline,
    width: width ?? this.width,
    indent: indent ?? this.indent,
    isLastLine: isLastLine ?? this.isLastLine,
    isHardBreak: isHardBreak ?? this.isHardBreak,
    offsetX: offsetX ?? this.offsetX,
    justifyExtra: justifyExtra ?? this.justifyExtra,
    justifyMode: justifyMode ?? this.justifyMode,
    ellipsized: ellipsized ?? this.ellipsized,
    ellipsisWidth: ellipsisWidth ?? this.ellipsisWidth,
    hyphenated: hyphenated ?? this.hyphenated,
    hyphenWidth: hyphenWidth ?? this.hyphenWidth,
    inlineBoxes: inlineBoxes ?? this.inlineBoxes,
    columnIndex: columnIndex ?? this.columnIndex,
    columnX: columnX ?? this.columnX,
    vertical: vertical ?? this.vertical,
  );

  @override
  String toString() =>
      'LineBox($start..$end, top=$top, h=$height, baseline=$baseline, w=$width, '
      'indent=$indent, last=$isLastLine, hard=$isHardBreak, x=$offsetX, '
      'justify=$justifyExtra)';
}


/// 软断点计划：`hyphens`/`overflow-wrap`/`word-break` 需要的「测量文本 +
/// 下标映射 + 行尾连字符断点」。
///
/// 断点用 U+200B（ZWSP，零宽、UAX#14 允许其后换行）表达：Skia 只在确实放
/// 不下时才在 ZWSP 处断开，因此「按需断词」语义由排版器保证。测量文本与
/// 原文的偏移映射保证 [LineBox.start]/[LineBox.end] 仍是原文坐标（CFI/
/// 选区/字数统计不受影响）。
class SoftBreakPlan {
  /// 创建计划。
  const SoftBreakPlan({
    required this.text,
    required this.offsets,
    required this.hyphenPoints,
    this.hyphenAdvance = 0,
  });

  /// 无断点时的直通计划。
  factory SoftBreakPlan.identity(String text, {double hyphenAdvance = 0}) =>
      SoftBreakPlan(
        text: text,
        offsets: List<int>.generate(text.length + 1, (i) => i),
        hyphenPoints: const <int>{},
        hyphenAdvance: hyphenAdvance,
      );

  /// 插入断点后的测量文本。
  final String text;

  /// 测量下标 → 原文下标（长度 = [text].length + 1）。
  final List<int> offsets;

  /// 需要在行尾画连字符的测量边界下标集合。
  final Set<int> hyphenPoints;

  /// 连字符（`-`）的 advance 宽。
  final double hyphenAdvance;

  /// 是否需要后处理（插入断点或存在连字符断点）。
  ///
  /// 软连字符 U+00AD 被等长替换成 ZWSP 时，下标映射是恒等的，但行尾仍需
  /// 补画连字符，所以连同 [hyphenPoints] 一起判断。
  bool get changed =>
      offsets.last != text.length || hyphenPoints.isNotEmpty;

  /// 测量下标换算回原文下标。
  int originalOffset(int measured) =>
      offsets[measured.clamp(0, offsets.length - 1)];

  /// 测量边界是否为连字符断点。
  bool isHyphenPoint(int measured) => hyphenPoints.contains(measured);
}

/// 行内样式区间：为文本 `[start, end)` 指定独立计算样式。
///
/// 混排字号、上下标、超出行高的行内元素都用它表达；区间必须升序且不重叠，
/// 未覆盖的部分沿用块的样式。
/// 注音标注（P8-08，CSS Ruby 1 flat 近似）：主文本区间 + 注音文本，
/// 渲染层注音趟消费（区间字符上方、50% 字号、居中）。
class RubyAnnotation {
  /// 创建注音。
  const RubyAnnotation({
    required this.start,
    required this.end,
    required this.text,
  });

  /// 起始偏移（UTF-16，含，块文本坐标系）。
  final int start;

  /// 结束偏移（半开）。
  final int end;

  /// 注音文本。
  final String text;
}

/// 行内盒的竖直对齐（CSS `vertical-align` 的行内块子集）。
enum InlineBoxVerticalAlign {
  /// 盒底 margin 边对齐基线（CSS 默认）。
  baseline,

  /// 盒竖直中点对齐「父基线 + x-height/2」（近似取行盒中线）。
  middle,

  /// 盒顶对齐行盒顶。
  top,

  /// 盒底对齐行盒底。
  bottom,
}

/// 行内盒规格（`display: inline-block` 的布局侧输入）。
///
/// 章节源把 inline-block 元素描述成「在文本 [offset] 处插入 `width × height`
/// 的盒」；排版器在该处预留宽度（放不下整块换行），并按 [verticalAlign] 与
/// [marginTop]/[marginBottom] 参与行高与基线计算。
class InlineBoxSpec {
  /// 创建规格。
  const InlineBoxSpec({
    required this.offset,
    required this.width,
    required this.height,
    this.verticalAlign = InlineBoxVerticalAlign.baseline,
    this.marginTop = 0,
    this.marginBottom = 0,
    this.baselineOffset = 0,
    this.contentHeight,
    this.payload,
  });

  /// 插入点（原文偏移；盒排在该偏移之前）。
  final int offset;

  /// 盒宽（含 padding/border，不含 margin）。
  final double width;

  /// 盒高（含 padding/border，不含 margin）。
  final double height;

  /// 竖直对齐方式。
  final InlineBoxVerticalAlign verticalAlign;

  /// 上外边距（参与行高）。
  final double marginTop;

  /// 下外边距（参与行高；baseline 对齐时落在基线以下）。
  final double marginBottom;

  /// 基线模式下的额外位移（正数向上抬）。
  final double baselineOffset;

  /// 盒内内容的排版高（`display:inline-block` 子内容溢出的高度，可空）。
  ///
  /// Chrome 口径：盒内内容溢出时，行盒/段落高度取**内容高**（超出盒高的部分
  /// 计入基线以上延伸），见 cases/53（120×34 盒、内部 2 行 54.38 → p 高 54.38）。
  final double? contentHeight;

  /// 绘制层用的引用（片段、样式等由上层决定）。
  final Object? payload;

  /// 盒总高（含上下 margin）。
  double get outerHeight => height + marginTop + marginBottom;

  /// 参与行盒计算的盒高：`max(margin box 高, 内容高)`（内容溢出向下延伸）。
  double get effectiveHeight =>
      math.max(outerHeight, contentHeight ?? outerHeight);

  /// 基线以上延伸。
  double get ascent => switch (verticalAlign) {
    InlineBoxVerticalAlign.baseline =>
      effectiveHeight - marginBottom - baselineOffset,
    InlineBoxVerticalAlign.middle => outerHeight / 2 + baselineOffset,
    InlineBoxVerticalAlign.top => outerHeight,
    InlineBoxVerticalAlign.bottom => 0,
  };

  /// 基线以下延伸。
  double get descent => switch (verticalAlign) {
    InlineBoxVerticalAlign.baseline => marginBottom + baselineOffset,
    InlineBoxVerticalAlign.middle => outerHeight / 2 - baselineOffset,
    InlineBoxVerticalAlign.top => 0,
    InlineBoxVerticalAlign.bottom => outerHeight,
  };
}

/// 竖排逐字符度量（绘制层逐字摆放用）。
class VerticalGlyphMetric {
  /// 创建度量。
  const VerticalGlyphMetric({
    required this.start,
    required this.end,
    required this.advance,
    required this.upright,
  });

  /// 原文起始偏移。
  final int start;

  /// 原文结束偏移（不含）。
  final int end;

  /// 列内纵向 advance（upright 时 = 1em，mixed 旋转时 = 字形宽）。
  final double advance;

  /// 是否正立（`text-orientation: upright` 或 CJK 类字形）；false 表示旋转 90°。
  final bool upright;
}

/// 行内盒在行内的放置结果。
class InlineBoxPlacement {
  /// 创建放置。
  const InlineBoxPlacement({
    required this.offset,
    required this.left,
    required this.width,
    required this.height,
    required this.ascent,
    required this.descent,
    required this.spec,
    this.vertical = false,
  });

  /// 插入点（原文偏移）。
  final int offset;

  /// 行内 x（相对行首，含 text-align 的 [LineBox.offsetX]）。
  final double left;

  /// 盒宽。
  final double width;

  /// 盒高（不含 margin）。
  final double height;

  /// 基线以上延伸（含 margin）。
  final double ascent;

  /// 基线以下延伸（含 margin）。
  final double descent;

  /// 原始规格（绘制层从 `spec.payload` 取内容）。
  final InlineBoxSpec spec;

  /// 是否竖排（竖排时 [left] = 列内纵向偏移，[ascent]/[descent] = 列的右/左延伸）。
  final bool vertical;

  /// 盒顶相对行顶的偏移（行顶 + 该值 = 盒顶）。
  double topIn(double lineAscent) => lineAscent - ascent;
}

/// 排版期内部标记：占位符在测量文本中的下标 + 规格。
class _InlineBoxMark {
  const _InlineBoxMark({required this.index, required this.spec});

  final int index;
  final InlineBoxSpec spec;
}

/// 行内盒占位文本：插入 U+FFFC 后的测量文本 + 偏移映射 + 标记。
class _InlineBoxText {
  const _InlineBoxText({
    required this.text,
    required this.offsets,
    required this.marks,
  });

  final String text;

  /// 测量边界 → 原文偏移（长度 = text.length + 1）。
  final List<int> offsets;

  final List<_InlineBoxMark> marks;

  /// 是否插入了占位符（含有盒即有映射，长度可能与原文相同）。
  bool get changed => marks.isNotEmpty;

  /// 测量下标换算回原文偏移。
  int originalOffset(int measured) =>
      offsets[measured.clamp(0, offsets.length - 1)];
}

class StyledRun {
  /// 创建区间。
  const StyledRun({
    required this.start,
    required this.end,
    required this.style,
    this.baselineShift = 0,
  });

  /// 起始偏移（UTF-16，含）。
  final int start;

  /// 结束偏移（UTF-16，不含）。
  final int end;

  /// 该区间的计算样式。
  final ComputedStyle style;

  /// 行内基线偏移（逻辑像素，正值向下）：上下标用，0 表示不偏移。
  final double baselineShift;
}

/// 按 CSS `text-transform` 变换文本（P2-16）。
///
/// `capitalize` 按空白分词，把每个词的首字符转大写（标点边界按空白近似）。
String applyTextTransform(String text, CssTextTransform transform) =>
    switch (transform) {
      CssTextTransform.none => text,
      CssTextTransform.uppercase => text.toUpperCase(),
      CssTextTransform.lowercase => text.toLowerCase(),
      CssTextTransform.capitalize => _capitalizeWords(text),
    };

String _capitalizeWords(String text) {
  final buffer = StringBuffer();
  var atWordStart = true;
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    if (char.trim().isEmpty) {
      buffer.write(char);
      atWordStart = true;
    } else {
      buffer.write(atWordStart ? char.toUpperCase() : char);
      atWordStart = false;
    }
  }
  return buffer.toString();
}

/// 把 `[start, end)` 按样式区间切成连续 span（§61.1 的行内 run）。
///
/// [runs] 需升序且不重叠；区间外的文本用 [baseStyle]。
List<InlineSpan> buildStyledSpans({
  required String text,
  required int start,
  required int end,
  required List<StyledRun> runs,
  required TextStyle baseStyle,
  required TextStyle Function(ComputedStyle style) styleOf,
}) {
  final spans = <InlineSpan>[];
  var cursor = start;
  for (final run in runs) {
    final runStart = math.max(run.start, start);
    final runEnd = math.min(run.end, end);
    if (runEnd <= cursor || runStart >= end) {
      continue;
    }
    final from = math.max(cursor, runStart);
    if (from > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, from), style: baseStyle));
    }
    if (runEnd > from) {
      spans.add(
        TextSpan(text: text.substring(from, runEnd), style: styleOf(run.style)),
      );
      cursor = runEnd;
    }
  }
  if (cursor < end) {
    spans.add(TextSpan(text: text.substring(cursor, end), style: baseStyle));
  }
  return spans;
}

/// 单个行内盒的竖直度量（相对自身基线）。
class _InlineBoxMetrics {
  const _InlineBoxMetrics({
    required this.ascent,
    required this.descent,
    required this.rawAscent,
    required this.rawDescent,
  });

  /// 上沿：字体 ascent + 半行距（自身 line-height 盒）。
  final double ascent;

  /// 下沿：字体 descent + 半行距。
  final double descent;

  /// 字体原始 ascent（不含半行距）：`super`/`sub`/`text-top` 的参照。
  final double rawAscent;

  /// 字体原始 descent（不含半行距）。
  final double rawDescent;
}

/// TextLayout 的测量结果。
class TextLayoutResult implements TextLayout {
  /// 创建结果。
  TextLayoutResult({
    required this.text,
    required this.lines,
    required this.width,
    required this.height,
    required this.maxWidth,
    this.runs = const <StyledRun>[],
    this.isRtl = false,
    this.writingMode = CssWritingMode.horizontalTb,
  });

  /// 原始文本。
  final String text;

  /// 行列表。
  final List<LineBox> lines;

  /// 最长行宽度。
  final double width;

  /// 总高度（各行高之和）。
  final double height;

  /// 布局使用的最大宽度。
  final double maxWidth;

  /// 行内样式区间（绘制用），偏移基于 [text]。
  final List<StyledRun> runs;

  /// 段落方向是否为 RTL（绘制/命中需用同一 baseDirection，否则字形顺序错位）。
  final bool isRtl;

  /// 书写模式（竖排块的行列表其实是「列」表，见 [LineBox.vertical]）。
  final CssWritingMode writingMode;

  /// 是否竖排。
  bool get isVertical => writingMode != CssWritingMode.horizontalTb;

  /// 行数。
  int get lineCount => lines.length;

  /// 是否有行被 `text-overflow: ellipsis` 截断（绘制端只按 padding-box
  /// 裁剪 ink，省略号由行内的 [LineBox.ellipsized] 标记决定）。
  bool get ellipsized => lines.any((line) => line.ellipsized);
}

/// 正文过窄告警。
class LineBreakWarning {
  /// 创建告警。
  const LineBreakWarning({
    required this.requestedWidth,
    required this.appliedWidth,
    required this.minimumWidth,
  });

  /// 告警码，固定为 `layout.tooNarrow`。
  String get code => 'layout.tooNarrow';

  /// 调用方请求的宽度。
  final double requestedWidth;

  /// 实际使用的宽度。
  final double appliedWidth;

  /// 3em 下限。
  final double minimumWidth;

  @override
  String toString() =>
      '$code(requested=$requestedWidth, applied=$appliedWidth, min=$minimumWidth)';
}

/// 断行告警回调。
typedef LineBreakWarningCallback = void Function(LineBreakWarning warning);

/// 基于 [TextPainter] 的断行器。
///
/// 正文内容宽低于 [minimumWidthEm]（默认 3em）时钳制到下限，并只触发一次告警；
/// 这是 S4 结论要求的工程约束，避免 2em 极端宽度下的禁则缺陷。
class LineBreaker {
  /// 创建断行器。
  LineBreaker({this.onWarning, this.minimumWidthEm = 3.0})
    : assert(minimumWidthEm > 0);

  /// 告警回调，只在首次钳制时调用。
  final LineBreakWarningCallback? onWarning;

  /// 宽度下限，单位为 em。
  final double minimumWidthEm;

  /// 是否保留 CSS 声明的小数行高（实验开关，默认关闭）。
  ///
  /// Skia 把行盒高四舍五入到整数（`line-height: 22.5px` → 23、
  /// `1.6 × 17px = 27.2` → 27），但 ascent 仍按小数行高算，因此基线是
  /// 对的、只有行盒高度被取整。打开后行盒高改用 `ComputedStyle.lineHeight`
  /// （小数），基线不变；影响面是所有依赖整数行高的分页/单元格高度。
  static bool preserveFractionalLineHeight = false;

  bool _tooNarrow = false;
  int _warningCount = 0;
  LineBreakWarning? _lastWarning;

  /// 是否发生过宽度钳制。
  bool get tooNarrow => _tooNarrow;

  /// 告警次数；一次断行器实例最多为 1。
  int get warningCount => _warningCount;

  /// 最近一次告警。
  LineBreakWarning? get lastWarning => _lastWarning;

  /// 按样式计算 3em 下限。
  double minimumWidthFor(ComputedStyle style) =>
      style.fontSize * minimumWidthEm;

  /// 返回实际使用的宽度；低于下限时钳制并记录一次告警。
  double effectiveWidth(ComputedStyle style, double requestedWidth) {
    final minimum = minimumWidthFor(style);
    if (!requestedWidth.isFinite || requestedWidth >= minimum) {
      return requestedWidth;
    }
    _tooNarrow = true;
    if (_warningCount == 0) {
      final warning = LineBreakWarning(
        requestedWidth: requestedWidth,
        appliedWidth: minimum,
        minimumWidth: minimum,
      );
      _warningCount = 1;
      _lastWarning = warning;
      onWarning?.call(warning);
    }
    return minimum;
  }

  /// 按 [maxWidth] 测量 [text]。
  ///
  /// 宽度低于 3em 时钳制到 3em；`nowrap`/`pre` 不软换行（测量时按无限宽
  /// 排一行），但 `maxWidth` 仍记录有限的内容宽，供对齐与诊断使用。
  /// [runs] 为行内样式区间，用于混排字号与行内元素；未覆盖部分沿用 [style]。
  /// [hasGlyph] 非空时按字形覆盖把 `style.fontFamilies` 切分成族分段（P2-12）。
  TextLayoutResult layout({
    required String text,
    required ComputedStyle style,
    required double maxWidth,
    double textScaleFactor = 1,
    TextLeadingDistribution leadingDistribution = TextLeadingDistribution.even,
    List<StyledRun> runs = const <StyledRun>[],
    bool Function(String family, int codeUnit)? hasGlyph,
    List<InlineBoxSpec> inlineBoxes = const <InlineBoxSpec>[],
  }) {
    // nowrap/pre 不软换行：测量时不软换行，但内容宽保持有限值（P9-28：
    // 无限宽会让对齐余量恒为 0，也让对照工具拿到 Infinity）。
    final softWrap =
        style.whiteSpace != CssWhiteSpace.nowrap &&
        style.whiteSpace != CssWhiteSpace.pre;
    return TextLayoutEngine._layoutRaw(
      text: text,
      style: style,
      maxWidth: effectiveWidth(style, maxWidth),
      textScaleFactor: textScaleFactor,
      leadingDistribution: leadingDistribution,
      runs: runs,
      hasGlyph: hasGlyph,
      inlineBoxes: inlineBoxes,
      softWrap: softWrap,
    );
  }
}

/// 用 TextPainter 做行测量。
abstract final class TextLayoutEngine {
  /// 按 [maxWidth] 测量 [text]。
  ///
  /// [style] 提供 fontSize/lineHeightFactor/fontFamily/字重/斜体/颜色/对齐；
  /// 行高使用 CSS 语义（`fontSize × factor`），并显式设置 even 行距分布。
  ///
  /// 默认使用 [LineBreaker] 执行 3em 宽度下限；需要观察告警时传入自定义
  /// [lineBreaker]。[hasGlyph] 非空时启用按字形覆盖的字体族分段（P2-12）。
  static TextLayoutResult layout({
    required String text,
    required ComputedStyle style,
    required double maxWidth,
    double textScaleFactor = 1,
    TextLeadingDistribution leadingDistribution = TextLeadingDistribution.even,
    LineBreaker? lineBreaker,
    List<StyledRun> runs = const <StyledRun>[],
    bool Function(String family, int codeUnit)? hasGlyph,
    List<InlineBoxSpec> inlineBoxes = const <InlineBoxSpec>[],
  }) {
    return (lineBreaker ?? LineBreaker()).layout(
      text: text,
      style: style,
      maxWidth: maxWidth,
      textScaleFactor: textScaleFactor,
      leadingDistribution: leadingDistribution,
      runs: runs,
      hasGlyph: hasGlyph,
      inlineBoxes: inlineBoxes,
    );
  }

  static TextLayoutResult _layoutRaw({
    required String text,
    required ComputedStyle style,
    required double maxWidth,
    required double textScaleFactor,
    required TextLeadingDistribution leadingDistribution,
    List<StyledRun> runs = const <StyledRun>[],
    bool Function(String family, int codeUnit)? hasGlyph,
    List<InlineBoxSpec> inlineBoxes = const <InlineBoxSpec>[],
    bool softWrap = true,
  }) {
    // text-transform 在测量前应用：layout.text 即变换后的文本，绘制直接用。
    text = applyTextTransform(text, style.textTransform);
    // 内容宽恒为「有限」值，用于缩进/对齐/诊断；软换行关闭时只把 TextPainter
    // 的排版宽放开到无限，让整段排成一行（硬换行仍生效）。
    final width = maxWidth.isFinite ? math.max(1.0, maxWidth) : double.infinity;
    final measureWidth = softWrap ? width : double.infinity;
    // 竖排（CSS Writing Modes §7.2）：内联轴是页面的纵向，列长由块高决定，
    // 因此测量宽 = 声明 height（缺省时退回内容宽，由调用方决定页高近似）。
    final vertical = style.writingMode != CssWritingMode.horizontalTb;
    final declaredColumnLength = vertical ? style.height?.resolve(width) : null;
    final columnLength =
        declaredColumnLength != null && declaredColumnLength > 0
        ? declaredColumnLength
        : measureWidth;
    final indent = softWrap && width.isFinite
        ? style.textIndent.clamp(0.0, math.max(0.0, width - 1)).toDouble()
        : 0.0;
    final ordered = _applyVerticalAlign(
      _normalizeRuns(runs, text.length),
      style,
      leadingDistribution,
    );
    // P2-12：按字形覆盖叠加字体族分段。未传 hasGlyph 或未声明 font-family 时
    // 走原路径，行为与之前完全一致。
    final styled = hasGlyph == null || style.fontFamilies.isEmpty
        ? ordered
        : _applyScriptFallback(
            runs: ordered,
            scriptRuns: buildScriptFontRuns(
              text,
              style.fontFamilies,
              hasGlyph: hasGlyph,
            ),
            baseStyle: style,
            length: text.length,
          );
    // 段尾换行不产生空行（与阅微一致：content 末尾的 '\n' 先剥离）。
    var measuredEnd = text.length;
    while (measuredEnd > 0 && text.codeUnitAt(measuredEnd - 1) == 10) {
      measuredEnd -= 1;
    }
    final measuredText = measuredEnd == text.length
        ? text
        : text.substring(0, measuredEnd);
    // 断词（hyphens / overflow-wrap / word-break）：插 U+200B 断点后测量，
    // 再把行区间映射回原文；行尾连字符宽在映射时补进行宽。
    final hyphenAdvance = _measureChar('-', style, textScaleFactor);
    // 行内盒与断词暂不叠加：两种文本改造同段生效会让偏移映射难以自洽
    // （图文混排段落不需要 hyphens 断词）。
    final breakPlan = inlineBoxes.isNotEmpty
        ? SoftBreakPlan.identity(measuredText, hyphenAdvance: hyphenAdvance)
        : planSoftBreaks(
            text: measuredText,
            hyphens: style.hyphens,
            overflowWrap: style.overflowWrap,
            wordBreak: style.wordBreak,
            contentWidth: width,
            style: style,
            textScaleFactor: textScaleFactor,
            hyphenAdvance: hyphenAdvance,
          );
    // 行内盒「整块换行」：盒在行尾放不下时在盒前强制换行后重测（最多 4 轮，
    // 每轮至少解决一个溢出盒）。
    final forcedBreaks = <int>{};
    late List<LineBox> measured;
    for (var attempt = 0; attempt < 4; attempt++) {
      final boxText = inlineBoxes.isEmpty
          ? null
          : _buildInlineBoxText(
              measuredText,
              inlineBoxes,
              forcedBreaks: forcedBreaks,
            );
      final rawMeasured = measuredText.isEmpty || indent <= 0
          ? _measureSegment(
              text: boxText?.text ?? breakPlan.text,
              inlineBoxMarks: boxText?.marks ?? const <_InlineBoxMark>[],
              width: columnLength,
              contentWidth: vertical ? columnLength : width,
              style: style,
              textScaleFactor: textScaleFactor,
              leadingDistribution: leadingDistribution,
              runs: styled,
            )
          : _measureWithIndent(
              text: boxText?.text ?? breakPlan.text,
              inlineBoxMarks: boxText?.marks ?? const <_InlineBoxMark>[],
              width: measureWidth,
              contentWidth: width,
              indent: indent,
              style: style,
              textScaleFactor: textScaleFactor,
              leadingDistribution: leadingDistribution,
              runs: styled,
            );
      measured = _mapSoftBreaks(rawMeasured, breakPlan);
      if (boxText != null && boxText.changed) {
        measured = _mapInlineBoxLines(measured, boxText);
      }

    if (style.writingMode != CssWritingMode.horizontalTb) {
      // 竖排（CSS Writing Modes §3，最小可用映射）：横排测量得到的每「行」
      // 变成一「列」，列宽 = 行高，列长 = 该行宽；rl 首列在最右、lr 在左。
      // 文字仍在列内自上而下（字符顺序与横排一致），逐字旋转由绘制层做。
      return _verticalFromLines(
        text: text,
        lines: measured,
        style: style,
        maxWidth: width,
        runs: styled,
        isRtl: style.isRtl,
      );
    }
      if (boxText == null) {
        break;
      }
      var retry = false;
      for (final line in measured) {
        for (final box in line.inlineBoxes) {
          // 行内还有前置文字、且盒右缘超出内容宽 → 盒整体换行。
          if (box.left > 0.5 && box.left + box.width > width + 0.5) {
            if (forcedBreaks.add(box.spec.offset)) {
              retry = true;
            }
          }
        }
      }
      if (!retry) {
        break;
      }
    }
    return _result(
      text,
      _align(measuredText, measured, style, width),
      width,
      styled,
      isRtl: style.isRtl,
    );
  }

  /// 构造软断点计划（`hyphens` / `overflow-wrap` / `word-break`）。
  ///
  /// - `hyphens: auto`：拉丁词按「元音-辅音-元音」近似音节边界插入断点，
  ///   并在这些断点处标记行尾连字符；`manual` 只认文本里的软连字符
  ///   U+00AD；`none` 不断词。
  /// - `overflow-wrap: break-word`：只给「单独放不下一行」的长词插断点；
  ///   `anywhere` 与 `word-break:break-all` 给所有拉丁词逐字插断点。
  ///
  /// 断点用 U+200B 表达（零宽、可断），Skia 只在真放不下时才用；偏移映射
  /// 保证行区间仍是原文坐标。
  static SoftBreakPlan planSoftBreaks({
    required String text,
    required CssHyphens hyphens,
    required CssOverflowWrap overflowWrap,
    required CssWordBreak wordBreak,
    required double contentWidth,
    required ComputedStyle style,
    double textScaleFactor = 1,
    double hyphenAdvance = 0,
  }) {
    final autoHyphen = hyphens == CssHyphens.auto;
    final manualHyphen = hyphens == CssHyphens.manual || autoHyphen;
    final breakAnywhere =
        overflowWrap == CssOverflowWrap.anywhere ||
        wordBreak == CssWordBreak.breakAll;
    final breakLongWord = overflowWrap == CssOverflowWrap.breakWord;
    final hasSoftHyphen = text.contains('\u00AD');
    if (!autoHyphen &&
        !(manualHyphen && hasSoftHyphen) &&
        !breakAnywhere &&
        !breakLongWord) {
      return SoftBreakPlan.identity(text, hyphenAdvance: hyphenAdvance);
    }
    // 断点：原文下标 → 是否带连字符（key 是「断在该下标之前」）。
    final breaks = <int, bool>{};
    var index = 0;
    while (index < text.length) {
      final code = text.codeUnitAt(index);
      if (_isLatinWordCode(code)) {
        final start = index;
        while (index < text.length && _isLatinWordCode(text.codeUnitAt(index))) {
          index += 1;
        }
        final word = text.substring(start, index);
        for (final offset in _wordBreakOffsets(
          word,
          autoHyphen: autoHyphen,
          breakAnywhere: breakAnywhere,
          breakLongWord: breakLongWord,
          contentWidth: contentWidth,
          style: style,
          textScaleFactor: textScaleFactor,
        )) {
          breaks[start + offset] = autoHyphen && !breakAnywhere;
        }
        continue;
      }
      if (code == 0x00AD && manualHyphen) {
        // 软连字符本身就是断点（原文保留 SHY，测量文本换成 ZWSP）。
        breaks[index] = true;
        index += 1;
        continue;
      }
      index += 1;
    }
    if (breaks.isEmpty) {
      return SoftBreakPlan.identity(text, hyphenAdvance: hyphenAdvance);
    }
    final buffer = StringBuffer();
    final offsets = <int>[0];
    final hyphenPoints = <int>{};
    for (var p = 0; p < text.length; p++) {
      final isSoftHyphen = text.codeUnitAt(p) == 0x00AD;
      if (breaks.containsKey(p)) {
        // 软连字符位本身用它换掉（零宽），其余位置插入 ZWSP。
        buffer.write('\u200B');
        offsets.add(p);
        if (breaks[p] == true) {
          hyphenPoints.add(buffer.length - 1);
        }
        if (isSoftHyphen) {
          continue; // SHY 已被 ZWSP 取代
        }
      }
      buffer.write(text[p]);
      offsets.add(p + 1);
    }
    final planned = buffer.toString();
    if (planned.length == text.length && hyphenPoints.isEmpty) {
      return SoftBreakPlan.identity(text, hyphenAdvance: hyphenAdvance);
    }
    if (planned.length == text.length) {
      // 等长替换（软连字符 → ZWSP）：映射恒等，但保留连字符断点。
      return SoftBreakPlan(
        text: planned,
        offsets: List<int>.generate(text.length + 1, (i) => i),
        hyphenPoints: hyphenPoints,
        hyphenAdvance: hyphenAdvance,
      );
    }
    return SoftBreakPlan(
      text: planned,
      offsets: offsets,
      hyphenPoints: hyphenPoints,
      hyphenAdvance: hyphenAdvance,
    );
  }

  /// 拉丁词内部的断点（相对词首的下标）：「断在该下标之前」。
  static List<int> _wordBreakOffsets(
    String word, {
    required bool autoHyphen,
    required bool breakAnywhere,
    required bool breakLongWord,
    required double contentWidth,
    required ComputedStyle style,
    required double textScaleFactor,
  }) {
    if (word.length < 4) {
      return const <int>[];
    }
    if (breakAnywhere) {
      return <int>[for (var i = 1; i < word.length; i++) i];
    }
    if (breakLongWord && _wordWidth(word, style, textScaleFactor) > contentWidth) {
      return <int>[for (var i = 1; i < word.length; i++) i];
    }
    if (!autoHyphen) {
      return const <int>[];
    }
    // 近似音节断点：V-C|V（元音-辅音-元音）在辅音前断开，两侧各留 ≥2 字符。
    final offsets = <int>[];
    for (var i = 2; i < word.length - 2; i++) {
      if (_isVowel(word.codeUnitAt(i - 1)) &&
          !_isVowel(word.codeUnitAt(i)) &&
          _isVowel(word.codeUnitAt(i + 1))) {
        offsets.add(i);
      }
    }
    return offsets;
  }

  /// 词宽（`overflow-wrap: break-word` 判定用）。
  static double _wordWidth(
    String word,
    ComputedStyle style,
    double textScaleFactor,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: word, style: textStyleFor(style)),
      textDirection: _textDirectionOf(style),
      textScaler: TextScaler.linear(textScaleFactor),
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  /// 拉丁字母/数字（含连字符与撇号，按整词处理）。
  static bool _isLatinWordCode(int code) =>
      (code >= 0x41 && code <= 0x5A) ||
      (code >= 0x61 && code <= 0x7A) ||
      (code >= 0x30 && code <= 0x39) ||
      code == 0x27 ||
      code == 0x2019;

  /// 元音（近似音节切分用）。
  static bool _isVowel(int code) {
    final lower = code >= 0x41 && code <= 0x5A ? code + 0x20 : code;
    return lower == 0x61 || // a
        lower == 0x65 || // e
        lower == 0x69 || // i
        lower == 0x6F || // o
        lower == 0x75 || // u
        lower == 0x79; // y
  }

  /// 把测量坐标的断点映射回原文坐标（行区间仍是原文）。
  static List<LineBox> _mapSoftBreaks(List<LineBox> lines, SoftBreakPlan plan) {
    if (!plan.changed) {
      return lines;
    }
    final mapped = <LineBox>[];
    for (final line in lines) {
      // Skia 的边界可能含 ZWSP 本身（end = 断点下标 + 1），两种都算断词。
      final hyphenated =
          plan.isHyphenPoint(line.end) ||
          (line.end > 0 && plan.isHyphenPoint(line.end - 1));
      mapped.add(
        line.copyWith(
          start: plan.originalOffset(line.start),
          end: plan.originalOffset(line.end),
          width: hyphenated ? line.width + plan.hyphenAdvance : line.width,
          hyphenated: hyphenated,
          hyphenWidth: hyphenated ? plan.hyphenAdvance : 0,
        ),
      );
    }
    return mapped;
  }

  /// 排序并裁掉越界区间；空区间丢弃。
  static List<StyledRun> _normalizeRuns(List<StyledRun> runs, int length) {
    if (runs.isEmpty) {
      return const <StyledRun>[];
    }
    final ordered = <StyledRun>[];
    for (final run in runs) {
      final start = run.start.clamp(0, length);
      final end = run.end.clamp(start, length);
      if (end > start) {
        ordered.add(
          StyledRun(
            start: start,
            end: end,
            style: run.style,
            baselineShift: run.baselineShift,
          ),
        );
      }
    }
    ordered.sort((a, b) => a.start.compareTo(b.start));
    return ordered;
  }

  /// 把字形覆盖分段叠加到调用方的 [runs] 上，返回升序、互不重叠的样式区间。
  ///
  /// 行内样式优先：调用方区间（混排字号、上下标等）只在自身计算样式上叠加
  /// font-family，字号/字重/颜色等保持原值；调用方未覆盖的文本以 [baseStyle]
  /// 兜底后再叠加。相邻且同源的片段会合并，尽量不把调用方区间打碎。
  static List<StyledRun> _applyScriptFallback({
    required List<StyledRun> runs,
    required List<ScriptFontRun> scriptRuns,
    required ComputedStyle baseStyle,
    required int length,
  }) {
    if (scriptRuns.isEmpty) {
      return runs;
    }
    // 用两种区间的全部端点把文本切成互不重叠的小段。
    final cuts = <int>{0, length};
    for (final run in runs) {
      cuts.add(run.start);
      cuts.add(run.end);
    }
    for (final run in scriptRuns) {
      cuts.add(run.start);
      cuts.add(run.end);
    }
    final boundaries = cuts.toList()..sort();

    // 同一来源样式 + 同一族复用同一实例，便于按对象身份合并相邻片段。
    final cache = <String, ComputedStyle>{};
    ComputedStyle withFamily(ComputedStyle source, String family) =>
        cache.putIfAbsent(
          '${identityHashCode(source)}|$family',
          () => _styleWithFontFamily(source, family),
        );

    final merged = <StyledRun>[];
    int? openStart;
    int? openEnd;
    ComputedStyle? openStyle;
    var openShift = 0.0;
    void flush() {
      final start = openStart;
      final end = openEnd;
      final style = openStyle;
      if (start != null && end != null && style != null) {
        merged.add(
          StyledRun(
            start: start,
            end: end,
            style: style,
            baselineShift: openShift,
          ),
        );
      }
      openStart = null;
      openEnd = null;
      openStyle = null;
      openShift = 0;
    }

    var scriptIndex = 0;
    for (var i = 0; i + 1 < boundaries.length; i++) {
      final start = boundaries[i];
      final end = boundaries[i + 1];
      if (end <= start) {
        continue;
      }
      while (scriptIndex < scriptRuns.length &&
          scriptRuns[scriptIndex].end <= start) {
        scriptIndex += 1;
      }
      final family =
          scriptIndex < scriptRuns.length &&
              scriptRuns[scriptIndex].start <= start
          ? scriptRuns[scriptIndex].family
          : null;
      final owner = _owningRun(runs, start, end);
      final style = _segmentStyle(owner, family, baseStyle, withFamily);
      final shift = owner?.baselineShift ?? 0;
      if (style == null) {
        flush(); // 无族的空隙不产出区间
      } else if (openStyle != null &&
          identical(openStyle, style) &&
          openShift == shift &&
          openEnd == start) {
        openEnd = end; // 同源同族同偏移，继续延伸
      } else {
        flush();
        openStart = start;
        openEnd = end;
        openStyle = style;
        openShift = shift;
      }
    }
    flush();
    return merged;
  }

  /// 完整覆盖 `[start, end)` 的调用方区间；重叠时取升序首个（与绘制一致）。
  static StyledRun? _owningRun(List<StyledRun> runs, int start, int end) {
    for (final run in runs) {
      if (run.start <= start && run.end >= end) {
        return run;
      }
    }
    return null;
  }

  /// 小段的最终样式；无调用方区间且无族时返回 null（该段不产出区间）。
  static ComputedStyle? _segmentStyle(
    StyledRun? owner,
    String? family,
    ComputedStyle baseStyle,
    ComputedStyle Function(ComputedStyle source, String family) withFamily,
  ) {
    final source = owner?.style ?? baseStyle;
    if (family == null) {
      return owner == null ? null : source;
    }
    return withFamily(source, family);
  }

  /// 只覆盖 font-family，其余字段继承 [source]（行内字号、字重等保持原值）。
  static ComputedStyle _styleWithFontFamily(
    ComputedStyle source,
    String family,
  ) => ComputedStyle(
    <String, String>{'font-family': family},
    parent: source,
    explicitProperties: const <String>{'font-family'},
    hasExplicitTextColor: source.hasExplicitTextColor,
  );

  /// 取 `[start, end)` 范围内的样式区间，偏移改为相对起点。
  static List<StyledRun> _sliceRuns(List<StyledRun> runs, int start, int end) {
    final sliced = <StyledRun>[];
    for (final run in runs) {
      final runStart = math.max(run.start, start);
      final runEnd = math.min(run.end, end);
      if (runEnd > runStart) {
        sliced.add(
          StyledRun(
            start: runStart - start,
            end: runEnd - start,
            style: run.style,
            baselineShift: run.baselineShift,
          ),
        );
      }
    }
    return sliced;
  }

  /// 首行减宽断行，尾段用完整宽度重排后合并（§61.2）。
  static List<LineBox> _measureWithIndent({
    required String text,
    required double width,
    required double contentWidth,
    required double indent,
    required ComputedStyle style,
    required double textScaleFactor,
    required TextLeadingDistribution leadingDistribution,
    List<StyledRun> runs = const <StyledRun>[],
    List<_InlineBoxMark> inlineBoxMarks = const <_InlineBoxMark>[],
  }) {
    final firstWidth = math.max(1.0, width - indent);
    // 首段先不带行内盒测一次，拿到分界后再把「落在首段」的盒补进去
    // （盒占宽会改变首段末行，但盒的位置由原文偏移决定，不受影响）。
    var head = _measureSegment(
      text: text,
      width: firstWidth,
      contentWidth: firstWidth,
      style: style,
      textScaleFactor: textScaleFactor,
      leadingDistribution: leadingDistribution,
      runs: runs,
    );
    if (head.isEmpty) {
      return const <LineBox>[];
    }
    if (inlineBoxMarks.isNotEmpty) {
      final headMarks = <_InlineBoxMark>[
        for (final mark in inlineBoxMarks)
          if (mark.index < head.first.end) mark,
      ];
      if (headMarks.isNotEmpty) {
        head = _measureSegment(
          text: text,
          width: firstWidth,
          contentWidth: firstWidth,
          inlineBoxMarks: headMarks,
          style: style,
          textScaleFactor: textScaleFactor,
          leadingDistribution: leadingDistribution,
          runs: runs,
        );
      }
    }
    final first = head.first.copyWith(indent: indent);
    var remainderStart = first.end;
    if (remainderStart < text.length && text.codeUnitAt(remainderStart) == 10) {
      remainderStart += 1;
    }
    final remainder = text.substring(remainderStart);
    final rest = _measureSegment(
      text: remainder,
      width: width,
      contentWidth: contentWidth,
      inlineBoxMarks: _shiftInlineBoxMarks(inlineBoxMarks, remainderStart),
      style: style,
      textScaleFactor: textScaleFactor,
      leadingDistribution: leadingDistribution,
      runs: _sliceRuns(runs, remainderStart, text.length),
    );
    final lines = <LineBox>[first];
    for (var i = 0; i < rest.length; i++) {
      final line = rest[i];
      lines.add(
        line.copyWith(
          start: line.start + remainderStart,
          end: line.end + remainderStart,
          top: first.height + line.top,
          isLastLine: i == rest.length - 1,
        ),
      );
    }
    lines[0] = lines[0].copyWith(isLastLine: rest.isEmpty);
    return lines;
  }

  /// 按 text-align 计算每行水平偏移与 justify 分摊宽度（§61.5）。
  ///
  /// 行宽已含 text-indent 造成的减宽，比较基准是 `width - indent`；
  /// justify 的末行与硬换行行按 start 对齐，不拉伸——除非
  /// `text-align-last` 指定（P7-21）或 `text-justify: justify-all`。
  static List<LineBox> _align(
    String text,
    List<LineBox> lines,
    ComputedStyle style,
    double width,
  ) {
    // 标点悬挂（P7-18）：`hanging-punctuation: allow-end` 时，两端
    // 对齐的非末行行尾句读挂到版心右缘外——该行的可分配余量加上
    // 句读 advance，末字（句读）落在右缘之外；末行与硬换行不悬挂
    // （_justifyExtra 内判定）。书内显式 CSS 优先：只有声明了
    // allow-end 才启用（默认 none）。
    final hanging = style.hangingPunctuation == CssHangingPunctuation.allowEnd;
    final punctWidths = <String, double>{};
    double punctWidthOf(String punct) => punctWidths[punct] ??= _measureChar(
      punct,
      style,
    );
    final mode = style.textJustify;
    // 末行（含硬换行）的对齐：text-align-last 优先，缺省 start。
    // text-justify: justify-all 或 text-align-last: justify 时末行参与拉伸。
    final lastMayJustify =
        mode == CssTextJustify.justifyAll ||
        style.textAlignLast == CssTextAlign.justify;
    final aligned = <LineBox>[];
    for (final line in lines) {
      final slack = width.isFinite
          ? math.max(0.0, width - line.indent - line.width)
          : 0.0;
      final isFinal = line.isLastLine || line.isHardBreak;
      // text-align-last:auto 语义（P7-21）：justify 文本的末行按 start；
      // 其余对齐延续 text-align。显式 textAlignLast 覆盖。
      final align = _resolveTextAlign(
        isFinal
            ? (style.textAlignLast ??
                  (style.textAlign == CssTextAlign.justify
                      ? CssTextAlign.start
                      : style.textAlign))
            : style.textAlign,
        style.isRtl,
      );
      // 拉伸余量：justify 对齐；或末行在 justify-all / align-last:
      // justify 下参与拉伸（对齐仍是 start，通过 justifyExtra 拉伸）。
      // 其余对齐保持 0（否则左对齐行也会被绘制端拉伸）。
      // 省略号截断行不拉伸：截断宽已含 `…`，再拉伸会让 `…` 溢出版心。
      final stretch =
          !line.ellipsized &&
          (align == CssTextAlign.justify || (isFinal && lastMayJustify));
      final justifyExtra = stretch
          ? _justifyExtra(
              text,
              line,
              slack,
              mode: mode,
              hanging: hanging,
              punctWidthOf: punctWidthOf,
              lastMayJustify: lastMayJustify,
            )
          : 0.0;
      aligned.add(switch (align) {
        CssTextAlign.start ||
        CssTextAlign.left => line.copyWith(
          offsetX: line.indent,
          justifyExtra: justifyExtra,
          justifyMode: mode,
        ),
        CssTextAlign.end ||
        CssTextAlign.right => line.copyWith(
          offsetX: line.indent + slack,
          justifyExtra: justifyExtra,
          justifyMode: mode,
        ),
        CssTextAlign.center => line.copyWith(
          offsetX: line.indent + slack / 2,
          justifyExtra: justifyExtra,
          justifyMode: mode,
        ),
        CssTextAlign.justify => line.copyWith(
          offsetX: line.indent,
          justifyExtra: justifyExtra,
          justifyMode: mode,
        ),
      });
    }
    return aligned;
  }

  /// 该行可用于 justify 的余量；没有可拉伸间隙时返回 0。
  ///
  /// 悬挂开启且行尾为悬挂句读时，余量加句读宽度（P7-18）。
  /// 末行/硬换行仅在 `lastMayJustify`（justify-all 或 align-last:
  /// justify）时参与拉伸（P7-21）。
  static double _justifyExtra(
    String text,
    LineBox line,
    double slack, {
    required CssTextJustify mode,
    required bool hanging,
    required double Function(String) punctWidthOf,
    required bool lastMayJustify,
  }) {
    if (slack < 0) {
      return 0;
    }
    final isFinal = line.isLastLine || line.isHardBreak;
    if (isFinal && !lastMayJustify) {
      return 0;
    }
    final lineText = text.substring(line.start, line.end);
    final gaps = cjkJustifyGapOffsets(lineText, mode: mode);
    if (gaps.isEmpty) {
      return 0;
    }
    if (hanging &&
        !isFinal &&
        lineText.isNotEmpty) {
      // 悬挂句读均为单个 UTF-16 码元（U+2026 与 CJK 句读区）。
      final lastChar = String.fromCharCode(
        lineText.codeUnitAt(lineText.length - 1),
      );
      if (hangableTrailingPunctuation.contains(lastChar)) {
        return slack + punctWidthOf(lastChar);
      }
    }
    return slack;
  }

  /// 行尾可悬挂的句读（P7-18；Reeden 150 号 §0-#5 悬挂行为——行尾
  /// 句号、逗号挂到版心外）。
  static const Set<String> hangableTrailingPunctuation = <String>{
    '，',
    '。',
    '、',
    '；',
    '：',
    '？',
    '！',
    '…',
  };

  /// 单字符 advance 测量（悬挂余量/省略号宽用；每次 layout 内缓存）。
  static double _measureChar(
    String char,
    ComputedStyle style, [
    double textScaleFactor = 1,
  ]) {
    final painter = TextPainter(
      text: TextSpan(
        text: char,
        style: textStyleFor(style, leadingDistribution: TextLeadingDistribution.even),
      ),
      textDirection: _textDirectionOf(style),
      textScaler: TextScaler.linear(textScaleFactor),
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  /// 纯文本段的逐字符 span（P7-19/P7-20）：相邻全角标点前标点加
  /// -0.5em（挤压）、CJK↔拉丁边界加 +0.125em（自动间距），同字符
  /// 代数叠加；无需调整时返回单 span。
  static TextSpan _plainSpan(
    String text,
    ComputedStyle style,
    TextStyle baseStyle,
    double textScaleFactor,
  ) {
    final advanceOf = punctAdvanceMeasurer(
      baseStyle,
      textScaleFactor,
      direction: _textDirectionOf(style),
    );
    final em = style.fontSize;
    final compressOffsets = style.textSpacingTrim ==
            CssTextSpacingTrim.trimAdjacent
        ? punctCompressionOffsets(text, em: em, advanceOf: advanceOf)
        : const <int>[];
    final autospace = style.textAutospace == CssTextAutospace.normal
        ? autospaceOffsets(text)
        : const <int>[];
    if (compressOffsets.isEmpty && autospace.isEmpty) {
      return TextSpan(text: text, style: baseStyle);
    }
    final compressionSpacing = punctCompressionSpacing(em);
    final boundarySpacing = autospaceSpacing(em);
    final compressStarts = compressOffsets.toSet();
    final autospaceStarts = autospace.toSet();
    final children = <InlineSpan>[];
    var offset = 0;
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      final extra =
          (compressStarts.contains(offset) ? compressionSpacing : 0.0) +
          (autospaceStarts.contains(offset) ? boundarySpacing : 0.0);
      children.add(
        TextSpan(
          text: char,
          style: extra == 0
              ? baseStyle
              : baseStyle.copyWith(
                  letterSpacing: (baseStyle.letterSpacing ?? 0) + extra,
                ),
        ),
      );
      offset += char.length;
    }
    return TextSpan(style: baseStyle, children: children);
  }

  static List<LineBox> _measureSegment({
    required String text,
    required double width,
    required ComputedStyle style,
    required double textScaleFactor,
    required TextLeadingDistribution leadingDistribution,
    List<StyledRun> runs = const <StyledRun>[],
    List<_InlineBoxMark> inlineBoxMarks = const <_InlineBoxMark>[],
    double? contentWidth,
  }) {
    final baseStyle = textStyleFor(
      style,
      leadingDistribution: leadingDistribution,
    );
    // 标点挤压（P7-19）与中西文间距（P7-20）：只作用于无行内样式
    // 区间的纯文本段（测量与绘制同规则，见 buildLineSpan）；两者都
    // 影响行宽，须在测量期生效。
    final compress =
        runs.isEmpty &&
        (style.textSpacingTrim == CssTextSpacingTrim.trimAdjacent ||
            style.textAutospace == CssTextAutospace.normal);
    // `/`（UAX#14 SY）在 ICU/Skia 里会给出断行机会，而 Chrome 不在
    // `right/bottom` 这类 token 内断行：用零宽 WORD JOINER 包住 SOLIDUS
    // 压掉两侧断点，测量后再把行偏移映射回原文。
    // `/`（UAX#14 SY）在 ICU/Skia 里会给出断行机会，Chrome 不在 token 内断行：
    // 记下「含 `/` 的 token」区间，测量后把落在其中的紧急断行合并回去。
    // 作者显式要求「任意位置可断」（break-all / anywhere / break-word）时不合并。
    final allowsAnyBreak =
        style.wordBreak == CssWordBreak.breakAll ||
        style.overflowWrap == CssOverflowWrap.anywhere ||
        style.overflowWrap == CssOverflowWrap.breakWord;
    final guardRanges = inlineBoxMarks.isEmpty && !allowsAnyBreak
        ? _guardedTokenRanges(text)
        : const <(int, int)>[];
    final measureText = text;
    final painter = TextPainter(
      text: inlineBoxMarks.isNotEmpty
          ? _inlineBoxSpans(
              measureText,
              baseStyle,
              inlineBoxMarks,
              style,
              textScaleFactor,
            )
          : runs.isEmpty
          ? (compress
                ? _plainSpan(measureText, style, baseStyle, textScaleFactor)
                : TextSpan(text: measureText, style: baseStyle))
          : TextSpan(
              style: baseStyle,
              children: buildStyledSpans(
                text: text,
                start: 0,
                end: text.length,
                runs: runs,
                baseStyle: baseStyle,
                styleOf: (runStyle) => textStyleFor(
                  runStyle,
                  leadingDistribution: leadingDistribution,
                ),
              ),
            ),
      textDirection: _textDirectionOf(style),
      textScaler: TextScaler.linear(textScaleFactor),
    )..layout(maxWidth: width);

    final metrics = painter.computeLineMetrics();
    // 小数行高（实验）：Skia 行盒高取整为整数，ascent 已按小数行高计算；
    // 这里把「被取整的 strut 行盒」换回 CSS 行高像素值。
    final cssLineHeight =
        LineBreaker.preserveFractionalLineHeight &&
                style.lineHeightFactor != null
            ? style.lineHeight
            : null;
    final lines = <LineBox>[];
    var top = 0.0;
    for (final metric in metrics) {
      final lineHeight = cssLineHeight != null &&
              (metric.height - cssLineHeight).abs() <= 0.6
          ? cssLineHeight
          : metric.height;
      // 用行框垂直中点取该行内的字符位置，再取边界；
      // 直接拿“上一行 end”做位置在硬换行/空行处会落回上一行。
      final position = painter.getPositionForOffset(
        Offset(0, top + metric.height / 2),
      );
      final boundary = painter.getLineBoundary(position);
      lines.add(
        LineBox(
          start: boundary.start,
          end: boundary.end,
          top: top,
          height: lineHeight,
          baseline: top + metric.ascent,
          width: math.max(0, metric.width).toDouble(),
        ),
      );
      top += lineHeight;
    }
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final hardBreak =
          line.end < text.length && text.codeUnitAt(line.end) == 10;
      lines[i] = line.copyWith(
        isLastLine: i == lines.length - 1,
        isHardBreak: hardBreak,
      );
    }
    // Skia 会对放不下的 token 做逐字紧急断行，Chrome 则让 token 整段溢出：
    // 把「断点处没有合法断行机会」的相邻行合并回去（URL、right/bottom 等）。
    final mergedLines = guardRanges.isEmpty
        ? lines
        : _mergeUnbreakableLines(
            lines,
            measureText,
            baseStyle,
            textScaleFactor,
            guardRanges,
          );
    var truncated = _applyTextOverflow(
      lines: mergedLines,
      painter: painter,
      contentWidth: contentWidth ?? width,
      style: style,
      textScaleFactor: textScaleFactor,
      leadingDistribution: leadingDistribution,
    );
    return _applyInlineVerticalBoxes(
      _applyInlineBoxes(
        truncated,
        inlineBoxMarks,
        painter,
        text: text,
        baseStyle: baseStyle,
        style: style,
        textScaleFactor: textScaleFactor,
      ),
      runs,
      style,
      leadingDistribution,
    );
  }

  /// 行内盒标记在子串测量时的下标平移（`_measureWithIndent` 的后半段）：
  /// 落在 [shift] 之前的标记属于首段，丢弃。
  static List<_InlineBoxMark> _shiftInlineBoxMarks(
    List<_InlineBoxMark> marks,
    int shift,
  ) {
    if (marks.isEmpty) {
      return marks;
    }
    return <_InlineBoxMark>[
      for (final mark in marks)
        if (mark.index >= shift)
          _InlineBoxMark(index: mark.index - shift, spec: mark.spec),
    ];
  }

  /// 把占位文本坐标的行区间与行内盒偏移映射回原文。
  static List<LineBox> _mapInlineBoxLines(
    List<LineBox> lines,
    _InlineBoxText boxText,
  ) {
    final mapped = <LineBox>[];
    for (final line in lines) {
      mapped.add(
        line.copyWith(
          start: boxText.originalOffset(line.start),
          end: boxText.originalOffset(line.end),
          inlineBoxes: line.inlineBoxes.isEmpty
              ? line.inlineBoxes
              : List<InlineBoxPlacement>.unmodifiable(<InlineBoxPlacement>[
                  for (final box in line.inlineBoxes)
                    InlineBoxPlacement(
                      offset: boxText.originalOffset(box.offset),
                      left: box.left,
                      width: box.width,
                      height: box.height,
                      ascent: box.ascent,
                      descent: box.descent,
                      spec: box.spec,
                    ),
                ]),
        ),
      );
    }
    return mapped;
  }

  /// 段落方向（`direction: rtl` 时 rtl）；测量与绘制必须同口径。
  static TextDirection _textDirectionOf(ComputedStyle style) =>
      style.isRtl ? TextDirection.rtl : TextDirection.ltr;

  /// 把 `start`/`end` 对齐按段落方向折算成物理左/右。
  ///
  /// 与 [ComputedStyle.resolvedTextAlign] 同口径，另外覆盖末行的
  /// `text-align-last`（它也允许 start/end）。
  static CssTextAlign _resolveTextAlign(CssTextAlign align, bool rtl) =>
      switch (align) {
        CssTextAlign.start => rtl ? CssTextAlign.right : CssTextAlign.left,
        CssTextAlign.end => rtl ? CssTextAlign.left : CssTextAlign.right,
        _ => align,
      };

  /// 行内盒占位符（U+FFFC：object replacement character）。
  static const String _inlineBoxPlaceholder = '\uFFFC';

  /// 构造行内盒占位文本：在每个盒的插入点插入一个占位符，并给出偏移映射。
  static _InlineBoxText _buildInlineBoxText(
    String text,
    List<InlineBoxSpec> specs, {
    Set<int> forcedBreaks = const <int>{},
  }) {
    final ordered = <InlineBoxSpec>[...specs]
      ..sort((a, b) => a.offset.compareTo(b.offset));
    final buffer = StringBuffer();
    final offsets = <int>[0];
    final marks = <_InlineBoxMark>[];
    var cursor = 0;
    for (final spec in ordered) {
      final stop = spec.offset.clamp(cursor, text.length);
      for (var i = cursor; i < stop; i++) {
        buffer.write(text[i]);
        offsets.add(i + 1);
      }
      // 盒放不下时先在容器内强制换行（CSS inline-block 整体换行）。
      if (forcedBreaks.contains(stop)) {
        buffer.write('\n');
        offsets.add(stop);
      }
      buffer.write(_inlineBoxPlaceholder);
      marks.add(_InlineBoxMark(index: buffer.length - 1, spec: spec));
      // 占位符前后两个边界都对应原文 [stop]（盒占 0 个字、只占宽度）。
      offsets.add(stop);
      cursor = stop;
    }
    for (var i = cursor; i < text.length; i++) {
      buffer.write(text[i]);
      offsets.add(i + 1);
    }
    return _InlineBoxText(
      text: buffer.toString(),
      offsets: offsets,
      marks: marks,
    );
  }

  /// 占位文本中 [index] 之前的宽度（行内盒 x 用；含此前占位符的宽度）。
  static double _prefixAdvance(
    String text,
    int index,
    TextStyle baseStyle,
    List<_InlineBoxMark> marks,
    ComputedStyle style,
    double textScaleFactor,
  ) {
    if (index <= 0) {
      return 0;
    }
    final prefix = text.substring(0, math.min(index, text.length));
    final activeMarks = <_InlineBoxMark>[
      for (final mark in marks)
        if (mark.index < prefix.length) mark,
    ];
    final span = _inlineBoxSpans(
      prefix,
      baseStyle,
      activeMarks,
      style,
      textScaleFactor,
    );
    final painter = TextPainter(
      text: span,
      textDirection: _textDirectionOf(style),
      textScaler: TextScaler.linear(textScaleFactor),
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  /// 行内盒占位 span：占位符用 letterSpacing 补到目标宽度。
  static TextSpan _inlineBoxSpans(
    String text,
    TextStyle baseStyle,
    List<_InlineBoxMark> marks,
    ComputedStyle style,
    double textScaleFactor,
  ) {
    final placeholderAdvance = _measureChar(
      _inlineBoxPlaceholder,
      style,
      textScaleFactor,
    );
    final children = <InlineSpan>[];
    var cursor = 0;
    for (final mark in marks) {
      final index = mark.index.clamp(0, text.length);
      if (index > cursor) {
        children.add(
          TextSpan(text: text.substring(cursor, index), style: baseStyle),
        );
      }
      final spacing = mark.spec.width - placeholderAdvance;
      children.add(
        TextSpan(
          text: _inlineBoxPlaceholder,
          style: spacing.abs() < 0.01
              ? baseStyle
              : baseStyle.copyWith(
                  letterSpacing: (baseStyle.letterSpacing ?? 0) + spacing,
                ),
        ),
      );
      cursor = index + 1;
    }
    if (cursor < text.length) {
      children.add(TextSpan(text: text.substring(cursor), style: baseStyle));
    }
    return TextSpan(style: baseStyle, children: children);
  }

  /// 把行内盒放到行上：x 取占位符的行内起点，按盒的 ascent/descent 撑高行盒
  /// 并重排后续行（CSS inline-block 参与行盒高度计算）。
  static List<LineBox> _applyInlineBoxes(
    List<LineBox> lines,
    List<_InlineBoxMark> marks,
    TextPainter painter, {
    required String text,
    required TextStyle baseStyle,
    required ComputedStyle style,
    required double textScaleFactor,
  }) {
    if (marks.isEmpty || lines.isEmpty) {
      return lines;
    }
    final perLine = List<List<InlineBoxPlacement>>.generate(
      lines.length,
      (_) => <InlineBoxPlacement>[],
    );
    final growUp = List<double>.filled(lines.length, 0);
    final growDown = List<double>.filled(lines.length, 0);
    for (final mark in marks) {
      var lineIndex = lines.length - 1;
      for (var i = 0; i < lines.length; i++) {
        if (mark.index >= lines[i].start && mark.index < lines[i].end) {
          lineIndex = i;
          break;
        }
      }
      final line = lines[lineIndex];
      // 行内 x：占位符之前的前缀宽 - 行首之前的前缀宽（用同一套 span 结构
      // 前缀测量；caret 位置在 letterSpacing 下含半间距，不能直接用）。
      final dx = _prefixAdvance(
            text,
            mark.index,
            baseStyle,
            marks,
            style,
            textScaleFactor,
          ) -
          _prefixAdvance(
            text,
            line.start,
            baseStyle,
            marks,
            style,
            textScaleFactor,
          );
      final placement = InlineBoxPlacement(
        offset: mark.index,
        left: line.offsetX + math.max(0.0, dx),
        width: mark.spec.width,
        height: mark.spec.height,
        ascent: mark.spec.ascent,
        descent: mark.spec.descent,
        spec: mark.spec,
      );
      perLine[lineIndex].add(placement);
      final lineAscent = line.baseline - line.top;
      final lineDescent = line.height - lineAscent;
      growUp[lineIndex] = math.max(
        growUp[lineIndex],
        placement.ascent - lineAscent,
      );
      growDown[lineIndex] = math.max(
        growDown[lineIndex],
        placement.descent - lineDescent,
      );
    }
    // Chrome 口径（实测 cases/53）：行盒高 = max(行高, 盒 margin box 高)，
    // 不是 ascent + descent 相加（否则会比 Chrome 多出文字 descent）。
    final heights = List<double>.filled(lines.length, 0);
    final ascents = List<double>.filled(lines.length, 0);
    for (var i = 0; i < lines.length; i++) {
      var boxHeight = 0.0;
      var boxAscent = 0.0;
      for (final placement in perLine[i]) {
        boxHeight = math.max(boxHeight, placement.ascent + placement.descent);
        boxAscent = math.max(boxAscent, placement.ascent);
      }
      final baseAscent = lines[i].baseline - lines[i].top;
      heights[i] = math.max(lines[i].height, boxHeight);
      ascents[i] = math.min(
        heights[i],
        math.max(baseAscent, boxAscent),
      );
    }
    var grown = false;
    for (var i = 0; i < lines.length; i++) {
      if ((heights[i] - lines[i].height).abs() > 0.01 ||
          (ascents[i] - (lines[i].baseline - lines[i].top)).abs() > 0.01) {
        grown = true;
        break;
      }
    }
    if (!grown) {
      for (var i = 0; i < lines.length; i++) {
        if (perLine[i].isEmpty) {
          continue;
        }
        lines[i] = lines[i].copyWith(
          inlineBoxes: List<InlineBoxPlacement>.unmodifiable(perLine[i]),
        );
      }
      return lines;
    }
    var top = 0.0;
    final adjusted = <LineBox>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final height = heights[i];
      final ascent = ascents[i];
      adjusted.add(
        LineBox(
          start: line.start,
          end: line.end,
          top: top,
          height: height,
          baseline: top + ascent,
          width: line.width,
          indent: line.indent,
          isLastLine: line.isLastLine,
          isHardBreak: line.isHardBreak,
          offsetX: line.offsetX,
          justifyExtra: line.justifyExtra,
          justifyMode: line.justifyMode,
          ellipsized: line.ellipsized,
          ellipsisWidth: line.ellipsisWidth,
          hyphenated: line.hyphenated,
          hyphenWidth: line.hyphenWidth,
          inlineBoxes: List<InlineBoxPlacement>.unmodifiable(perLine[i]),
        ),
      );
      top += height;
    }
    return adjusted;
  }

  /// `text-overflow: ellipsis`（P2-37）：行宽超过内容宽时截成「最长可放
  /// 前缀 + …」，截断行的 [LineBox.width] 已含省略号 advance，保证行宽
  /// ≤ 内容宽；`clip` 不做截断（绘制端按 padding-box 裁剪 ink）。
  ///
  /// 行区间仍指向原文（只取前缀），因此 CFI/选区映射不受影响；绘制端据
  /// [LineBox.ellipsized] 决定是否在行尾补画省略号。
  static List<LineBox> _applyTextOverflow({
    required List<LineBox> lines,
    required TextPainter painter,
    required double contentWidth,
    required ComputedStyle style,
    required double textScaleFactor,
    required TextLeadingDistribution leadingDistribution,
  }) {
    if (style.textOverflow != CssTextOverflow.ellipsis ||
        !contentWidth.isFinite ||
        contentWidth <= 0) {
      return lines;
    }
    final overflowing = lines.any((line) => line.width > contentWidth + 0.5);
    if (!overflowing) {
      return lines;
    }
    final ellipsisAdvance = _measureChar('…', style, textScaleFactor);
    final available = math.max(0.0, contentWidth - ellipsisAdvance);
    var changed = false;
    final result = <LineBox>[];
    for (final line in lines) {
      if (line.width <= contentWidth + 0.5) {
        result.add(line);
        continue;
      }
      // 用已排好的 painter 反查：内容宽内最长的字符位置即截断点。
      final at = painter.getPositionForOffset(
        Offset(available, line.top + line.height / 2),
      );
      var end = at.offset.clamp(line.start, line.end);
      if (end <= line.start) {
        end = math.min(line.start + 1, line.end);
      }
      var prefixWidth = _advanceAt(painter, end);
      while (prefixWidth + ellipsisAdvance > contentWidth + 0.5 &&
          end > line.start + 1) {
        end -= 1;
        prefixWidth = _advanceAt(painter, end);
      }
      changed = true;
      result.add(
        line.copyWith(
          end: end,
          width: math.min(contentWidth, prefixWidth + ellipsisAdvance),
          ellipsized: true,
          ellipsisWidth: ellipsisAdvance,
        ),
      );
    }
    return changed ? result : lines;
  }

  /// 指定字符位置的行内 advance（用于省略号前缀宽度）。
  static double _advanceAt(TextPainter painter, int offset) =>
      painter.getOffsetForCaret(TextPosition(offset: offset), Rect.zero).dx;

  /// 行内盒竖直几何（CSS 2.1 §10.8 的 CU 近似）。
  ///
  /// SkParagraph 的行盒已包含各 run 未偏移时的字体盒，但 `vertical-align`
  /// 造成的竖直平移不参与行盒计算：上下标只挪墨迹、行高不变。这里对带
  /// 偏移的 run 取「自身 line-height 盒」（含半行距）按偏移平移，越出
  /// 当前行盒上/下沿才撑高——浏览器（Chromium）就是这么算的，`sup/sub`
  /// 会把行撑高而不是借行距。
  ///
  /// 行盒只放大不缩小：块级 strut（根样式）始终参与，因此行高下限是
  /// 根行高。
  static List<LineBox> _applyInlineVerticalBoxes(
    List<LineBox> lines,
    List<StyledRun> runs,
    ComputedStyle style,
    TextLeadingDistribution leadingDistribution,
  ) {
    if (!runs.any((run) => run.baselineShift != 0)) {
      return lines;
    }
    final growUps = List<double>.filled(lines.length, 0, growable: false);
    final growDowns = List<double>.filled(lines.length, 0, growable: false);
    final metrics = <ComputedStyle, _InlineBoxMetrics>{};
    var grew = false;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final ascent = line.baseline - line.top;
      final descent = line.height - ascent;
      for (final run in runs) {
        if (run.baselineShift == 0) {
          continue;
        }
        if (math.min(run.end, line.end) <= math.max(run.start, line.start)) {
          continue;
        }
        final box = metrics[run.style] ??= _inlineBoxMetrics(
          run.style,
          leadingDistribution,
        );
        final top = run.baselineShift - box.ascent;
        final bottom = run.baselineShift + box.descent;
        if (top < -ascent - 0.01) {
          growUps[i] = math.max(growUps[i], -ascent - top);
        }
        if (bottom > descent + 0.01) {
          growDowns[i] = math.max(growDowns[i], bottom - descent);
        }
      }
      if (growUps[i] > 0 || growDowns[i] > 0) {
        grew = true;
      }
    }
    if (!grew) {
      return lines;
    }
    // 撑高后重排 top/baseline：向上生长抬高基线，后续行顺延。
    var top = 0.0;
    final adjusted = <LineBox>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final ascent = line.baseline - line.top;
      final height = line.height + growUps[i] + growDowns[i];
      adjusted.add(
        LineBox(
          start: line.start,
          end: line.end,
          top: top,
          height: height,
          baseline: top + ascent + growUps[i],
          width: line.width,
          isLastLine: line.isLastLine,
          isHardBreak: line.isHardBreak,
        ),
      );
      top += height;
    }
    return adjusted;
  }

  /// 把行内竖直对齐折算成 run 的基线偏移（CSS 2.1 §10.8）。
  ///
  /// 返回的 run 同时供行盒测量与绘制（`TextLayoutResult.runs`）使用，
  /// 保证测量与绘制的基线位移一致。口径对齐 Chromium：
  /// - 已带 `baselineShift` 的 run（`super`/`sub`、`vertical-align: <length>`）
  ///   原样沿用：长度/百分比解析后枚举仍是 `baseline`，偏移只落在
  ///   `ComputedStyle.verticalAlignShift` 上，必须靠 baselineShift 识别；
  /// - `text-top` / `text-bottom` 把行内盒上/下沿对齐父内容区上/下沿
  ///   （`ComputedStyle` 只给 0，须在这里按字体度量补）；
  /// - `middle` 把行内盒中线对齐父基线 + x-height/2。
  ///
  /// 短路条件只看「有没有竖直偏移要处理」：全部 run 都无偏移且未声明
  /// 竖直对齐时才跳过，避免长度型偏移（枚举为 baseline）被漏掉。
  static List<StyledRun> _applyVerticalAlign(
    List<StyledRun> runs,
    ComputedStyle style,
    TextLeadingDistribution leadingDistribution,
  ) {
    if (runs.isEmpty ||
        !runs.any(
          (run) =>
              run.baselineShift != 0 ||
              run.style.verticalAlign != CssVerticalAlign.baseline,
        )) {
      return runs;
    }
    _InlineBoxMetrics? parentMetrics;
    _InlineBoxMetrics parent() =>
        parentMetrics ??= _inlineBoxMetrics(style, leadingDistribution);
    final boxes = <ComputedStyle, _InlineBoxMetrics>{};
    _InlineBoxMetrics boxOf(ComputedStyle runStyle) =>
        boxes[runStyle] ??= _inlineBoxMetrics(runStyle, leadingDistribution);
    double? xHeight;
    var changed = false;
    final aligned = <StyledRun>[];
    for (final run in runs) {
      final shift = switch (run.style.verticalAlign) {
        CssVerticalAlign.baseline => run.baselineShift,
        // 以 ComputedStyle 为唯一真源；调用方漏写时按同一公式兜底。
        CssVerticalAlign.superscript =>
          run.baselineShift != 0
              ? run.baselineShift
              : -(run.style.parentFontSize / 3 + 1),
        CssVerticalAlign.subscript =>
          run.baselineShift != 0
              ? run.baselineShift
              : run.style.parentFontSize / 5 + 1,
        CssVerticalAlign.top => boxOf(run.style).ascent - parent().rawAscent,
        CssVerticalAlign.bottom =>
          parent().rawDescent - boxOf(run.style).descent,
        CssVerticalAlign.middle =>
          (boxOf(run.style).ascent - boxOf(run.style).descent) / 2 -
              (xHeight ??= _xHeightFor(style)) / 2,
      };
      if (shift == run.baselineShift) {
        aligned.add(run);
        continue;
      }
      changed = true;
      aligned.add(
        StyledRun(
          start: run.start,
          end: run.end,
          style: run.style,
          baselineShift: shift,
        ),
      );
    }
    return changed ? aligned : runs;
  }

  /// 单个 run / 块级 strut 的竖直度量。
  static _InlineBoxMetrics _inlineBoxMetrics(
    ComputedStyle style,
    TextLeadingDistribution leadingDistribution,
  ) {
    final box = _lineMetricsOf(
      textStyleFor(style, leadingDistribution: leadingDistribution),
    );
    final raw = _lineMetricsOf(_rawTextStyleFor(style));
    return _InlineBoxMetrics(
      ascent: box.ascent,
      descent: box.descent,
      rawAscent: raw.ascent,
      rawDescent: raw.descent,
    );
  }

  /// 单字符 'x' 的段落度量（只为拿字体 ascent/descent，避免整段重排）。
  static LineMetrics _lineMetricsOf(TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: 'x', style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final metrics = painter.computeLineMetrics().first;
    painter.dispose();
    return metrics;
  }

  /// 去掉 line-height 倍数的测量样式：取字体原始 ascent/descent。
  static TextStyle _rawTextStyleFor(ComputedStyle style) {
    final styled = textStyleFor(style);
    return TextStyle(
      fontSize: styled.fontSize,
      fontWeight: styled.fontWeight,
      fontStyle: styled.fontStyle,
      fontFamily: styled.fontFamily,
      fontFamilyFallback: styled.fontFamilyFallback,
      letterSpacing: styled.letterSpacing,
      wordSpacing: styled.wordSpacing,
    );
  }

  /// x-height 近似（`vertical-align: middle` 用）：0.5em。
  ///
  /// Flutter 没有暴露 x-height；CJK 字体 x-height 约 0.5em。该偏差只影响
  /// middle 行内元素的竖直位置，不影响行高（小字号盒仍落在 strut 内）。
  static double _xHeightFor(ComputedStyle style) => style.fontSize * 0.5;

  /// 合并「非法断点」处的紧急断行：token 内不换行（与 Chrome 一致）。
  static List<LineBox> _mergeUnbreakableLines(
    List<LineBox> lines,
    String text,
    TextStyle baseStyle,
    double textScaleFactor,
    List<(int, int)> guardRanges,
  ) {
    if (lines.length < 2 || guardRanges.isEmpty) {
      return lines;
    }
    final merged = <LineBox>[];
    var current = lines.first;
    for (var i = 1; i < lines.length; i++) {
      final next = lines[i];
      // 只在「含 `/` 的 token」内部合并（Skia 会对放不下的 token 逐字紧急
      // 断行，Chrome 让 token 整段溢出）。
      final canBreak =
          current.end != next.start ||
          !_insideGuardedRanges(current.end, guardRanges);
      if (canBreak) {
        merged.add(current);
        current = next;
        continue;
      }
      // 合并：宽度按合并后子串重测（行内可能有空格/变形，不能简单相加）。
      // 行宽不含行尾空白（与 Skia 的行度量口径一致）。
      final painter = TextPainter(
        text: TextSpan(
          text: text.substring(current.start, next.end).trimRight(),
          style: baseStyle,
        ),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.linear(textScaleFactor),
      )..layout();
      final width = painter.width;
      painter.dispose();
      current = current.copyWith(
        end: next.end,
        width: width,
        isLastLine: next.isLastLine,
        isHardBreak: next.isHardBreak,
      );
    }
    merged.add(current);
    var top = 0.0;
    final result = <LineBox>[];
    for (final line in merged) {
      final ascent = line.baseline - line.top;
      result.add(
        LineBox(
          start: line.start,
          end: line.end,
          top: top,
          height: line.height,
          baseline: top + ascent,
          width: line.width,
          indent: line.indent,
          isLastLine: line.isLastLine,
          isHardBreak: line.isHardBreak,
          offsetX: line.offsetX,
          justifyExtra: line.justifyExtra,
          justifyMode: line.justifyMode,
          ellipsized: line.ellipsized,
          ellipsisWidth: line.ellipsisWidth,
          hyphenated: line.hyphenated,
          hyphenWidth: line.hyphenWidth,
          inlineBoxes: line.inlineBoxes,
        ),
      );
      top += line.height;
    }
    return result;
  }

  /// 含 `/`（SOLIDUS）的 token 区间（升序、已合并重叠）；两侧都是空白时不算。
  static List<(int, int)> _guardedTokenRanges(String text) {
    if (!text.contains('/')) {
      return const <(int, int)>[];
    }
    final ranges = <(int, int)>[];
    for (var i = 0; i < text.length; i++) {
      if (text[i] != '/') {
        continue;
      }
      final hasPrev = i > 0 && !_isBreakGuardSpace(text[i - 1]);
      final hasNext = i + 1 < text.length && !_isBreakGuardSpace(text[i + 1]);
      if (!hasPrev && !hasNext) {
        continue;
      }
      var start = i;
      while (start > 0 && !_isBreakGuardSpace(text[start - 1])) {
        start -= 1;
      }
      var end = i + 1;
      while (end < text.length && !_isBreakGuardSpace(text[end])) {
        end += 1;
      }
      ranges.add((start, end));
    }
    return _mergeRanges(ranges);
  }

  /// 是否空白（守卫只在 token 内部生效）。
  static bool _isBreakGuardSpace(String char) =>
      char == ' ' ||
      char == '\t' ||
      char == '\n' ||
      char == '\r' ||
      char == '\u00A0' ||
      char == '\u3000';

  /// 合并重叠/相邻的区间。
  static List<(int, int)> _mergeRanges(List<(int, int)> ranges) {
    if (ranges.isEmpty) {
      return ranges;
    }
    final sorted = <(int, int)>[...ranges]
      ..sort((a, b) => a.$1.compareTo(b.$1));
    final merged = <(int, int)>[sorted.first];
    for (final range in sorted.skip(1)) {
      final last = merged.last;
      if (range.$1 <= last.$2) {
        if (range.$2 > last.$2) {
          merged[merged.length - 1] = (last.$1, range.$2);
        }
      } else {
        merged.add(range);
      }
    }
    return merged;
  }

  /// [index] 是否落在含 `/` 的 token 区间内。
  static bool _insideGuardedRanges(int index, List<(int, int)> ranges) {
    for (final range in ranges) {
      if (index > range.$1 && index < range.$2) {
        return true;
      }
    }
    return false;
  }

  /// 竖排逐字符度量：`text-orientation` 决定正立/旋转，advance 随之取
  /// 1em 或字形宽（旋转后横向宽度变成列内纵向 advance）。
  ///
  /// 绘制层可用它逐字摆放/旋转；同一段文本的 advance 之和即列长。
  static List<VerticalGlyphMetric> verticalGlyphMetrics(
    String text,
    ComputedStyle style, {
    double textScaleFactor = 1,
  }) {
    final metrics = <VerticalGlyphMetric>[];
    final em = style.fontSize;
    var offset = 0;
    for (final rune in text.runes) {
      final length = rune > 0xFFFF ? 2 : 1;
      final char = String.fromCharCode(rune);
      final upright = switch (style.textOrientation) {
        CssTextOrientation.upright => true,
        CssTextOrientation.sideways => false,
        CssTextOrientation.mixed => _isUprightRune(rune),
      };
      final advance = upright ? em : _measureChar(char, style, textScaleFactor);
      metrics.add(
        VerticalGlyphMetric(
          start: offset,
          end: offset + length,
          advance: advance,
          upright: upright,
        ),
      );
      offset += length;
    }
    return metrics;
  }

  /// 竖排下是否正立：CJK 汉字/假名/注音符号/全角标点等按 1em 正立，
  /// 拉丁/数字/半角符号侧躺（CSS Writing Modes §6.1 的 mixed 规则近似）。
  static bool _isUprightRune(int rune) {
    if (rune >= 0x1100 && rune <= 0x11FF) {
      return true; // 谚文字母
    }
    if (rune >= 0x2E80 && rune <= 0x303F) {
      return true; // CJK 部首/符号/标点
    }
    if (rune >= 0x3041 && rune <= 0x33FF) {
      return true; // 假名/注音/兼容 CJK
    }
    if (rune >= 0x3400 && rune <= 0x4DBF) {
      return true; // CJK 扩展 A
    }
    if (rune >= 0x4E00 && rune <= 0x9FFF) {
      return true; // CJK 统一表意
    }
    if (rune >= 0xF900 && rune <= 0xFAFF) {
      return true; // CJK 兼容表意
    }
    if (rune >= 0xFF00 && rune <= 0xFF60) {
      return true; // 全角形式
    }
    if (rune >= 0x20000 && rune <= 0x3FFFF) {
      return true; // CJK 扩展 B+
    }
    return false;
  }

  /// 横排测量结果 → 竖排列（CSS Writing Modes §3）。
  ///
  /// - 列数 = 横排行数；列宽 = CSS 行高（`line-height` 解算值）；
  /// - 列长 = 该行横排宽（近似：拉丁字形旋转后按原宽计，见已知限制）；
  /// - `vertical-rl` 首列在最右（列从右向左推进），`vertical-lr` 在左；
  /// - 块宽 = 列数 × 列宽，块高 = 最长列；行内 `top` 恒为 0。
  static TextLayoutResult _verticalFromLines({
    required String text,
    required List<LineBox> lines,
    required ComputedStyle style,
    required double maxWidth,
    required List<StyledRun> runs,
    required bool isRtl,
  }) {
    // 列宽 = 行高：优先用实测行高（`line-height: normal` 时由字体度量决定，
    // 不能拿 1.2em 之类的常数近似）；无行时退回字号。
    var columnWidth = 0.0;
    for (final line in lines) {
      columnWidth = math.max(columnWidth, line.height);
    }
    if (columnWidth <= 0) {
      columnWidth = math.max(1.0, style.fontSize * 1.2);
    }
    final count = lines.length;
    final rl = style.writingMode == CssWritingMode.verticalRl;
    final columns = <LineBox>[];
    var longest = 0.0;
    for (var i = 0; i < count; i++) {
      final line = lines[i];
      final columnX = rl ? (count - 1 - i) * columnWidth : i * columnWidth;
      longest = math.max(longest, line.width);
      columns.add(
        LineBox(
          start: line.start,
          end: line.end,
          top: 0,
          height: line.width,
          baseline: 0,
          width: columnWidth,
          offsetX: columnX,
          columnIndex: i,
          columnX: columnX,
          vertical: true,
          isLastLine: line.isLastLine,
          isHardBreak: line.isHardBreak,
          ellipsized: line.ellipsized,
          ellipsisWidth: line.ellipsisWidth,
          hyphenated: line.hyphenated,
          hyphenWidth: line.hyphenWidth,
        ),
      );
    }
    return TextLayoutResult(
      text: text,
      lines: List<LineBox>.unmodifiable(columns),
      // 竖排块的「宽」是列带总宽（= 列数 × 列宽），「高」是最长列。
      width: count * columnWidth,
      height: longest,
      maxWidth: maxWidth,
      runs: List<StyledRun>.unmodifiable(runs),
      isRtl: isRtl,
      writingMode: style.writingMode,
    );
  }

  static TextLayoutResult _result(
    String text,
    List<LineBox> lines,
    double maxWidth,
    List<StyledRun> runs, {
    bool isRtl = false,
  }) {
    var maxLineWidth = 0.0;
    for (final line in lines) {
      maxLineWidth = math.max(maxLineWidth, line.width);
    }
    final height = lines.isEmpty ? 0.0 : lines.last.bottom;
    return TextLayoutResult(
      text: text,
      lines: List<LineBox>.unmodifiable(lines),
      width: maxLineWidth,
      height: height,
      maxWidth: maxWidth,
      runs: List<StyledRun>.unmodifiable(runs),
      isRtl: isRtl,
    );
  }

  /// 从计算样式生成绘制/测量用 TextStyle。
  /// `font-variant-caps` → OpenType 特性标签。
  ///
  /// - `small-caps` = `smcp`；`all-small-caps` = `smcp` + `c2sc`（大写字母也转小号大写）
  /// - `petite-caps` = `pcap`；`all-petite-caps` = `pcap` + `c2pc`
  /// - `unicase` = `unic`；`titling-caps` = `titl`；`normal` 不加特性
  static List<FontFeature>? _fontFeatures(CssFontVariantCaps caps) =>
      switch (caps) {
        CssFontVariantCaps.normal => null,
        CssFontVariantCaps.smallCaps => const <FontFeature>[
          FontFeature.enable('smcp'),
        ],
        CssFontVariantCaps.allSmallCaps => const <FontFeature>[
          FontFeature.enable('smcp'),
          FontFeature.enable('c2sc'),
        ],
        CssFontVariantCaps.petiteCaps => const <FontFeature>[
          FontFeature.enable('pcap'),
        ],
        CssFontVariantCaps.allPetiteCaps => const <FontFeature>[
          FontFeature.enable('pcap'),
          FontFeature.enable('c2pc'),
        ],
        CssFontVariantCaps.unicase => const <FontFeature>[
          FontFeature.enable('unic'),
        ],
        CssFontVariantCaps.titlingCaps => const <FontFeature>[
          FontFeature.enable('titl'),
        ],
      };

  static TextStyle textStyleFor(
    ComputedStyle style, {
    TextLeadingDistribution leadingDistribution = TextLeadingDistribution.even,
  }) => TextStyle(
    fontSize: style.fontSize,
    height: style.lineHeightFactor,
    leadingDistribution: leadingDistribution,
    // 小型大写（`font-variant-caps`）：CSS 的 caps 族映射到 OpenType 特性，
    // 测量与绘制共用本方法，因此宽度与字形两端一致；字体缺特性时不生效。
    fontFeatures: _fontFeatures(style.fontVariantCaps),
    fontWeight: _fontWeight(style.fontWeight),
    fontStyle: style.italic ? FontStyle.italic : FontStyle.normal,
    // 别名映射（P3-03）：宋体/黑体/楷体等中文族名与 serif/sans-serif
    // 泛型映射到内置规范名；未命中原样保留（显式回退引擎处理）。
    fontFamily: style.fontFamily == null
        ? null
        : FontFamilyAliases.mapFamilies([style.fontFamily!]).single,
    // 回退链（P3-04，§68.4）：声明族之后追加默认 CJK 链，缺字由引擎
    // 按序兜底（运行期不做逐字覆盖检测，§28.4）。
    fontFamilyFallback: _fallbackChain(style),
    letterSpacing: style.letterSpacing,
    wordSpacing: style.wordSpacing,
    decoration: _decoration(style.textDecoration),
    // 装饰线颜色/线型（P9-18）：书籍常用彩色下划线标重点。
    decorationColor: style.textDecorationColor ?? style.color,
    decorationStyle: _decorationStyle(style.textDecorationStyle),
    shadows: style.textShadow.isEmpty
        ? null
        : [
            for (final shadow in style.textShadow)
              Shadow(
                color: shadow.color ?? style.color,
                offset: Offset(shadow.offsetX, shadow.offsetY),
                blurRadius: shadow.blur,
              ),
          ],
    color: style.color,
  );

  static TextDecorationStyle _decorationStyle(
    CssTextDecorationStyle value,
  ) => switch (value) {
    CssTextDecorationStyle.solid => TextDecorationStyle.solid,
    CssTextDecorationStyle.double => TextDecorationStyle.double,
    CssTextDecorationStyle.dotted => TextDecorationStyle.dotted,
    CssTextDecorationStyle.dashed => TextDecorationStyle.dashed,
    CssTextDecorationStyle.wavy => TextDecorationStyle.wavy,
  };

  static TextDecoration _decoration(CssTextDecoration value) => switch (value) {
    CssTextDecoration.none => TextDecoration.none,
    CssTextDecoration.underline => TextDecoration.underline,
    CssTextDecoration.lineThrough => TextDecoration.lineThrough,
    CssTextDecoration.overline => TextDecoration.overline,
  };

  /// 回退链（P3-04）：声明的 fallback 经别名映射后，追加默认 CJK 链
  /// （去重，且不与主族重复）。声明链为空时返回默认链。
  ///
  /// 主族是黑体时改追加 [FontFamilyAliases.sansChain]，避免内置宋体
  /// 把黑体书整本替换成宋体（P9-05）。
  static List<String>? _fallbackChain(ComputedStyle style) {
    final chain = FontFamilyAliases.mapFamilies(style.fontFamilyFallback);
    final primary = style.fontFamily == null
        ? null
        : FontFamilyAliases.mapFamilies([style.fontFamily!]).single;
    final fallbacks = primary == FontFamilyAliases.hei
        ? FontFamilyAliases.sansChain
        : FontFamilyAliases.defaultChain;
    for (final family in fallbacks) {
      if (family != primary && !chain.contains(family)) {
        chain.add(family);
      }
    }
    return chain.isEmpty ? null : chain;
  }

  static FontWeight _fontWeight(int weight) {
    final index = ((weight / 100).round() - 1).clamp(0, 8);
    return FontWeight.values[index];
  }
}
