/// 按「字形覆盖」选择字体族的字符分段（P2-12）。
///
/// 参考阅微 `ContentDom.applyScriptFontFallback()` + `buildScriptRanges()`：
/// 先选择能覆盖完整字簇的族，无法覆盖时逐码点回退，连续同族合并成一段；
/// 没有命中任何族的字符不产出区间，继续沿用块的字体。
library;

import 'package:flutter/widgets.dart' show StringCharacters;

/// 一段使用指定字体族的字符区间（参考阅微 buildScriptRanges）。
class ScriptFontRun {
  /// 创建区间。
  const ScriptFontRun({
    required this.start,
    required this.end,
    required this.family,
  });

  /// 起始偏移（UTF-16，含）。
  final int start;

  /// 结束偏移（UTF-16，不含）。
  final int end;

  /// 该区间使用的字体族。
  final String family;

  @override
  String toString() => 'ScriptFontRun($start..$end, $family)';
}

/// 按 [families] 顺序优先选择完整字簇，避免拆开组合附加符的定位与塑形。
///
/// - [text] 或 [families] 为空时返回空列表；
/// - 无命中的字符不产出区间，相邻两段之间因此可能空出字符；
/// - 返回区间升序、互不重叠，[ScriptFontRun.start]/[ScriptFontRun.end] 为
///   UTF-16 下标，调用方保证不超过 `text.length`。
List<ScriptFontRun> buildScriptFontRuns(
  String text,
  List<String> families, {
  required bool Function(String family, int codePoint) hasGlyph,
}) {
  if (text.isEmpty || families.isEmpty) {
    return const <ScriptFontRun>[];
  }
  final runs = _ScriptFontRuns();
  var offset = 0;
  for (final cluster in text.characters) {
    final points = cluster.runes;
    final family = _fontFor(points, families, hasGlyph);
    final firstLength = points.first > 0xffff ? 2 : 1;
    if (family != null || cluster.length == firstLength) {
      runs.add(offset, offset + cluster.length, family);
      offset += cluster.length;
      continue;
    }
    for (final point in points) {
      final end = offset + (point > 0xffff ? 2 : 1);
      runs.add(offset, end, _fontFor([point], families, hasGlyph));
      offset = end;
    }
  }
  return runs.finish();
}

String? _fontFor(
  Iterable<int> points,
  List<String> families,
  bool Function(String, int) hasGlyph,
) {
  for (final family in families) {
    if (points.every((point) => hasGlyph(family, point))) return family;
  }
  return null;
}

class _ScriptFontRuns {
  final List<ScriptFontRun> _runs = [];
  String? _family;
  int _start = 0;
  int _end = 0;

  void add(int start, int end, String? family) {
    if (family != _family) {
      _flush();
      _family = family;
      _start = start;
    }
    _end = end;
  }

  void _flush() {
    final family = _family;
    if (family != null) {
      _runs.add(ScriptFontRun(start: _start, end: _end, family: family));
    }
  }

  List<ScriptFontRun> finish() {
    _flush();
    return _runs;
  }
}
