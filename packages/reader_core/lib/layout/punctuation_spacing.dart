import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter/widgets.dart' show CharacterRange, StringCharacters;

import '../css/computed_style.dart';
import 'autospace.dart';
import 'punct_trim.dart';
import 'text_spacing.dart';

typedef SpacingStyle = ({
  ComputedStyle css,
  TextStyle text,
  double baselineShift,
});

final _punctuationUnits = {
  for (final char in punctUniformCompressionSet) char.codeUnitAt(0),
};

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
  final _metrics = <int, ({double advance, double reduction})>{};
  final _punctuation = <int>{};
  final _blockedGaps = <int>{};
  final _singleClusters = <int, bool>{};

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
      final glyph = _adjustment(offset, fallback: false);
      if (glyph != null) _uniform[offset] = glyph;
    }
  }

  /// 没有字体支持的行边调整时沿用整段一次测量的快路径。
  bool get hasEdgeAdjustments {
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
    for (final offset in _punctuation) {
      if (styleAt(offset).css.textSpacingTrim.trimsEnd &&
          punctClosingSet.contains(text[offset]) &&
          _singleCluster(offset)) {
        reduction = math.max(reduction, metricsAt(offset).reduction);
      }
    }
    return reduction;
  }

  ({double advance, double reduction}) metricsAt(int offset) =>
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
      for (final gap in _blockedGaps)
        if (gap >= start && gap < end) gap - start,
    };
    _uniformAdjustments(start, end, glyphs, locked);
    for (final pair in _pairs) {
      if (pair.left < start || pair.right >= end) continue;
      final local = pair.glyph.offset - start;
      glyphs[local] = pair.glyph.atOffset(local);
      locked.add(pair.left - start);
    }
    for (final entry in _autospace.entries) {
      if (entry.key >= start &&
          entry.key + 1 < end &&
          !barriers.contains(entry.key + 1)) {
        glyphs[entry.key - start] = entry.value.atOffset(entry.key - start);
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
    for (final entry in _uniform.entries) {
      if (entry.key < start || entry.key >= end) continue;
      final local = entry.key - start;
      glyphs[local] = entry.value.atOffset(local);
      // 压缩后的标点两侧不再分配对齐字距，避免在非末行重新拉宽。
      if (local > 0) locked.add(local - 1);
      if (entry.key + 1 < end) locked.add(local);
    }
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
      halfWidth: true,
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
        halfWidth: true,
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

final Map<(TextStyle, String), ({double advance, double reduction})>
_punctuationCache = {};

({double advance, double reduction}) _punctuationMetrics(
  String char,
  TextStyle style,
) {
  final probeStyle = TextStyle(
    fontSize: style.fontSize,
    fontFamily: style.fontFamily,
    fontFamilyFallback: style.fontFamilyFallback,
    fontWeight: style.fontWeight,
    fontStyle: style.fontStyle,
    fontVariations: style.fontVariations,
    fontFeatures: style.fontFeatures,
  );
  final key = (probeStyle, char);
  final cached = _punctuationCache[key];
  if (cached != null) return cached;
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
  final result = (advance: advance, reduction: safe ? reduction : 0.0);
  if (_punctuationCache.length >= 1024) {
    _punctuationCache.remove(_punctuationCache.keys.first);
  }
  return _punctuationCache[key] = result;
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
