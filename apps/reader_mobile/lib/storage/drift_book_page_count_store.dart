import 'dart:convert';

import '../library/revision_anchor_store.dart';
import '../reader/epub/book_page_counter.dart';
import 'db.dart';

typedef _StoredPageCounts = ({String layoutKey, Map<int, int> counts});

/// 复用设置表保存同一本书最近两套排版的分章页数。
///
/// 内容版本和完整布局键分别校验；缓存只含页数，不保存页面或原书资源。
class DriftBookPageCountStore implements BookPageCountStore {
  DriftBookPageCountStore(
    this._db, {
    required this.bookId,
    required this.contentRevision,
  });

  static const int _schemaVersion = 1;
  final AppDatabase _db;
  final String bookId;
  final String contentRevision;

  String get _settingKey => 'epub-page-counts:v1:$bookId';

  @override
  Future<Map<int, int>> load(String layoutKey) async {
    if (layoutKey.isEmpty || !await _matchesCurrentBook()) return {};
    final layouts = await _readLayouts();
    if (!await _matchesCurrentBook()) return {};
    for (final layout in layouts.reversed) {
      if (layout.layoutKey == layoutKey) {
        return Map<int, int>.unmodifiable(layout.counts);
      }
    }
    return {};
  }

  @override
  Future<void> save(String layoutKey, Map<int, int> counts) async {
    if (layoutKey.isEmpty) return;
    if (counts.entries.any((entry) => entry.key < 0 || entry.value < 0)) {
      throw ArgumentError.value(counts, 'counts', '章节序号和页数不能为负');
    }
    final snapshot = Map<int, int>.unmodifiable(counts);
    await _db.transaction(() async {
      if (!await _matchesCurrentBook()) return;
      final layouts = [
        for (final layout in await _readLayouts())
          if (layout.layoutKey != layoutKey) layout,
        (layoutKey: layoutKey, counts: snapshot),
      ];
      final recent = layouts.skip(layouts.length > 2 ? layouts.length - 2 : 0);
      await _db
          .into(_db.settingsTable)
          .insertOnConflictUpdate(
            SettingsTableCompanion.insert(
              key: _settingKey,
              value: jsonEncode({
                'schemaVersion': _schemaVersion,
                'contentRevision': contentRevision,
                'layouts': [for (final layout in recent) _encodeLayout(layout)],
              }),
            ),
          );
    });
  }

  Future<bool> _matchesCurrentBook() async {
    final row = await resolveBookRow(_db, bookId, allowAliases: false);
    return row != null &&
        row.deletedAt == null &&
        row.contentRevision == contentRevision;
  }

  Future<List<_StoredPageCounts>> _readLayouts() async {
    final row = await (_db.select(
      _db.settingsTable,
    )..where((table) => table.key.equals(_settingKey))).getSingleOrNull();
    if (row == null) return [];
    try {
      final value = jsonDecode(row.value);
      if (value is! Map<String, dynamic> ||
          value['schemaVersion'] != _schemaVersion ||
          value['contentRevision'] != contentRevision ||
          value['layouts'] is! List) {
        return [];
      }
      return [
        for (final layout in value['layouts'] as List<dynamic>)
          ?_decodeLayout(layout),
      ];
    } on FormatException {
      return [];
    }
  }

  _StoredPageCounts? _decodeLayout(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final key = value['layoutKey'];
    final rawCounts = value['counts'];
    if (key is! String || key.isEmpty || rawCounts is! Map<String, dynamic>) {
      return null;
    }
    final counts = <int, int>{};
    for (final entry in rawCounts.entries) {
      final spine = int.tryParse(entry.key);
      final pages = entry.value;
      if (spine == null || spine < 0 || pages is! int || pages < 0) return null;
      counts[spine] = pages;
    }
    return (layoutKey: key, counts: counts);
  }

  Map<String, Object> _encodeLayout(_StoredPageCounts layout) => {
    'layoutKey': layout.layoutKey,
    'counts': {
      for (final entry in layout.counts.entries) '${entry.key}': entry.value,
    },
  };
}
