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
  /// 创建缓存。
  TextLayoutCache({this.maxEntries = 512});

  /// 条目上限（LRU）。
  final int maxEntries;

  final LinkedHashMap<String, TextLayoutResult> _entries =
      LinkedHashMap<String, TextLayoutResult>();
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
    );
    final cached = _take(
      key,
      () => TextLayoutEngine.styledRuns(
        text: text,
        style: style,
        runs: runs,
        hasGlyph: hasGlyph,
        leadingDistribution: leadingDistribution,
      ),
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
    );
    _entries[key] = result;
    _evict();
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
    );
    final cached = _take(
      key,
      () => TextLayoutEngine.styledRuns(
        text: text,
        style: style,
        runs: runs,
        hasGlyph: hasGlyph,
        leadingDistribution: leadingDistribution,
      ),
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
    );
    if (checkpoint != null) await checkpoint();
    if (epoch == _epoch) {
      _entries[key] = result;
      _evict();
    }
    return result;
  }

  TextLayoutResult? _take(String key, List<StyledRun> Function() currentRuns) {
    final cached = _entries.remove(key);
    if (cached == null) {
      _misses += 1;
      return null;
    }
    _entries[key] = cached;
    _hits += 1;
    final result = cached.withRuns(currentRuns());
    reuseTextLineEdges(cached, result);
    return result;
  }

  /// 清空缓存（设置重排时调用）。
  void clear() {
    _epoch += 1;
    _entries.clear();
    _hits = 0;
    _misses = 0;
  }

  void _evict() {
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  static String _key({
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
  }) {
    final buffer = StringBuffer('spacing=$textSpacingRevision|')
      ..write('fractional=${LineBreaker.preserveFractionalLineHeight}|')
      ..write('fonts=$fontDependency|')
      ..write(
        'contentWidth=${preserveContentWidth || style.intrinsicWidth != null}|',
      )
      ..write(style.layoutFingerprint)
      ..write('|w=')
      ..write(maxWidth.toString())
      ..write('|s=')
      ..write(textScaleFactor)
      ..write('|ld=')
      ..write(leadingDistribution.name)
      ..write('|hg=')
      ..write(hasGlyph == null ? 0 : 1);
    if (runs.isNotEmpty) {
      buffer.write('|r=');
      for (final run in runs) {
        buffer
          ..write(run.start)
          ..write(',')
          ..write(run.end)
          ..write(',')
          ..write(run.baselineShift)
          ..write(',')
          ..write(run.style.layoutFingerprint)
          ..write(';');
      }
    }
    for (final ruby in rubies) {
      buffer.write('|ruby=${ruby.start}:${ruby.end}');
    }
    buffer
      ..write('|')
      ..write(text);
    return buffer.toString();
  }
}
