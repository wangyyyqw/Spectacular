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
library;

import 'package:flutter/painting.dart';

/// 参与挤压的全角标点（与相邻全角标点挨着时留整格空白）。
const Set<String> punctCompressionSet = <String>{
  '，', '。', '、', '；', '：', '？', '！', '…',
  '」', '』', '）', '》', '】', '〉',
  '「', '『', '（', '《', '【', '〈',
};

/// 全角标点的判定比例阈值：advance ≥ 0.9em 视为整格字形。
const double fullWidthRatioThreshold = 0.9;

/// 挤压字距：前标点上加 `-0.5em`。
double punctCompressionSpacing(double fontSize) => -fontSize / 2;

/// 需要挤压的「前标点」代码单元偏移集合。
///
/// [advanceOf] 返回字符的实际 advance（像素）；[em] 为当前字号。
/// 规则：
/// 1. 相邻字符 `(i, i+1)` 都在 [punctCompressionSet]；
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
    if (punctCompressionSet.contains(left) &&
        punctCompressionSet.contains(right) &&
        advanceOf(left) >= em * fullWidthRatioThreshold) {
      offsets.add(offset);
    }
    offset += runes[i] > 0xFFFF ? 2 : 1;
  }
  return offsets;
}

/// 构造带缓存的 advance 测量器（同一字符重复测量复用）。
double Function(String) punctAdvanceMeasurer(
  TextStyle baseStyle,
  double textScaleFactor,
) {
  final cache = <String, double>{};
  return (String char) => cache[char] ??= () {
    final painter = TextPainter(
      text: TextSpan(text: char, style: baseStyle),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.linear(textScaleFactor),
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }();
}
