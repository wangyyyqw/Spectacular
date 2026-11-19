import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter/widgets.dart' show StringCharacters;

import '../css/computed_style.dart';
import '../css/font_face.dart';
import '../css/font_face_selection.dart';
import '../src/api/models.dart' show TextLayout;
import 'cjk_justify.dart';
import 'autospace.dart';
import 'hyphenation.dart';
import 'punct_trim.dart';
import 'punctuation_spacing.dart';
import 'spaced_paragraph.dart';
import 'text_spacing.dart';
import '../text/font_metrics.dart';
import '../text/font_coverage.dart';
import '../text/script.dart';
import '../text/script_fallback.dart';
import '../text/text_offsets.dart';

export 'text_spacing.dart' show LineSpacing, GlyphSpacing, textSpacingRevision;

/// CSS `hyphens: auto` 在行尾补画的连字符。
///
/// Chromium 使用 U+2010，而非 ASCII `-`；两者在内置宋体中的 advance
/// 明显不同，测量与绘制必须使用同一字形。
const String cssAutoHyphen = '\u2010';

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
    this.spacing,
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

  /// 测量时确定的字簇占宽与可拉伸间隙；绘制、命中不再各自推算。
  final LineSpacing? spacing;

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

  /// 复制并更新标志；行顶搬移时基线同步搬移，保持行内基线位置。
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
    LineSpacing? spacing,
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
    baseline: baseline + ((top ?? this.top) - this.top),
    width: width ?? this.width,
    indent: indent ?? this.indent,
    isLastLine: isLastLine ?? this.isLastLine,
    isHardBreak: isHardBreak ?? this.isHardBreak,
    offsetX: offsetX ?? this.offsetX,
    justifyExtra: justifyExtra ?? this.justifyExtra,
    justifyMode: justifyMode ?? this.justifyMode,
    spacing: spacing ?? this.spacing,
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
  bool get changed => offsets.last != text.length || hyphenPoints.isNotEmpty;

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
    this.style,
  });

  /// 起始偏移（UTF-16，含，块文本坐标系）。
  final int start;

  /// 结束偏移（半开）。
  final int end;

  /// 注音文本。
  final String text;

  /// 作者 rt 的最终样式；旧的直接构造入口仍沿用基字半号默认值。
  final ComputedStyle? style;
}

/// 行内盒的竖直对齐（CSS `vertical-align` 的行内块子集）。
enum InlineBoxVerticalAlign {
  /// 盒底 margin 边对齐基线（CSS 默认）。
  baseline,

  /// 盒竖直中点对齐父基线上方半个 x 高度。
  middle,

  /// 盒顶对齐行盒顶。
  top,

  /// 盒底对齐行盒底。
  bottom,
}

/// 普通行内盒的首尾占宽，绘制时由对应文字片段消费其装饰。
enum InlineSpacingEdge { leading, trailing }

/// 行内盒规格（`display: inline-block` 与行内替换图的布局侧输入）。
///
/// 章节源把 inline-block 元素描述成「在文本 [offset] 处插入 `width × height`
/// 的盒」；排版器在该处预留宽度（放不下整块换行），并按 [verticalAlign] 与
/// [marginTop]/[marginBottom] 参与行高与基线计算；图片可复用原文占位符。
class InlineBoxSpec {
  /// 创建规格。
  const InlineBoxSpec({
    required this.offset,
    required this.width,
    required this.height,
    this.verticalAlign = InlineBoxVerticalAlign.baseline,
    this.marginTop = 0,
    this.marginBottom = 0,
    this.marginLeft = 0,
    this.marginRight = 0,
    this.baselineOffset = 0,
    this.contentHeight,
    this.contentBaseline,
    this.replacesPlaceholder = false,
    this.payload,
  });

  /// 插入点（原文偏移；盒排在该偏移之前）。
  final int offset;

  /// 替换原文该处的 U+FFFC，而非额外插入字符；保留图片的原文/CFI 偏移。
  final bool replacesPlaceholder;

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

  /// 左右外边距参与换行，占位与实际边框盒分开保存。
  final double marginLeft;
  final double marginRight;

  double get outerWidth => math.max(0, width + marginLeft + marginRight);

  /// 基线模式下的额外位移（正数向上抬）。
  final double baselineOffset;

  /// 盒内内容的排版高（`display:inline-block` 子内容溢出的高度，可空）。
  ///
  /// 未提供 [contentBaseline] 时用于近似溢出延伸；提供实测基线后以 margin
  /// 盒与文字 strut 合成行高，不把溢出内容当作盒尺寸。
  final double? contentHeight;

  /// 盒内**最后一行的基线**相对盒边框盒顶的距离（`overflow: visible` 的
  /// inline-block 基线，CSS 2.2 §10.8.1）；无行或非 visible 时取底部 margin
  /// 边缘。为空时退回按字体内边距近似。
  final double? contentBaseline;

  /// 绘制层用的引用（片段、样式等由上层决定）。
  final Object? payload;

  /// 盒总高（含上下 margin）。
  double get outerHeight => height + marginTop + marginBottom;

  /// 复用尺寸与载荷，仅移动原文插入点（段落摘取或绕排重测时使用）。
  InlineBoxSpec atOffset(int offset) => InlineBoxSpec(
    offset: offset,
    width: width,
    height: height,
    verticalAlign: verticalAlign,
    marginTop: marginTop,
    marginBottom: marginBottom,
    marginLeft: marginLeft,
    marginRight: marginRight,
    baselineOffset: baselineOffset,
    contentHeight: contentHeight,
    contentBaseline: contentBaseline,
    replacesPlaceholder: replacesPlaceholder,
    payload: payload,
  );

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
    this.combine = false,
  });

  /// 原文起始偏移。
  final int start;

  /// 原文结束偏移（不含）。
  final int end;

  /// 列内纵向 advance（upright 时 = 1em，mixed 旋转时 = 字形宽）。
  final double advance;

  /// 是否正立（`text-orientation: upright` 或 CJK 类字形）；false 表示旋转 90°。
  final bool upright;

  /// 是否为縦中横组合（`text-combine-upright: all` 的 2–4 位数字）：
  /// 纵向只占 1em，绘制时横排缩小塞进列宽。
  final bool combine;
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

  /// 基线以下延伸（含 margin）；实际基线在盒底之外时可为负。
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

/// 同一原文边界共用占位符，首行和续行分别使用各自级联后的留白。
class _FirstLineSpacingBoxSpec extends InlineBoxSpec {
  const _FirstLineSpacingBoxSpec({
    required super.offset,
    required super.width,
    required this.firstLineWidth,
    required InlineSpacingEdge edge,
  }) : super(height: 0, payload: edge);

  final double firstLineWidth;

  InlineBoxSpec get forFirstLine => InlineBoxSpec(
    offset: offset,
    width: firstLineWidth,
    height: 0,
    payload: payload,
  );

  @override
  _FirstLineSpacingBoxSpec atOffset(int offset) => _FirstLineSpacingBoxSpec(
    offset: offset,
    width: width,
    firstLineWidth: firstLineWidth,
    edge: payload! as InlineSpacingEdge,
  );
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

typedef _PaddedSegment = ({
  String text,
  double width,
  ComputedStyle style,
  double scale,
  TextLeadingDistribution leading,
  List<StyledRun> runs,
  List<_InlineBoxMark> marks,
  Set<int> barriers,
  bool firstLine,
  bool firstLineOnly,
});

class StyledRun {
  /// 创建区间。
  const StyledRun({
    required this.start,
    required this.end,
    required this.style,
    this.baselineShift = 0,
    this.syntheticFontFallback = false,
    this.inlineLeadingInset,
    this.inlineTrailingInset,
    this.inlinePadding = EdgeInsets.zero,
  });

  /// 起始偏移（UTF-16，含）。
  final int start;

  /// 结束偏移（UTF-16，不含）。
  final int end;

  /// 该区间的计算样式。
  final ComputedStyle style;

  /// 行内基线偏移（逻辑像素，正值向下）：上下标用，0 表示不偏移。
  final double baselineShift;

  /// 是否为字体回退从正文样式合成的纯文本区间。
  ///
  /// 这类区间没有对应的行内元素，不能据此重复绘制块的背景、边框或内边距。
  final bool syntheticFontFallback;

  /// 原行内元素在此片段首尾的水平占宽；null 兼容直接使用自身样式的调用。
  /// 嵌套元素可在同一边界累加，拆分片段未触及原边界时为零。
  final double? inlineLeadingInset;
  final double? inlineTrailingInset;
  final EdgeInsets inlinePadding;

  double get leadingInset =>
      inlineLeadingInset ??
      style.padding.left +
          (style.borders.left.isVisible ? style.borders.left.width : 0);
  double get trailingInset =>
      inlineTrailingInset ??
      style.padding.right +
          (style.borders.right.isVisible ? style.borders.right.width : 0);
}

/// 按制表位展开制表符（CSS Text 3 `tab-size`）：每遇到 `\t` 补齐到下一个
/// `tabSize` 列，换行后列计数归零。
///
/// 传入 [measureWidth] 与 [spaceWidth] 时按实际字形宽度计算制表位，避免把
/// 比例字体的制表符错误地当成 `tabSize` 个固定空格。
String expandTabs(
  String text,
  int tabSize, {
  double Function(String prefix)? measureWidth,
  double? spaceWidth,
  TextOffsetMapBuilder? offsets,
}) {
  if (tabSize <= 0 || !text.contains('\t')) {
    return text;
  }
  final buffer = StringBuffer();
  final line = StringBuffer();
  var column = 0;
  final measuredTabs =
      measureWidth != null && spaceWidth != null && spaceWidth > 0;
  final tabStopWidth = measuredTabs ? tabSize * spaceWidth : 0.0;
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    if (char == '\t') {
      int spaces;
      if (measuredTabs) {
        final currentWidth = measureWidth(line.toString());
        final nextStop =
            (currentWidth / tabStopWidth + 1e-9).floor() * tabStopWidth +
            tabStopWidth;
        spaces = math.max(1, ((nextStop - currentWidth) / spaceWidth).round());
      } else {
        spaces = tabSize - (column % tabSize);
      }
      buffer.write(' ' * spaces);
      line.write(' ' * spaces);
      column += spaces;
      offsets?.add(char.length, spaces);
    } else if (char == '\n') {
      buffer.write(char);
      line.clear();
      column = 0;
      offsets?.add(char.length, char.length);
    } else {
      buffer.write(char);
      line.write(char);
      column += 1;
      offsets?.add(char.length, char.length);
    }
  }
  return buffer.toString();
}

/// 按 CSS `text-transform` 变换文本（P2-16）。
///
/// `capitalize` 按空白分词，把每个词的首字符转大写（标点边界按空白近似）。
String applyTextTransform(
  String text,
  CssTextTransform transform, {
  TextOffsetMapBuilder? offsets,
}) {
  if (transform == CssTextTransform.none) return text;
  final buffer = StringBuffer();
  var atWordStart = true;
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    final transformed = switch (transform) {
      CssTextTransform.uppercase => char.toUpperCase(),
      CssTextTransform.lowercase => char.toLowerCase(),
      CssTextTransform.capitalize => atWordStart ? char.toUpperCase() : char,
      CssTextTransform.none => char,
    };
    buffer.write(transformed);
    offsets?.add(char.length, transformed.length);
    atWordStart = char.trim().isEmpty;
  }
  return buffer.toString();
}

/// 样式范围沿用同次文字变换的边界，字体分段仍在显示文字上执行。
List<StyledRun> remapStyledRuns(List<StyledRun> runs, TextOffsetMap? offsets) {
  if (offsets == null || runs.isEmpty) return runs;
  return [
    for (final run in runs)
      StyledRun(
        start: offsets.at(run.start),
        end: offsets.at(run.end),
        style: run.style,
        baselineShift: run.baselineShift,
        syntheticFontFallback: run.syntheticFontFallback,
        inlineLeadingInset: run.inlineLeadingInset,
        inlineTrailingInset: run.inlineTrailingInset,
        inlinePadding: run.inlinePadding,
      ),
  ];
}

/// 内置宋体是否需要用合成小型大写。
///
/// 字体没有 `smcp/c2sc` 特性，Chromium 会选用大写字形并按 70% 字号合成；
/// 其它字体暂时仍交给 OpenType 特性处理，避免覆盖真正的小型大写设计。
bool usesSyntheticSmallCaps(ComputedStyle style) {
  if (style.fontVariantCaps != CssFontVariantCaps.smallCaps &&
      style.fontVariantCaps != CssFontVariantCaps.allSmallCaps) {
    return false;
  }
  final family = style.fontFamily;
  if (family == null) {
    return false;
  }
  // `builtin_song` 是别名表的目标规范名，不是可再映射的输入别名；
  // 直接比较它，否则内置宋体会漏掉 Chromium 同款的小型大写合成。
  return family.trim().toLowerCase() == FontFamilyAliases.song ||
      FontFamilyAliases.resolve(family) == FontFamilyAliases.song;
}

/// 从测量/绘制共用的 TextStyle 还原需要合成的小型大写类别。
CssFontVariantCaps? syntheticSmallCapsFromTextStyle(TextStyle style) {
  if (style.fontFamily != FontFamilyAliases.song) {
    return null;
  }
  final tags = style.fontFeatures?.map((feature) => feature.feature).toSet();
  if (tags?.contains('c2sc') ?? false) {
    return CssFontVariantCaps.allSmallCaps;
  }
  if (tags?.contains('smcp') ?? false) {
    return CssFontVariantCaps.smallCaps;
  }
  return null;
}

/// 按 CSS 小型大写规则生成测量/绘制共用的 span。
///
/// 只合成 ASCII 拉丁字母；连续同字号的字符会合并，避免逐字符破坏字距。
///
/// Chromium 把合成字号四舍五入到整数 CSS 像素（18px → 13px、22px → 15px）；
/// `all-small-caps` 还会把空格、标点和 CJK 等非拉丁字母一并缩小。
const syntheticSmallCapsScale = 0.7;

InlineSpan buildSyntheticSmallCapsSpan({
  required String text,
  required TextStyle style,
  required CssFontVariantCaps caps,
}) {
  final all = caps == CssFontVariantCaps.allSmallCaps;
  final baseFontSize = style.fontSize ?? 0;
  final smallFontSize = (baseFontSize * syntheticSmallCapsScale)
      .roundToDouble();
  final children = <InlineSpan>[];
  final buffer = StringBuffer();
  double? openSize;

  void flush() {
    final content = buffer.toString();
    final size = openSize;
    if (content.isEmpty || size == null) {
      return;
    }
    final features = style.fontFeatures
        ?.where(
          (feature) => feature.feature != 'smcp' && feature.feature != 'c2sc',
        )
        .toList(growable: false);
    children.add(
      TextSpan(
        text: content,
        style: style.copyWith(fontSize: size, fontFeatures: features),
      ),
    );
    buffer.clear();
  }

  for (final rune in text.runes) {
    final source = String.fromCharCode(rune);
    final upper = source.toUpperCase();
    final isUpper = rune >= 0x41 && rune <= 0x5A;
    final isLower = rune >= 0x61 && rune <= 0x7A;
    final isLetter = isUpper || isLower;
    final size = all || isLower ? smallFontSize : (style.fontSize ?? 0.0);
    if (openSize != null && size != openSize) {
      flush();
    }
    openSize = size;
    buffer.write(isLetter ? upper : source);
  }
  flush();
  return TextSpan(style: style, children: children);
}

/// 对 styled runs 构建出的 span 树应用合成小型大写。
InlineSpan applySyntheticSmallCaps(
  InlineSpan span, {
  TextStyle? inheritedStyle,
}) {
  final textSpan = span as TextSpan;
  final style = textSpan.style ?? inheritedStyle;
  final caps = style == null ? null : syntheticSmallCapsFromTextStyle(style);
  final children = textSpan.children;
  final transformedText = caps != null && textSpan.text != null && style != null
      ? buildSyntheticSmallCapsSpan(
          text: textSpan.text!,
          style: style,
          caps: caps,
        ) as TextSpan
      : null;
  if (children == null || children.isEmpty) {
    return transformedText ?? textSpan;
  }
  final transformedChildren = <InlineSpan>[
    for (final child in children)
      child is TextSpan
          ? applySyntheticSmallCaps(child, inheritedStyle: style)
          : child,
  ];
  return TextSpan(
    text: textSpan.text,
    style: textSpan.style,
    children: [
      if (transformedText case final TextSpan capsSpan) ...?capsSpan.children,
      ...transformedChildren,
    ],
    recognizer: textSpan.recognizer,
    semanticsLabel: textSpan.semanticsLabel,
    semanticsIdentifier: textSpan.semanticsIdentifier,
  );
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
    this.plainTextLayout = false,
    this.firstLineStyle,
    this.firstLineRuns,
    this.sourceRuns,
    this.inputOffsets,
  });

  /// 测量及绘制使用的显示文字。
  final String text;

  /// 输入文字到 [text] 的边界；恒等变换为 null。
  final TextOffsetMap? inputOffsets;

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

  /// 首行断行前的级联输入；变宽重排时重新确定首行范围。
  final ComputedStyle? firstLineStyle;
  final List<StyledRun>? firstLineRuns;
  final List<StyledRun>? sourceRuns;

  List<StyledRun> get inputRuns => sourceRuns ?? runs;

  /// 段落方向是否为 RTL（绘制/命中需用同一 baseDirection，否则字形顺序错位）。
  final bool isRtl;

  /// 书写模式（竖排块的行列表其实是「列」表，见 [LineBox.vertical]）。
  final CssWritingMode writingMode;

  /// 现有 runs 是否与块级测量样式等价（只允许颜色/装饰等排版无关差异）。
  ///
  /// 为 true 时，旧的间距兼容路径仍可按纯文本测量；带 spacing 的行直接
  /// 使用实际 run 的间距结果，绘制端继续保留作者颜色与装饰。
  final bool plainTextLayout;

  /// 是否竖排。
  bool get isVertical => writingMode != CssWritingMode.horizontalTb;

  /// 复用同一份几何，仅替换本次调用的行内绘制 runs。
  ///
  /// 段落缓存键只包含影响度量的 run 指纹，颜色、背景和装饰不在键内；
  /// 命中后必须重新绑定当前 runs，不能把首段绘制样式带给后续段落。
  /// 首行输入也必须完整传入；显式 null 清除旧值，不表示保留缓存输入。
  TextLayoutResult withRuns(
    List<StyledRun> currentRuns, {
    required ComputedStyle? firstLineStyle,
    required List<StyledRun>? firstLineRuns,
    required List<StyledRun>? sourceRuns,
  }) {
    var same =
        currentRuns.length == runs.length &&
        identical(firstLineStyle, this.firstLineStyle) &&
        identical(firstLineRuns, this.firstLineRuns) &&
        identical(sourceRuns, this.sourceRuns);
    if (same) {
      for (var i = 0; i < runs.length; i++) {
        final current = currentRuns[i];
        final cached = runs[i];
        if (current.start != cached.start ||
            current.end != cached.end ||
            current.baselineShift != cached.baselineShift ||
            current.syntheticFontFallback != cached.syntheticFontFallback ||
            current.inlineLeadingInset != cached.inlineLeadingInset ||
            current.inlineTrailingInset != cached.inlineTrailingInset ||
            current.inlinePadding != cached.inlinePadding ||
            !identical(current.style, cached.style)) {
          same = false;
          break;
        }
      }
    }
    if (same) return this;
    return TextLayoutResult(
      text: text,
      lines: lines,
      width: width,
      height: height,
      maxWidth: maxWidth,
      runs: List<StyledRun>.unmodifiable(currentRuns),
      isRtl: isRtl,
      writingMode: writingMode,
      plainTextLayout: plainTextLayout,
      firstLineStyle: firstLineStyle,
      firstLineRuns: firstLineRuns,
      sourceRuns: sourceRuns,
      inputOffsets: inputOffsets,
    );
  }

  /// 载荷摘取与测量变换合并为同一输入坐标，几何和字体分段保持原样。
  TextLayoutResult withInputOffsets(TextOffsetMap? offsets) {
    if (identical(offsets, inputOffsets)) return this;
    return TextLayoutResult(
      text: text,
      lines: lines,
      width: width,
      height: height,
      maxWidth: maxWidth,
      runs: runs,
      isRtl: isRtl,
      writingMode: writingMode,
      plainTextLayout: plainTextLayout,
      firstLineStyle: firstLineStyle,
      firstLineRuns: firstLineRuns,
      sourceRuns: sourceRuns,
      inputOffsets: offsets,
    );
  }

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
/// 行内块按自身内容宽排版，不把短标签撑成正文宽度。
class LineBreaker {
  /// 创建断行器。
  LineBreaker({this.onWarning, this.minimumWidthEm = 3.0})
    : assert(minimumWidthEm >= 0);

  /// 告警回调，只在首次钳制时调用。
  final LineBreakWarningCallback? onWarning;

  /// 宽度下限，单位为 em；已求解的内在容器内容使用 0 保留真实窄宽。
  final double minimumWidthEm;

  /// 是否按 CSS 像素解算行盒高（实验开关，默认关闭）。
  ///
  /// Skia 把行盒高四舍五入到整数（`line-height: 22.5px` → 23、
  /// `1.6 × 17px = 27.2` → 27），但 ascent 仍按小数行高算，因此基线是
  /// 对的、只有行盒高度被取整。打开后显式行高改用
  /// `ComputedStyle.lineHeight`（小数）；`normal` 则像 Chrome 一样分别把
  /// 字体 ascent/descent 取整后相加。基线不变；影响面是所有依赖行盒高的
  /// 分页/单元格高度。
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

  /// 返回实际宽度；无作者宽度的正文低于下限时钳制并记录一次告警。
  double effectiveWidth(ComputedStyle style, double requestedWidth) {
    if (style.display == CssDisplay.inlineBlock ||
        style.hasIntrinsicWidth ||
        (style.width != null && !style.width!.isAuto)) {
      return requestedWidth;
    }
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
  /// 无作者宽度的正文低于 3em 时钳制；行内块和作者声明宽度保留请求宽。
  /// `nowrap`/`pre` 不软换行（测量时按无限宽排一行），但 `maxWidth` 仍记录
  /// 有限的内容宽，供对齐与诊断使用。
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
    List<RubyAnnotation> rubies = const <RubyAnnotation>[],
    ComputedStyle? firstLineStyle,
    List<StyledRun>? firstLineRuns,
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
      rubies: rubies,
      softWrap: softWrap,
      firstLineStyle: firstLineStyle,
      firstLineRuns: firstLineRuns,
    );
  }

  /// 分批驱动同一断行算法；检查点异常会中止并释放本次原生测量资源。
  Future<TextLayoutResult> layoutAsync({
    required String text,
    required ComputedStyle style,
    required double maxWidth,
    double textScaleFactor = 1,
    TextLeadingDistribution leadingDistribution = TextLeadingDistribution.even,
    List<StyledRun> runs = const <StyledRun>[],
    bool Function(String family, int codeUnit)? hasGlyph,
    List<InlineBoxSpec> inlineBoxes = const <InlineBoxSpec>[],
    List<RubyAnnotation> rubies = const <RubyAnnotation>[],
    Future<void> Function()? checkpoint,
    ComputedStyle? firstLineStyle,
    List<StyledRun>? firstLineRuns,
  }) {
    final softWrap =
        style.whiteSpace != CssWhiteSpace.nowrap &&
        style.whiteSpace != CssWhiteSpace.pre;
    return TextLayoutEngine._layoutRawAsync(
      text: text,
      style: style,
      maxWidth: effectiveWidth(style, maxWidth),
      textScaleFactor: textScaleFactor,
      leadingDistribution: leadingDistribution,
      runs: runs,
      hasGlyph: hasGlyph,
      inlineBoxes: inlineBoxes,
      rubies: rubies,
      softWrap: softWrap,
      checkpoint: checkpoint,
      firstLineStyle: firstLineStyle,
      firstLineRuns: firstLineRuns,
    );
  }
}

/// 用 TextPainter 做行测量。
/// 首行缩进探测的初始字符窗口；不足时按需倍增到全文。
const int _indentProbeChars = 32;

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
    List<RubyAnnotation> rubies = const <RubyAnnotation>[],
    ComputedStyle? firstLineStyle,
    List<StyledRun>? firstLineRuns,
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
      rubies: rubies,
      firstLineStyle: firstLineStyle,
      firstLineRuns: firstLineRuns,
    );
  }

  /// 可取消的文字测量入口；TextPainter 仍在当前 Flutter 主 isolate 执行。
  ///
  /// 同步/异步仅驱动方式不同，字体、标点、行内盒与原文下标共用同一算法。
  static Future<TextLayoutResult> layoutAsync({
    required String text,
    required ComputedStyle style,
    required double maxWidth,
    double textScaleFactor = 1,
    TextLeadingDistribution leadingDistribution = TextLeadingDistribution.even,
    LineBreaker? lineBreaker,
    List<StyledRun> runs = const <StyledRun>[],
    bool Function(String family, int codeUnit)? hasGlyph,
    List<InlineBoxSpec> inlineBoxes = const <InlineBoxSpec>[],
    List<RubyAnnotation> rubies = const <RubyAnnotation>[],
    Future<void> Function()? checkpoint,
    ComputedStyle? firstLineStyle,
    List<StyledRun>? firstLineRuns,
  }) => (lineBreaker ?? LineBreaker()).layoutAsync(
    text: text,
    style: style,
    maxWidth: maxWidth,
    textScaleFactor: textScaleFactor,
    leadingDistribution: leadingDistribution,
    runs: runs,
    hasGlyph: hasGlyph,
    inlineBoxes: inlineBoxes,
    rubies: rubies,
    checkpoint: checkpoint,
    firstLineStyle: firstLineStyle,
    firstLineRuns: firstLineRuns,
  );

  /// 计算绘制用 runs（含字形回退分段），不执行断行。
  ///
  /// 段落缓存命中后几何可以复用，但颜色、背景、装饰和当前字体的回退分段
  /// 必须按本次调用重新生成，不能沿用缓存首段的绘制信息。
  static List<StyledRun> styledRuns({
    required String text,
    required ComputedStyle style,
    List<StyledRun> runs = const <StyledRun>[],
    bool Function(String family, int codeUnit)? hasGlyph,
    TextLeadingDistribution leadingDistribution = TextLeadingDistribution.even,
    ComputedStyle? firstLineStyle,
    List<StyledRun>? firstLineRuns,
    int firstLineEnd = 0,
    bool transformText = true,
  }) {
    if (transformText) {
      final offsets = TextOffsetMapBuilder();
      text = applyTextTransform(text, style.textTransform, offsets: offsets);
      final mapping = offsets.build();
      runs = remapStyledRuns(runs, mapping);
      if (firstLineRuns != null) {
        firstLineRuns = remapStyledRuns(firstLineRuns, mapping);
      }
    }
    if (firstLineStyle != null && firstLineEnd > 0) {
      runs = _runsWithFirstLine(
        text.length,
        firstLineEnd,
        runs,
        firstLineRuns ?? inheritedFirstLineRuns(runs, firstLineStyle),
        firstLineStyle,
      );
    }
    final ordered = _applyVerticalAlign(
      _normalizeRuns(runs, text.length),
      style,
      leadingDistribution,
    );
    if (hasGlyph == null &&
        !style.hasBookFontFaces &&
        !ordered.any((run) => run.style.hasBookFontFaces)) {
      return ordered;
    }
    return _applyScriptFallback(
      text: text,
      runs: ordered,
      baseStyle: style,
      hasGlyph: (family, codePoint) => _covers(family, codePoint, hasGlyph),
    );
  }

  /// 横排文本的最小内容宽；复用正式排版的字体、软断点和字间距规则。
  /// 探测不会生成分页结果，原生测量前后与每批断点都检查取消预算。
  static Future<double> minContentTextWidthAsync({
    required String text,
    required ComputedStyle style,
    List<StyledRun> runs = const [],
    bool Function(String family, int codeUnit)? hasGlyph,
    Future<void> Function()? checkpoint,
  }) async {
    final work = _TextLayoutWork<double>();
    try {
      await checkpoint?.call();
      for (final _ in _minContentWidthSteps(work, text, style, (
        runs: runs,
        hasGlyph: hasGlyph,
      ))) {
        await checkpoint?.call();
      }
      return work.result!;
    } finally {
      work.painters.dispose();
    }
  }

  static Iterable<bool> _minContentWidthSteps(
    _TextLayoutWork<double> work,
    String text,
    ComputedStyle style,
    ({List<StyledRun> runs, bool Function(String, int)? hasGlyph}) context,
  ) sync* {
    final prepared = _measurementText(text, style, (
      tabs: context.runs.isEmpty,
      scale: 1,
      leading: TextLeadingDistribution.even,
    ));
    text = prepared.text;
    final styled = styledRuns(
      text: text,
      style: style,
      runs: remapStyledRuns(context.runs, prepared.offsets),
      hasGlyph: context.hasGlyph,
      transformText: false,
    );
    final breaks = _TextLayoutWork<SoftBreakPlan>(work.painters);
    yield* _intrinsicBreakSteps(breaks, text, style);
    final plan = breaks.result!;
    final span = _intrinsicSpan(
      plan.text,
      style,
      _measurementRuns(styled, plan.offsets),
    );
    yield* _measureIntrinsicWidthSteps(work, span, plan.text, style);
  }

  static Iterable<bool> _intrinsicBreakSteps(
    _TextLayoutWork<SoftBreakPlan> work,
    String text,
    ComputedStyle style,
  ) sync* {
    final soft = _TextLayoutWork<SoftBreakPlan>(work.painters);
    yield* _softBreakSteps(
      soft,
      text: text,
      hyphens: style.hyphens,
      overflowWrap: style.overflowWrap,
      wordBreak: style.wordBreak,
      contentWidth: double.infinity,
      style: style,
      textScaleFactor: 1,
      hyphenAdvance: 0,
    );
    if (_intrinsicNoWrap(style)) {
      work.result = soft.result;
      return;
    }
    yield* _intrinsicHardBreakSteps(work, soft.result!, style);
  }

  static Iterable<bool> _measureIntrinsicWidthSteps(
    _TextLayoutWork<double> work,
    TextSpan span,
    String text,
    ComputedStyle style,
  ) sync* {
    final noWrap = _intrinsicNoWrap(style);
    final firstEnd = style.textIndent == 0
        ? 0
        : _firstIntrinsicSegmentEnd(text, noWrap);
    final painter = work.painters.own(
      TextPainter(
        text: firstEnd == 0 ? span : sliceTextSpan(span, firstEnd, text.length),
        textDirection: _textDirectionOf(style),
      ),
    )..layout();
    yield false;
    var width = noWrap ? painter.maxIntrinsicWidth : painter.minIntrinsicWidth;
    if (firstEnd > 0) {
      width = math.max(
        width,
        _measureTextSpan(sliceTextSpan(span, 0, firstEnd), 1) +
            style.textIndent,
      );
      yield false;
    }
    if (!noWrap && !_allowsIntrinsicBreakAnywhere(style)) {
      for (final range in _guardedTokenRanges(text)) {
        width = math.max(
          width,
          _measureTextSpan(sliceTextSpan(span, range.$1, range.$2), 1) +
              (range.$1 == 0 ? style.textIndent : 0),
        );
        yield false;
      }
    }
    work.result = width;
  }

  static int _firstIntrinsicSegmentEnd(String text, bool noWrap) {
    if (!noWrap) {
      final guarded = _guardedTokenRanges(text).firstOrNull;
      if (guarded?.$1 == 0) return guarded!.$2;
    }
    for (var index = 0; index < text.length; index++) {
      final code = text.codeUnitAt(index);
      if (code == 0x0A || code == 0x0D) return index;
      if (!noWrap && _isHorizontalSpace(code)) return index;
      if (!noWrap && code == 0x2D) return index + 1;
    }
    return text.length;
  }

  static bool _intrinsicNoWrap(ComputedStyle style) =>
      style.whiteSpace == CssWhiteSpace.nowrap ||
      style.whiteSpace == CssWhiteSpace.pre;

  /// 原生无界测量会漏算 CJK/ZWSP 断点。仅在测量副本中强制已有合法断点，
  /// 合并一次原生测量；按字簇遍历并保留映射，不改原文、正式断行或 CFI。
  static Iterable<bool> _intrinsicHardBreakSteps(
    _TextLayoutWork<SoftBreakPlan> work,
    SoftBreakPlan soft,
    ComputedStyle style,
  ) sync* {
    final text = StringBuffer();
    final offsets = <int>[0];
    var offset = 0;
    var previous = '';
    var checked = 0;
    for (final cluster in soft.text.characters) {
      if (_intrinsicBreakBetween(previous, cluster, style)) {
        text.write('\n');
        offsets.add(soft.originalOffset(offset));
      }
      if (cluster == '\u200B') {
        if (soft.isHyphenPoint(offset)) {
          text.write(cssAutoHyphen);
          offsets.add(soft.originalOffset(offset));
        }
        text.write('\n');
      } else {
        text.write(cluster);
      }
      for (var index = 1; index <= cluster.length; index++) {
        offsets.add(soft.originalOffset(offset + index));
      }
      offset += cluster.length;
      previous = cluster;
      if (++checked % 64 == 0) yield false;
    }
    work.result = SoftBreakPlan(
      text: text.toString(),
      offsets: offsets,
      hyphenPoints: const {},
    );
  }

  static bool _intrinsicBreakBetween(
    String previous,
    String next,
    ComputedStyle style,
  ) {
    if (previous.isEmpty ||
        previous.trim().isEmpty ||
        next.trim().isEmpty ||
        previous == '\u200B' ||
        next == '\u200B') {
      return false;
    }
    if (_allowsIntrinsicBreakAnywhere(style)) return true;
    if (style.wordBreak == CssWordBreak.keepAll ||
        previous == '\u2060' ||
        next == '\u2060' ||
        punctOpeningSet.contains(previous) ||
        punctLineStartProhibitedSet.contains(next)) {
      return false;
    }
    return isCjkCodePoint(previous.runes.last) ||
        isCjkCodePoint(next.runes.first);
  }

  static bool _allowsIntrinsicBreakAnywhere(ComputedStyle style) =>
      style.wordBreak == CssWordBreak.breakAll ||
      style.overflowWrap == CssOverflowWrap.anywhere ||
      style.lineBreak == CssLineBreak.anywhere;

  static ({String text, TextOffsetMap? offsets}) _measurementText(
    String text,
    ComputedStyle style,
    ({bool tabs, double scale, TextLeadingDistribution leading}) options,
  ) {
    final transformOffsets = TextOffsetMapBuilder();
    text = applyTextTransform(
      text,
      style.textTransform,
      offsets: transformOffsets,
    );
    final transformed = transformOffsets.build();
    if (!options.tabs || !text.contains('\t') || style.tabSize <= 0) {
      return (text: text, offsets: transformed);
    }
    final tabOffsets = TextOffsetMapBuilder();
    text = expandTabs(
      text,
      style.tabSize,
      measureWidth: (prefix) =>
          _measureTextWidth(prefix, style, options.scale, options.leading),
      spaceWidth: _measureChar(' ', style, options.scale),
      offsets: tabOffsets,
    );
    final tabs = tabOffsets.build();
    return (
      text: text,
      offsets: tabs == null ? transformed : transformed?.then(tabs) ?? tabs,
    );
  }

  static TextSpan _intrinsicSpan(
    String text,
    ComputedStyle style,
    List<StyledRun> runs,
  ) {
    final base = textStyleFor(style);
    final span = _measurementSpan(text, runs, base, const [], (
      css: style,
      scale: 1,
      leading: TextLeadingDistribution.even,
    ));
    if (style.isRtl ||
        (style.whiteSpace != CssWhiteSpace.normal &&
            style.whiteSpace != CssWhiteSpace.nowrap)) {
      return span;
    }
    final spacing = _punctuationPlan(text, style, runs, (
      base: base,
      leading: TextLeadingDistribution.even,
      autospace:
          !_runsAffectTextLayout(runs, style) &&
          style.textAutospace == CssTextAutospace.normal,
    ), const {});
    return applyTextSpacing(
      span,
      spacing.range(0, text.length, trimTrailing: false),
    );
  }

  /// 批量测量纯文本片段的无界宽度。
  ///
  /// 表格最小内容宽会把中文逐字、拉丁词逐段测量；每个片段单独创建
  /// `TextPainter` 会让大表格产生数百次排版。这里把片段按硬换行合并为一次
  /// 排版，再用选区盒读取每行宽度。字体回退、文字变换和 textScaleFactor
  /// 与普通布局路径保持一致。
  static Map<String, double> measureTextWidths({
    required Iterable<String> texts,
    required ComputedStyle style,
    double textScaleFactor = 1,
    bool Function(String family, int codeUnit)? hasGlyph,
  }) {
    final originals = <String>[];
    final seen = <String>{};
    for (final text in texts) {
      if (text.isEmpty || !seen.add(text)) {
        continue;
      }
      originals.add(text);
    }
    if (originals.isEmpty) {
      return const <String, double>{};
    }
    if (style.writingMode != CssWritingMode.horizontalTb) {
      return <String, double>{
        for (final text in originals)
          text: layout(
            text: text,
            style: style,
            maxWidth: double.infinity,
            textScaleFactor: textScaleFactor,
            hasGlyph: hasGlyph,
          ).width,
      };
    }

    final measured = <String, String>{
      for (final text in originals)
        text: applyTextTransform(text, style.textTransform),
    };
    final joined = originals.map((text) => measured[text]!).join('\n');
    final baseStyle = textStyleFor(style);
    final styled = styledRuns(text: joined, style: style, hasGlyph: hasGlyph);
    final painter = TextPainter(
      text: _measurementSpan(
        joined,
        styled,
        baseStyle,
        const <_InlineBoxMark>[],
        (
          css: style,
          scale: textScaleFactor,
          leading: TextLeadingDistribution.even,
        ),
      ),
      textDirection: _textDirectionOf(style),
      textScaler: TextScaler.linear(textScaleFactor),
    )..layout();

    final result = <String, double>{};
    var offset = 0;
    for (final original in originals) {
      final end = offset + measured[original]!.length;
      final boxes = painter.getBoxesForSelection(
        TextSelection(baseOffset: offset, extentOffset: end),
      );
      result[original] = boxes.isEmpty
          ? 0
          : boxes.map((box) => box.right).reduce(math.max) -
                boxes.map((box) => box.left).reduce(math.min);
      offset = end + 1;
    }
    painter.dispose();
    return result;
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
    List<RubyAnnotation> rubies = const <RubyAnnotation>[],
    bool softWrap = true,
    ComputedStyle? firstLineStyle,
    List<StyledRun>? firstLineRuns,
  }) {
    final work = _TextLayoutWork<TextLayoutResult>();
    try {
      for (final _ in _layoutRawSteps(
        work,
        text: text,
        style: style,
        maxWidth: maxWidth,
        textScaleFactor: textScaleFactor,
        leadingDistribution: leadingDistribution,
        runs: runs,
        hasGlyph: hasGlyph,
        inlineBoxes: inlineBoxes,
        rubies: rubies,
        softWrap: softWrap,
        firstLineStyle: firstLineStyle,
        firstLineRuns: firstLineRuns,
      )) {}
      return work.result!;
    } finally {
      work.painters.dispose();
    }
  }

  static Future<TextLayoutResult> _layoutRawAsync({
    required String text,
    required ComputedStyle style,
    required double maxWidth,
    required double textScaleFactor,
    required TextLeadingDistribution leadingDistribution,
    List<StyledRun> runs = const <StyledRun>[],
    bool Function(String family, int codeUnit)? hasGlyph,
    List<InlineBoxSpec> inlineBoxes = const <InlineBoxSpec>[],
    List<RubyAnnotation> rubies = const <RubyAnnotation>[],
    bool softWrap = true,
    Future<void> Function()? checkpoint,
    ComputedStyle? firstLineStyle,
    List<StyledRun>? firstLineRuns,
  }) async {
    final work = _TextLayoutWork<TextLayoutResult>();
    try {
      if (checkpoint != null) await checkpoint();
      for (final _ in _layoutRawSteps(
        work,
        text: text,
        style: style,
        maxWidth: maxWidth,
        textScaleFactor: textScaleFactor,
        leadingDistribution: leadingDistribution,
        runs: runs,
        hasGlyph: hasGlyph,
        inlineBoxes: inlineBoxes,
        rubies: rubies,
        softWrap: softWrap,
        firstLineStyle: firstLineStyle,
        firstLineRuns: firstLineRuns,
      )) {
        if (checkpoint != null) await checkpoint();
      }
      if (checkpoint != null) await checkpoint();
      return work.result!;
    } finally {
      work.painters.dispose();
    }
  }

  static Iterable<bool> _layoutRawSteps(
    _TextLayoutWork<TextLayoutResult> work, {
    required String text,
    required ComputedStyle style,
    required double maxWidth,
    required double textScaleFactor,
    required TextLeadingDistribution leadingDistribution,
    List<StyledRun> runs = const <StyledRun>[],
    bool Function(String family, int codeUnit)? hasGlyph,
    List<InlineBoxSpec> inlineBoxes = const <InlineBoxSpec>[],
    List<RubyAnnotation> rubies = const <RubyAnnotation>[],
    bool softWrap = true,
    ComputedStyle? firstLineStyle,
    List<StyledRun>? firstLineRuns,
  }) sync* {
    // tab-size（CSS Text 3）：`white-space: pre*` 里的制表符按制表位展开成
    // 空格。展开会改变字符下标，因此只在「纯文本段」（无行内样式区间/行内盒）
    // 做；带行内标记的 pre 文本保留原样（已知限制）。
    final prepared = _measurementText(text, style, (
      tabs: runs.isEmpty && inlineBoxes.isEmpty,
      scale: textScaleFactor,
      leading: leadingDistribution,
    ));
    text = prepared.text;
    final inputOffsets = prepared.offsets;
    runs = remapStyledRuns(runs, inputOffsets);
    if (firstLineRuns != null) {
      firstLineRuns = remapStyledRuns(firstLineRuns, inputOffsets);
    }
    if (inputOffsets != null) {
      inlineBoxes = [
        for (final box in inlineBoxes)
          box.atOffset(inputOffsets.at(box.offset)),
      ];
      rubies = [
        for (final ruby in rubies)
          RubyAnnotation(
            start: inputOffsets.at(ruby.start),
            end: inputOffsets.at(ruby.end),
            text: ruby.text,
            style: ruby.style,
          ),
      ];
    }
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
    // 竖排的内联轴是纵向，可用尺寸必须取列长；块宽只决定列带宽度。
    final inlineWidth = vertical ? columnLength : width;
    final verticalMeasureWidth = softWrap ? columnLength : double.infinity;
    // 负 text-indent 是合法的「首行外凸」（CSS Text 3 §3.1）：首行可用宽
    // 变宽（width - indent > width）、行左缘画到内容盒左侧，不能钳成 0。
    final indent = softWrap && inlineWidth.isFinite
        ? style.textIndent
              .clamp(-inlineWidth, math.max(0.0, inlineWidth - 1))
              .toDouble()
        : 0.0;
    // P2-12：按字形覆盖叠加字体族分段。未传 hasGlyph 时走原路径，
    // 行为与之前完全一致。
    var styled = styledRuns(
      text: text,
      style: style,
      runs: runs,
      hasGlyph: hasGlyph,
      leadingDistribution: leadingDistribution,
      transformText: false,
    );
    final headRuns = firstLineStyle == null
        ? runs
        : firstLineRuns ?? inheritedFirstLineRuns(runs, firstLineStyle);
    final firstStyled = firstLineStyle == null
        ? styled
        : styledRuns(
            text: text,
            style: firstLineStyle,
            runs: headRuns,
            hasGlyph: hasGlyph,
            leadingDistribution: leadingDistribution,
            transformText: false,
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
    // 普通正文没有连字符断点，不必为从不绘制的字形额外构建段落。
    final hyphenAdvance =
        inlineBoxes.isEmpty &&
            (style.hyphens == CssHyphens.auto ||
                (style.hyphens == CssHyphens.manual &&
                    measuredText.contains('\u00AD')))
        ? _measureChar(cssAutoHyphen, style, textScaleFactor)
        : 0.0;
    // 行内盒与断词暂不叠加：两种文本改造同段生效会让偏移映射难以自洽
    // （图文混排段落不需要 hyphens 断词）。
    // TextPainter 遇到多个 ZWSP 时会优先停在词内较早的音节，而不是像
    // Chrome 那样在当前行可容纳的位置断词。纯文本自动断词因此先算出
    // 实际断行点，再用硬换行交给 TextPainter 排版；带行内样式的段落仍
    // 走 ZWSP 路径。
    final autoBreakWork = _TextLayoutWork<Map<int, bool>>(work.painters);
    if (inlineBoxes.isEmpty &&
        runs.isEmpty &&
        firstLineStyle == null &&
        softWrap &&
        !vertical &&
        style.hyphens == CssHyphens.auto &&
        style.wordBreak == CssWordBreak.normal &&
        style.overflowWrap == CssOverflowWrap.normal &&
        style.lineBreak != CssLineBreak.anywhere &&
        !measuredText.contains('\u00AD')) {
      yield* _autoHyphenBreakSteps(
        autoBreakWork,
        text: measuredText,
        width: width,
        firstLineWidth: width - indent,
        style: style,
        textScaleFactor: textScaleFactor,
        leadingDistribution: leadingDistribution,
        hyphenAdvance: hyphenAdvance,
      );
    }
    final autoHyphenBreaks = autoBreakWork.result ?? const <int, bool>{};
    final planWork = _TextLayoutWork<SoftBreakPlan>(work.painters);
    if (inlineBoxes.isNotEmpty) {
      planWork.result = SoftBreakPlan.identity(
        measuredText,
        hyphenAdvance: hyphenAdvance,
      );
    } else if (autoHyphenBreaks.isNotEmpty) {
      planWork.result = _planForcedHyphenBreaks(
        text: measuredText,
        breaks: autoHyphenBreaks,
        hyphenAdvance: hyphenAdvance,
      );
    } else {
      yield* _softBreakSteps(
        planWork,
        text: measuredText,
        hyphens: style.hyphens,
        overflowWrap: style.overflowWrap,
        wordBreak: style.wordBreak,
        contentWidth: inlineWidth,
        style: style,
        textScaleFactor: textScaleFactor,
        hyphenAdvance: hyphenAdvance,
      );
    }
    final breakPlan = planWork.result!;
    if (!vertical && !style.isRtl) {
      inlineBoxes = [
        ...inlineBoxes,
        if (firstLineStyle == null)
          ..._inlineSpacingBoxes(runs, text.length, textScaleFactor)
        else
          ..._firstLineSpacingBoxes(
            runs,
            headRuns,
            text.length,
            textScaleFactor,
          ),
      ];
    }
    late List<LineBox> measured;
    Iterable<bool> measureText(
      String source,
      List<_InlineBoxMark> inlineBoxMarks,
      List<int> offsets,
    ) sync* {
      final measuredRuns = _measurementRuns(styled, offsets);
      final barriers = _spacingBarriers(rubies, inlineBoxMarks, offsets);
      final segment = _TextLayoutWork<List<LineBox>>(work.painters);
      if (measuredText.isEmpty || (indent == 0 && firstLineStyle == null)) {
        yield* _measureSegmentSteps(
          segment,
          text: source,
          inlineBoxMarks: inlineBoxMarks,
          width: vertical ? verticalMeasureWidth : measureWidth,
          contentWidth: inlineWidth,
          style: style,
          textScaleFactor: textScaleFactor,
          leadingDistribution: leadingDistribution,
          runs: measuredRuns,
          spacingBarriers: barriers,
        );
      } else {
        yield* _measureWithIndentSteps(
          segment,
          text: source,
          inlineBoxMarks: inlineBoxMarks,
          width: vertical ? verticalMeasureWidth : measureWidth,
          contentWidth: inlineWidth,
          indent: indent,
          style: style,
          textScaleFactor: textScaleFactor,
          leadingDistribution: leadingDistribution,
          runs: measuredRuns,
          spacingBarriers: barriers,
          firstLineStyle: firstLineStyle,
          firstLineRuns: _measurementRuns(firstStyled, offsets),
        );
      }
      measured = segment.result!;
    }

    // 行内盒「整块换行」：盒在行尾放不下时在盒前强制换行后重测（最多 4 轮，
    // 每轮至少解决一个溢出盒）。
    final forcedBreaks = <int>{};
    for (var attempt = 0; attempt < 4; attempt++) {
      final boxText = inlineBoxes.isEmpty
          ? null
          : _buildInlineBoxText(
              breakPlan.text,
              breakPlan.changed
                  ? [
                      for (final box in inlineBoxes)
                        box.atOffset(
                          _measuredOffset(breakPlan.offsets, box.offset),
                        ),
                    ]
                  : inlineBoxes,
              forcedBreaks: forcedBreaks,
            );
      // 缩进非零就走首行减宽路径：负缩进的首行宽 = width + |indent|，
      // 行左缘由 LineBox.indent（负值）画到内容盒左侧。
      yield* measureText(
        boxText?.text ?? breakPlan.text,
        boxText?.marks ?? const <_InlineBoxMark>[],
        boxText == null
            ? breakPlan.offsets
            : [
                for (final offset in boxText.offsets)
                  breakPlan.originalOffset(offset),
              ],
      );
      if (boxText != null && boxText.changed) {
        measured = _mapInlineBoxLines(measured, boxText);
      }
      measured = _mapSoftBreaks(measured, breakPlan);
      if (style.writingMode != CssWritingMode.horizontalTb) {
        // 竖排（CSS Writing Modes §3，最小可用映射）：横排测量得到的每「行」
        // 变成一「列」，列宽 = 行高，列长 = 该行宽；rl 首列在最右、lr 在左。
        // 文字仍在列内自上而下（字符顺序与横排一致），逐字旋转由绘制层做。
        work.result = _verticalFromLines(
          text: text,
          lines: measured,
          style: style,
          maxWidth: width,
          runs: firstLineStyle == null || measured.isEmpty
              ? styled
              : styledRuns(
                  text: text,
                  style: style,
                  runs: runs,
                  hasGlyph: hasGlyph,
                  leadingDistribution: leadingDistribution,
                  firstLineStyle: firstLineStyle,
                  firstLineRuns: firstLineRuns,
                  firstLineEnd: measured.first.end,
                  transformText: false,
                ),
          isRtl: style.isRtl,
          firstLineStyle: firstLineStyle,
          firstLineRuns: firstLineRuns,
          sourceRuns: firstLineStyle == null ? null : runs,
          inputOffsets: inputOffsets,
        );
        return;
      }
      if (boxText == null) {
        break;
      }
      var retry = false;
      for (final line in measured) {
        for (final box in line.inlineBoxes) {
          if (box.spec.payload is InlineSpacingEdge) continue;
          // 行内还有前置文字、且盒右缘超出内容宽 → 盒整体换行。
          if (box.left > 0.5 && box.left + box.width > width + 0.5) {
            if (forcedBreaks.add(box.spec.offset)) {
              retry = true;
            }
          } else if (box.offset == line.start &&
              box.spec.offset > 0 &&
              box.spec.offset < measuredText.length &&
              punctLineStartProhibitedSet.contains(
                measuredText[box.spec.offset],
              )) {
            // 注号等行内盒被单独挤到行首、后面紧跟收尾标点时，把前一个字
            // 一起移到下一行，避免「注号 + 逗号/句号」占据行首。
            final previous = _previousCharacterOffset(
              measuredText,
              box.spec.offset,
            );
            if (previous < box.spec.offset &&
                !_isWhitespace(measuredText.codeUnitAt(previous)) &&
                forcedBreaks.add(previous)) {
              retry = true;
            }
          }
        }
      }
      if (!retry) {
        break;
      }
    }
    if (firstLineStyle != null && measured.isNotEmpty) {
      styled = styledRuns(
        text: text,
        style: style,
        runs: runs,
        hasGlyph: hasGlyph,
        leadingDistribution: leadingDistribution,
        firstLineStyle: firstLineStyle,
        firstLineRuns: firstLineRuns,
        firstLineEnd: measured.first.end,
        transformText: false,
      );
    }
    final aligned = <LineBox>[];
    for (final line in _align(measuredText, measured, style, width, (
      runs: styled,
      scale: textScaleFactor,
      leading: leadingDistribution,
    ))) {
      aligned.add(line);
      if (aligned.length % 16 == 0) yield false;
    }
    work.result = _result(
      text,
      aligned,
      width,
      styled,
      style,
      isRtl: style.isRtl,
      // Chromium 会给横排 under 着重号增加约 0.12em 的块底部空间。
      bottomOverflow:
          style.hasTextEmphasis && style.textEmphasisPosition.isUnder
          ? style.fontSize * 0.12
          : 0,
      firstLineStyle: firstLineStyle,
      firstLineRuns: firstLineRuns,
      sourceRuns: firstLineStyle == null ? null : runs,
      inputOffsets: inputOffsets,
    );
  }

  /// 构造软断点计划（`hyphens` / `overflow-wrap` / `word-break`）。
  ///
  /// - `hyphens: auto`：英文按 hyph_en_US 词表（Liang 算法）插入音节断点，
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
    final work = _TextLayoutWork<SoftBreakPlan>();
    for (final _ in _softBreakSteps(
      work,
      text: text,
      hyphens: hyphens,
      overflowWrap: overflowWrap,
      wordBreak: wordBreak,
      contentWidth: contentWidth,
      style: style,
      textScaleFactor: textScaleFactor,
      hyphenAdvance: hyphenAdvance,
    )) {}
    return work.result!;
  }

  static Iterable<bool> _softBreakSteps(
    _TextLayoutWork<SoftBreakPlan> work, {
    required String text,
    required CssHyphens hyphens,
    required CssOverflowWrap overflowWrap,
    required CssWordBreak wordBreak,
    required double contentWidth,
    required ComputedStyle style,
    double textScaleFactor = 1,
    double hyphenAdvance = 0,
  }) sync* {
    final autoHyphen = hyphens == CssHyphens.auto;
    final manualHyphen = hyphens == CssHyphens.manual || autoHyphen;
    final breakAnywhere =
        overflowWrap == CssOverflowWrap.anywhere ||
        wordBreak == CssWordBreak.breakAll ||
        // `line-break: anywhere` 允许任意字符间断行（CSS Text 3）。
        style.lineBreak == CssLineBreak.anywhere;
    final breakLongWord = overflowWrap == CssOverflowWrap.breakWord;
    final hasSoftHyphen = text.contains('\u00AD');
    if (!autoHyphen &&
        !(manualHyphen && hasSoftHyphen) &&
        !breakAnywhere &&
        !breakLongWord) {
      work.result = SoftBreakPlan.identity(text, hyphenAdvance: hyphenAdvance);
      return;
    }
    // 断点：原文下标 → 是否带连字符（key 是「断在该下标之前」）。
    final breaks = <int, bool>{};
    // `break-word` 的紧急断点不能在当前行有余宽时直接吃掉词头。浏览器会
    // 先尝试把整个词移到下一行，只有从新行起点仍放不下才逐字断开；这里在
    // 超宽词前加硬换行，模拟第一步的整词换行。
    final forcedWordBreaks = <int>{};
    var index = 0;
    while (index < text.length) {
      final code = text.codeUnitAt(index);
      if (_isLatinWordCode(code)) {
        final start = index;
        while (index < text.length &&
            _isLatinWordCode(text.codeUnitAt(index))) {
          index += 1;
        }
        final word = text.substring(start, index);
        final longWord =
            breakLongWord &&
            _wordWidth(word, style, textScaleFactor) > contentWidth;
        if (longWord &&
            !breakAnywhere &&
            _hasContentOnCurrentLine(text, start)) {
          forcedWordBreaks.add(start);
        }
        for (final offset in _wordBreakOffsets(
          word,
          autoHyphen: autoHyphen,
          breakAnywhere: breakAnywhere,
          breakLongWord: longWord,
        )) {
          breaks[start + offset] = autoHyphen && !breakAnywhere;
        }
        yield false;
        continue;
      }
      if (code == 0x00AD && manualHyphen) {
        // 软连字符本身就是断点（原文保留 SHY，测量文本换成 ZWSP）。
        breaks[index] = true;
        index += 1;
        continue;
      }
      index += 1;
      if (index % 64 == 0) yield false;
    }
    if (breaks.isEmpty) {
      work.result = SoftBreakPlan.identity(text, hyphenAdvance: hyphenAdvance);
      return;
    }
    final buffer = StringBuffer();
    final offsets = <int>[0];
    final hyphenPoints = <int>{};
    for (var p = 0; p < text.length; p++) {
      final isSoftHyphen = text.codeUnitAt(p) == 0x00AD;
      if (forcedWordBreaks.contains(p)) {
        buffer.write('\n');
        offsets.add(p);
      }
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
      if (p % 64 == 63) yield false;
    }
    final planned = buffer.toString();
    if (planned.length == text.length && hyphenPoints.isEmpty) {
      work.result = SoftBreakPlan.identity(text, hyphenAdvance: hyphenAdvance);
      return;
    }
    if (planned.length == text.length) {
      // 等长替换（软连字符 → ZWSP）：映射恒等，但保留连字符断点。
      work.result = SoftBreakPlan(
        text: planned,
        offsets: List<int>.generate(text.length + 1, (i) => i),
        hyphenPoints: hyphenPoints,
        hyphenAdvance: hyphenAdvance,
      );
      return;
    }
    work.result = SoftBreakPlan(
      text: planned,
      offsets: offsets,
      hyphenPoints: hyphenPoints,
      hyphenAdvance: hyphenAdvance,
    );
  }

  /// 计算纯文本 `hyphens:auto` 的逐行断点。
  ///
  /// 先按完整的自然词测量当前行；下一个词放不下时，从该词的音节断点中取
  /// 加上行尾连字符仍能放下的最靠后位置。这样断点随实际行宽推进，与
  /// Chrome 的 `ShapingLineBreaker` 行为一致。
  static Iterable<bool> _autoHyphenBreakSteps(
    _TextLayoutWork<Map<int, bool>> work, {
    required String text,
    required double width,
    required double firstLineWidth,
    required ComputedStyle style,
    required double textScaleFactor,
    required TextLeadingDistribution leadingDistribution,
    required double hyphenAdvance,
  }) sync* {
    if (!width.isFinite || width <= hyphenAdvance) {
      work.result = const <int, bool>{};
      return;
    }
    final breaks = <int, bool>{};
    var lineStart = 0;
    var firstLine = true;
    while (lineStart < text.length) {
      final available = firstLine ? firstLineWidth : width;
      final result = _nextAutoHyphenLine(
        text: text,
        lineStart: lineStart,
        width: available,
        style: style,
        textScaleFactor: textScaleFactor,
        leadingDistribution: leadingDistribution,
        hyphenAdvance: hyphenAdvance,
      );
      final breakAt = result.$1;
      final hyphenated = result.$2;
      final nextLine = result.$3;
      if (breakAt != null && breakAt > lineStart) {
        breaks[breakAt] = hyphenated;
        lineStart = hyphenated ? breakAt : nextLine ?? breakAt;
      } else if (nextLine != null && nextLine > lineStart) {
        lineStart = nextLine;
      } else {
        break;
      }
      firstLine = false;
      yield false;
    }
    work.result = breaks;
  }

  /// 返回 `(本行断点, 是否断词, 下一行起点)`。
  static (int?, bool, int?) _nextAutoHyphenLine({
    required String text,
    required int lineStart,
    required double width,
    required ComputedStyle style,
    required double textScaleFactor,
    required TextLeadingDistribution leadingDistribution,
    required double hyphenAdvance,
  }) {
    var cursor = lineStart;
    int? lastSafeEnd;
    while (cursor < text.length) {
      final code = text.codeUnitAt(cursor);
      if (code == 0x0A || code == 0x0D) {
        return (null, false, _afterLineBreak(text, cursor));
      }
      if (_isHorizontalSpace(code)) {
        cursor += 1;
        continue;
      }
      final wordStart = cursor;
      while (cursor < text.length && !_isWhitespace(text.codeUnitAt(cursor))) {
        cursor += 1;
      }
      final wordEnd = cursor;
      final lineWidth = _measureTextWidth(
        text.substring(lineStart, wordEnd),
        style,
        textScaleFactor,
        leadingDistribution,
      );
      if (lineWidth <= width + 0.5) {
        lastSafeEnd = wordEnd;
        continue;
      }
      final hyphenBreak = _lastHyphenBreakThatFits(
        text: text,
        lineStart: lineStart,
        wordStart: wordStart,
        wordEnd: wordEnd,
        width: width,
        style: style,
        textScaleFactor: textScaleFactor,
        leadingDistribution: leadingDistribution,
        hyphenAdvance: hyphenAdvance,
      );
      if (hyphenBreak != null) {
        return (hyphenBreak, true, hyphenBreak);
      }
      if (lastSafeEnd != null) {
        return (lastSafeEnd, false, _skipHorizontalSpaces(text, lastSafeEnd));
      }
      // 首词连最早音节也放不下时保留浏览器式溢出，不制造无限断点。
      return (null, false, null);
    }
    return (null, false, null);
  }

  static int? _lastHyphenBreakThatFits({
    required String text,
    required int lineStart,
    required int wordStart,
    required int wordEnd,
    required double width,
    required ComputedStyle style,
    required double textScaleFactor,
    required TextLeadingDistribution leadingDistribution,
    required double hyphenAdvance,
  }) {
    // 行首可能落在上一次断词后的词中；词表必须仍按完整原词查询。
    var fullWordStart = wordStart;
    if (wordStart == lineStart && lineStart > 0) {
      while (fullWordStart > 0 &&
          _isLatinWordCode(text.codeUnitAt(fullWordStart - 1))) {
        fullWordStart -= 1;
      }
    }
    var fullWordEnd = wordEnd;
    while (fullWordEnd < text.length &&
        _isLatinWordCode(text.codeUnitAt(fullWordEnd))) {
      fullWordEnd += 1;
    }
    final offsets = EnUsHyphenator.breakOffsets(
      text.substring(fullWordStart, fullWordEnd),
    );
    int? best;
    for (final offset in offsets) {
      final point = fullWordStart + offset;
      if (point <= lineStart || point >= fullWordEnd) {
        continue;
      }
      final prefixWidth = _measureTextWidth(
        text.substring(lineStart, point),
        style,
        textScaleFactor,
        leadingDistribution,
      );
      if (prefixWidth + hyphenAdvance <= width + 0.5) {
        best = point;
      }
    }
    return best;
  }

  static bool _isWhitespace(int code) =>
      code == 0x20 ||
      code == 0x09 ||
      code == 0x0A ||
      code == 0x0D ||
      code == 0x0C;

  static bool _isHorizontalSpace(int code) =>
      code == 0x20 || code == 0x09 || code == 0x0C;

  static int _skipHorizontalSpaces(String text, int index) {
    var cursor = index;
    while (cursor < text.length &&
        _isHorizontalSpace(text.codeUnitAt(cursor))) {
      cursor += 1;
    }
    return cursor;
  }

  static int _afterLineBreak(String text, int index) {
    if (text.codeUnitAt(index) == 0x0D &&
        index + 1 < text.length &&
        text.codeUnitAt(index + 1) == 0x0A) {
      return index + 2;
    }
    return index + 1;
  }

  /// 把计算好的自动断词位置作为硬换行交给 TextPainter。
  static SoftBreakPlan _planForcedHyphenBreaks({
    required String text,
    required Map<int, bool> breaks,
    required double hyphenAdvance,
  }) {
    final buffer = StringBuffer();
    final offsets = <int>[0];
    final hyphenPoints = <int>{};
    var index = 0;
    while (index < text.length) {
      if (breaks.containsKey(index)) {
        buffer.write('\n');
        offsets.add(index);
        final hyphenated = breaks[index]!;
        if (hyphenated) {
          hyphenPoints.add(buffer.length - 1);
        } else {
          // 自然换行后的行首空格由 CSS 折叠掉，保留会多算一个空格宽。
          var next = index + 1;
          while (next < text.length &&
              _isHorizontalSpace(text.codeUnitAt(next))) {
            next += 1;
          }
          index = next;
          continue;
        }
      }
      buffer.write(text[index]);
      offsets.add(index + 1);
      index += 1;
    }
    return SoftBreakPlan(
      text: buffer.toString(),
      offsets: offsets,
      hyphenPoints: hyphenPoints,
      hyphenAdvance: hyphenAdvance,
    );
  }

  /// 原文 [index] 之前、同一个逻辑行上是否已有非空白内容。
  ///
  /// 显式换行之后（或段落开头）无需再插入整词换行，否则会多出空行。
  static bool _hasContentOnCurrentLine(String text, int index) {
    for (var i = index - 1; i >= 0; i--) {
      final code = text.codeUnitAt(i);
      if (code == 0x0A || code == 0x0D) {
        return false;
      }
      if (code != 0x20 && code != 0x09 && code != 0x0C) {
        return true;
      }
    }
    return false;
  }

  /// 拉丁词内部的断点（相对词首的下标）：「断在该下标之前」。
  static List<int> _wordBreakOffsets(
    String word, {
    required bool autoHyphen,
    required bool breakAnywhere,
    required bool breakLongWord,
  }) {
    if (word.length < 4) {
      return const <int>[];
    }
    if (breakAnywhere) {
      return <int>[for (var i = 1; i < word.length; i++) i];
    }
    if (breakLongWord) {
      return <int>[for (var i = 1; i < word.length; i++) i];
    }
    if (!autoHyphen) {
      return const <int>[];
    }
    return EnUsHyphenator.breakOffsets(word);
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

  /// 拉丁字母/数字（含撇号，按整词处理）。
  ///
  /// 连字符不并入 token：它是正常断行机会，须优先于
  /// `overflow-wrap: break-word` 的紧急逐字断点。复合长词因此会按连字符
  /// 分段判断宽度，避免紧急断点抢占连字符前的位置。
  static bool _isLatinWordCode(int code) =>
      (code >= 0x41 && code <= 0x5A) ||
      (code >= 0x61 && code <= 0x7A) ||
      (code >= 0x30 && code <= 0x39) ||
      code == 0x27 ||
      code == 0x2019;

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
          spacing: line.spacing?.remap(
            (offset) =>
                plan.originalOffset(line.start + offset) -
                plan.originalOffset(line.start),
          ),
          width: hyphenated ? line.width + plan.hyphenAdvance : line.width,
          hyphenated: hyphenated,
          hyphenWidth: hyphenated ? plan.hyphenAdvance : 0,
          inlineBoxes: [
            for (final box in line.inlineBoxes)
              InlineBoxPlacement(
                offset: plan.originalOffset(box.offset),
                left: box.left,
                width: box.width,
                height: box.height,
                ascent: box.ascent,
                descent: box.descent,
                spec: box.spec,
                vertical: box.vertical,
              ),
          ],
        ),
      );
    }
    return mapped;
  }

  static int _measuredOffset(List<int> offsets, int original) {
    var low = 0;
    var high = offsets.length - 1;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (offsets[middle] < original) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  static List<StyledRun> _measurementRuns(
    List<StyledRun> runs,
    List<int> offsets,
  ) {
    if (offsets.length == offsets.last + 1) return runs;
    return [
      for (final run in runs)
        StyledRun(
          start: _measuredOffset(offsets, run.start),
          end: _measuredOffset(offsets, run.end),
          style: run.style,
          baselineShift: run.baselineShift,
          syntheticFontFallback: run.syntheticFontFallback,
          inlineLeadingInset: run.inlineLeadingInset,
          inlineTrailingInset: run.inlineTrailingInset,
          inlinePadding: run.inlinePadding,
        ),
    ];
  }

  static Set<int> _spacingBarriers(
    List<RubyAnnotation> rubies,
    List<_InlineBoxMark> marks,
    List<int> offsets,
  ) => {
    for (final mark in marks) ...[mark.index, mark.index + 1],
    for (final ruby in rubies)
      for (
        var i = _measuredOffset(offsets, ruby.start);
        i <= _measuredOffset(offsets, ruby.end);
        i++
      )
        i,
  };

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
            syntheticFontFallback: run.syntheticFontFallback,
            inlineLeadingInset: start == run.start ? run.inlineLeadingInset : 0,
            inlineTrailingInset: end == run.end ? run.inlineTrailingInset : 0,
            inlinePadding: run.inlinePadding,
          ),
        );
      }
    }
    ordered.sort((a, b) => a.start.compareTo(b.start));
    return ordered;
  }

  /// 直接测量入口没有 DOM 时，按 run 自身声明重建首行继承。
  /// 缓存键复用同一结果的度量指纹，避免相同正文字号漏掉声明来源差异。
  /// 这里只重建级联，不测量或裁剪首行范围。
  /// 章节入口提供完整重级联结果，避免把祖先声明当成 span 的显式值。
  static List<StyledRun> inheritedFirstLineRuns(
    List<StyledRun> runs,
    ComputedStyle firstLineStyle,
  ) => [
    for (final run in runs)
      StyledRun(
        start: run.start,
        end: run.end,
        style: ComputedStyle(
          run.style.values,
          parent: firstLineStyle,
          explicitProperties: run.style.explicitProperties,
          hasExplicitTextColor: run.style.hasExplicitTextColor,
          declaredTextProperties: run.style.declaredTextProperties,
          rootFontSize: firstLineStyle.fontSize,
          valueContext: firstLineStyle.valueContext,
        ),
        baselineShift: run.baselineShift,
        syntheticFontFallback: run.syntheticFontFallback,
        inlineLeadingInset: run.inlineLeadingInset,
        inlineTrailingInset: run.inlineTrailingInset,
        inlinePadding: run.inlinePadding,
      ),
  ];

  static StyledRun _runFragment(StyledRun run, int start, int end) => StyledRun(
    start: start,
    end: end,
    style: run.style,
    baselineShift: run.baselineShift,
    syntheticFontFallback: run.syntheticFontFallback,
    inlineLeadingInset: start == run.start ? run.inlineLeadingInset : 0,
    inlineTrailingInset: end == run.end ? run.inlineTrailingInset : 0,
    inlinePadding: run.inlinePadding,
  );

  /// 只把真正第一物理行替换为首行样式，余文保留正文声明和盒边界。
  static List<StyledRun> _runsWithFirstLine(
    int length,
    int firstLineEnd,
    List<StyledRun> bodyRuns,
    List<StyledRun> firstLineRuns,
    ComputedStyle firstLineStyle,
  ) {
    final end = firstLineEnd.clamp(0, length);
    final result = <StyledRun>[];
    var cursor = 0;
    void fill(int to) {
      if (to <= cursor) return;
      result.add(
        StyledRun(
          start: cursor,
          end: to,
          style: firstLineStyle,
          inlineLeadingInset: 0,
          inlineTrailingInset: 0,
        ),
      );
      cursor = to;
    }

    for (final run in _normalizeRuns(firstLineRuns, length)) {
      final start = math.max(cursor, run.start);
      final stop = math.min(end, run.end);
      if (stop <= start) continue;
      fill(start);
      result.add(_runFragment(run, start, stop));
      cursor = stop;
    }
    fill(end);
    for (final run in _normalizeRuns(bodyRuns, length)) {
      final start = math.max(end, run.start);
      if (run.end > start) result.add(_runFragment(run, start, run.end));
    }
    return result;
  }

  /// 把字形覆盖分段叠加到调用方的 [runs] 上，返回升序、互不重叠的样式区间。
  ///
  /// 行内样式优先：调用方区间（混排字号、上下标等）只在自身计算样式上叠加
  /// font-family，字号/字重/颜色等保持原值；调用方未覆盖的文本以 [baseStyle]
  /// 兜底后再叠加。相邻且同源的片段会合并，尽量不把调用方区间打碎。
  static List<StyledRun> _applyScriptFallback({
    required String text,
    required List<StyledRun> runs,
    required ComputedStyle baseStyle,
    required bool Function(String family, int codeUnit) hasGlyph,
  }) {
    final baseFamilies = _scriptFamilies(baseStyle);
    final baseScriptRuns = buildScriptFontRuns(
      text,
      baseFamilies,
      hasGlyph: hasGlyph,
    );
    var hasScriptCoverage = baseScriptRuns.isNotEmpty;
    // 行内 run 的字体声明优先于正文默认链；为每个 owner 单独计算覆盖分段，
    // 否则正文的默认回退字体会覆盖书内 span 自己声明的字体。
    final ownerScriptRuns = <int, List<ScriptFontRun>>{};
    final cuts = <int>{0, text.length};
    for (final run in runs) {
      final start = run.start.clamp(0, text.length).toInt();
      final end = run.end.clamp(start, text.length).toInt();
      cuts
        ..add(start)
        ..add(end);
      if (end <= start) {
        continue;
      }
      final families = _scriptFamilies(run.style);
      final localRuns = buildScriptFontRuns(
        text.substring(start, end),
        families,
        hasGlyph: hasGlyph,
      );
      if (localRuns.isNotEmpty) {
        hasScriptCoverage = true;
      }
      ownerScriptRuns[run.start] = <ScriptFontRun>[
        for (final local in localRuns)
          ScriptFontRun(
            start: local.start + start,
            end: local.end + start,
            family: local.family,
          ),
      ];
      for (final local in ownerScriptRuns[run.start]!) {
        cuts
          ..add(local.start)
          ..add(local.end);
      }
    }
    for (final run in baseScriptRuns) {
      cuts
        ..add(run.start)
        ..add(run.end);
    }
    // 用全部端点把文本切成互不重叠的小段。
    if (!hasScriptCoverage) {
      return runs;
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
    var openSynthetic = false;
    var openLeadingInset = 0.0;
    var openTrailingInset = 0.0;
    var openPadding = EdgeInsets.zero;
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
            syntheticFontFallback: openSynthetic,
            inlineLeadingInset: openLeadingInset,
            inlineTrailingInset: openTrailingInset,
            inlinePadding: openPadding,
          ),
        );
      }
      openStart = null;
      openEnd = null;
      openStyle = null;
      openShift = 0;
      openSynthetic = false;
    }

    for (var i = 0; i + 1 < boundaries.length; i++) {
      final start = boundaries[i];
      final end = boundaries[i + 1];
      if (end <= start) {
        continue;
      }
      final owner = _owningRun(runs, start, end);
      final family = _scriptFamilyAt(
        owner == null ? baseScriptRuns : ownerScriptRuns[owner.start],
        start,
      );
      final style = _segmentStyle(owner, family, baseStyle, withFamily);
      final shift = owner?.baselineShift ?? 0;
      final synthetic = owner?.syntheticFontFallback ?? true;
      if (style == null) {
        flush(); // 无族的空隙不产出区间
      } else if (openStyle != null &&
          identical(openStyle, style) &&
          openShift == shift &&
          openSynthetic == synthetic &&
          openPadding == (owner?.inlinePadding ?? EdgeInsets.zero) &&
          openTrailingInset == 0 &&
          (owner?.start != start || owner!.leadingInset == 0) &&
          openEnd == start) {
        openEnd = end; // 同源同族同偏移，继续延伸
        openTrailingInset = owner?.end == end ? owner!.trailingInset : 0;
      } else {
        flush();
        openStart = start;
        openEnd = end;
        openStyle = style;
        openShift = shift;
        openSynthetic = synthetic;
        openPadding = owner?.inlinePadding ?? EdgeInsets.zero;
        openLeadingInset = owner?.start == start ? owner!.leadingInset : 0;
        openTrailingInset = owner?.end == end ? owner!.trailingInset : 0;
      }
    }
    flush();
    return merged;
  }

  static List<String> _scriptFamilies(ComputedStyle style) {
    final families = <String>[];
    void add(String family) {
      if (!families.contains(family)) {
        families.add(family);
      }
    }

    for (final family in style.fontFaceFamilies) {
      // 这里同样要走别名映射：`仿宋`、`宋体` 等主族保留原名时，
      // hasGlyph 能识别别名，但最终 run 仍写原名，引擎找不到对应字库
      // 就画豆腐块。映射后选中项与实际可使用的主族一致。
      add(FontFamilyAliases.resolve(family) ?? family);
    }
    final primary =
        FontFamilyAliases.resolve(style.fontFamily ?? '') ?? style.fontFamily;
    final fallback = primary == FontFamilyAliases.hei
        ? FontFamilyAliases.sansChain
        : FontFamilyAliases.defaultChain;
    for (final family in fallback) {
      add(family);
    }
    return families;
  }

  static bool _covers(
    String family,
    int codePoint,
    bool Function(String, int)? hasGlyph,
  ) =>
      BookFontFaceRegistry.covers(family, codePoint) ??
      hasGlyph?.call(family, codePoint) ??
      FontCoverageRegistry.covers(family, codePoint) ??
      (family != FontFamilyAliases.kai);

  static String? _scriptFamilyAt(List<ScriptFontRun>? runs, int offset) {
    if (runs == null) {
      return null;
    }
    for (final run in runs) {
      if (run.start > offset) {
        return null;
      }
      if (run.start <= offset && run.end > offset) {
        return run.family;
      }
    }
    return null;
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
  ) => source.withTypography(fontFamily: family);

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
            syntheticFontFallback: run.syntheticFontFallback,
            inlineLeadingInset: runStart == run.start
                ? run.inlineLeadingInset
                : 0,
            inlineTrailingInset: runEnd == run.end
                ? run.inlineTrailingInset
                : 0,
            inlinePadding: run.inlinePadding,
          ),
        );
      }
    }
    return sliced;
  }

  /// 首行减宽断行，尾段用完整宽度重排后合并（§61.2）。
  static Iterable<bool> _measureWithIndentSteps(
    _TextLayoutWork<List<LineBox>> work, {
    required String text,
    required double width,
    required double contentWidth,
    required double indent,
    required ComputedStyle style,
    required double textScaleFactor,
    required TextLeadingDistribution leadingDistribution,
    List<StyledRun> runs = const <StyledRun>[],
    List<_InlineBoxMark> inlineBoxMarks = const <_InlineBoxMark>[],
    Set<int> spacingBarriers = const {},
    ComputedStyle? firstLineStyle,
    List<StyledRun>? firstLineRuns,
  }) sync* {
    final headStyle = firstLineStyle ?? style;
    final sourceHeadRuns = firstLineRuns ?? runs;
    final sourceHeadMarks = [
      for (final mark in inlineBoxMarks)
        if (mark.spec case final _FirstLineSpacingBoxSpec spec)
          _InlineBoxMark(index: mark.index, spec: spec.forFirstLine)
        else
          mark,
    ];
    final firstWidth = math.max(1.0, width - indent);
    // 首段先不带行内盒测一次，拿到分界后再把「落在首段」的盒补进去
    // （盒占宽会改变首段末行，但盒的位置由原文偏移决定，不受影响）。
    // 首行探测只需断点前的少量上下文；长段按需倍增，避免为一行塑形整段余文。
    var headText = text.length <= _indentProbeChars
        ? text
        : text.substring(0, _indentProbeChars);
    var headRuns = text.length <= _indentProbeChars
        ? sourceHeadRuns
        : _sliceRuns(sourceHeadRuns, 0, _indentProbeChars);
    var headMarks = text.length <= _indentProbeChars
        ? sourceHeadMarks
        : <_InlineBoxMark>[
            for (final mark in sourceHeadMarks)
              if (mark.index < _indentProbeChars) mark,
          ];
    late List<LineBox> head;
    while (true) {
      final segment = _TextLayoutWork<List<LineBox>>(work.painters);
      yield* _measureSegmentSteps(
        segment,
        text: headText,
        width: firstWidth,
        contentWidth: firstWidth,
        style: headStyle,
        textScaleFactor: textScaleFactor,
        leadingDistribution: leadingDistribution,
        runs: headRuns,
        inlineBoxMarks: headMarks,
        spacingBarriers: spacingBarriers,
        firstLineOnly: true,
      );
      head = segment.result!;
      if (head.isEmpty ||
          head.first.end < headText.length ||
          headText.length == text.length) {
        break;
      }
      final next = math.min(text.length, headText.length * 2);
      headText = text.substring(0, next);
      headRuns = _sliceRuns(sourceHeadRuns, 0, next);
      headMarks = <_InlineBoxMark>[
        for (final mark in sourceHeadMarks)
          if (mark.index < next) mark,
      ];
    }
    if (head.isEmpty) {
      work.result = const <LineBox>[];
      return;
    }
    if (headMarks.isNotEmpty) {
      final firstMarks = <_InlineBoxMark>[
        for (final mark in sourceHeadMarks)
          if (mark.index < head.first.end) mark,
      ];
      if (firstMarks.isNotEmpty) {
        final segment = _TextLayoutWork<List<LineBox>>(work.painters);
        yield* _measureSegmentSteps(
          segment,
          text: headText,
          width: firstWidth,
          contentWidth: firstWidth,
          inlineBoxMarks: firstMarks,
          style: headStyle,
          textScaleFactor: textScaleFactor,
          leadingDistribution: leadingDistribution,
          runs: headRuns,
          spacingBarriers: spacingBarriers,
          firstLineOnly: true,
        );
        head = segment.result!;
      }
    }
    final first = head.first.copyWith(indent: indent);
    var remainderStart = first.end;
    if (remainderStart < text.length && text.codeUnitAt(remainderStart) == 10) {
      remainderStart += 1;
    }
    final remainder = text.substring(remainderStart);
    final restSegment = _TextLayoutWork<List<LineBox>>(work.painters);
    yield* _measureSegmentSteps(
      restSegment,
      text: remainder,
      width: width,
      contentWidth: contentWidth,
      inlineBoxMarks: _shiftInlineBoxMarks(inlineBoxMarks, remainderStart),
      style: style,
      textScaleFactor: textScaleFactor,
      leadingDistribution: leadingDistribution,
      runs: _sliceRuns(runs, remainderStart, text.length),
      spacingBarriers: {
        for (final offset in spacingBarriers)
          if (offset >= remainderStart) offset - remainderStart,
      },
      firstLine: remainderStart > 0 && text[remainderStart - 1] == '\n',
    );
    final rest = restSegment.result!;
    final lines = <LineBox>[first];
    for (var i = 0; i < rest.length; i++) {
      final line = rest[i];
      lines.add(
        line.copyWith(
          start: line.start + remainderStart,
          end: line.end + remainderStart,
          inlineBoxes: line.inlineBoxes.isEmpty
              ? line.inlineBoxes
              : <InlineBoxPlacement>[
                  for (final box in line.inlineBoxes)
                    InlineBoxPlacement(
                      offset: box.offset + remainderStart,
                      left: box.left,
                      width: box.width,
                      height: box.height,
                      ascent: box.ascent,
                      descent: box.descent,
                      spec: box.spec,
                      vertical: box.vertical,
                    ),
                ],
          top: first.height + line.top,
          isLastLine: i == rest.length - 1,
        ),
      );
      yield false;
    }
    lines[0] = lines[0].copyWith(isLastLine: rest.isEmpty);
    work.result = lines;
  }

  /// 按 text-align 计算每行水平偏移与 justify 分摊宽度（§61.5）。
  ///
  /// 行宽已含 text-indent 造成的减宽，比较基准是 `width - indent`；
  /// justify 的末行与硬换行行按 start 对齐，不拉伸——除非
  /// `text-align-last` 指定（P7-21）或 `text-justify: justify-all`。
  static Iterable<LineBox> _align(
    String text,
    List<LineBox> lines,
    ComputedStyle style,
    double width,
    ({List<StyledRun> runs, double scale, TextLeadingDistribution leading})
    context,
  ) sync* {
    // 标点悬挂（P7-18）：`hanging-punctuation: allow-end` 时，两端
    // 对齐的非末行行尾句读挂到版心右缘外——该行的可分配余量加上
    // 句读 advance，末字（句读）落在右缘之外；末行与硬换行不悬挂
    // （_justifyExtra 内判定）。书内显式 CSS 优先：只有声明了
    // allow-end 才启用（默认 none）。
    final hanging = style.hangingPunctuation == CssHangingPunctuation.allowEnd;
    final punctWidths = <(ComputedStyle, String), double>{};
    double hangingWidth(LineBox line) {
      final end =
          line.start +
          (line.spacing?.trailingSpaceStart ?? line.end - line.start);
      if (!hanging ||
          end <= line.start ||
          line.isLastLine ||
          line.isHardBreak) {
        return 0;
      }
      final char = text[end - 1];
      if (!hangableTrailingPunctuation.contains(char)) return 0;
      final css =
          context.runs
              .where((run) => run.start <= end - 1 && run.end >= end)
              .map((run) => run.style)
              .firstOrNull ??
          style;
      final advance = punctWidths[(css, char)] ??= _measureChar(
        char,
        css,
        context.scale,
      );
      final glyph = line.spacing?.glyphs[end - line.start - 1];
      final trimmed =
          (glyph?.reduction ?? 0) *
          (glyph?.halfWidth == true ? context.scale : 1);
      return math.max(0, advance - trimmed);
    }

    final mode = style.textJustify;
    // 末行（含硬换行）的对齐：text-align-last 优先，缺省 start。
    // text-justify: justify-all 或 text-align-last: justify 时末行参与拉伸。
    final lastMayJustify =
        mode == CssTextJustify.justifyAll ||
        style.textAlignLast == CssTextAlign.justify;
    for (final line in lines) {
      // 超宽内容仍需居中或贴右缘；两端对齐的拉伸另行排除负余量。
      final slack = width.isFinite
          ? width - line.indent - line.width
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
      final centeredOffset = align == CssTextAlign.center
          ? _centeredTextOffset(text, line, style, width, context)
          : null;
      // 拉伸余量：justify 对齐；或末行在 justify-all / align-last:
      // justify 下参与拉伸（对齐仍是 start，通过 justifyExtra 拉伸）。
      // 其余对齐保持 0（否则左对齐行也会被绘制端拉伸）。
      // 省略号截断行不拉伸：截断宽已含 `…`，再拉伸会让 `…` 溢出版心。
      final stretch =
          !line.ellipsized &&
          (align == CssTextAlign.justify || (isFinal && lastMayJustify));
      final gaps = stretch ? _lineJustifyGaps(text, line, mode) : const <int>[];
      final spacing = line.spacing?.withJustifyGaps(gaps);
      final justifyExtra = stretch
          ? _justifyExtra(
              line,
              slack,
              hangingWidth: hangingWidth(line),
              lastMayJustify: lastMayJustify,
              gaps: gaps,
            )
          : 0.0;
      final boxes =
          spacing != null && justifyExtra > 0 && line.inlineBoxes.isNotEmpty
          ? _justifyInlineBoxes(line, gaps, justifyExtra)
          : line.inlineBoxes;
      yield switch (align) {
        CssTextAlign.start || CssTextAlign.left => line.copyWith(
          offsetX: line.indent,
          justifyExtra: justifyExtra,
          justifyMode: mode,
          spacing: spacing,
          inlineBoxes: boxes,
        ),
        CssTextAlign.end || CssTextAlign.right => line.copyWith(
          offsetX: line.indent + slack,
          justifyExtra: justifyExtra,
          justifyMode: mode,
          spacing: spacing,
          inlineBoxes: boxes,
        ),
        CssTextAlign.center => line.copyWith(
          // 真实书里常用 &nbsp; 给标题做视觉留白。居中对齐按首末可见字形
          // 的几何范围计算，不能把行首空白和行尾字距算进可见文字宽度。
          offsetX: centeredOffset ?? line.indent + slack / 2,
          justifyExtra: justifyExtra,
          justifyMode: mode,
          spacing: spacing,
          inlineBoxes: boxes,
        ),
        CssTextAlign.justify => line.copyWith(
          offsetX: line.indent,
          justifyExtra: justifyExtra,
          justifyMode: mode,
          spacing: spacing,
          inlineBoxes: boxes,
        ),
      };
    }
  }

  static double? _centeredTextOffset(
    String text,
    LineBox line,
    ComputedStyle style,
    double width,
    ({List<StyledRun> runs, double scale, TextLeadingDistribution leading})
    context,
  ) {
    if (style.isRtl ||
        style.writingMode != CssWritingMode.horizontalTb ||
        style.whiteSpace != CssWhiteSpace.normal ||
        !width.isFinite ||
        line.inlineBoxes.isNotEmpty) {
      return null;
    }
    final lineText = text.substring(line.start, line.end);
    var prefixLength = 0;
    for (final cluster in lineText.characters) {
      if (cluster.trim().isNotEmpty) break;
      prefixLength += cluster.length;
    }
    var contentEnd = lineText.length;
    for (final cluster in lineText.characters.toList().reversed) {
      if (cluster.trim().isNotEmpty) break;
      contentEnd -= cluster.length;
    }
    if ((prefixLength == 0 && contentEnd == lineText.length) ||
        prefixLength == contentEnd) {
      return null;
    }
    final span = applyTextSpacing(
      _measurementSpan(
        lineText,
        _shiftRuns(context.runs, line.start, line.end),
        textStyleFor(style, leadingDistribution: context.leading),
        const <_InlineBoxMark>[],
        (css: style, scale: context.scale, leading: context.leading),
      ),
      line.spacing ?? LineSpacing.empty,
    );
    final painter = TextPainter(
      text: span,
      textDirection: _textDirectionOf(style),
      textScaler: TextScaler.linear(context.scale),
    )..layout();
    final boxes = painter.getBoxesForSelection(
      TextSelection(baseOffset: prefixLength, extentOffset: contentEnd),
    );
    // 零宽字符可能既不参与 trim，也没有实际字形。此时 TextPainter 的
    // caret 几何会触发 glyphBounds 断言，直接退回普通居中偏移。
    if (boxes.isEmpty) {
      painter.dispose();
      return null;
    }
    final visibleStart = painter
        .getOffsetForCaret(TextPosition(offset: prefixLength), Rect.zero)
        .dx;
    // 行尾空格会让 getOffsetForCaret 进入 Flutter 的空字形 caret 分支并
    // 触发断言；可见文字已由选区盒确定，末尾空格不应再参与居中。
    final endsWithWhitespace =
        painter.plainText.isNotEmpty &&
        painter.plainText.characters.last.trim().isEmpty;
    final caretEnd = endsWithWhitespace
        ? boxes.last.right
        : painter
              .getOffsetForCaret(TextPosition(offset: contentEnd), Rect.zero)
              .dx;
    final visibleEnd = 2 * caretEnd - boxes.last.right;
    painter.dispose();
    final center = line.indent + (width - line.indent) / 2;
    return center - (visibleStart + visibleEnd) / 2;
  }

  static List<int> _lineJustifyGaps(
    String text,
    LineBox line,
    CssTextJustify mode,
  ) {
    final gaps = cjkJustifyGapOffsets(
      text.substring(line.start, line.end),
      mode: mode,
    );
    final locked = line.spacing?.lockedGaps;
    return locked == null || locked.isEmpty
        ? gaps
        : gaps.where((offset) => !locked.contains(offset)).toList();
  }

  static List<InlineBoxPlacement> _justifyInlineBoxes(
    LineBox line,
    List<int> gaps,
    double extra,
  ) {
    return [
      for (final box in line.inlineBoxes)
        InlineBoxPlacement(
          offset: box.offset,
          left:
              box.left +
              (gaps.isEmpty
                  ? 0
                  : extra /
                        gaps.length *
                        gaps
                            .where((offset) => offset < box.offset - line.start)
                            .length),
          width: box.width,
          height: box.height,
          ascent: box.ascent,
          descent: box.descent,
          spec: box.spec,
          vertical: box.vertical,
        ),
    ];
  }

  /// 该行可用于 justify 的余量；没有可拉伸间隙时返回 0。
  ///
  /// 悬挂开启且行尾为悬挂句读时，余量加句读宽度（P7-18）。
  /// 末行/硬换行仅在 `lastMayJustify`（justify-all 或 align-last:
  /// justify）时参与拉伸（P7-21）。
  static double _justifyExtra(
    LineBox line,
    double slack, {
    required double hangingWidth,
    required bool lastMayJustify,
    required List<int> gaps,
  }) {
    if (slack < 0) {
      return 0;
    }
    final isFinal = line.isLastLine || line.isHardBreak;
    if (isFinal && !lastMayJustify) {
      return 0;
    }
    if (gaps.isEmpty) {
      return 0;
    }
    return slack + hangingWidth;
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
        style: textStyleFor(
          style,
          leadingDistribution: TextLeadingDistribution.even,
        ),
      ),
      textDirection: _textDirectionOf(style),
      textScaler: TextScaler.linear(textScaleFactor),
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  /// 测量纯文本前缀宽度；用于 `tab-size` 的实际制表位计算。
  static double _measureTextWidth(
    String text,
    ComputedStyle style,
    double textScaleFactor,
    TextLeadingDistribution leadingDistribution,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: textStyleFor(style, leadingDistribution: leadingDistribution),
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
    final compressOffsets =
        style.textSpacingTrim == CssTextSpacingTrim.trimAdjacent
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

  static Iterable<bool> _measureSegmentSteps(
    _TextLayoutWork<List<LineBox>> work, {
    required String text,
    required double width,
    required ComputedStyle style,
    required double textScaleFactor,
    required TextLeadingDistribution leadingDistribution,
    List<StyledRun> runs = const <StyledRun>[],
    List<_InlineBoxMark> inlineBoxMarks = const <_InlineBoxMark>[],
    double? contentWidth,
    Set<int> spacingBarriers = const {},
    bool firstLine = true,
    bool firstLineOnly = false,
    bool clonePadding = true,
  }) sync* {
    if (clonePadding &&
        width.isFinite &&
        !style.isRtl &&
        runs.any((run) => run.inlinePadding.horizontal > 0)) {
      yield* _measurePaddedSegmentSteps(work, (
        text: text,
        width: width,
        style: style,
        scale: textScaleFactor,
        leading: leadingDistribution,
        runs: runs,
        marks: inlineBoxMarks,
        barriers: spacingBarriers,
        firstLine: firstLine,
        firstLineOnly: firstLineOnly,
      ));
      return;
    }
    final baseStyle = textStyleFor(
      style,
      leadingDistribution: leadingDistribution,
    );
    // 横排新路径按实际 run 测量标点；其他排版保留旧的纯文本兼容规则。
    // 中西文自动间距继续沿用已有适用范围，不扩展到混合字号。
    final plainTextLayout = !_runsAffectTextLayout(runs, style);
    // 仅颜色/装饰不同的 run 不改变字形、字距和行高；测量时退化成单一样式，
    // 绘制仍保留原始 runs。这样逐行精确测量不必反复遍历无意义的样式树。
    final layoutRuns = plainTextLayout ? const <StyledRun>[] : runs;
    final compress =
        plainTextLayout &&
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
    // 首行缩进只消费首行；token 合并和可能被推到次行的盒仍需要完整行表。
    final maxLines =
        firstLineOnly && guardRanges.isEmpty && inlineBoxMarks.isEmpty
        ? 1
        : null;
    final measureText = text;
    final horizontal =
        !style.isRtl &&
        style.writingMode == CssWritingMode.horizontalTb &&
        (style.whiteSpace == CssWhiteSpace.normal ||
            style.whiteSpace == CssWhiteSpace.nowrap);
    final sourceSpan = _measurementSpan(
      text,
      layoutRuns,
      baseStyle,
      inlineBoxMarks,
      (css: style, scale: textScaleFactor, leading: leadingDistribution),
    );
    final spacingPlan = horizontal
        ? _punctuationPlan(text, style, layoutRuns, (
            base: baseStyle,
            leading: leadingDistribution,
            autospace:
                plainTextLayout &&
                style.textAutospace == CssTextAutospace.normal,
          ), spacingBarriers)
        : null;
    final paragraph = spacingPlan == null
        ? null
        : SpacedParagraph(
            text: text,
            span: sourceSpan,
            spacing: spacingPlan,
            width: width,
            scale: textScaleFactor,
            firstLine: firstLine,
            maxLines: maxLines,
          );
    final painter = work.painters.own(
      TextPainter(
        text: spacingPlan != null
            ? applyTextSpacing(
                sourceSpan,
                spacingPlan.range(0, text.length, trimTrailing: false),
              )
            : compress && inlineBoxMarks.isEmpty && plainTextLayout
            ? applySyntheticSmallCaps(
                _plainSpan(text, style, baseStyle, textScaleFactor),
              )
            : sourceSpan,
        textDirection: _textDirectionOf(style),
        textScaler: TextScaler.linear(textScaleFactor),
        maxLines: maxLines,
      ),
    );
    painter.layout(maxWidth: width);
    yield false;
    final steps = paragraph?.lineSteps(painter);
    final measuredLines = steps == null ? null : <SpacedLine>[];
    if (steps != null) {
      for (final line in steps) {
        measuredLines!.add(line);
        yield false;
      }
    }
    final metrics =
        measuredLines?.map((line) => line.metrics).toList() ??
        painter.computeLineMetrics();
    // 小数行高（实验）：Skia 行盒高取整为整数，ascent 已按小数行高计算；
    // 这里把「被取整的 strut 行盒」换回 CSS 行高像素值。
    final cssLineHeight =
        LineBreaker.preserveFractionalLineHeight &&
            style.lineHeightFactor != null
        ? style.lineHeight
        : null;
    final lineRanges = measuredLines == null
        ? textLineRanges(painter, text, metrics.length)
        : const <TextRange>[];
    final lines = <LineBox>[];
    var top = 0.0;
    for (var metricIndex = 0; metricIndex < metrics.length; metricIndex++) {
      final metric = metrics[metricIndex];
      final measured = measuredLines?[metricIndex];
      final boundary = measured == null
          ? lineRanges[metricIndex]
          : TextRange(start: measured.start, end: measured.end);
      final syntheticCapsLineHeight = LineBreaker.preserveFractionalLineHeight
          ? _syntheticCapsLineHeight(style, runs, boundary.start, boundary.end)
          : null;
      final normalCssLineHeight =
          LineBreaker.preserveFractionalLineHeight &&
              style.lineHeightFactor == null
          ? metric.ascent.roundToDouble() + metric.descent.roundToDouble()
          : null;
      final lineHeight =
          syntheticCapsLineHeight ??
          normalCssLineHeight ??
          (cssLineHeight != null && (metric.height - cssLineHeight).abs() <= 0.6
              ? cssLineHeight
              : metric.height);
      final line = LineBox(
        start: boundary.start,
        end: boundary.end,
        top: top,
        height: lineHeight,
        baseline: top + metric.ascent,
        width: math.max(0, metric.width).toDouble(),
        spacing:
            measured?.spacing ??
            spacingPlan?.range(boundary.start, boundary.end),
      );
      lines.add(
        horizontal && inlineBoxMarks.isNotEmpty
            ? _withTrailingInlineSpacingWidth(
                line,
                sourceSpan,
                inlineBoxMarks,
                textScaleFactor,
              )
            : line,
      );
      top += lineHeight;
      if (steps == null || metricIndex % 16 == 15) yield false;
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
    final reflowedLines =
        style.whiteSpace != CssWhiteSpace.nowrap &&
            style.whiteSpace != CssWhiteSpace.pre
        ? _recoverTrailingLetterSpacingOrphan(
            lines: lines,
            text: text,
            width: contentWidth ?? width,
            style: style,
            runs: runs,
            baseStyle: baseStyle,
            textScaleFactor: textScaleFactor,
            leadingDistribution: leadingDistribution,
            paragraph: paragraph,
          )
        : lines;
    // Skia 会对放不下的 token 做逐字紧急断行，Chrome 则让 token 整段溢出：
    // 把「断点处没有合法断行机会」的相邻行合并回去（URL、right/bottom 等）。
    final mergedLines = guardRanges.isEmpty
        ? reflowedLines
        : _mergeUnbreakableLines(
            reflowedLines,
            measureText,
            baseStyle,
            textScaleFactor,
            guardRanges,
            paragraph: paragraph,
          );
    var truncated = _applyTextOverflow(
      lines: mergedLines,
      painter: painter,
      paragraph: paragraph,
      contentWidth: contentWidth ?? width,
      style: style,
      textScaleFactor: textScaleFactor,
      leadingDistribution: leadingDistribution,
    );
    final result = _applyInlineVerticalBoxes(
      _applyInlineBoxes(
        truncated,
        inlineBoxMarks,
        painter,
        sourceSpan: paragraph == null ? null : sourceSpan,
        text: text,
        baseStyle: baseStyle,
        style: style,
        textScaleFactor: textScaleFactor,
      ),
      runs,
      style,
      leadingDistribution,
      (scale: textScaleFactor, painter: painter),
    );
    work.painters.release(painter);
    work.result = result;
  }

  static Iterable<bool> _measurePaddedSegmentSteps(
    _TextLayoutWork<List<LineBox>> work,
    _PaddedSegment input,
  ) sync* {
    final lines = <LineBox>[];
    var cursor = 0;
    var top = 0.0;
    while (cursor < input.text.length) {
      final measured = _TextLayoutWork<LineBox>(work.painters);
      yield* _fitPaddedLineSteps(measured, input, cursor);
      final line = measured.result!;
      final end = cursor + line.end;
      lines.add(
        _shiftMeasuredLine(
          line,
          cursor,
          top,
        ).copyWith(isLastLine: end == input.text.length),
      );
      top += line.height;
      if (input.firstLineOnly) break;
      cursor = end;
      if (cursor < input.text.length && input.text.codeUnitAt(cursor) == 10) {
        cursor++;
      }
    }
    work.result = lines;
  }

  static Iterable<bool> _fitPaddedLineSteps(
    _TextLayoutWork<LineBox> work,
    _PaddedSegment input,
    int cursor,
  ) sync* {
    final left = _continuationPadding(input.runs, cursor, true) * input.scale;
    var right = 0.0;
    final measured = _TextLayoutWork<LineBox>(work.painters);
    while (true) {
      yield* _measurePaddedLineSteps(
        measured,
        input,
        cursor,
        math.max(1, input.width - left - right),
      );
      final needed =
          _continuationPadding(
            input.runs,
            cursor + measured.result!.end,
            false,
          ) *
          input.scale;
      if (needed <= right) break;
      right = needed;
    }
    work.result = _withContinuationPadding(measured.result!, left, right);
  }

  static LineBox _shiftMeasuredLine(LineBox line, int offset, double top) =>
      line.copyWith(
        start: line.start + offset,
        end: line.end + offset,
        top: top,
        inlineBoxes: [
          for (final box in line.inlineBoxes)
            InlineBoxPlacement(
              offset: box.offset + offset,
              left: box.left,
              width: box.width,
              height: box.height,
              ascent: box.ascent,
              descent: box.descent,
              spec: box.spec,
              vertical: box.vertical,
            ),
        ],
      );

  static Iterable<bool> _measurePaddedLineSteps(
    _TextLayoutWork<LineBox> work,
    _PaddedSegment input,
    int cursor,
    double width,
  ) sync* {
    var limit = math.min(input.text.length, cursor + _indentProbeChars);
    while (true) {
      final segment = _TextLayoutWork<List<LineBox>>(work.painters);
      yield* _measureSegmentSteps(
        segment,
        text: input.text.substring(cursor, limit),
        width: width,
        contentWidth: width,
        style: input.style,
        textScaleFactor: input.scale,
        leadingDistribution: input.leading,
        runs: _sliceRuns(input.runs, cursor, limit),
        inlineBoxMarks: [
          for (final mark in _shiftInlineBoxMarks(input.marks, cursor))
            if (mark.index < limit - cursor) mark,
        ],
        spacingBarriers: {
          for (final offset in input.barriers)
            if (offset >= cursor && offset < limit) offset - cursor,
        },
        firstLine: cursor == 0
            ? input.firstLine
            : input.text.codeUnitAt(cursor - 1) == 10,
        firstLineOnly: true,
        clonePadding: false,
      );
      final line = segment.result!.first;
      if (line.end < limit - cursor || limit == input.text.length) {
        work.result = line;
        return;
      }
      limit = math.min(input.text.length, cursor + (limit - cursor) * 2);
    }
  }

  static double _continuationPadding(
    List<StyledRun> runs,
    int offset,
    bool leading,
  ) {
    var width = 0.0;
    for (final run in runs) {
      final inside = leading
          ? run.start <= offset && offset < run.end
          : run.start < offset && offset <= run.end;
      final boundary = leading
          ? run.start == offset && run.inlineLeadingInset != 0
          : run.end == offset && run.inlineTrailingInset != 0;
      if (!inside || boundary) continue;
      width = math.max(
        width,
        leading ? run.inlinePadding.left : run.inlinePadding.right,
      );
    }
    return width;
  }

  static LineBox _withContinuationPadding(
    LineBox line,
    double left,
    double right,
  ) => line.copyWith(
    width: line.width + left + right,
    inlineBoxes: [
      if (left > 0)
        _paddingPlacement(line.start, 0, left, InlineSpacingEdge.leading),
      for (final box in line.inlineBoxes)
        InlineBoxPlacement(
          offset: box.offset,
          left: box.left + left,
          width: box.width,
          height: box.height,
          ascent: box.ascent,
          descent: box.descent,
          spec: box.spec,
          vertical: box.vertical,
        ),
      if (right > 0)
        _paddingPlacement(
          line.end,
          line.width + left,
          right,
          InlineSpacingEdge.trailing,
        ),
    ],
  );

  static InlineBoxPlacement _paddingPlacement(
    int offset,
    double left,
    double width,
    InlineSpacingEdge edge,
  ) => InlineBoxPlacement(
    offset: offset,
    left: left,
    width: width,
    height: 0,
    ascent: 0,
    descent: 0,
    spec: InlineBoxSpec(offset: offset, width: width, height: 0, payload: edge),
  );

  /// 收回被行尾字距挤到单独一行的末字。
  ///
  /// Skia 把正字距累计到行尾末字之后；当这一段不可见字距刚好让末字放不下时，
  /// 标题会出现只剩一个字的孤行。若去掉该字距后两行可合并，则按原字序收回，
  /// 不改字号或字距。
  static List<LineBox> _recoverTrailingLetterSpacingOrphan({
    required List<LineBox> lines,
    required String text,
    required double width,
    required ComputedStyle style,
    required List<StyledRun> runs,
    required TextStyle baseStyle,
    required double textScaleFactor,
    required TextLeadingDistribution leadingDistribution,
    required SpacedParagraph? paragraph,
  }) {
    if (lines.length < 2 ||
        style.isRtl ||
        style.writingMode != CssWritingMode.horizontalTb ||
        !width.isFinite) {
      return lines;
    }
    final previous = lines[lines.length - 2];
    final last = lines.last;
    if (previous.isHardBreak ||
        last.isHardBreak ||
        previous.end != last.start) {
      return lines;
    }
    final lastText = text.substring(last.start, last.end);
    if (lastText.characters.length != 1) {
      return lines;
    }
    final lastOffset = last.start + lastText.characters.first.length - 1;
    var lastStyle = baseStyle;
    for (final run in runs) {
      if (lastOffset >= run.start && lastOffset < run.end) {
        lastStyle = textStyleFor(
          run.style,
          leadingDistribution: leadingDistribution,
        );
        break;
      }
    }
    final trailingSpacing = (lastStyle.letterSpacing ?? 0) * textScaleFactor;
    if (trailingSpacing <= 0) {
      return lines;
    }
    final merged = paragraph?.measure(previous.start, last.end);
    final mergedWidth =
        (merged?.metrics.width ??
            _measureTextSpan(
              _measurementSpan(
                text.substring(previous.start, last.end),
                _shiftRuns(runs, previous.start, last.end),
                baseStyle,
                const <_InlineBoxMark>[],
                (
                  css: style,
                  scale: textScaleFactor,
                  leading: leadingDistribution,
                ),
              ),
              textScaleFactor,
            )) -
        trailingSpacing;
    if (mergedWidth > width + 0.5) {
      return lines;
    }
    return <LineBox>[
      ...lines.take(lines.length - 2),
      previous.copyWith(
        end: last.end,
        width: math.max(previous.width, mergedWidth),
        isLastLine: true,
        isHardBreak: false,
        spacing: merged?.spacing ?? previous.spacing,
      ),
    ];
  }

  /// 截取子串测量时把行内样式区间平移、裁剪到子串范围。
  static List<StyledRun> _shiftRuns(
    List<StyledRun> runs,
    int start,
    int end,
  ) => <StyledRun>[
    for (final run in runs)
      if (run.end > start && run.start < end)
        StyledRun(
          start: math.max(run.start, start) - start,
          end: math.min(run.end, end) - start,
          style: run.style,
          baselineShift: run.baselineShift,
          syntheticFontFallback: run.syntheticFontFallback,
          inlineLeadingInset: run.start >= start ? run.inlineLeadingInset : 0,
          inlineTrailingInset: run.end <= end ? run.inlineTrailingInset : 0,
          inlinePadding: run.inlinePadding,
        ),
  ];

  static double _measureTextSpan(InlineSpan span, double textScaleFactor) {
    final painter = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.linear(textScaleFactor),
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  static TextSpan _measurementSpan(
    String text,
    List<StyledRun> runs,
    TextStyle base,
    List<_InlineBoxMark> marks,
    ({ComputedStyle css, double scale, TextLeadingDistribution leading})
    context,
  ) {
    var span = runs.isEmpty
        ? TextSpan(text: text, style: base)
        : TextSpan(
            style: base,
            children: buildStyledSpans(
              text: text,
              start: 0,
              end: text.length,
              runs: runs,
              baseStyle: base,
              styleOf: (style) =>
                  textStyleFor(style, leadingDistribution: context.leading),
            ),
          );
    if (usesSyntheticSmallCaps(context.css) ||
        runs.any((run) => usesSyntheticSmallCaps(run.style))) {
      span = applySyntheticSmallCaps(span) as TextSpan;
    }
    return marks.isEmpty
        ? span
        : _inlineBoxSpans(
            text,
            base,
            marks,
            context.css,
            context.scale,
            sourceSpan: span,
          );
  }

  static PunctuationSpacing _punctuationPlan(
    String text,
    ComputedStyle style,
    List<StyledRun> runs,
    ({TextStyle base, TextLeadingDistribution leading, bool autospace}) context,
    Set<int> barriers,
  ) {
    final styles = <ComputedStyle, TextStyle>{style: context.base};
    TextStyle resolved(ComputedStyle css) =>
        styles[css] ??= textStyleFor(css, leadingDistribution: context.leading);
    return PunctuationSpacing(
      text: text,
      barriers: barriers,
      autospace: context.autospace,
      styleAt: (offset) {
        for (final run in runs) {
          if (run.start <= offset && offset < run.end) {
            return (
              css: run.style,
              text: resolved(run.style),
              baselineShift: run.baselineShift,
            );
          }
        }
        return (css: style, text: resolved(style), baselineShift: 0);
      },
    );
  }

  /// 合成小型大写会让 Skia 按混合字号算出偏高的行盒；CSS 行盒由参与该行
  /// 的所有行内盒行高取最大值决定（18px×1.6 与 22px×1.6 → 35.2px）。
  static double? _syntheticCapsLineHeight(
    ComputedStyle base,
    List<StyledRun> runs,
    int start,
    int end,
  ) {
    final hasSyntheticCaps =
        usesSyntheticSmallCaps(base) ||
        runs.any((run) => usesSyntheticSmallCaps(run.style));
    if (!hasSyntheticCaps || base.lineHeightFactor == null) {
      return null;
    }
    var height = base.lineHeight;
    for (final run in runs) {
      if (run.end <= start || run.start >= end) {
        continue;
      }
      if (run.style.lineHeightFactor != null && run.style.lineHeight > height) {
        height = run.style.lineHeight;
      }
    }
    return height;
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
          spacing: line.spacing?.remap(
            (offset) =>
                boxText.originalOffset(line.start + offset) -
                boxText.originalOffset(line.start),
          ),
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

  /// 普通行内元素的水平内边距和边框参与占宽；零高盒不撑高行盒。
  static Iterable<InlineBoxSpec> _inlineSpacingBoxes(
    List<StyledRun> runs,
    int length,
    double scale,
  ) sync* {
    for (final run in runs) {
      if (run.end <= run.start ||
          run.syntheticFontFallback && run.inlinePadding == EdgeInsets.zero) {
        continue;
      }
      final left = run.leadingInset;
      final right = run.trailingInset;
      if (left > 0) {
        yield InlineBoxSpec(
          offset: run.start.clamp(0, length),
          width: left * scale,
          height: 0,
          payload: InlineSpacingEdge.leading,
        );
      }
      if (right > 0) {
        yield InlineBoxSpec(
          offset: run.end.clamp(0, length),
          width: right * scale,
          height: 0,
          payload: InlineSpacingEdge.trailing,
        );
      }
    }
  }

  static Iterable<InlineBoxSpec> _firstLineSpacingBoxes(
    List<StyledRun> runs,
    List<StyledRun> firstLineRuns,
    int length,
    double scale,
  ) sync* {
    final body = <(int, InlineSpacingEdge), double>{};
    final first = <(int, InlineSpacingEdge), double>{};
    for (final (widths, source) in [(body, runs), (first, firstLineRuns)]) {
      for (final box in _inlineSpacingBoxes(source, length, scale)) {
        final key = (box.offset, box.payload! as InlineSpacingEdge);
        widths[key] = (widths[key] ?? 0) + box.width;
      }
    }
    // 一侧为零也保留同一占位符，防止两套度量的原文偏移或首尾边界错位。
    for (final key in {...body.keys, ...first.keys}) {
      yield _FirstLineSpacingBoxSpec(
        offset: key.$1,
        width: body[key] ?? 0,
        firstLineWidth: first[key] ?? 0,
        edge: key.$2,
      );
    }
  }

  /// 原文 [offset] 前一个字簇的起始下标。
  static int _previousCharacterOffset(String text, int offset) {
    if (offset <= 0) {
      return 0;
    }
    final prefix = text.substring(0, math.min(offset, text.length));
    if (prefix.isEmpty) {
      return 0;
    }
    return prefix.length - prefix.characters.last.length;
  }

  /// 构造行内盒占位文本：插入或复用图片原占位符，并给出原文偏移映射。
  static _InlineBoxText _buildInlineBoxText(
    String text,
    List<InlineBoxSpec> specs, {
    Set<int> forcedBreaks = const <int>{},
  }) {
    // 空盒可能共享偏移；以输入顺序打破平局，避免不稳定排序打乱文档顺序。
    final ordered = [for (var i = 0; i < specs.length; i++) (i, specs[i])]
      ..sort((a, b) {
        final offsetOrder = a.$2.offset.compareTo(b.$2.offset);
        if (offsetOrder != 0) return offsetOrder;
        final edgeOrder = _inlineBoxOrder(a.$2)
            .compareTo(_inlineBoxOrder(b.$2));
        return edgeOrder == 0 ? a.$1.compareTo(b.$1) : edgeOrder;
      });
    final buffer = StringBuffer();
    final offsets = <int>[0];
    final marks = <_InlineBoxMark>[];
    var cursor = 0;
    void writeUntil(int stop) {
      for (var i = cursor; i < stop; i++) {
        if (i > 0 && forcedBreaks.contains(i)) {
          buffer.write('\n');
          offsets.add(i);
        }
        buffer.write(text[i]);
        offsets.add(i + 1);
      }
      cursor = stop;
    }

    for (final (_, spec) in ordered) {
      final stop = spec.offset.clamp(cursor, text.length);
      writeUntil(stop);
      // 盒放不下时先在容器内强制换行（CSS inline-block 整体换行）。
      if (forcedBreaks.contains(stop)) {
        buffer.write('\n');
        offsets.add(stop);
      }
      if (spec.payload == InlineSpacingEdge.trailing) {
        buffer.write('\u2060');
        offsets.add(stop);
      }
      buffer.write(_inlineBoxPlaceholder);
      marks.add(_InlineBoxMark(index: buffer.length - 1, spec: spec));
      // 图片复用原文占位符；普通行内块仍只插入盒、不消耗原文字。
      cursor =
          spec.replacesPlaceholder &&
              stop < text.length &&
              text.codeUnitAt(stop) == 0xFFFC
          ? stop + 1
          : stop;
      offsets.add(cursor);
      if (spec.payload == InlineSpacingEdge.leading) {
        buffer.write('\u2060');
        offsets.add(cursor);
      }
    }
    writeUntil(text.length);
    return _InlineBoxText(
      text: buffer.toString(),
      offsets: offsets,
      marks: marks,
    );
  }

  static int _inlineBoxOrder(InlineBoxSpec box) => switch (box.payload) {
    InlineSpacingEdge.trailing => 0,
    InlineSpacingEdge.leading => 1,
    _ => 2,
  };

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
  /// 原文、连接符和占位符共用游标，保留线性拼接以避免拆分后漏算或重复偏移。
  static TextSpan _inlineBoxSpans(
    String text,
    TextStyle baseStyle,
    List<_InlineBoxMark> marks,
    ComputedStyle style,
    double textScaleFactor, {
    TextSpan? sourceSpan,
  }) {
    final placeholderAdvance = _measureChar(
      _inlineBoxPlaceholder,
      style,
      textScaleFactor,
    );
    final children = <InlineSpan>[];
    final controlStyle = baseStyle.copyWith(
      fontFamily: 'sans-serif',
      fontFamilyFallback: const [],
      fontSize: 0,
      letterSpacing: 0,
      wordSpacing: 0,
    );
    var cursor = 0;
    for (final mark in marks) {
      final index = mark.index.clamp(0, text.length);
      // 内边距的零宽连接符属于测量占位，不能继承两侧不同的书内字体。
      // 否则缺控制字形的子集字体会形成孤立 run，使 Skia 行度量原生崩溃。
      // 连接符使用零字号、零字距，不影响原文字体的行高或占位宽度。
      final start = mark.spec.payload == InlineSpacingEdge.trailing && index > 0
          ? index - 1
          : index;
      final end =
          mark.spec.payload == InlineSpacingEdge.leading &&
              index + 1 < text.length
          ? index + 2
          : index + 1;
      if (start > cursor) {
        children.add(
          sourceSpan == null
              ? TextSpan(text: text.substring(cursor, start), style: baseStyle)
              : sliceTextSpan(sourceSpan, cursor, start),
        );
      }
      if (start < index) {
        children.add(
          TextSpan(text: text.substring(start, index), style: controlStyle),
        );
      }
      final spacing =
          (mark.spec.outerWidth - placeholderAdvance) / textScaleFactor;
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
      if (end > index + 1) {
        children.add(
          TextSpan(text: text.substring(index + 1, end), style: controlStyle),
        );
      }
      cursor = end;
    }
    if (cursor < text.length) {
      children.add(
        sourceSpan == null
            ? TextSpan(text: text.substring(cursor), style: baseStyle)
            : sliceTextSpan(sourceSpan, cursor, text.length),
      );
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
    TextSpan? sourceSpan,
  }) {
    if (marks.isEmpty || lines.isEmpty) {
      return lines;
    }
    final perLine = List<List<InlineBoxPlacement>>.generate(
      lines.length,
      (_) => <InlineBoxPlacement>[],
    );
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
      final dx = sourceSpan != null
          ? _linePrefixAdvance(sourceSpan, line, mark.index, textScaleFactor)
          : _prefixAdvance(
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
      // 优先使用调用方测得的末行基线；缺失时仍按外部字体近似下沉量。
      final spec = mark.spec;
      final contentHeight = spec.contentHeight ?? spec.height;
      final boxHeight = math.max(spec.outerHeight, contentHeight);
      var ascent = spec.ascent;
      var descent = spec.descent;
      if (spec.verticalAlign == InlineBoxVerticalAlign.baseline) {
        final declaredBaseline = spec.contentBaseline;
        if (declaredBaseline != null) {
          // 距离相对边框盒顶；无行或非 visible 时由调用方提供底部 margin。
          ascent = spec.marginTop + declaredBaseline - spec.baselineOffset;
          // 末行基线可能在边框盒外；溢出不改变 margin 盒，延伸可为负。
          descent = spec.outerHeight - ascent;
        } else {
          final metrics = _fontBoxMetrics(baseStyle, textScaleFactor);
          final fontBoxHeight = metrics.ascent + metrics.descent;
          final halfLeading = math.max(0.0, (line.height - fontBoxHeight) / 2);
          final sink = math.min(contentHeight, halfLeading + metrics.descent);
          ascent =
              spec.marginTop + (contentHeight - sink) - spec.baselineOffset;
          descent = math.max(0.0, boxHeight - ascent);
        }
      } else if (spec.verticalAlign == InlineBoxVerticalAlign.middle) {
        final halfXHeight = _xHeightFor(style) * textScaleFactor / 2;
        ascent += halfXHeight;
        descent -= halfXHeight;
      }
      final placement = InlineBoxPlacement(
        offset: mark.index,
        left: line.offsetX + math.max(0.0, dx) + spec.marginLeft,
        width: spec.width,
        height: spec.height,
        ascent: ascent,
        descent: descent,
        spec: spec,
      );
      perLine[lineIndex].add(placement);
    }
    // 实测基线和 middle 按 CSS 2.2 §10.8 合成上下边缘，包含文字 strut；
    // 其余对齐保留原有近似，避免推测未声明基线的盒内结构。
    final heights = List<double>.filled(lines.length, 0);
    final ascents = List<double>.filled(lines.length, 0);
    for (var i = 0; i < lines.length; i++) {
      var boxHeight = 0.0;
      var boxAscent = 0.0;
      var boxDescent = 0.0;
      var includeTextStrut = false;
      for (final placement in perLine[i]) {
        boxHeight = math.max(boxHeight, placement.ascent + placement.descent);
        boxAscent = math.max(boxAscent, placement.ascent);
        boxDescent = math.max(boxDescent, placement.descent);
        includeTextStrut |=
            placement.spec.verticalAlign == InlineBoxVerticalAlign.middle ||
            (placement.spec.contentBaseline != null &&
                placement.spec.verticalAlign ==
                    InlineBoxVerticalAlign.baseline);
      }
      final baseAscent = lines[i].baseline - lines[i].top;
      heights[i] = includeTextStrut
          ? math.max(baseAscent, boxAscent) +
                math.max(lines[i].height - baseAscent, boxDescent)
          : math.max(lines[i].height, boxHeight);
      ascents[i] = math.min(heights[i], math.max(baseAscent, boxAscent));
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
          spacing: line.spacing,
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

  /// 行末尾盒前的 WORD JOINER 会让部分字体忽略占位符的负字距，
  /// 把原字形宽带入行宽；改用前缀的实际 advance 加连续尾盒的真实宽度。
  static LineBox _withTrailingInlineSpacingWidth(
    LineBox line,
    TextSpan source,
    List<_InlineBoxMark> marks,
    double scale,
  ) {
    final last = marks.lastIndexWhere((mark) => mark.index < line.end);
    if (last < 0 ||
        marks[last].index < line.start ||
        marks[last].index + 1 != line.end ||
        marks[last].spec.payload != InlineSpacingEdge.trailing) {
      return line;
    }
    var first = last;
    var width = marks[last].spec.outerWidth;
    while (first > 0) {
      final previous = marks[first - 1];
      // 相邻尾盒之间只有 _buildInlineBoxText 固定插入的 WORD JOINER。
      if (previous.index < line.start ||
          previous.spec.payload != InlineSpacingEdge.trailing ||
          previous.index + 2 != marks[first].index) {
        break;
      }
      width += previous.spec.outerWidth;
      first--;
    }
    return line.copyWith(
      width: math.max(
        0.0,
        _linePrefixAdvance(source, line, marks[first].index, scale) + width,
      ),
    );
  }

  static double _linePrefixAdvance(
    TextSpan span,
    LineBox line,
    int end,
    double scale,
  ) {
    final source = sliceTextSpan(span, line.start, line.end);
    final spaced = line.spacing == null
        ? source
        : applyTextSpacing(source, line.spacing!);
    final painter = TextPainter(
      text: sliceTextSpan(spaced, 0, end - line.start),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.linear(scale),
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
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
    SpacedParagraph? paragraph,
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
      if (paragraph != null) {
        result.add(
          _truncateSpacedLine(line, paragraph, available, ellipsisAdvance),
        );
        changed = true;
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

  static LineBox _truncateSpacedLine(
    LineBox line,
    SpacedParagraph paragraph,
    double available,
    double ellipsis,
  ) {
    final text = paragraph.text.substring(line.start, line.end);
    final boundaries = <int>[line.start];
    for (final cluster in text.characters) {
      boundaries.add(boundaries.last + cluster.length);
    }
    var low = 0;
    var high = boundaries.length - 1;
    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      if (paragraph
              .measure(line.start, boundaries[mid], trimEnd: false)
              .metrics
              .width <=
          available) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    final prefix = paragraph.measure(
      line.start,
      boundaries[low],
      trimEnd: false,
    );
    return line.copyWith(
      end: prefix.end,
      width: prefix.metrics.width + ellipsis,
      spacing: prefix.spacing,
      ellipsized: true,
      ellipsisWidth: ellipsis,
    );
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
    ({double scale, TextPainter painter}) measurement,
  ) {
    if (!runs.any(
      (run) => run.baselineShift != 0 || run.inlinePadding.vertical > 0,
    )) {
      return lines;
    }
    final growUps = List<double>.filled(lines.length, 0, growable: false);
    final growDowns = List<double>.filled(lines.length, 0, growable: false);
    final metrics = <ComputedStyle, _InlineBoxMetrics>{};
    final lineMetrics = measurement.painter.computeLineMetrics();
    var grew = false;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final ascent = line.baseline - line.top;
      final descent = line.height - ascent;
      for (final run in runs) {
        if (run.baselineShift == 0 && run.inlinePadding.vertical == 0) {
          continue;
        }
        if (math.min(run.end, line.end) <= math.max(run.start, line.start)) {
          continue;
        }
        final box = metrics[run.style] ??= _inlineBoxMetrics(
          run.style,
          leadingDistribution,
        );
        final padding = run.inlinePadding * measurement.scale;
        var above = box.ascent;
        var below = box.descent;
        if (padding.vertical > 0) {
          final baseline = lineMetrics[i].baseline;
          for (final glyph in measurement.painter.getBoxesForSelection(
            TextSelection(
              baseOffset: math.max(run.start, line.start),
              extentOffset: math.min(run.end, line.end),
            ),
          )) {
            above = math.max(above, baseline - glyph.top + padding.top);
            below = math.max(below, glyph.bottom - baseline + padding.bottom);
          }
        }
        final top = run.baselineShift - above;
        final bottom = run.baselineShift + below;
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
          spacing: line.spacing,
          inlineBoxes: line.inlineBoxes,
          ellipsized: line.ellipsized,
          ellipsisWidth: line.ellipsisWidth,
          hyphenated: line.hyphenated,
          hyphenWidth: line.hyphenWidth,
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
          syntheticFontFallback: run.syntheticFontFallback,
          inlineLeadingInset: run.inlineLeadingInset,
          inlineTrailingInset: run.inlineTrailingInset,
          inlinePadding: run.inlinePadding,
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

  /// x-height（`vertical-align: middle` 用）。
  ///
  /// `font-size-adjust` 的目标正是把 x-height 固定为「ratio × font-size」；
  /// 未声明时 Flutter 没有暴露字体 x-height，仍用 CJK 字体约 0.5em 的近似。
  static double _xHeightFor(ComputedStyle style) =>
      style.fontSize * (style.fontSizeAdjust ?? 0.5);

  /// 合并「非法断点」处的紧急断行：token 内不换行（与 Chrome 一致）。
  static List<LineBox> _mergeUnbreakableLines(
    List<LineBox> lines,
    String text,
    TextStyle baseStyle,
    double textScaleFactor,
    List<(int, int)> guardRanges, {
    SpacedParagraph? paragraph,
  }) {
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
      if (paragraph != null) {
        final combined = paragraph.measure(current.start, next.end);
        current = current.copyWith(
          end: next.end,
          width: combined.metrics.width,
          spacing: combined.spacing,
          isLastLine: next.isLastLine,
          isHardBreak: next.isHardBreak,
        );
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
          spacing: line.spacing,
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

  /// 字体盒（不含 leading）的 ascent/descent：用于行盒基线与 half-leading 解算。
  ///
  /// `height` 置空后 `preferredLineHeight` 即字体盒高（Chrome 的
  /// fontBoundingBoxAscent/Descent 同口径，实测 17px 内置宋 = 20/5）。
  static ({double ascent, double descent}) _fontBoxMetrics(
    TextStyle baseStyle,
    double textScaleFactor,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: 'x', style: baseStyle.copyWith(height: null)),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.linear(textScaleFactor),
    )..layout();
    final ascent = painter.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    final descent = math.max(0.0, painter.height - ascent);
    painter.dispose();
    return (ascent: ascent, descent: descent);
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
      // token 边界只取 ASCII 可见字符：`16px/1.6，中文…` 这类不能整段变
      // 成不可断 token（CJK/全角标点/空白都视为边界）。
      var start = i;
      while (start > 0 && _isGuardTokenChar(text[start - 1])) {
        start -= 1;
      }
      var end = i + 1;
      while (end < text.length && _isGuardTokenChar(text[end])) {
        end += 1;
      }
      ranges.add((start, end));
    }
    return _mergeRanges(ranges);
  }

  /// 是否 token 内字符（ASCII 可见字符）：守卫只在这类 token 内部生效。
  static bool _isGuardTokenChar(String char) {
    final code = char.codeUnitAt(0);
    return code > 0x20 && code < 0x7F;
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
    List<StyledRun> runs = const [],
  }) {
    final metrics = <VerticalGlyphMetric>[];
    ComputedStyle styleAt(int offset) =>
        runs
            .where((run) => offset >= run.start && offset < run.end)
            .map((run) => run.style)
            .firstOrNull ??
        style;
    var offset = 0;
    for (final rune in text.runes) {
      final length = rune > 0xFFFF ? 2 : 1;
      final char = String.fromCharCode(rune);
      final upright = switch (style.textOrientation) {
        CssTextOrientation.upright => true,
        CssTextOrientation.sideways => false,
        CssTextOrientation.mixed => _isUprightRune(rune),
      };
      final runStyle = styleAt(offset);
      final advance = upright
          ? runStyle.fontSize
          : _measureChar(char, runStyle, textScaleFactor);
      metrics.add(
        VerticalGlyphMetric(
          start: offset,
          end: offset + length,
          advance: math.max(
            0,
            advance +
                (runStyle.layoutFingerprint != style.layoutFingerprint
                    ? runStyle.letterSpacing
                    : 0),
          ),
          upright: upright,
        ),
      );
      offset += length;
    }
    // 縦中横（CSS Writing Modes §9.1 `text-combine-upright`）：连续 2–4 位
    // 数字合并成一个正立块，纵向只占 1em（网页正文里的年份/编号「2024」）。
    if (style.textCombine != CssTextCombine.none && metrics.length > 1) {
      final combined = <VerticalGlyphMetric>[];
      var index = 0;
      while (index < metrics.length) {
        if (!_isDigitSpan(text, metrics[index])) {
          combined.add(metrics[index]);
          index += 1;
          continue;
        }
        var end = index;
        while (end < metrics.length &&
            end - index < 4 &&
            _isDigitSpan(text, metrics[end])) {
          end += 1;
        }
        final count = end - index;
        if (count < 2) {
          combined.add(metrics[index]);
          index += 1;
          continue;
        }
        final runStyle = styleAt(metrics[index].start);
        combined.add(
          VerticalGlyphMetric(
            start: metrics[index].start,
            end: metrics[end - 1].end,
            advance: math.max(
              0,
              runStyle.fontSize +
                  (runStyle.layoutFingerprint != style.layoutFingerprint
                      ? runStyle.letterSpacing
                      : 0),
            ),
            upright: true,
            combine: true,
          ),
        );
        index = end;
      }
      return combined;
    }
    return metrics;
  }

  /// 该度量是否单个半角数字（縦中横只合并数字；`digits` 与 `all` 同口径）。
  static bool _isDigitSpan(String text, VerticalGlyphMetric metric) {
    if (metric.end != metric.start + 1 || metric.end > text.length) {
      return false;
    }
    final code = text.codeUnitAt(metric.start);
    return code >= 0x30 && code <= 0x39;
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
  /// - 列长与绘制使用同一套逐字纵向度量，包含正立空格与行内字号；
  /// - `vertical-rl` 首列在最右（列从右向左推进），`vertical-lr` 在左；
  /// - 块宽 = 列数 × 列宽，块高 = 最长列；行内 `top` 恒为 0。
  static TextLayoutResult _verticalFromLines({
    required String text,
    required List<LineBox> lines,
    required ComputedStyle style,
    required double maxWidth,
    required List<StyledRun> runs,
    required bool isRtl,
    ComputedStyle? firstLineStyle,
    List<StyledRun>? firstLineRuns,
    List<StyledRun>? sourceRuns,
    TextOffsetMap? inputOffsets,
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
    final metrics = verticalGlyphMetrics(text, style, runs: runs);
    final rl = style.writingMode == CssWritingMode.verticalRl;
    final columns = <LineBox>[];
    var longest = 0.0;
    var metricIndex = 0;
    for (var i = 0; i < count; i++) {
      final line = lines[i];
      final columnX = rl ? (count - 1 - i) * columnWidth : i * columnWidth;
      // 竖排逐字绘制使用纵向 advance；横排字宽不能作为含空格、正立拉丁字的盒高。
      var extent = 0.0;
      while (metricIndex < metrics.length &&
          metrics[metricIndex].start < line.end) {
        final metric = metrics[metricIndex++];
        if (metric.start >= line.start) extent += metric.advance;
      }
      extent += line.ellipsized
          ? line.ellipsisWidth
          : (line.hyphenated ? line.hyphenWidth : 0);
      longest = math.max(longest, extent);
      columns.add(
        LineBox(
          start: line.start,
          end: line.end,
          top: 0,
          height: extent,
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
      plainTextLayout: !_runsAffectTextLayout(runs, style),
      firstLineStyle: firstLineStyle,
      firstLineRuns: firstLineRuns,
      sourceRuns: sourceRuns,
      inputOffsets: inputOffsets,
    );
  }

  static TextLayoutResult _result(
    String text,
    List<LineBox> lines,
    double maxWidth,
    List<StyledRun> runs,
    ComputedStyle style, {
    bool isRtl = false,
    double bottomOverflow = 0,
    ComputedStyle? firstLineStyle,
    List<StyledRun>? firstLineRuns,
    List<StyledRun>? sourceRuns,
    TextOffsetMap? inputOffsets,
  }) {
    var maxLineWidth = 0.0;
    for (final line in lines) {
      maxLineWidth = math.max(maxLineWidth, line.width);
    }
    final height = lines.isEmpty ? 0.0 : lines.last.bottom + bottomOverflow;
    return TextLayoutResult(
      text: text,
      lines: List<LineBox>.unmodifiable(lines),
      width: maxLineWidth,
      height: height,
      maxWidth: maxWidth,
      runs: List<StyledRun>.unmodifiable(runs),
      isRtl: isRtl,
      plainTextLayout: !_runsAffectTextLayout(runs, style),
      firstLineStyle: firstLineStyle,
      firstLineRuns: firstLineRuns,
      sourceRuns: sourceRuns,
      inputOffsets: inputOffsets,
    );
  }

  /// runs 是否改变了文本测量；颜色、装饰等不影响排版的属性除外。
  static bool _runsAffectTextLayout(List<StyledRun> runs, ComputedStyle style) {
    for (final run in runs) {
      if (run.baselineShift != 0 ||
          run.inlinePadding != EdgeInsets.zero ||
          run.style.layoutFingerprint != style.layoutFingerprint) {
        return true;
      }
    }
    return false;
  }

  /// 从计算样式生成绘制/测量用 TextStyle。
  /// `font-variant-caps` → OpenType 特性标签。
  ///
  /// - `small-caps` = `smcp`；`all-small-caps` = `smcp` + `c2sc`（大写字母也转小号大写）
  /// - `petite-caps` = `pcap`；`all-petite-caps` = `pcap` + `c2pc`
  /// - `unicase` = `unic`；`titling-caps` = `titl`；`normal` 不加特性
  static List<FontFeature>? _fontFeatures(ComputedStyle style) {
    final features = <FontFeature>[
      ...switch (style.fontVariantCaps) {
        CssFontVariantCaps.normal => const <FontFeature>[],
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
      },
    ];
    final disableLigatures =
        style.fontVariantLigatures == CssFontVariantLigatures.none;
    if (disableLigatures) {
      features.addAll(const <FontFeature>[
        FontFeature.disable('liga'),
        FontFeature.disable('clig'),
      ]);
    }
    if (style.fontKerning == CssFontKerning.none) {
      features.add(const FontFeature.disable('kern'));
    }
    // 作者显式特性最后追加，同标签可覆盖上面由 font-variant/kerning
    // 推导出的默认值。
    for (final setting in style.fontFeatureSettings) {
      features.add(FontFeature(setting.tag, setting.value));
    }
    return features.isEmpty ? null : features;
  }

  static TextStyle textStyleFor(
    ComputedStyle style, {
    TextLeadingDistribution leadingDistribution = TextLeadingDistribution.even,
    bool applyFontSizeAdjust = true,
  }) {
    final fontSize = applyFontSizeAdjust
        ? _adjustedFontSize(style)
        : style.fontSize;
    return TextStyle(
      fontSize: fontSize,
      // 数值 line-height 按 CSS font-size 的原值计算，不随 x-height 调整放大；
      // 换成调整后字号的相对倍数，保持行距不变。
      height: style.lineHeightFactor == null || fontSize <= 0
          ? null
          : style.lineHeight / fontSize,
      leadingDistribution: leadingDistribution,
      // 小型大写（`font-variant-caps`）：CSS 的 caps 族映射到 OpenType 特性，
      // 测量与绘制共用本方法，因此宽度与字形两端一致；字体缺特性时不生效。
      fontFeatures: _fontFeatures(style),
      // CSS `font-stretch` 直接映射可变字体的宽度轴。静态字体没有 `wdth`
      // 轴时 Flutter 会忽略该设置；浏览器同样不会对静态字体做几何拉伸。
      fontVariations: style.fontStretch == 100
          ? null
          : <FontVariation>[FontVariation('wdth', style.fontStretch)],
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
  }

  /// CSS `font-size-adjust` 的 used font-size。
  ///
  /// 内置宋体与运行期书籍字体使用注册的真实 x-height；其余字体按 CJK
  /// 字体常见的 0.5em aspect ratio 近似。
  static double _adjustedFontSize(ComputedStyle style) {
    final adjust = style.fontSizeAdjust;
    if (adjust == null ||
        !adjust.isFinite ||
        adjust <= 0 ||
        style.fontSize <= 0) {
      return style.fontSize;
    }
    final xHeightRatio =
        FontMetricsRegistry.xHeightRatio(style.fontFamily) ?? 0.5;
    return style.fontSize * adjust / xHeightRatio;
  }

  static TextDecorationStyle _decorationStyle(CssTextDecorationStyle value) =>
      switch (value) {
        CssTextDecorationStyle.solid => TextDecorationStyle.solid,
        CssTextDecorationStyle.double => TextDecorationStyle.double,
        CssTextDecorationStyle.dotted => TextDecorationStyle.dotted,
        CssTextDecorationStyle.dashed => TextDecorationStyle.dashed,
        CssTextDecorationStyle.wavy => TextDecorationStyle.wavy,
      };

  static TextDecoration _decoration(CssTextDecoration value) {
    final decorations = [
      if (value.hasUnderline) TextDecoration.underline,
      if (value.hasLineThrough) TextDecoration.lineThrough,
      if (value.hasOverline) TextDecoration.overline,
    ];
    return decorations.isEmpty
        ? TextDecoration.none
        : TextDecoration.combine(decorations);
  }

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

/// 单次文字测量的临时状态；同步和异步驱动器共用同一算法与资源所有权。
class _TextLayoutWork<T> {
  _TextLayoutWork([_LayoutPainters? painters])
    : painters = painters ?? _LayoutPainters();

  final _LayoutPainters painters;
  T? result;
}

class _LayoutPainters {
  final _owned = <TextPainter>{};

  TextPainter own(TextPainter painter) {
    _owned.add(painter);
    return painter;
  }

  void release(TextPainter painter) {
    if (_owned.remove(painter)) painter.dispose();
  }

  void dispose() {
    for (final painter in _owned) {
      painter.dispose();
    }
    _owned.clear();
  }
}
