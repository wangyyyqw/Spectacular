/// 纯文本分词与切句（P4-16，§40.2）。
///
/// 不依赖排版结果，只吃字符串与偏移；TTS 切句、分享粒度、选区扩展都复用
/// 这里。中文不做词典分词：CJK 连续段即一个"词"。
library;

/// 文本区间（半开）。
class TextSpanRange {
  /// 创建区间。
  const TextSpanRange(this.start, this.end);

  /// 起点（含）。
  final int start;

  /// 终点（不含）。
  final int end;

  /// 长度。
  int get length => end - start;

  /// 是否为空区间。
  bool get isEmpty => start >= end;

  @override
  String toString() => 'TextSpanRange($start, $end)';
}

/// 分词与切句规则（§40.2）。
abstract final class TextSegmenter {
  /// 句末标点。
  static const String sentenceBreaks = '。！？!?…';

  /// 紧跟句末标点、归入前一句的收尾字符（后引号/后括号，§40.2）。
  static const String sentenceTrailers = '”’」』）)】》〉"\'}]';

  /// 段内换行按句界处理。
  static const String sentenceLineBreaks = '\n\r';

  /// 取偏移所在的词。
  ///
  /// 规则：CJK 连续段 / 拉丁字母数字连续段 / 其他字符单独成词。偏移等于
  /// 文本长度时取最后一个字符所在的词。
  static TextSpanRange wordRangeAt(String text, int offset) {
    if (text.isEmpty) {
      return const TextSpanRange(0, 0);
    }
    final index = offset >= text.length ? text.length - 1 : offset;
    final pivot = index < 0 ? 0 : index;
    final char = text.substring(pivot, pivot + 1);
    if (_isCjkLetter(char)) {
      return _expand(text, pivot, _isCjkLetter);
    }
    if (_isLatinOrDigit(char)) {
      return _expand(text, pivot, _isLatinOrDigit);
    }
    return TextSpanRange(pivot, pivot + 1);
  }

  /// 取偏移所在的句。
  ///
  /// 句界：句末标点（后引号/后括号归入前一句）与换行；文本首尾、块边界也
  /// 由调用方视为句界（这里只管字符串内部）。
  static TextSpanRange sentenceRangeAt(String text, int offset) {
    if (text.isEmpty) {
      return const TextSpanRange(0, 0);
    }
    final index = offset.clamp(0, text.length);
    // 向左找句首：上一个句末标点（连同其后的收尾字符）或换行之后。
    var start = 0;
    for (var i = index - 1; i >= 0; i--) {
      final char = text.substring(i, i + 1);
      if (sentenceLineBreaks.contains(char)) {
        start = i + 1;
        break;
      }
      if (sentenceBreaks.contains(char)) {
        var next = i + 1;
        // 连续句末标点（「……」「！？」连写）按一个句末处理。
        while (next < text.length &&
            sentenceBreaks.contains(text.substring(next, next + 1))) {
          next += 1;
        }
        while (next < text.length &&
            sentenceTrailers.contains(text.substring(next, next + 1))) {
          next += 1;
        }
        if (next <= index) {
          start = next;
          break;
        }
      }
    }
    // 向右找句尾：句末标点（含其后收尾字符）或换行。
    var end = text.length;
    for (var i = index; i < text.length; i++) {
      final char = text.substring(i, i + 1);
      if (sentenceLineBreaks.contains(char)) {
        end = i;
        break;
      }
      if (sentenceBreaks.contains(char)) {
        var next = i + 1;
        while (next < text.length &&
            sentenceBreaks.contains(text.substring(next, next + 1))) {
          next += 1;
        }
        while (next < text.length &&
            sentenceTrailers.contains(text.substring(next, next + 1))) {
          next += 1;
        }
        end = next;
        break;
      }
    }
    if (end < start) {
      end = start;
    }
    return TextSpanRange(start, end);
  }

  /// 是否 CJK 字母（汉字、假名、谚文）。
  static bool _isCjkLetter(String char) {
    if (char.isEmpty) {
      return false;
    }
    final code = char.codeUnitAt(0);
    return (code >= 0x4E00 && code <= 0x9FFF) ||
        (code >= 0x3400 && code <= 0x4DBF) ||
        (code >= 0x3040 && code <= 0x30FF) ||
        (code >= 0xAC00 && code <= 0xD7AF) ||
        (code >= 0xF900 && code <= 0xFAFF) ||
        (code >= 0xFF21 && code <= 0xFF5A);
  }

  /// 是否拉丁字母或数字。
  static bool _isLatinOrDigit(String char) {
    if (char.isEmpty) {
      return false;
    }
    final code = char.codeUnitAt(0);
    return (code >= 0x30 && code <= 0x39) ||
        (code >= 0x41 && code <= 0x5A) ||
        (code >= 0x61 && code <= 0x7A);
  }

  static TextSpanRange _expand(
    String text,
    int pivot,
    bool Function(String) predicate,
  ) {
    var start = pivot;
    var end = pivot + 1;
    while (start > 0 && predicate(text.substring(start - 1, start))) {
      start -= 1;
    }
    while (end < text.length && predicate(text.substring(end, end + 1))) {
      end += 1;
    }
    return TextSpanRange(start, end);
  }
}
