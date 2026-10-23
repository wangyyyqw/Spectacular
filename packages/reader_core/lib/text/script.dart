/// CJK 字符范围判定。
///
/// 阅微的 `isCjk` 把 `0 <= c < 42720` 整段算作 CJK，连 ASCII 都包含在内
/// （§16）；这里按 Unicode 区块重新划定，只保留真正的 CJK 文字。
library;

/// 是否属于 CJK 文字（含假名、谚文、全角符号与 CJK 标点）。
bool isCjkCodePoint(int codePoint) {
  if (codePoint >= 0x4E00 && codePoint <= 0x9FFF) {
    return true; // CJK 统一表意文字基本区
  }
  if (codePoint >= 0x3400 && codePoint <= 0x4DBF) {
    return true; // 扩展 A
  }
  if (codePoint >= 0xF900 && codePoint <= 0xFAFF) {
    return true; // 兼容表意文字
  }
  if (codePoint >= 0x20000 && codePoint <= 0x2FA1F) {
    return true; // 扩展 B 及以后
  }
  if (codePoint >= 0x3000 && codePoint <= 0x303F) {
    return true; // CJK 符号与标点
  }
  if (codePoint >= 0x3040 && codePoint <= 0x30FF) {
    return true; // 平假名与片假名
  }
  if (codePoint >= 0xAC00 && codePoint <= 0xD7AF) {
    return true; // 谚文音节
  }
  if (codePoint >= 0xFF00 && codePoint <= 0xFFEF) {
    return true; // 全角字符
  }
  return false;
}

/// 文本是否含 CJK 字符。
bool containsCjk(String text) {
  for (final rune in text.runes) {
    if (isCjkCodePoint(rune)) {
      return true;
    }
  }
  return false;
}
