import 'dart:collection';

import 'package:flutter/painting.dart' show TextLeadingDistribution;

import '../css/computed_style.dart';
import 'line_breaker.dart';
import 'text_edges.dart';

/// 段落布局缓存（P2-26，S2 结论：逐段 Paragraph + 缓存，不合并整页）。
///
/// 键包含测量相关全部输入：文本、样式测量指纹、行宽、textScaleFactor、
/// leading 分布、行内 run 摘要、是否启用字形覆盖回调；样式或宽度变化自然
/// 产生新键，清缓存用于设置重排（P2-24）。
class TextLayoutCache {
  /// 限制快速复用的同步注音快照与校验；更长列表交回带检查点的重排。
  static const _maxReusableRubies = 64;

  /// 创建缓存。
  TextLayoutCache({this.maxEntries = 512});

  /// 条目上限（LRU）。
  final int maxEntries;

  final LinkedHashMap<String, TextLayoutResult> _entries =
      LinkedHashMap<String, TextLayoutResult>();
  Expando<_ReusableMeasurement> _measurements = Expando();
  int _hits = 0;
  int _misses = 0;
  int _epoch = 0;

  /// 命中次数。
  int get hits => _hits;

  /// 未命中次数。
  int get misses => _misses;

  /// 当前条目数。
  int get length => _entries.length;

  /// 命中率（无访问时为 0）。
  double get hitRate => _hits + _misses == 0 ? 0 : _hits / (_hits + _misses);

  /// 取缓存的段落布局；未命中时按 [TextLayoutEngine.layout] 计算并写入。
  TextLayoutResult layout({
    required String text,
    required ComputedStyle style,
    required double maxWidth,
    double textScaleFactor = 1,
    TextLeadingDistribution leadingDistribution = TextLeadingDistribution.even,
    List<StyledRun> runs = const <StyledRun>[],
    List<RubyAnnotation> rubies = const <RubyAnnotation>[],
    bool Function(String family, int codeUnit)? hasGlyph,
    String fontDependency = '',
    bool preserveContentWidth = false,
    ComputedStyle? firstLineStyle,
    List<StyledRun>? firstLineRuns,
  }) {
    final key = _key(
      text: text,
      style: style,
      maxWidth: maxWidth,
      textScaleFactor: textScaleFactor,
      leadingDistribution: leadingDistribution,
      runs: runs,
      rubies: rubies,
      hasGlyph: hasGlyph,
      fontDependency: fontDependency,
      preserveContentWidth: preserveContentWidth,
      firstLineStyle: firstLineStyle,
      firstLineRuns: firstLineRuns,
    );
    final cached = _take(
      key.value,
      (cached) => TextLayoutEngine.styledRuns(
        text: cached.text,
        style: style,
        runs: remapStyledRuns(runs, cached.inputOffsets),
        hasGlyph: hasGlyph,
        leadingDistribution: leadingDistribution,
        firstLineStyle: firstLineStyle,
        firstLineRuns: firstLineRuns == null
            ? null
            : remapStyledRuns(firstLineRuns, cached.inputOffsets),
        firstLineEnd: cached.lines.firstOrNull?.end ?? 0,
        transformText: false,
      ),
      firstLineStyle: firstLineStyle,
      firstLineRuns: firstLineRuns,
      sourceRuns: firstLineStyle == null ? null : runs,
    );
    if (cached != null) {
      return cached;
    }
    final result = TextLayoutEngine.layout(
      text: text,
      style: style,
      maxWidth: maxWidth,
      textScaleFactor: textScaleFactor,
      leadingDistribution: leadingDistribution,
      runs: runs,
      rubies: rubies,
      hasGlyph: hasGlyph,
      lineBreaker: preserveContentWidth ? LineBreaker(minimumWidthEm: 0) : null,
      firstLineStyle: firstLineStyle,
      firstLineRuns: firstLineRuns,
    );
    _entries[key.value] = result;
    _evict();
    if (textScaleFactor == 1 &&
        leadingDistribution == TextLeadingDistribution.even &&
        hasGlyph != null &&
        !preserveContentWidth &&
        firstLineStyle == null &&
        rubies.length <= _maxReusableRubies) {
      _rememberMeasurement(result, key.style, maxWidth, fontDependency, rubies);
    }
    return result;
  }

  /// 同步入口使用的同一布局键与算法；取消或失败不会留下缓存条目。
  Future<TextLayoutResult> layoutAsync({
    required String text,
    required ComputedStyle style,
    required double maxWidth,
    double textScaleFactor = 1,
    TextLeadingDistribution leadingDistribution = TextLeadingDistribution.even,
    List<StyledRun> runs = const <StyledRun>[],
    List<RubyAnnotation> rubies = const <RubyAnnotation>[],
    bool Function(String family, int codeUnit)? hasGlyph,
    String fontDependency = '',
    Future<void> Function()? checkpoint,
    bool preserveContentWidth = false,
    ComputedStyle? firstLineStyle,
    List<StyledRun>? firstLineRuns,
  }) async {
    if (checkpoint != null) await checkpoint();
    final key = _key(
      text: text,
      style: style,
      maxWidth: maxWidth,
      textScaleFactor: textScaleFactor,
      leadingDistribution: leadingDistribution,
      runs: runs,
      rubies: rubies,
      hasGlyph: hasGlyph,
      fontDependency: fontDependency,
      preserveContentWidth: preserveContentWidth,
      firstLineStyle: firstLineStyle,
      firstLineRuns: firstLineRuns,
    );
    final cached = _take(
      key.value,
      (cached) => TextLayoutEngine.styledRuns(
        text: cached.text,
        style: style,
        runs: remapStyledRuns(runs, cached.inputOffsets),
        hasGlyph: hasGlyph,
        leadingDistribution: leadingDistribution,
        firstLineStyle: firstLineStyle,
        firstLineRuns: firstLineRuns == null
            ? null
            : remapStyledRuns(firstLineRuns, cached.inputOffsets),
        firstLineEnd: cached.lines.firstOrNull?.end ?? 0,
        transformText: false,
      ),
      firstLineStyle: firstLineStyle,
      firstLineRuns: firstLineRuns,
      sourceRuns: firstLineStyle == null ? null : runs,
    );
    if (cached != null) return cached;
    final epoch = _epoch;
    final result = await TextLayoutEngine.layoutAsync(
      text: text,
      style: style,
      maxWidth: maxWidth,
      textScaleFactor: textScaleFactor,
      leadingDistribution: leadingDistribution,
      runs: runs,
      rubies: rubies,
      hasGlyph: hasGlyph,
      checkpoint: checkpoint,
      lineBreaker: preserveContentWidth ? LineBreaker(minimumWidthEm: 0) : null,
      firstLineStyle: firstLineStyle,
      firstLineRuns: firstLineRuns,
    );
    if (checkpoint != null) await checkpoint();
    if (epoch == _epoch) {
      _entries[key.value] = result;
      _evict();
      if (textScaleFactor == 1 &&
          leadingDistribution == TextLeadingDistribution.even &&
          hasGlyph != null &&
          !preserveContentWidth &&
          firstLineStyle == null &&
          rubies.length <= _maxReusableRubies) {
        _rememberMeasurement(
          result,
          key.style,
          maxWidth,
          fontDependency,
          rubies,
        );
      }
    }
    return result;
  }

  TextLayoutResult? _take(
    String key,
    List<StyledRun> Function(TextLayoutResult cached) currentRuns, {
    ComputedStyle? firstLineStyle,
    List<StyledRun>? firstLineRuns,
    List<StyledRun>? sourceRuns,
  }) {
    final cached = _entries.remove(key);
    if (cached == null) {
      _misses += 1;
      return null;
    }
    _entries[key] = cached;
    _hits += 1;
    final result = cached.withRuns(
      currentRuns(cached),
      firstLineStyle: firstLineStyle,
      firstLineRuns: firstLineRuns == null
          ? null
          : remapStyledRuns(firstLineRuns, cached.inputOffsets),
      sourceRuns: sourceRuns == null
          ? null
          : remapStyledRuns(sourceRuns, cached.inputOffsets),
    );
    reuseTextLineEdges(cached, result);
    _measurements[result] = _measurements[cached];
    return result;
  }

  /// 判断原对象是否已按浮动分页的默认选项测量，且全部外部条件未变。
  /// 只适用于完整原文和现有 runs；不接受缩放、特殊 leading、无字形回调
  /// 或保留内容宽的测量。弱引用记录不延长布局及其书籍资源的生命周期。
  bool canReuseUnchanged(
    TextLayoutResult result, {
    required ComputedStyle style,
    required double maxWidth,
    required String fontDependency,
    List<RubyAnnotation> rubies = const [],
  }) {
    final measured = _measurements[result];
    if (measured == null ||
        measured.width != maxWidth ||
        measured.fonts != fontDependency ||
        measured.fractional != LineBreaker.preserveFractionalLineHeight ||
        measured.rubies.length != rubies.length ||
        measured.style != style.layoutFingerprint) {
      return false;
    }
    for (var i = 0; i < rubies.length; i++) {
      final before = measured.rubies[i];
      final current = rubies[i];
      if (before.start != current.start ||
          before.end != current.end ||
          before.text != current.text ||
          before.style != current.style?.layoutFingerprint) {
        return false;
      }
    }
    return true;
  }

  void _rememberMeasurement(
    TextLayoutResult result,
    String styleFingerprint,
    double maxWidth,
    String fontDependency,
    List<RubyAnnotation> rubies,
  ) {
    _measurements[result] = (
      style: styleFingerprint,
      width: maxWidth,
      fonts: fontDependency,
      fractional: LineBreaker.preserveFractionalLineHeight,
      rubies: [
        for (final ruby in rubies)
          (
            start: ruby.start,
            end: ruby.end,
            text: ruby.text,
            style: ruby.style?.layoutFingerprint,
          ),
      ],
    );
  }

  /// 清空缓存（设置重排时调用）。
  void clear() {
    _epoch += 1;
    _entries.clear();
    _measurements = Expando();
    _hits = 0;
    _misses = 0;
  }

  void _evict() {
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  static ({String value, String style}) _key({
    required String text,
    required ComputedStyle style,
    required double maxWidth,
    required double textScaleFactor,
    required TextLeadingDistribution leadingDistribution,
    required List<StyledRun> runs,
    required List<RubyAnnotation> rubies,
    required bool Function(String family, int codeUnit)? hasGlyph,
    required String fontDependency,
    required bool preserveContentWidth,
    required ComputedStyle? firstLineStyle,
    required List<StyledRun>? firstLineRuns,
  }) {
    final styleFingerprint = style.layoutFingerprint;
    final buffer = StringBuffer('spacing=$textSpacingRevision|')
      ..write('fractional=${LineBreaker.preserveFractionalLineHeight}|')
      ..write('fonts=$fontDependency|')
      ..write(
        'contentWidth=${preserveContentWidth || style.intrinsicWidth != null}|',
      )
      ..write(styleFingerprint)
      ..write('|w=')
      ..write(maxWidth.toString())
      ..write('|s=')
      ..write(textScaleFactor)
      ..write('|ld=')
      ..write(leadingDistribution.name)
      ..write('|hg=')
      ..write(hasGlyph == null ? 0 : 1);
    _writeRuns(buffer, '|r=', runs);
    if (firstLineStyle != null) {
      buffer.write('|first=${firstLineStyle.layoutFingerprint}');
      // null 自动继承正文声明，显式空列表只采用首行样式，度量可不同。
      buffer.write(
        '|firstRunsMode=${firstLineRuns == null ? 'inherited' : 'explicit'}',
      );
      final effectiveFirstRuns =
          firstLineRuns ??
          TextLayoutEngine.inheritedFirstLineRuns(runs, firstLineStyle);
      _writeRuns(buffer, '|firstRuns=', effectiveFirstRuns);
    }
    for (final ruby in rubies) {
      buffer.write('|ruby=${ruby.start}:${ruby.end}');
    }
    buffer
      ..write('|')
      ..write(text);
    return (value: buffer.toString(), style: styleFingerprint);
  }

  static void _writeRuns(
    StringBuffer buffer,
    String label,
    List<StyledRun> runs,
  ) {
    if (runs.isEmpty) return;
    buffer.write(label);
    for (final run in runs) {
      buffer
        ..write(run.start)
        ..write(',')
        ..write(run.end)
        ..write(',')
        ..write(run.baselineShift)
        ..write(',')
        ..write(run.syntheticFontFallback ? 0 : run.leadingInset)
        ..write(',')
        ..write(run.syntheticFontFallback ? 0 : run.trailingInset)
        ..write(',')
        ..write(run.style.layoutFingerprint)
        ..write(';');
    }
  }
}

typedef _ReusableMeasurement = ({
  String style,
  double width,
  String fonts,
  bool fractional,
  List<({int start, int end, String text, String? style})> rubies,
});
