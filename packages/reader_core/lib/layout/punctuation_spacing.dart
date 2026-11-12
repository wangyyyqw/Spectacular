import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter/widgets.dart' show CharacterRange, StringCharacters;

import '../css/computed_style.dart';
import '../text/font_punctuation_metrics.dart';
import 'autospace.dart';
import 'punct_trim.dart';
import 'text_spacing.dart';

typedef SpacingStyle = ({
  ComputedStyle css,
  TextStyle text,
  double baselineShift,
});

typedef _PunctuationMetrics = ({
  double advance,
  double reduction,
  bool halfWidth,
});

final _punctuationUnits = {
  for (final char in punctUniformCompressionSet) char.codeUnitAt(0),
};

// 按原始未压缩的 advance 计算：行内保留 80%，相邻或行边保留 60%。
const _innerCompressionRatio = 0.2;
const _edgeCompressionRatio = 0.4;

/// 段落内只测一次字形；每行据真实相邻关系选择调整，不跨行借用半格空白。
class PunctuationSpacing {
  PunctuationSpacing({
    required this.text,
    required this.styleAt,
    this.autospace = false,
    this.barriers = const {},
  }) {
    _collectBoundaries();
    _collectUniform();
    _collectPairs();
    if (autospace) {
      for (final offset in autospaceOffsets(text)) {
        _autospace[offset] = GlyphSpacing(
          offset: offset,
          letterSpacing: autospaceSpacing(styleAt(offset).css.fontSize),
        );
      }
    }
  }

  final String text;
  final SpacingStyle Function(int offset) styleAt;
  final bool autospace;
  final Set<int> barriers;
  final _pairs = <({int left, int right, GlyphSpacing glyph})>[];
  final _uniform = <int, GlyphSpacing>{};
  final _autospace = <int, GlyphSpacing>{};
  final _metrics = <int, _PunctuationMetrics>{};
  final _punctuation = <int>{};
  final _blockedGaps = <int>{};
  final _singleClusters = <int, bool>{};
  // 收集过程按文档顺序插入；索引只缩小章内区间，不改变规则发射顺序。
  late final _uniformOffsets = _uniform.keys.toList(growable: false);
  late final _autospaceOffsets = _autospace.keys.toList(growable: false);
  late final _pairOffsets = [for (final pair in _pairs) pair.left];
  late final _blockedOffsets = _blockedGaps.toList(growable: false);

  void _collectBoundaries() {
    for (var offset = 0; offset < text.length; offset++) {
      if (_punctuationUnits.contains(text.codeUnitAt(offset))) {
        _punctuation.add(offset);
      }
    }
    if (barriers.isNotEmpty) {
      var offset = 0;
      for (final cluster in text.characters) {
        if (barriers.contains(offset + cluster.length)) {
          _blockedGaps.add(offset);
        }
        offset += cluster.length;
      }
    }
  }

  bool _singleCluster(int offset) => _singleClusters.putIfAbsent(
    offset,
    () => CharacterRange.at(text, offset, offset + 1).current.length == 1,
  );

  bool get hasAdjustments =>
      _uniform.isNotEmpty || _pairs.isNotEmpty || _autospace.isNotEmpty;

  void _collectUniform() {
    for (final offset in _punctuation) {
      final css = styleAt(offset).css;
      if (css.textSpacingTrim != CssTextSpacingTrim.trimAll ||
          css.isRtl ||
          css.writingMode != CssWritingMode.horizontalTb ||
          !_singleCluster(offset) ||
          barriers.contains(offset) ||
          barriers.contains(offset + 1)) {
        continue;
      }
      final glyph = _proportionalGlyph(offset, _innerCompressionRatio);
      if (glyph != null) _uniform[offset] = glyph;
    }
  }

  /// 没有字体支持的行边调整时沿用整段一次测量的快路径。
  bool get hasEdgeAdjustments {
    if (_uniform.isNotEmpty) return true;
    for (final offset in _punctuation) {
      final trim = styleAt(offset).css.textSpacingTrim;
      if ((trim.trimsStart && punctOpeningSet.contains(text[offset]) ||
              trim.trimsEnd && punctClosingSet.contains(text[offset])) &&
          _singleCluster(offset) &&
          metricsAt(offset).reduction > 0) {
        return true;
      }
    }
    return false;
  }

  double get maxEndReduction {
    var reduction = 0.0;
    for (final entry in _uniform.entries) {
      final edge = _proportionalGlyph(entry.key, _edgeCompressionRatio)!;
      reduction = math.max(reduction, edge.reduction - entry.value.reduction);
    }
    for (final offset in _punctuation) {
      if (styleAt(offset).css.textSpacingTrim.trimsEnd &&
          punctClosingSet.contains(text[offset]) &&
          _singleCluster(offset)) {
        reduction = math.max(reduction, metricsAt(offset).reduction);
      }
    }
    return reduction;
  }

  /// 断行探测的行尾候选；正文模式包含问叹号及中文引号。
  bool canTrimEnd(int offset) =>
      _uniform.containsKey(offset) ||
      styleAt(offset).css.textSpacingTrim.trimsEnd &&
          punctClosingSet.contains(text[offset]);

  ({double advance, double reduction, bool halfWidth}) metricsAt(int offset) =>
      _metrics.putIfAbsent(
        offset,
        () => _punctuationMetrics(text[offset], styleAt(offset).text),
      );

  LineSpacing range(
    int start,
    int end, {
    ({bool firstLine, bool trimEnd})? edges,
    bool trimTrailing = true,
  }) {
    final contentEnd = _contentEnd(start, end);
    if (edges == null &&
        _uniform.isEmpty &&
        _pairs.isEmpty &&
        _autospace.isEmpty &&
        _blockedGaps.isEmpty &&
        (!trimTrailing || contentEnd == end)) {
      return LineSpacing.empty;
    }
    final (glyphs, locked) = _innerAdjustments(start, end);
    var startTrim = 0.0;
    var endTrim = 0.0;
    if (edges != null && contentEnd > start) {
      startTrim = _edge(glyphs, start, start, firstLine: edges.firstLine);
      if (edges.trimEnd) {
        endTrim = _edge(glyphs, start, contentEnd - 1, atEnd: true);
      }
    }
    return LineSpacing(
      glyphs: glyphs,
      lockedGaps: locked,
      startTrim: startTrim,
      endTrim: endTrim,
      trailingSpaceStart: trimTrailing && contentEnd < end
          ? contentEnd - start
          : null,
    );
  }

  (Map<int, GlyphSpacing>, Set<int>) _innerAdjustments(int start, int end) {
    final glyphs = <int, GlyphSpacing>{};
    final locked = <int>{
      for (final gap in _offsetsInRange(_blockedOffsets, start, end))
        gap - start,
    };
    _uniformAdjustments(start, end, glyphs, locked);
    for (
      var index = _firstOffset(_pairOffsets, start);
      index < _pairs.length && _pairs[index].left < end;
      index++
    ) {
      final pair = _pairs[index];
      if (pair.right >= end) continue;
      final local = pair.glyph.offset - start;
      glyphs[local] = pair.glyph.atOffset(local);
      locked.add(pair.left - start);
    }
    for (final offset in _offsetsInRange(_autospaceOffsets, start, end - 1)) {
      if (!barriers.contains(offset + 1)) {
        glyphs[offset - start] = _autospace[offset]!.atOffset(offset - start);
      }
    }
    return (glyphs, locked);
  }

  void _uniformAdjustments(
    int start,
    int end,
    Map<int, GlyphSpacing> glyphs,
    Set<int> locked,
  ) {
    for (final offset in _offsetsInRange(_uniformOffsets, start, end)) {
      final local = offset - start;
      final glyph = _uniformAdjacent(offset, start, end)
          ? _proportionalGlyph(offset, _edgeCompressionRatio)!
          : _uniform[offset]!;
      glyphs[local] = glyph.atOffset(local);
      // 压缩后的标点两侧不再分配对齐字距，避免在非末行重新拉宽。
      if (local > 0) locked.add(local - 1);
      if (offset + 1 < end) locked.add(local);
    }
  }

  bool _uniformAdjacent(int offset, int start, int end) =>
      offset > start &&
          _uniform.containsKey(offset - 1) &&
          _canJoin(offset - 1, offset) ||
      offset + 1 < end &&
          _uniform.containsKey(offset + 1) &&
          _canJoin(offset, offset + 1);

  GlyphSpacing? _proportionalGlyph(int offset, double ratio) {
    if (_explicitHalt(offset)) return null;
    final metric = metricsAt(offset);
    if (metric.reduction <= 0) return null;
    final reduction = math.min(metric.advance * ratio, metric.reduction);
    return GlyphSpacing(
      offset: offset,
      halfWidth: metric.halfWidth,
      // halt 先回收留白再补占宽；轮廓回退直接收紧字距，两者均不缩放字形。
      letterSpacing: metric.halfWidth
          ? metric.reduction - reduction
          : -reduction,
      reduction: reduction,
    );
  }

  double _uniformEdge(Map<int, GlyphSpacing> glyphs, int start, int offset) {
    if (!_uniform.containsKey(offset)) return 0;
    final local = offset - start;
    final previous = glyphs[local]?.reduction ?? 0;
    final glyph = _proportionalGlyph(offset, _edgeCompressionRatio)!;
    glyphs[local] = glyph.atOffset(local);
    // 行边与相邻规则取最大压缩量，不叠加；这里只记录行边新增的收缩。
    return math.max(0, glyph.reduction - previous);
  }

  int _contentEnd(int start, int end) {
    while (end > start && (text[end - 1] == ' ' || text[end - 1] == '\t')) {
      end--;
    }
    return end;
  }

  double _edge(
    Map<int, GlyphSpacing> glyphs,
    int start,
    int offset, {
    bool atEnd = false,
    bool firstLine = false,
  }) {
    final trim = styleAt(offset).css.textSpacingTrim;
    if (trim == CssTextSpacingTrim.trimAll) {
      return _uniformEdge(glyphs, start, offset);
    }
    final eligible = atEnd
        ? trim.trimsEnd && punctClosingSet.contains(text[offset])
        : trim.trimsStart &&
              punctOpeningSet.contains(text[offset]) &&
              !(firstLine && trim == CssTextSpacingTrim.spaceFirst);
    if (!eligible ||
        !_punctuation.contains(offset) ||
        !_singleCluster(offset) ||
        barriers.contains(atEnd ? offset + 1 : offset) ||
        styleAt(offset).css.isRtl ||
        styleAt(offset).css.writingMode != CssWritingMode.horizontalTb) {
      return 0;
    }
    final reduction = metricsAt(offset).reduction;
    if (reduction <= 0) return 0;
    final local = offset - start;
    glyphs[local] = GlyphSpacing(
      offset: local,
      halfWidth: metricsAt(offset).halfWidth,
      letterSpacing: metricsAt(offset).halfWidth ? 0 : -reduction,
      reduction: reduction,
    );
    return reduction;
  }

  void _collectPairs() {
    for (final offset in _punctuation) {
      if (!_punctuation.contains(offset + 1) ||
          !_singleCluster(offset) ||
          !_singleCluster(offset + 1)) {
        continue;
      }
      final target = _pairTarget(offset);
      if (target == null) continue;
      final closing = punctClosingSet.contains(text[offset]);
      final glyph = _adjustment(target, fallback: closing && target == offset);
      if (glyph != null) {
        _pairs.add((left: offset, right: offset + 1, glyph: glyph));
      } else if (closing && target != offset && !_explicitHalt(target)) {
        final fallback = _adjustment(offset, fallback: true);
        if (fallback != null) {
          _pairs.add((left: offset, right: offset + 1, glyph: fallback));
        }
      }
    }
  }

  int? _pairTarget(int offset) {
    if (!_pairModeEnabled(offset) || !_canJoin(offset, offset + 1)) {
      return null;
    }
    final closing = punctClosingSet.contains(text[offset]);
    final opening = punctOpeningSet.contains(text[offset + 1]);
    final advanced =
        styleAt(offset).css.textSpacingTrim != CssTextSpacingTrim.trimAdjacent;
    if (!closing && !(advanced && opening)) return null;
    return !closing ||
            (advanced &&
                opening &&
                styleAt(offset).text.fontSize! >=
                    styleAt(offset + 1).text.fontSize!)
        ? offset + 1
        : offset;
  }

  bool _pairModeEnabled(int offset) =>
      punctCompressionSet.contains(text[offset]) &&
      punctCompressionSet.contains(text[offset + 1]) &&
      styleAt(offset).css.textSpacingTrim != CssTextSpacingTrim.trimAll &&
      styleAt(offset + 1).css.textSpacingTrim != CssTextSpacingTrim.trimAll;

  bool _canJoin(int left, int right) {
    if (barriers.contains(right)) return false;
    final a = styleAt(left);
    final b = styleAt(right);
    return !a.css.isRtl &&
        !b.css.isRtl &&
        a.css.writingMode == CssWritingMode.horizontalTb &&
        b.css.writingMode == CssWritingMode.horizontalTb &&
        a.css.textSpacingTrim.enabled &&
        b.css.textSpacingTrim.enabled &&
        a.baselineShift == b.baselineShift;
  }

  GlyphSpacing? _adjustment(int offset, {required bool fallback}) {
    if (_explicitHalt(offset)) return null;
    final metric = metricsAt(offset);
    if (metric.reduction > 0) {
      return GlyphSpacing(
        offset: offset,
        halfWidth: metric.halfWidth,
        letterSpacing: metric.halfWidth ? 0 : -metric.reduction,
        reduction: metric.reduction,
      );
    }
    final em = styleAt(offset).text.fontSize ?? 0;
    if (!fallback || metric.advance < em * fullWidthRatioThreshold) return null;
    // 旧相邻规则的兼容路径；新增的开标点和行边不使用固定负字距猜测。
    return GlyphSpacing(
      offset: offset,
      letterSpacing: -em / 2,
      reduction: em / 2,
    );
  }

  bool _explicitHalt(int offset) =>
      styleAt(offset).text.fontFeatures?.any((f) => f.feature == 'halt') ??
      false;
}

int _firstOffset(List<int> offsets, int start) {
  var lower = 0;
  var upper = offsets.length;
  while (lower < upper) {
    final middle = (lower + upper) ~/ 2;
    if (offsets[middle] < start) {
      lower = middle + 1;
    } else {
      upper = middle;
    }
  }
  return lower;
}

Iterable<int> _offsetsInRange(List<int> offsets, int start, int end) sync* {
  for (
    var index = _firstOffset(offsets, start);
    index < offsets.length && offsets[index] < end;
    index++
  ) {
    yield offsets[index];
  }
}

final Map<(TextStyle, String, int, bool), _PunctuationMetrics>
_punctuationCache = {};

_PunctuationMetrics _punctuationMetrics(String char, TextStyle style) {
  final probeStyle = TextStyle(
    fontSize: style.fontSize,
    fontFamily: style.fontFamily,
    fontFamilyFallback: style.fontFamilyFallback,
    fontWeight: style.fontWeight,
    fontStyle: style.fontStyle,
    fontVariations: style.fontVariations,
    fontFeatures: style.fontFeatures,
  );
  final key = (
    probeStyle,
    char,
    FontPunctuationRegistry.revision,
    (style.letterSpacing ?? 0) < 0,
  );
  final cached = _punctuationCache[key];
  if (cached != null) return cached;
  final result = _measurePunctuation(char, style, probeStyle);
  if (_punctuationCache.length >= 1024) {
    _punctuationCache.remove(_punctuationCache.keys.first);
  }
  return _punctuationCache[key] = result;
}

_PunctuationMetrics _measurePunctuation(
  String char,
  TextStyle style,
  TextStyle probeStyle,
) {
  final advance = _advance(char, probeStyle);
  final explicitHalt =
      style.fontFeatures?.any((f) => f.feature == 'halt') ?? false;
  final half = explicitHalt
      ? advance
      : _advance(
          char,
          const GlyphSpacing(offset: 0, halfWidth: true).apply(probeStyle, 0),
        );
  final reduction = advance - half;
  final safe =
      !explicitHalt &&
      advance >= (style.fontSize ?? 0) * fullWidthRatioThreshold &&
      reduction > 0.01 &&
      half >= advance * 0.4;
  return (
    advance: advance,
    reduction: safe ? reduction : _outlineReduction(char, style, advance),
    halfWidth: safe,
  );
}

/// 无半宽特性的静态字库只回收已确认的侧边留白，左右各留 .04em。
/// 原生负字距会向两侧各收一半，故以较小侧留白限制总收缩量。
double _outlineReduction(String char, TextStyle style, double advance) {
  final em = style.fontSize ?? 0;
  if (em <= 0 ||
      advance < em * fullWidthRatioThreshold ||
      (style.letterSpacing ?? 0) < 0 ||
      style.fontFeatures?.isNotEmpty == true ||
      style.fontVariations?.isNotEmpty == true) {
    return 0;
  }
  final metrics = FontPunctuationRegistry.lookup(
    style.fontFamily,
    char.codeUnitAt(0),
    weight: style.fontWeight?.value ?? 400,
    italic: style.fontStyle == FontStyle.italic,
  );
  if (metrics == null ||
      (metrics.advanceRatio * em - advance).abs() > em * .01) {
    return 0;
  }
  final side = math.min(metrics.leftBearingRatio, metrics.rightBearingRatio);
  return math.max(0.0, (side - .04) * em * 2);
}

double _advance(String char, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: char, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}
