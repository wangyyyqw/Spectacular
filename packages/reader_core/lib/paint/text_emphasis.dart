import 'package:flutter/painting.dart';
import 'package:flutter/widgets.dart' show StringCharacters;

import '../css/computed_style.dart';

import 'package:reader_core/layout/line_breaker.dart';

import 'line_spans.dart';

typedef _StyledCluster = ({
  int start,
  int end,
  ComputedStyle style,
  double shift,
});

/// 按 CSS 标准字形创建横排、竖排共用的着重号画笔；空字符串不绘制。
/// 返回的画笔已排版，调用方负责调用 [TextPainter.dispose] 释放资源。
TextPainter? createTextEmphasisPainter(ComputedStyle style, Color color) {
  final base = TextLayoutEngine.textStyleFor(style);
  final glyph = switch (style.textEmphasisStyle) {
    CssTextEmphasisStyle.dot => '\u2022',
    CssTextEmphasisStyle.openDot => '\u25e6',
    CssTextEmphasisStyle.circle => '\u25cf',
    CssTextEmphasisStyle.openCircle => '\u25cb',
    CssTextEmphasisStyle.doubleCircle => '\u25c9',
    CssTextEmphasisStyle.openDoubleCircle => '\u25ce',
    CssTextEmphasisStyle.triangle => '\u25b2',
    CssTextEmphasisStyle.openTriangle => '\u25b3',
    CssTextEmphasisStyle.sesame => '\ufe45',
    CssTextEmphasisStyle.openSesame => '\ufe46',
    CssTextEmphasisStyle.custom =>
      style.textEmphasisString?.characters.firstOrNull ?? '',
    CssTextEmphasisStyle.none => '',
  };
  if (glyph.isEmpty) return null;
  return TextPainter(
    text: TextSpan(
      text: glyph,
      style: TextStyle(
        fontFamily: base.fontFamily,
        fontFamilyFallback: base.fontFamilyFallback,
        fontSize: base.fontSize! / 2,
        fontWeight: base.fontWeight,
        fontStyle: base.fontStyle,
        fontFeatures: [...?base.fontFeatures, const FontFeature('ruby')],
        fontVariations: base.fontVariations,
        height: 1,
        leadingDistribution: TextLeadingDistribution.even,
        color: color,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
}

/// 横排着重号：按字素簇选择行内样式，同一块内复用标记字形。
class HorizontalTextEmphasis {
  /// 未被行内区间覆盖的字符使用 [base]；正文主题策略由 [textColorFor] 提供。
  HorizontalTextEmphasis(
    TextLayoutResult layout,
    ComputedStyle base,
    Color? Function(ComputedStyle) textColorFor,
  ) : _layout = layout,
      _base = base,
      _textColorFor = textColorFor;

  final TextLayoutResult _layout;
  final ComputedStyle _base;
  final Color? Function(ComputedStyle) _textColorFor;
  final _marks = <ComputedStyle, _EmphasisMark>{};

  /// 整块没有着重号时跳过额外的逐行排版。
  bool get hasMarks =>
      _base.hasTextEmphasis ||
      _layout.runs.any((run) => run.style.hasTextEmphasis);

  // CSS Text Decoration 3 §3.1：标点例外包含 NFKD 对应的兼容字符。
  static final _punctuationExceptions = '#%‰‱٪؉؊&⁊@§¶⁋⁓〽＃％＆＠﹟﹠﹪﹫'.runes.toSet();
  static final _unmarked = RegExp(r'^[\p{P}\p{Cc}\p{Cf}\p{Cn}]', unicode: true);
  static final _separator = RegExp(r'^\p{Z}', unicode: true);
  static final _combinedSpace = RegExp(r'^\p{Z}\p{M}+$', unicode: true);

  static bool _receivesMark(String cluster) {
    if (cluster == '\uFFFC') return false;
    if (_punctuationExceptions.contains(cluster.runes.first)) return true;
    if (_unmarked.hasMatch(cluster)) return false;
    return !_separator.hasMatch(cluster) || _combinedSpace.hasMatch(cluster);
  }

  Iterable<_StyledCluster> _clusters(LineBox line) sync* {
    final runs = _layout.runs;
    var runIndex = runs.indexWhere((run) => run.end > line.start);
    if (runIndex < 0) runIndex = runs.length;
    var start = 0;
    for (final cluster
        in _layout.text.substring(line.start, line.end).characters) {
      final end = start + cluster.length;
      final absolute = line.start + start;
      while (runIndex < runs.length && runs[runIndex].end <= absolute) {
        runIndex++;
      }
      final run = runIndex < runs.length && runs[runIndex].start <= absolute
          ? runs[runIndex]
          : null;
      final style = run?.style ?? _base;
      // 字素簇跨样式边界时采用起始字符样式，不拆开代理对或组合字符。
      if (style.hasTextEmphasis &&
          style.visibility == CssVisibility.visible &&
          _receivesMark(cluster)) {
        yield (
          start: start,
          end: end,
          style: style,
          shift: run?.baselineShift ?? 0,
        );
      }
      start = end;
    }
  }

  /// [origin] 与正文使用同一个行画笔原点；盒占宽和基线位移在此同步。
  void paint(Canvas canvas, TextPainter text, LineBox line, Offset origin) {
    final baseline = text.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    final shifted = _layout.runs.any(
      (run) =>
          run.start < line.end &&
          run.end > line.start &&
          run.baselineShift != 0,
    );
    for (final cluster in _clusters(line)) {
      final style = cluster.style;
      final mark = _marks.putIfAbsent(
        style,
        () => _EmphasisMark(
          style,
          style.textEmphasisColor ?? _textColorFor(style) ?? style.color,
        ),
      );
      final boxes = text.getBoxesForSelection(
        TextSelection(baseOffset: cluster.start, extentOffset: cluster.end),
      );
      if (boxes.isEmpty) continue;
      final advance = inlineBoxAdvanceAt(
        line,
        TextPosition(offset: cluster.start),
      );
      mark.paint(
        canvas,
        boxes.first.toRect(),
        Offset(
          origin.dx + advance,
          origin.dy + (shifted ? mark.textBaseline : baseline) + cluster.shift,
        ),
      );
    }
  }

  /// 释放本块的字形排版资源，不跨页保留。
  void dispose() {
    for (final mark in _marks.values) {
      mark.dispose();
    }
    _marks.clear();
  }
}

class _EmphasisMark {
  factory _EmphasisMark(ComputedStyle style, Color color) {
    final base = TextLayoutEngine.textStyleFor(style);
    final mark = createTextEmphasisPainter(style, color)!;
    final probe = TextPainter(
      text: TextSpan(text: '国Hg', style: base),
      textDirection: TextDirection.ltr,
    )..layout();
    final textBaseline = probe.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    probe.text = TextSpan(
      text: '国Hg',
      style: base.copyWith(height: kTextHeightNone),
    );
    probe.layout();
    final font = probe.computeLineMetrics().first;
    final metrics = mark.computeLineMetrics().first;
    final size = TextLayoutEngine.textStyleFor(style).fontSize!;
    // 上侧注音区从 em 盒顶开始；下侧从字体下降部之后开始，避免压住下伸笔画。
    final emAscent = font.ascent - (font.ascent + font.descent - size) / 2;
    final offset = style.textEmphasisPosition.isOver
        ? (-emAscent - metrics.descent).floorToDouble()
        : (font.descent + metrics.ascent).ceilToDouble();
    probe.dispose();
    return _EmphasisMark._(
      style,
      mark,
      offset - metrics.baseline,
      textBaseline,
    );
  }

  _EmphasisMark._(this._style, this._mark, this._top, this.textBaseline);

  final ComputedStyle _style;
  final TextPainter _mark;
  final double _top;
  final double textBaseline;

  void paint(Canvas canvas, Rect glyph, Offset baseline) {
    final center = (glyph.left + glyph.right - _style.letterSpacing) / 2;
    _mark.paint(
      canvas,
      Offset(baseline.dx + center - _mark.width / 2, baseline.dy + _top),
    );
  }

  void dispose() => _mark.dispose();
}
