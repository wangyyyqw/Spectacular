/// 按「字形覆盖」选择字体族的字符分段（P2-12）。
///
/// 参考阅微 `ContentDom.applyScriptFontFallback()` + `buildScriptRanges()`：
/// 逐字符按 font-family 声明顺序找第一个有字形的族，连续同族合并成一段；
/// 没有命中任何族的字符不产出区间，继续沿用块的字体。
library;

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

/// 逐字符按 [families] 顺序找第一个 [hasGlyph] 命中的族，连续同族合并成区间。
///
/// - [text] 或 [families] 为空时返回空列表；
/// - 无命中的字符不产出区间，相邻两段之间因此可能空出字符；
/// - 返回区间升序、互不重叠，[ScriptFontRun.start]/[ScriptFontRun.end] 为
///   UTF-16 下标，调用方保证不超过 `text.length`。
List<ScriptFontRun> buildScriptFontRuns(
  String text,
  List<String> families, {
  required bool Function(String family, int codeUnit) hasGlyph,
}) {
  if (text.isEmpty || families.isEmpty) {
    return const <ScriptFontRun>[];
  }
  final runs = <ScriptFontRun>[];
  var runStart = -1;
  String? runFamily;
  for (var i = 0; i < text.length; i++) {
    final codeUnit = text.codeUnitAt(i);
    String? chosen;
    for (final family in families) {
      if (hasGlyph(family, codeUnit)) {
        chosen = family;
        break;
      }
    }
    if (chosen == runFamily) {
      continue; // 同族继续延伸
    }
    if (runFamily != null) {
      runs.add(ScriptFontRun(start: runStart, end: i, family: runFamily));
    }
    runStart = chosen == null ? -1 : i;
    runFamily = chosen;
  }
  if (runFamily != null) {
    runs.add(
      ScriptFontRun(start: runStart, end: text.length, family: runFamily),
    );
  }
  return runs;
}
