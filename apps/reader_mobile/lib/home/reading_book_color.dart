import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../library/library_store.dart';

const _bookPalette = [
  Color(0xFF397665),
  Color(0xFF417786),
  Color(0xFF95634F),
  Color(0xFFA3413F),
  Color(0xFF70658E),
  Color(0xFF77723F),
];

/// 同一本书在阅读日历与时长图表中使用一致的识别色。
Color readingBookColor(
  String bookId, {
  Brightness brightness = Brightness.light,
  Map<String, Color> bookColors = const {},
}) {
  final color =
      bookColors[bookId] ??
      _bookPalette[_bookColorSeed(bookId) % _bookPalette.length];
  return brightness == Brightness.dark
      ? Color.lerp(color, Colors.white, .3)!
      : color;
}

/// 统计页复用封面取色结果；换封面路径才重新解码，不在动画帧中读取图片。
class ReadingBookColorCache {
  final _covers = <String, Future<Color?>>{};

  Future<Map<String, Color>> load(
    Iterable<BookEntry> books,
    Iterable<String> bookIds,
  ) async {
    final booksById = {for (final book in books) book.id: book};
    final ids = bookIds.toSet().toList()..sort();
    final colors = <String, Color>{};
    for (final id in ids) {
      final coverColor = await _coverFor(booksById[id]);
      colors[id] = _distinctBookColor(
        id,
        coverColor ?? readingBookColor(id),
        colors.values,
      );
    }
    return Map.unmodifiable(colors);
  }

  Future<Color?> _coverFor(BookEntry? book) {
    final path = book?.coverPath;
    if (path == null) return Future.value(null);
    return _covers.putIfAbsent(path, () => _coverColor(path));
  }
}

Future<Color?> _coverColor(String path) async {
  try {
    final scheme = await ColorScheme.fromImageProvider(
      provider: ResizeImage(
        FileImage(File(path)),
        width: 48,
        height: 48,
        policy: ResizeImagePolicy.fit,
      ),
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
    return scheme.primary;
  } on Exception {
    // 封面缺失或无法解码时仍正常显示统计，使用书籍身份对应的备用色。
    return null;
  }
}

Color _distinctBookColor(String bookId, Color base, Iterable<Color> assigned) {
  var best = base;
  var bestDistance = _minimumColorDistance(base, assigned);
  if (bestDistance >= .025) return base;
  final hsl = HSLColor.fromColor(base);
  // 优先保留封面色相；相近书籍从小幅偏移开始，仍使用可读的主色明度。
  for (final offset in [
    16,
    -16,
    32,
    -32,
    48,
    -48,
    64,
    -64,
    96,
    -96,
    144,
    -144,
    180,
    for (var index = 0; index < 12; index++)
      (_bookColorSeed(bookId) * .61 + index * 137.508) % 360,
  ]) {
    final candidate = ColorScheme.fromSeed(
      seedColor: hsl.withHue((hsl.hue + offset) % 360).toColor(),
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    ).primary;
    final distance = _minimumColorDistance(candidate, assigned);
    if (distance >= .025) return candidate;
    if (distance > bestDistance) {
      best = candidate;
      bestDistance = distance;
    }
  }
  return best;
}

double _minimumColorDistance(Color color, Iterable<Color> assigned) =>
    assigned.fold(double.infinity, (distance, other) {
      final r = color.r - other.r;
      final g = color.g - other.g;
      final b = color.b - other.b;
      return math.min(distance, r * r + g * g + b * b);
    });

int _bookColorSeed(String bookId) {
  var hash = 0;
  for (final unit in bookId.codeUnits) {
    hash = (hash * 31 + unit) & 0x3fffffff;
  }
  return hash;
}
