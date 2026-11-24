import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../library/library_store.dart';

const _bookColorSettingKey = 'stats.book_colors';

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

/// 单张封面的取色入口，测试可替换为可控延迟。
typedef BookCoverColorLoader = Future<Color?> Function(String path);

/// 一本书的本地取色结果；封面路径用于识别换封面。
class StoredBookColor {
  const StoredBookColor({required this.coverPath, required this.color});

  final String? coverPath;
  final Color color;

  Map<String, Object?> toJson() => {'p': coverPath, 'c': color.toARGB32()};

  static StoredBookColor? fromJson(Object? value) {
    if (value is! Map) return null;
    final color = value['c'];
    final path = value['p'];
    if (color is! int || (path != null && path is! String)) return null;
    return StoredBookColor(coverPath: path as String?, color: Color(color));
  }
}

/// 封面取色的本地存储，独立于书架记录，删书后仍保留。
abstract interface class ReadingBookColorStore {
  Future<Map<String, StoredBookColor>> load();

  Future<void> save(Map<String, StoredBookColor> colors);
}

/// 用设置表保存取色结果；书籍删除或移出书架都不会清理这些条目。
class SettingsBookColorStore implements ReadingBookColorStore {
  SettingsBookColorStore(this._library);

  final LibraryStore _library;

  @override
  Future<Map<String, StoredBookColor>> load() async {
    final raw = await _library.getSetting(_bookColorSettingKey);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return {
        for (final entry in decoded.entries)
          if (entry.key is String)
            entry.key as String: ?StoredBookColor.fromJson(entry.value),
      };
    } catch (_) {
      return const {};
    }
  }

  @override
  Future<void> save(Map<String, StoredBookColor> colors) => _library.setSetting(
    _bookColorSettingKey,
    jsonEncode({
      for (final entry in colors.entries) entry.key: entry.value.toJson(),
    }),
  );
}

/// 统计页复用封面取色结果；换封面路径才重新解码，不在动画帧中读取图片。
class ReadingBookColorCache {
  ReadingBookColorCache({BookCoverColorLoader? loadCoverColor, this.store})
    : _loadCoverColor = loadCoverColor ?? _coverColor;

  static const _maxConcurrent = 4;
  static const _coverTimeout = Duration(seconds: 3);

  final BookCoverColorLoader _loadCoverColor;
  final ReadingBookColorStore? store;
  final _covers = <String, Future<Color?>>{};
  final _stored = <String, StoredBookColor>{};
  final _resolved = <String, Color>{};
  Future<void>? _storedLoad;

  /// 已确定的配色（本地记录或本次取色）；未就绪的书籍由图表使用备用色。
  Map<String, Color> readyColors(Iterable<String> bookIds) {
    final ids = bookIds.toSet().toList()..sort();
    return Map.unmodifiable({for (final id in ids) id: ?_resolved[id]});
  }

  Future<Map<String, Color>> load(
    Iterable<BookEntry> books,
    Iterable<String> bookIds,
  ) async {
    await (_storedLoad ??= _loadStored());
    final booksById = {for (final book in books) book.id: book};
    final ids = bookIds.toSet().toList()..sort();
    final colors = <String, Color>{};
    final pending = <String>[];
    for (final id in ids) {
      final stored = _stored[id];
      final book = booksById[id];
      // 已移除的书没有书架记录，仍沿用上次取色；换封面才重新取色。
      if (stored != null &&
          (book == null || stored.coverPath == book.coverPath)) {
        colors[id] = stored.color;
      } else {
        pending.add(id);
      }
    }
    final covers = <String, Color?>{};
    for (var offset = 0; offset < pending.length; offset += _maxConcurrent) {
      final batch = pending.skip(offset).take(_maxConcurrent);
      await Future.wait([
        for (final id in batch)
          _coverFor(booksById[id]).then((color) => covers[id] = color),
      ]);
    }
    final updated = Map<String, StoredBookColor>.of(_stored);
    for (final id in pending) {
      final color = _distinctBookColor(
        id,
        covers[id] ?? readingBookColor(id),
        colors.values,
      );
      colors[id] = color;
      updated[id] = StoredBookColor(
        coverPath: booksById[id]?.coverPath,
        color: color,
      );
    }
    for (final entry in colors.entries) {
      _resolved[entry.key] = entry.value;
    }
    if (pending.isNotEmpty) {
      _stored
        ..clear()
        ..addAll(updated);
      await _saveStored();
    }
    return Map.unmodifiable(colors);
  }

  Future<void> _loadStored() async {
    try {
      _stored.addAll(await store?.load() ?? const {});
    } catch (_) {
      // 本地记录不可读时重新取色，不阻断统计。
    }
    for (final entry in _stored.entries) {
      _resolved[entry.key] = entry.value.color;
    }
  }

  Future<void> _saveStored() async {
    try {
      await store?.save(Map.unmodifiable(_stored));
    } catch (_) {
      // 写入失败仍保留内存配色，下次进入统计可重新取色。
    }
  }

  Future<Color?> _coverFor(BookEntry? book) {
    final path = book?.coverPath;
    if (path == null) return Future.value(null);
    return _covers.putIfAbsent(path, () async {
      Color? color;
      try {
        color = await _loadCoverColor(path).timeout(_coverTimeout);
      } catch (_) {
        // 封面缺失、损坏或解码超时仍正常显示统计，使用备用色。
        color = null;
      }
      return color;
    });
  }
}

Future<Color?> _coverColor(String path) async {
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
