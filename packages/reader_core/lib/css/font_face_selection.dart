import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../text/font_coverage.dart';
import '../util/bounded_cache.dart';

/// CSS Fonts 3 的码点范围；非法描述符按未声明处理，默认覆盖全 Unicode。
class CssUnicodeRange {
  const CssUnicodeRange._(this.ranges);

  static const all = CssUnicodeRange._([(0, 0x10ffff)]);
  final List<(int, int)> ranges;

  static CssUnicodeRange parse(String? declaration) =>
      declaration == null ? all : tryParse(declaration) ?? all;

  static CssUnicodeRange? tryParse(String declaration) {
    final ranges = <(int, int)>[];
    for (final part in declaration.split(',')) {
      final range = _parseRange(part.trim());
      if (range == null) return null;
      ranges.add(range);
    }
    ranges.sort((a, b) => a.$1.compareTo(b.$1));
    final merged = <(int, int)>[];
    for (final range in ranges) {
      if (merged.isNotEmpty && range.$1 <= merged.last.$2 + 1) {
        final previous = merged.removeLast();
        merged.add((
          previous.$1,
          range.$2 > previous.$2 ? range.$2 : previous.$2,
        ));
      } else {
        merged.add(range);
      }
    }
    return CssUnicodeRange._(List.unmodifiable(merged));
  }

  static final _rangePattern = RegExp(
    r'^u\+([0-9a-f]{1,6})(?:-([0-9a-f]{1,6}))?$',
    caseSensitive: false,
  );
  static final _wildcardPattern = RegExp(
    r'^u\+([0-9a-f]*\?+)$',
    caseSensitive: false,
  );

  static (int, int)? _parseRange(String raw) {
    final wildcard = _wildcardPattern.firstMatch(raw)?.group(1);
    int start;
    int end;
    if (wildcard != null && wildcard.length <= 6) {
      start = int.parse(wildcard.replaceAll('?', '0'), radix: 16);
      end = int.parse(wildcard.replaceAll('?', 'f'), radix: 16);
    } else {
      final match = _rangePattern.firstMatch(raw);
      if (match == null) return null;
      start = int.parse(match[1]!, radix: 16);
      end = int.parse(match[2] ?? match[1]!, radix: 16);
    }
    if (start > end || start > 0x10ffff || end > 0x10ffff) return null;
    return (start, end);
  }

  bool covers(int codePoint) =>
      ranges.any((range) => codePoint >= range.$1 && codePoint <= range.$2);

  String get fingerprint =>
      ranges.map((range) => '${range.$1}-${range.$2}').join(',');
}

/// 一个独立 face 的不可变选择信息，不持有字体字节或书籍资源。
class BookFontFace {
  const BookFontFace({
    required this.alias,
    required this.nativeFamily,
    required this.weight,
    required this.style,
    required this.unicodeRange,
    this.coverage,
    this.defaultCovered = true,
  });

  final String alias;
  final String nativeFamily;
  final int weight;
  final String style;
  final CssUnicodeRange unicodeRange;
  final FontCoverage? coverage;
  final bool defaultCovered;

  bool covers(int codePoint) =>
      unicodeRange.covers(codePoint) &&
      (coverage?.covers(codePoint) ?? defaultCovered);
}

/// 内容稳定的内部族映射。与 Flutter 已加载字体同寿命，旧布局关闭后仍可绘制。
abstract final class BookFontFaceRegistry {
  static final Map<String, BookFontFace> _faces = {};
  static final Map<String, List<BookFontFace>> _families = {};
  static final _matches = BoundedCache<(String, int, String), List<String>>(
    512,
  );

  static void registerFace(BookFontFace face) {
    _faces.putIfAbsent(face.alias, () => face);
  }

  /// 组合族只保存当前声明集合与顺序；相同属性的重叠范围后声明先检查。
  static String registerFamily(String cssFamily, List<BookFontFace> faces) {
    final digest = sha256.convert(
      utf8.encode(
        jsonEncode([
          cssFamily.toLowerCase(),
          for (final face in faces) face.alias,
        ]),
      ),
    );
    final alias = 'bi_${digest}_${cssFamily.toLowerCase()}';
    _families.putIfAbsent(alias, () => List.unmodifiable(faces));
    return alias;
  }

  static bool contains(String family) =>
      _families.containsKey(family) || _faces.containsKey(family);

  static String nativeFamily(String family) =>
      _faces[family]?.nativeFamily ?? family;

  static bool? covers(String family, int codePoint) {
    final face = _faces[family];
    if (face != null) return face.covers(codePoint);
    final faces = _families[family];
    return faces?.any((face) => face.covers(codePoint));
  }

  /// 先匹配族内样式与字重，再由逐码点分段检查所选组合的覆盖。
  static List<String> match(String family, int weight, String style) {
    final faces = _families[family];
    if (faces == null) return [family];
    return _matches.putIfAbsent((family, weight, style), () {
      final matchedStyle = _styleOrder(
        style,
      ).firstWhere((candidate) => faces.any((face) => face.style == candidate));
      final styled = faces.where((face) => face.style == matchedStyle).toList();
      final weights = styled.map((face) => face.weight).toSet().toList()
        ..sort(
          (a, b) => _weightOrder(a, weight).compareTo(_weightOrder(b, weight)),
        );
      return List.unmodifiable([
        for (final face in styled.reversed)
          if (face.weight == weights.first) face.alias,
      ]);
    });
  }

  static List<String> _styleOrder(String style) => switch (style) {
    'italic' => const ['italic', 'oblique', 'normal'],
    'oblique' => const ['oblique', 'italic', 'normal'],
    _ => const ['normal', 'oblique', 'italic'],
  };

  static int _weightOrder(int candidate, int requested) {
    if (requested >= 400 && requested <= 500) {
      if (candidate >= requested && candidate <= 500) {
        return candidate - requested;
      }
      if (candidate < requested) return 1000 + requested - candidate;
      return 2000 + candidate - requested;
    }
    if (requested < 400) {
      return candidate <= requested
          ? requested - candidate
          : 1000 + candidate - requested;
    }
    return candidate >= requested
        ? candidate - requested
        : 1000 + requested - candidate;
  }
}
