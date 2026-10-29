import 'dart:convert';
import 'dart:math' as math;

import 'en_us_hyphenation.dart';

/// 基于 Liang 算法的美式英语断词器。
///
/// 词表来自 hyph_en_US.dic（BSD-style 许可），由生成脚本内嵌为 Dart 常量。
/// 断点使用 UTF-16 下标，并遵守词表声明的左右最小字符数。
final class EnUsHyphenator {
  static Map<String, List<int>>? _patterns;
  static int _maxPatternLength = 0;
  // macOS CoreFoundation 的 en_US 词库与 hyph_en_US 在少数复合词上不同。
  // Chrome 在 macOS 用前者；这些补充断点经
  // `CFStringGetHyphenationLocationBeforeIndex` 核对。
  static const Map<String, List<int>> _platformBreakOffsets = {
    'extraordinarily': <int>[5],
  };

  /// 返回可在 `word[offset]` 前断行的偏移（不含词首/词尾）。
  static List<int> breakOffsets(String word) {
    final lower = word.toLowerCase().replaceAll('\u2019', "'");
    if (lower.length < 5 || !_isHyphenatable(lower)) {
      return const <int>[];
    }
    _ensureLoaded();
    final patterns = _patterns!;
    final padded = '.$lower.';
    final scores = List<int>.filled(padded.length + 1, 0);
    for (var start = 0; start < padded.length; start++) {
      final limit = math.min(_maxPatternLength, padded.length - start);
      for (var length = 1; length <= limit; length++) {
        final values = patterns[padded.substring(start, start + length)];
        if (values == null) {
          continue;
        }
        for (var i = 0; i < values.length; i++) {
          scores[start + i] = math.max(scores[start + i], values[i]);
        }
      }
    }
    final offsets = <int>[...?_platformBreakOffsets[lower]];
    for (var offset = 2; offset <= lower.length - 3; offset++) {
      if (scores[offset + 1].isOdd) {
        offsets.add(offset);
      }
    }
    offsets.sort();
    return offsets;
  }

  static bool _isHyphenatable(String word) {
    for (final code in word.codeUnits) {
      final letter =
          (code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A);
      if (!letter && code != 0x27) {
        return false;
      }
    }
    return true;
  }

  static void _ensureLoaded() {
    if (_patterns != null) {
      return;
    }
    final patterns = <String, List<int>>{};
    for (final line in const LineSplitter().convert(enUsHyphenationPatterns)) {
      final value = line.trim();
      if (value.isEmpty) {
        continue;
      }
      final key = StringBuffer();
      final scores = <int>[0];
      for (final rune in value.runes) {
        final digit = rune >= 0x30 && rune <= 0x39;
        if (digit) {
          scores[scores.length - 1] = rune - 0x30;
        } else {
          key.writeCharCode(rune);
          scores.add(0);
        }
      }
      final pattern = key.toString();
      if (pattern.isEmpty) {
        continue;
      }
      patterns[pattern] = scores;
      _maxPatternLength = math.max(_maxPatternLength, pattern.length);
    }
    _patterns = patterns;
  }
}
