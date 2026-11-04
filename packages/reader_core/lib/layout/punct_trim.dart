/// 标点挤压（P7-19；对照 Reeden 行为「两个标点挨在一起时挤掉中间的
/// 整格空白，标点贴着汉字的一侧留白保留。字体不支持时自动跳过」，
/// 150 号 §0-#5；CSS Text 4 的 `text-spacing-trim: trim-adjacent` 语义子集）。
///
/// 原理：全角标点字形占 em 方框的一半（句读靠左、闭口引号靠右等），
/// 相邻两个全角标点之间留出一个半角空白。挤压在**前一个标点**上加
/// `-0.5em` 字距，把后一个标点拉进来——留白只落在字之间，不压缩字形。
///
/// 字体守卫：前标点的实际 advance 明显小于 em（比例字体没有整格空白）
/// 时不挤压该对——「字体不支持时自动跳过」的逐对判定。
///
/// 方向性（对齐 Chrome `text-spacing-trim: normal`，headless 实测 22 组）：
/// 只有**收尾类**标点（句读、闭括号、冒号分号）在左侧时才折叠，且右侧须是
/// 收尾类或起首类；起首类在左、`！？…` 任意相邻都不折叠。
library;

import 'package:flutter/painting.dart';

/// 收尾类全角标点（句读、冒号分号、闭括号与闭引号）。
///
/// Chrome `text-spacing-trim: normal` 里只有「收尾类」字形带右侧空白，
/// 才会被压在左侧（CLREQ 收尾标点）。
const Set<String> punctClosingSet = <String>{
  '，', '。', '、', '；', '：', '」', '』', '）', '》', '】', '〉',
};

/// 行首禁则标点：收尾类加上不成对的叹号、问号与省略号。
///
/// 挤压集合刻意不含 `！？…`，但换行避头仍须包含它们。
const Set<String> punctLineStartProhibitedSet = <String>{
  ...punctClosingSet,
  '！',
  '？',
  '…',
};

/// 起首类全角标点（开括号与开引号）：只作为挤压对的**右侧**参与。
const Set<String> punctOpeningSet = <String>{
  '「', '『', '（', '《', '【', '〈',
};

/// 参与挤压判定的全角标点全集（收尾 ∪ 起首）。
///
/// `！？…` 刻意不在集合内：Chrome 实测它们相邻时不折叠（全角叹号/问号
/// 字形居中、两侧留白对称，压缩会撞字）。
const Set<String> punctCompressionSet = <String>{
  ...punctClosingSet,
  ...punctOpeningSet,
};

/// 全角标点的判定比例阈值：advance ≥ 0.9em 视为整格字形。
const double fullWidthRatioThreshold = 0.9;

/// 挤压字距：前标点上加 `-0.5em`。
double punctCompressionSpacing(double fontSize) => -fontSize / 2;

/// 需要挤压的「前标点」代码单元偏移集合。
///
/// [advanceOf] 返回字符的实际 advance（像素）；[em] 为当前字号。
/// 规则（对齐 Chrome `text-spacing-trim: normal` 的方向性折叠，实测 22 组）：
/// 1. 相邻字符 `(i, i+1)`：左为 [punctClosingSet] 的收尾类，右为收尾类或
///    起首类——只有「收尾标点的右空白」会被挤掉；起首类在左、`！？…`
///    相邻时都不折叠；
/// 2. 前标点 advance ≥ 0.9em（整格字形，字体守卫）；
/// 3. 跳过换行；
/// 4. 返回「前标点」的偏移（绘制/测量时在其上加负字距）。
List<int> punctCompressionOffsets(
  String text, {
  required double em,
  required double Function(String char) advanceOf,
}) {
  if (text.length < 2) {
    return const <int>[];
  }
  final offsets = <int>[];
  final runes = text.runes.toList(growable: false);
  var offset = 0;
  for (var i = 0; i + 1 < runes.length; i++) {
    final left = String.fromCharCode(runes[i]);
    final right = String.fromCharCode(runes[i + 1]);
    if (punctClosingSet.contains(left) &&
        (punctClosingSet.contains(right) ||
            punctOpeningSet.contains(right)) &&
        advanceOf(left) >= em * fullWidthRatioThreshold) {
      offsets.add(offset);
    }
    offset += runes[i] > 0xFFFF ? 2 : 1;
  }
  return offsets;
}

/// 构造带缓存的 advance 测量器（同一字符重复测量复用）。
///
/// [direction] 与段落 baseDirection 保持一致（单字符 advance 与方向无关，
/// 仅用于避免 RTL 段落里测量/绘制方向口径不一致的隐性回归）。
double Function(String) punctAdvanceMeasurer(
  TextStyle baseStyle,
  double textScaleFactor, {
  TextDirection direction = TextDirection.ltr,
}) {
  final cache = <String, double>{};
  return (String char) => cache[char] ??= () {
    final painter = TextPainter(
      text: TextSpan(text: char, style: baseStyle),
      textDirection: direction,
      textScaler: TextScaler.linear(textScaleFactor),
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }();
}
