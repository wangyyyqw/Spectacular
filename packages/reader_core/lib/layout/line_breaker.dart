import 'dart:math' as math;
import 'dart:ui' show BoxHeightStyle;

import 'package:flutter/painting.dart';

import '../css/computed_style.dart';
import '../src/api/models.dart' show TextLayout;
import 'cjk_justify.dart';
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

  /// 行底。
  double get bottom => top + height;

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
  }) => LineBox(
    start: start ?? this.start,
    end: end ?? this.end,
    top: top ?? this.top,
    height: height,
    baseline: baseline,
    width: width,
    indent: indent ?? this.indent,
    isLastLine: isLastLine ?? this.isLastLine,
    isHardBreak: isHardBreak ?? this.isHardBreak,
    offsetX: offsetX ?? this.offsetX,
    justifyExtra: justifyExtra ?? this.justifyExtra,
  );

  @override
  String toString() =>
      'LineBox($start..$end, top=$top, h=$height, baseline=$baseline, w=$width, '
      'indent=$indent, last=$isLastLine, hard=$isHardBreak, x=$offsetX, '
      'justify=$justifyExtra)';
}

/// 行内样式区间：为文本 `[start, end)` 指定独立计算样式。
///
/// 混排字号、上下标、超出行高的行内元素都用它表达；区间必须升序且不重叠，
/// 未覆盖的部分沿用块的样式。
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

  /// 行数。
  int get lineCount => lines.length;
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
  /// 宽度低于 3em 时钳制到 3em；无限宽保持单行断行。
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
  }) {
    // nowrap/pre 不软换行：按无限宽测量，得到单行（硬换行仍生效）。
    final wraps =
        style.whiteSpace != CssWhiteSpace.nowrap &&
        style.whiteSpace != CssWhiteSpace.pre;
    final width = wraps ? effectiveWidth(style, maxWidth) : double.infinity;
    return TextLayoutEngine._layoutRaw(
      text: text,
      style: style,
      maxWidth: width,
      textScaleFactor: textScaleFactor,
      leadingDistribution: leadingDistribution,
      runs: runs,
      hasGlyph: hasGlyph,
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
  }) {
    return (lineBreaker ?? LineBreaker()).layout(
      text: text,
      style: style,
      maxWidth: maxWidth,
      textScaleFactor: textScaleFactor,
      leadingDistribution: leadingDistribution,
      runs: runs,
      hasGlyph: hasGlyph,
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
  }) {
    // text-transform 在测量前应用：layout.text 即变换后的文本，绘制直接用。
    text = applyTextTransform(text, style.textTransform);
    final width = maxWidth.isFinite ? math.max(1.0, maxWidth) : double.infinity;
    final indent = width.isFinite
        ? style.textIndent.clamp(0.0, math.max(0.0, width - 1)).toDouble()
        : 0.0;
    final ordered = _normalizeRuns(runs, text.length);
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
    final measured = measuredText.isEmpty || indent <= 0
        ? _measureSegment(
            text: measuredText,
            width: width,
            style: style,
            textScaleFactor: textScaleFactor,
            leadingDistribution: leadingDistribution,
            runs: styled,
          )
        : _measureWithIndent(
            text: measuredText,
            width: width,
            indent: indent,
            style: style,
            textScaleFactor: textScaleFactor,
            leadingDistribution: leadingDistribution,
            runs: styled,
          );
    return _result(
      text,
      _align(measuredText, measured, style, width),
      width,
      styled,
    );
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
    required double indent,
    required ComputedStyle style,
    required double textScaleFactor,
    required TextLeadingDistribution leadingDistribution,
    List<StyledRun> runs = const <StyledRun>[],
  }) {
    final firstWidth = math.max(1.0, width - indent);
    final head = _measureSegment(
      text: text,
      width: firstWidth,
      style: style,
      textScaleFactor: textScaleFactor,
      leadingDistribution: leadingDistribution,
      runs: runs,
    );
    if (head.isEmpty) {
      return const <LineBox>[];
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
  /// justify 的末行与硬换行行按 start 对齐，不拉伸。
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
    final aligned = <LineBox>[];
    for (final line in lines) {
      final slack = width.isFinite
          ? math.max(0.0, width - line.indent - line.width)
          : 0.0;
      aligned.add(switch (style.textAlign) {
        CssTextAlign.start ||
        CssTextAlign.left => line.copyWith(offsetX: line.indent),
        CssTextAlign.end ||
        CssTextAlign.right => line.copyWith(offsetX: line.indent + slack),
        CssTextAlign.center => line.copyWith(offsetX: line.indent + slack / 2),
        CssTextAlign.justify => line.copyWith(
          offsetX: line.indent,
          justifyExtra: _justifyExtra(
            text,
            line,
            slack,
            hanging: hanging,
            punctWidthOf: punctWidthOf,
          ),
        ),
      });
    }
    return aligned;
  }

  /// 该行可用于 justify 的余量；没有可拉伸间隙时返回 0。
  ///
  /// 悬挂开启且行尾为悬挂句读时，余量加句读宽度（P7-18）。
  static double _justifyExtra(
    String text,
    LineBox line,
    double slack, {
    required bool hanging,
    required double Function(String) punctWidthOf,
  }) {
    if (slack < 0 || line.isLastLine || line.isHardBreak) {
      return 0;
    }
    final lineText = text.substring(line.start, line.end);
    final gaps = cjkJustifyGapOffsets(lineText);
    if (gaps.isEmpty) {
      return 0;
    }
    if (hanging && lineText.isNotEmpty) {
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

  /// 单字符 advance 测量（悬挂余量用；每次 layout 内缓存）。
  static double _measureChar(String char, ComputedStyle style) {
    final painter = TextPainter(
      text: TextSpan(
        text: char,
        style: textStyleFor(style, leadingDistribution: TextLeadingDistribution.even),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  /// 挤压 span（P7-19）：相邻全角标点的前标点加 -0.5em 字距。
  static TextSpan _compressedSpan(
    String text,
    ComputedStyle style,
    TextStyle baseStyle,
    double textScaleFactor,
  ) {
    final offsets = punctCompressionOffsets(
      text,
      em: style.fontSize,
      advanceOf: punctAdvanceMeasurer(baseStyle, textScaleFactor),
    );
    if (offsets.isEmpty) {
      return TextSpan(text: text, style: baseStyle);
    }
    final spacing = punctCompressionSpacing(style.fontSize);
    final starts = offsets.toSet();
    final children = <InlineSpan>[];
    var offset = 0;
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      final isStart = starts.contains(offset);
      children.add(
        TextSpan(
          text: char,
          style: isStart
              ? baseStyle.copyWith(
                  letterSpacing: (baseStyle.letterSpacing ?? 0) + spacing,
                )
              : baseStyle,
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
  }) {
    final baseStyle = textStyleFor(
      style,
      leadingDistribution: leadingDistribution,
    );
    // 标点挤压（P7-19）：只作用于无行内样式区间的纯文本段（测量与
    // 绘制同规则，见 buildLineSpan）；挤压影响行宽，须在测量期生效。
    final compress =
        runs.isEmpty &&
        style.textSpacingTrim == CssTextSpacingTrim.trimAdjacent;
    final painter = TextPainter(
      text: runs.isEmpty
          ? (compress
                ? _compressedSpan(text, style, baseStyle, textScaleFactor)
                : TextSpan(text: text, style: baseStyle))
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
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.linear(textScaleFactor),
    )..layout(maxWidth: width);

    final metrics = painter.computeLineMetrics();
    final lines = <LineBox>[];
    var top = 0.0;
    for (final metric in metrics) {
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
          height: metric.height,
          baseline: top + metric.ascent,
          width: math.max(0, metric.width).toDouble(),
        ),
      );
      top += metric.height;
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
    return _applyBorrowedLeading(painter, lines, runs);
  }

  /// 上下标借行距（P7-09，Reeden 630 号 §2-3 / fixups N5）：
  /// `baselineShift` 只平移墨迹，不参与行盒计算——墨迹越出所在行盒
  /// 才把该行撑高（先借后撑）。只在含 `baselineShift != 0` 的行调用
  /// `getBoxesForSelection` 取字形框：上下标区间短且低频，属 §8.2
  /// 「段落内小范围使用」的例外。
  static List<LineBox> _applyBorrowedLeading(
    TextPainter painter,
    List<LineBox> lines,
    List<StyledRun> runs,
  ) {
    if (!runs.any((run) => run.baselineShift != 0)) {
      return lines;
    }
    final growUps = List<double>.filled(lines.length, 0, growable: false);
    final growDowns = List<double>.filled(lines.length, 0, growable: false);
    var grew = false;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lineBottom = line.top + line.height;
      for (final run in runs) {
        if (run.baselineShift == 0) {
          continue;
        }
        final start = math.max(run.start, line.start);
        final end = math.min(run.end, line.end);
        if (end <= start) {
          continue;
        }
        final boxes = painter.getBoxesForSelection(
          TextSelection(baseOffset: start, extentOffset: end),
          boxHeightStyle: BoxHeightStyle.tight,
        );
        for (final box in boxes) {
          // 跨行 run 只统计落在本行的框。
          if (box.top >= lineBottom || box.bottom <= line.top) {
            continue;
          }
          final inkTop = box.top + run.baselineShift;
          final inkBottom = box.bottom + run.baselineShift;
          if (inkTop < line.top - 0.01) {
            growUps[i] = math.max(growUps[i], line.top - inkTop);
          }
          if (inkBottom > lineBottom + 0.01) {
            growDowns[i] = math.max(growDowns[i], inkBottom - lineBottom);
          }
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

  static TextLayoutResult _result(
    String text,
    List<LineBox> lines,
    double maxWidth,
    List<StyledRun> runs,
  ) {
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
    );
  }

  /// 从计算样式生成绘制/测量用 TextStyle。
  static TextStyle textStyleFor(
    ComputedStyle style, {
    TextLeadingDistribution leadingDistribution = TextLeadingDistribution.even,
  }) => TextStyle(
    fontSize: style.fontSize,
    height: style.lineHeightFactor,
    leadingDistribution: leadingDistribution,
    fontWeight: _fontWeight(style.fontWeight),
    fontStyle: style.italic ? FontStyle.italic : FontStyle.normal,
    fontFamily: style.fontFamily,
    fontFamilyFallback: style.fontFamilyFallback.isEmpty
        ? null
        : style.fontFamilyFallback,
    letterSpacing: style.letterSpacing,
    wordSpacing: style.wordSpacing,
    decoration: _decoration(style.textDecoration),
    decorationColor: style.color,
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

  static TextDecoration _decoration(CssTextDecoration value) => switch (value) {
    CssTextDecoration.none => TextDecoration.none,
    CssTextDecoration.underline => TextDecoration.underline,
    CssTextDecoration.lineThrough => TextDecoration.lineThrough,
    CssTextDecoration.overline => TextDecoration.overline,
  };

  static FontWeight _fontWeight(int weight) {
    final index = ((weight / 100).round() - 1).clamp(0, 8);
    return FontWeight.values[index];
  }
}
