/// 中西文自动间距（P7-20；CSS Text 4 `text-autospace` 语义子集）。
///
/// 在 CJK 与拉丁字母/数字的边界插入 0.125em 视觉间距（只调字距，
/// 不改字符）。默认**关闭**——与技术方案 §38.2「不在中西文之间自动
/// 插入空格，书里有什么就是什么」一致；书内显式声明 `text-autospace:
/// normal`（或 `ideograph-alpha`）才启用，`no-autospace` 显式关闭。
/// 与规范初始值的偏差（规范 normal=启用）已在解析层注明。
library;

/// 参与自动间距的 CJK 码点范围（汉字/假名/谚文；句读不参与——全角
/// 标点与西文相邻由字体字形自行留白）。
bool isAutospaceCjkCodePoint(int codePoint) =>
    (codePoint >= 0x4E00 && codePoint <= 0x9FFF) || // CJK 统一表意
    (codePoint >= 0x3400 && codePoint <= 0x4DBF) || // 扩展 A
    (codePoint >= 0x3040 && codePoint <= 0x30FF) || // 假名
    (codePoint >= 0xAC00 && codePoint <= 0xD7AF); // 谚文

/// 参与自动间距的西文码点（拉丁字母与数字）。
bool isAutospaceLatinCodePoint(int codePoint) =>
    (codePoint >= 0x41 && codePoint <= 0x5A) ||
    (codePoint >= 0x61 && codePoint <= 0x7A) ||
    (codePoint >= 0x30 && codePoint <= 0x39) ||
    (codePoint >= 0xC0 && codePoint <= 0x24F);

/// 自动间距字距：0.125em（CSS Text 4 规定值）。
double autospaceSpacing(double fontSize) => fontSize * 0.125;

/// 需要加间距的「边界左侧字符」代码单元偏移。
///
/// 相邻字符 `(i, i+1)` 一侧 CJK、一侧拉丁/数字时计入；跳过换行。
List<int> autospaceOffsets(String text) {
  if (text.length < 2) {
    return const <int>[];
  }
  final offsets = <int>[];
  final runes = text.runes.toList(growable: false);
  var offset = 0;
  for (var i = 0; i + 1 < runes.length; i++) {
    final left = runes[i];
    final right = runes[i + 1];
    final cjkLeft = isAutospaceCjkCodePoint(left);
    final cjkRight = isAutospaceCjkCodePoint(right);
    final latinLeft = isAutospaceLatinCodePoint(left);
    final latinRight = isAutospaceLatinCodePoint(right);
    final boundary =
        (cjkLeft && latinRight) || (latinLeft && cjkRight);
    if (boundary && left != 0x0A && right != 0x0A) {
      offsets.add(offset);
    }
    offset += left > 0xFFFF ? 2 : 1;
  }
  return offsets;
}
