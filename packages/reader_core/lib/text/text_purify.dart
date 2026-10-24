/// 书内空格整理（P7-20；对照 Reeden 行为「把 , . ! ? : ; ( ) 改成
/// ，．！？：；（）；不改 ～ = - / 等符号、3.14 这类数字和空格」，
/// 150 号 §0-#5）。
///
/// 定位：**TXT 源改路径的纯函数工具**（Reeden 的整理属 TXT「改源」
/// 哲学，330 号），EPUB 渲染路径不接线——字符替换会改变锚定文本，
/// 破坏 CFI/引文匹配；EPUB 的等价诉求走样式路径。
///
/// 白名单（逐条有单测）：
/// 1. `3.14` 类数字：`.` 两侧都是 ASCII 数字时不转换；
/// 2. `～ = - /` 等符号不在映射表，原样保留；
/// 3. 空格原样保留（整理不改空格、不改换行）；
/// 4. 仅当至少一侧是 CJK 时才转换（纯西文上下文不动）。
library;

/// 半角 → 全角映射（仅此表内字符参与整理）。
const Map<String, String> halfwidthToFullwidth = <String, String>{
  ',': '，',
  '.': '．',
  '!': '！',
  '?': '？',
  ':': '：',
  ';': '；',
  '(': '（',
  ')': '）',
};

bool _isCjkCodePoint(int codePoint) =>
    (codePoint >= 0x4E00 && codePoint <= 0x9FFF) ||
    (codePoint >= 0x3400 && codePoint <= 0x4DBF) ||
    (codePoint >= 0x3040 && codePoint <= 0x30FF) ||
    (codePoint >= 0xAC00 && codePoint <= 0xD7AF) ||
    (codePoint >= 0x3000 && codePoint <= 0x303F); // CJK 标点。

bool _isAsciiDigit(int codePoint) => codePoint >= 0x30 && codePoint <= 0x39;

/// 整理 [text]：按映射表转换半角标点为全角。
///
/// 规则：
/// - 字符在映射表内，且至少一侧相邻字符是 CJK；
/// - `.`/`,` 两侧都是 ASCII 数字时保留（`3.14`、`1,000`）；
/// - 其余字符（含空格、换行、映射外符号）原样保留。
String purifySpaces(String text) {
  final runes = text.runes.toList(growable: false);
  final buffer = StringBuffer();
  for (var i = 0; i < runes.length; i++) {
    final char = String.fromCharCode(runes[i]);
    final replacement = halfwidthToFullwidth[char];
    if (replacement == null) {
      buffer.write(char);
      continue;
    }
    final prev = i > 0 ? runes[i - 1] : null;
    final next = i + 1 < runes.length ? runes[i + 1] : null;
    // 数字保护：3.14 / 1,000。
    if (_isAsciiDigit(prev ?? 0) && _isAsciiDigit(next ?? 0)) {
      buffer.write(char);
      continue;
    }
    // 上下文要求：跳过空格后最近邻至少一侧 CJK
    //（「你好 , 世界」的逗号两侧是空格，按最近非空格邻判定）。
    final cjkNear =
        _nearestNonSpaceIsCjk(runes, i - 1, -1) ||
        _nearestNonSpaceIsCjk(runes, i + 1, 1);
    buffer.write(cjkNear ? replacement : char);
  }
  return buffer.toString();
}

/// 从 [start] 沿 [step] 方向找最近的非空格字符，是 CJK 返回 true；
/// 越界或不存在返回 false。
bool _nearestNonSpaceIsCjk(List<int> runes, int start, int step) {
  var i = start;
  while (i >= 0 && i < runes.length) {
    final codePoint = runes[i];
    if (codePoint != 0x20 && codePoint != 0x09) {
      return _isCjkCodePoint(codePoint);
    }
    i += step;
  }
  return false;
}
