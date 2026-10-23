import 'script.dart';

/// 两端对齐时可拉伸的间隙（§8.4）。
///
/// 返回“间隙左侧字符”的代码单元偏移：绘制时给这些字符加额外字距，间距只
/// 落在字符之间，末字之后不产生间隙。
///
/// 规则：
/// 1. 只在相邻字符之间取间隙；
/// 2. 跳过含换行的间隙；
/// 3. 跳过两侧都是拉丁字母/数字的间隙，不拆英文单词；
/// 4. 不含 CJK 的行改为拉伸词间空格。
List<int> justifyGapOffsets(String text) {
  if (text.length < 2) {
    return const <int>[];
  }
  final cjk = containsCjk(text);
  final runes = text.runes.toList(growable: false);
  final offsets = <int>[];
  var offset = 0;
  for (var i = 0; i < runes.length; i++) {
    if (i < runes.length - 1) {
      final left = runes[i];
      final right = runes[i + 1];
      final stretchable = cjk
          ? left != 0x0A &&
                right != 0x0A &&
                !(_isLatinWordPart(left) && _isLatinWordPart(right))
          : left == 0x20;
      if (stretchable) {
        offsets.add(offset);
      }
    }
    offset += runes[i] > 0xFFFF ? 2 : 1;
  }
  return offsets;
}

/// 拉丁字母或数字，用于避免拆开英文单词。
bool _isLatinWordPart(int codePoint) {
  if (codePoint >= 0x30 && codePoint <= 0x39) {
    return true; // 0-9
  }
  if (codePoint >= 0x41 && codePoint <= 0x5A) {
    return true; // A-Z
  }
  if (codePoint >= 0x61 && codePoint <= 0x7A) {
    return true; // a-z
  }
  if (codePoint >= 0xC0 && codePoint <= 0x24F) {
    return true; // 拉丁扩展
  }
  return false;
}
