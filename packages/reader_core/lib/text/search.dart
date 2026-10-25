/// 一个 2-gram 及其在章文本中的位置（§66.2）。
class SearchGram {
  /// 创建 gram。
  const SearchGram({required this.gram, required this.offset});

  /// gram 文本。
  final String gram;

  /// 起始字符偏移（章内）。
  final int offset;

  @override
  String toString() => 'SearchGram($gram@$offset)';
}

/// 2-gram 索引的切分规则（§66.2）。
///
/// - 中文：逐字两两切；
/// - 英文：按词切，词内两两切（避免跨词伪匹配）；
/// - 数字：整串做一个 gram；
/// - 标点与空白：分隔符，不产生 gram。
abstract final class SearchTokenizer {
  /// 一段文本的全部 gram（按 offset 升序）。
  static List<SearchGram> gramsOf(String text) {
    final grams = <SearchGram>[];
    var index = 0;
    while (index < text.length) {
      final code = text.codeUnitAt(index);
      if (_isCjk(code)) {
        // 连续中文段。
        final start = index;
        while (index < text.length && _isCjk(text.codeUnitAt(index))) {
          index++;
        }
        for (var i = start; i + 1 < index; i++) {
          grams.add(
            SearchGram(gram: text.substring(i, i + 2), offset: i),
          );
        }
        continue;
      }
      if (_isDigit(code)) {
        // 数字整串作为一个 gram。
        final start = index;
        while (index < text.length && _isDigit(text.codeUnitAt(index))) {
          index++;
        }
        grams.add(
          SearchGram(gram: text.substring(start, index), offset: start),
        );
        continue;
      }
      if (_isLatin(code)) {
        // 拉丁词：词内两两切。
        final start = index;
        while (index < text.length && _isLatin(text.codeUnitAt(index))) {
          index++;
        }
        final word = text.substring(start, index);
        if (word.length == 1) {
          grams.add(SearchGram(gram: word, offset: start));
        } else {
          for (var i = 0; i + 1 < word.length; i++) {
            grams.add(
              SearchGram(gram: word.substring(i, i + 2), offset: start + i),
            );
          }
        }
        continue;
      }
      // 标点/空白：分隔符。
      index++;
    }
    return grams;
  }

  /// 查询词的 gram（与建索引用同一套规则，去掉重复）。
  static List<String> queryGrams(String query) {
    final seen = <String>{};
    final result = <String>[];
    for (final gram in gramsOf(query)) {
      if (seen.add(gram.gram)) {
        result.add(gram.gram);
      }
    }
    return result;
  }

  static bool _isCjk(int code) =>
      (code >= 0x4E00 && code <= 0x9FFF) ||
      (code >= 0x3400 && code <= 0x4DBF) ||
      (code >= 0x3040 && code <= 0x30FF);

  static bool _isLatin(int code) =>
      (code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A);

  static bool _isDigit(int code) => code >= 0x30 && code <= 0x39;
}
