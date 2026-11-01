import 'package:flutter/painting.dart';
import 'package:flutter/widgets.dart' show StringCharacters;

/// 几何规则版本；颜色不参与布局缓存失效。
const int textSpacingRevision = 1;

/// 改变占宽但不改变原文的单个字簇调整；偏移相对于所在行。
class GlyphSpacing {
  const GlyphSpacing({
    required this.offset,
    this.length = 1,
    this.letterSpacing = 0,
    this.halfWidth = false,
    this.reduction = 0,
  });

  final int offset;
  final int length;
  final double letterSpacing;
  final bool halfWidth;
  final double reduction;

  GlyphSpacing atOffset(int offset) => GlyphSpacing(
    offset: offset,
    length: length,
    letterSpacing: letterSpacing,
    halfWidth: halfWidth,
    reduction: reduction,
  );

  TextStyle apply(TextStyle style, double extra) => style.copyWith(
    letterSpacing: (style.letterSpacing ?? 0) + letterSpacing + extra,
    fontFeatures: halfWidth
        ? [
            for (final feature in style.fontFeatures ?? const <FontFeature>[])
              if (feature.feature != 'halt') feature,
            const FontFeature.enable('halt'),
          ]
        : style.fontFeatures,
  );
}

/// 测量产生、绘制与命中共享的行间距。所有下标均为行内 UTF-16 偏移。
class LineSpacing {
  static final empty = LineSpacing();

  LineSpacing({
    Map<int, GlyphSpacing> glyphs = const {},
    Set<int> lockedGaps = const {},
    List<int> justifyGaps = const [],
    this.startTrim = 0,
    this.endTrim = 0,
    this.trailingSpaceStart,
  }) : glyphs = Map.unmodifiable(glyphs),
       lockedGaps = Set.unmodifiable(lockedGaps),
       justifyGaps = List.unmodifiable(justifyGaps);

  LineSpacing._withGaps(LineSpacing source, List<int> gaps)
    : glyphs = source.glyphs,
      lockedGaps = source.lockedGaps,
      justifyGaps = List.unmodifiable(gaps),
      startTrim = source.startTrim,
      endTrim = source.endTrim,
      trailingSpaceStart = source.trailingSpaceStart;

  final Map<int, GlyphSpacing> glyphs;
  final Set<int> lockedGaps;
  final List<int> justifyGaps;
  final double startTrim;
  final double endTrim;
  final int? trailingSpaceStart;

  LineSpacing withJustifyGaps(List<int> gaps) =>
      gaps.isEmpty && justifyGaps.isEmpty
      ? this
      : LineSpacing._withGaps(this, gaps);

  /// 仅在测量文本插入了断点或占位符时重映射；整行搬移无需改下标。
  LineSpacing remap(int Function(int offset) originalOffset) => LineSpacing(
    glyphs: {
      for (final entry in glyphs.entries)
        if (originalOffset(entry.key + entry.value.length) >
            originalOffset(entry.key))
          originalOffset(entry.key): entry.value.atOffset(
            originalOffset(entry.key),
          ),
    },
    lockedGaps: {
      for (final offset in lockedGaps)
        if (originalOffset(offset + 1) > originalOffset(offset))
          originalOffset(offset),
    },
    justifyGaps: [
      for (final offset in justifyGaps)
        if (originalOffset(offset + 1) > originalOffset(offset))
          originalOffset(offset),
    ],
    startTrim: startTrim,
    endTrim: endTrim,
    trailingSpaceStart: trailingSpaceStart == null
        ? null
        : originalOffset(trailingSpaceStart!),
  );

  late final String fingerprint = [
    for (final glyph in glyphs.values)
      '${glyph.offset}:${glyph.length}:${glyph.letterSpacing}:'
          '${glyph.halfWidth}:${glyph.reduction}',
    'j=${justifyGaps.join(',')};l=${lockedGaps.join(',')};s=$startTrim;e=$endTrim;t=$trailingSpaceStart',
  ].join(';');
}

/// 只在发生调整的字簇边界拆 span，未调整的单词、连字和 emoji 保持连续。
TextSpan applyTextSpacing(
  TextSpan source,
  LineSpacing spacing, {
  double justifyExtra = 0,
  Set<int> hiddenPlaceholders = const {},
  Set<int> replacedPlaceholders = const {},
}) {
  if (spacing.glyphs.isEmpty &&
      (justifyExtra == 0 || spacing.justifyGaps.isEmpty) &&
      hiddenPlaceholders.isEmpty &&
      spacing.trailingSpaceStart == null) {
    return source;
  }
  return _SpacingSpans(
    spacing,
    justifyExtra,
    hiddenPlaceholders,
    replacedPlaceholders,
  ).visit(source, const TextStyle());
}

class _SpacingSpans {
  _SpacingSpans(this.spacing, double extra, this.hidden, this.replaced)
    : gaps = spacing.justifyGaps.toSet(),
      extra = spacing.justifyGaps.isEmpty
          ? 0
          : extra / spacing.justifyGaps.length;

  final LineSpacing spacing;
  final Set<int> gaps;
  final double extra;
  final Set<int> hidden;
  final Set<int> replaced;
  int cursor = 0;

  TextStyle? _adjusted(int offset, TextStyle style) {
    final glyph = spacing.glyphs[offset];
    final gap = gaps.contains(offset) ? extra : 0.0;
    final trailing =
        spacing.trailingSpaceStart != null &&
        offset >= spacing.trailingSpaceStart!;
    if (glyph == null && gap == 0 && !hidden.contains(offset) && !trailing) {
      return null;
    }
    final adjusted = (glyph ?? GlyphSpacing(offset: offset)).apply(style, gap);
    if (trailing || replaced.contains(offset)) {
      return adjusted.copyWith(
        fontSize: 0,
        letterSpacing: 0,
        wordSpacing: 0,
        color: const Color(0x00000000),
      );
    }
    return hidden.contains(offset)
        ? adjusted.copyWith(color: const Color(0x00000000))
        : adjusted;
  }

  TextSpan visit(TextSpan span, TextStyle inherited) {
    final style = inherited.merge(span.style);
    final text = span.text ?? '';
    final children = <InlineSpan>[];
    var start = 0;
    var local = 0;
    for (final cluster in text.characters) {
      final adjusted = _adjusted(cursor + local, style);
      if (adjusted != null) {
        if (local > start) {
          children.add(
            TextSpan(text: text.substring(start, local), style: style),
          );
        }
        children.add(TextSpan(text: cluster, style: adjusted));
        start = local + cluster.length;
      }
      local += cluster.length;
    }
    if (start < text.length) {
      children.add(TextSpan(text: text.substring(start), style: style));
    }
    cursor += text.length;
    for (final child in span.children ?? const <InlineSpan>[]) {
      children.add(child is TextSpan ? visit(child, style) : child);
    }
    return TextSpan(style: span.style, children: children);
  }
}

/// 保留完整样式树的原文子区间，供断行探测与上下标分段绘制复用。
TextSpan sliceTextSpan(TextSpan source, int start, int end) {
  var cursor = 0;
  TextSpan visit(TextSpan span) {
    final text = span.text ?? '';
    final from = (start - cursor).clamp(0, text.length);
    final until = (end - cursor).clamp(from, text.length);
    cursor += text.length;
    final children = <InlineSpan>[];
    for (final child in span.children ?? const <InlineSpan>[]) {
      if (child is TextSpan) {
        final sliced = visit(child);
        if ((sliced.text?.isNotEmpty ?? false) ||
            (sliced.children?.isNotEmpty ?? false)) {
          children.add(sliced);
        }
      }
    }
    return TextSpan(
      text: text.substring(from, until),
      style: span.style,
      children: children.isEmpty ? null : children,
    );
  }

  return visit(source);
}
