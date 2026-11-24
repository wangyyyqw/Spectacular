import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:reader_ui/decorations/decoration_rules.dart';
import 'package:reader_ui/decorations/decoration_image_store.dart';
import 'package:reader_ui/decorations/decoration_rule_defaults.dart';
import 'package:reader_ui/decorations/decoration_rule_matching.dart';

import '../library/revision_anchor_store.dart';
import 'db.dart';
import 'decoration_image_cleanup.dart';

/// 本书与全局的自动装饰规格存储；不写入任何匹配结果。
class DriftDecorationRuleStore
    implements ReaderDecorationRuleStore, ReaderDecorationRulePreferences {
  /// 为当前书提供两个作用域，书籍外键不随身份摘要更新而改变。
  DriftDecorationRuleStore(this._db, String bookId, {this.images})
    : _binding = RevisionBookBinding(_db, bookId);

  final AppDatabase _db;
  final RevisionBookBinding _binding;
  final ReaderDecorationImageStore? images;

  @override
  Future<List<ReaderDecorationRuleGroup>> listGroups() async {
    final book = await _binding.read();
    final rows = await _db.transaction(() async {
      await _ensureDefault(null);
      if (book != null) await _ensureDefault(book.id);
      return (_db.select(_db.decorationRuleGroups)
            ..where(
              (table) => book == null
                  ? table.bookId.isNull()
                  : table.bookId.isNull() | table.bookId.equals(book.id),
            )
            ..orderBy([
              (table) => OrderingTerm.asc(table.bookId),
              (table) => OrderingTerm.asc(table.isDefault),
              (table) => OrderingTerm.asc(table.sortOrder),
            ]))
          .get();
    });
    return [
      for (final row in rows)
        ReaderDecorationRuleGroup(
          id: row.id,
          bookId: row.bookId == null ? null : book?.uuid,
          name: row.name,
          enabled: row.enabled,
          isDefault: row.isDefault,
          sortOrder: row.sortOrder,
        ),
    ];
  }

  @override
  Future<List<ReaderDecorationRule>> listRules() async {
    final groups = await listGroups();
    await _ensureBuiltIns();
    final styles = {
      for (final style in await listStyles()) style.id: style.style,
    };
    final ids = groups.map((group) => group.id).toList();
    final rows =
        await (_db.select(_db.decorationRules)
              ..where((table) => table.groupId.isIn(ids))
              ..orderBy([
                (table) => OrderingTerm.asc(table.sortOrder),
                (table) => OrderingTerm.asc(table.createdAt),
              ]))
            .get();
    return [for (final row in rows) _decodeRule(row, styles)];
  }

  ReaderDecorationRule _decodeRule(
    DecorationRuleRow row,
    Map<String, ReaderDecorationRuleStyle> styles,
  ) {
    Map<String, Object?> json;
    try {
      final decoded = jsonDecode(row.styleJson);
      json = decoded is Map<String, Object?> ? decoded : {};
    } on FormatException {
      json = {};
    }
    final styleId = json['styleId'] as String?;
    final darkStyleId = json['darkStyleId'] as String?;
    final embedded = _style(row.styleJson);
    final style = styles[styleId] ?? embedded;
    return ReaderDecorationRule(
      id: row.id,
      groupId: row.groupId,
      name: row.name,
      pattern: row.pattern,
      isRegex: row.isRegex,
      caseSensitive: row.caseSensitive,
      enabled: row.enabled,
      style: style.withValues({
        'darkStyle': (styles[darkStyleId] ?? embedded.darkStyle)?.toJson(),
      }),
      sortOrder: row.sortOrder,
      type: ReaderDecorationRuleType.values
          .where((type) => type.name == json['matchType'])
          .firstOrNull,
      allowCrossParagraph: json['allowCrossParagraph'] == true,
      styleId: styleId,
      darkStyleId: darkStyleId,
    );
  }

  @override
  Future<void> saveGroup(ReaderDecorationRuleGroup group) async {
    final name = group.name.trim();
    if (name.isEmpty) throw const FormatException('分组名称不能为空');
    final book = group.bookId == null
        ? null
        : await _requireBook(group.bookId!);
    await _db.transaction(() async {
      if (book != null) await _requireBook(book.uuid);
      final existing = await (_db.select(
        _db.decorationRuleGroups,
      )..where((table) => table.id.equals(group.id))).getSingleOrNull();
      if (existing != null && existing.bookId != book?.id) {
        throw const FormatException('分组不能改变作用域');
      }
      if (existing == null && group.isDefault) {
        throw const FormatException('默认组由系统管理');
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      await _db
          .into(_db.decorationRuleGroups)
          .insertOnConflictUpdate(
            DecorationRuleGroupsCompanion.insert(
              id: group.id,
              bookId: Value(book?.id),
              name: name,
              enabled: Value(group.enabled),
              isDefault: Value(existing?.isDefault ?? false),
              sortOrder: Value(
                existing?.isDefault == true ? 0x7fffffff : group.sortOrder,
              ),
              createdAt: existing?.createdAt ?? now,
              updatedAt: now,
            ),
          );
      await _ensureDefault(book?.id);
    });
  }

  @override
  Future<void> removeGroup(String id) => _db.transaction(() async {
    final group = await _visibleGroup(id, writing: true);
    if (group == null) return;
    if (group.isDefault) throw const FormatException('默认组不能删除');
    final target = await _ensureDefault(group.bookId);
    final targetRules = await (_db.select(
      _db.decorationRules,
    )..where((table) => table.groupId.equals(target.id))).get();
    var order =
        targetRules.fold<int>(
          -1,
          (last, rule) => rule.sortOrder > last ? rule.sortOrder : last,
        ) +
        1;
    final rules =
        await (_db.select(_db.decorationRules)
              ..where((table) => table.groupId.equals(id))
              ..orderBy([(table) => OrderingTerm.asc(table.sortOrder)]))
            .get();
    for (final rule in rules) {
      await (_db.update(
        _db.decorationRules,
      )..where((table) => table.id.equals(rule.id))).write(
        DecorationRulesCompanion(
          groupId: Value(target.id),
          sortOrder: Value(order++),
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );
    }
    await (_db.delete(
      _db.decorationRuleGroups,
    )..where((table) => table.id.equals(id))).go();
  });

  @override
  Future<void> saveRule(ReaderDecorationRule rule) async {
    final error = validateDecorationRule(rule.effectiveType, rule.pattern);
    if (error != null) throw FormatException(error);
    await _db.transaction(() async {
      final group = await _visibleGroup(rule.groupId, writing: true);
      if (group == null) throw const FormatException('规则分组不存在');
      final existing = await (_db.select(
        _db.decorationRules,
      )..where((table) => table.id.equals(rule.id))).getSingleOrNull();
      if (existing != null &&
          await _visibleGroup(existing.groupId, writing: true) == null) {
        throw const FormatException('不能修改其他书籍的规则');
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      final name = rule.name?.trim();
      await _db
          .into(_db.decorationRules)
          .insertOnConflictUpdate(
            DecorationRulesCompanion.insert(
              id: rule.id,
              groupId: rule.groupId,
              name: Value(name == null || name.isEmpty ? null : name),
              pattern: rule.pattern,
              isRegex: Value(rule.isRegex),
              caseSensitive: Value(rule.caseSensitive),
              enabled: Value(rule.enabled),
              styleJson: jsonEncode({
                ...rule.style.toJson(),
                'matchType': rule.effectiveType.name,
                'allowCrossParagraph': rule.allowCrossParagraph,
                'styleId': rule.styleId,
                'darkStyleId': rule.darkStyleId,
              }),
              sortOrder: Value(rule.sortOrder),
              createdAt: existing?.createdAt ?? now,
              updatedAt: now,
            ),
          );
    });
    await cleanDecorationImages(_db, images);
  }

  @override
  Future<void> removeRule(String id) async {
    await _db.transaction(() async {
      final rule = await (_db.select(
        _db.decorationRules,
      )..where((table) => table.id.equals(id))).getSingleOrNull();
      if (rule == null) return;
      if (await _visibleGroup(rule.groupId, writing: true) == null) {
        throw const FormatException('不能删除其他书籍的规则');
      }
      await (_db.delete(
        _db.decorationRules,
      )..where((table) => table.id.equals(id))).go();
    });
    await cleanDecorationImages(_db, images);
  }

  @override
  Future<void> reorderGroups(List<String> ids) => _db.transaction(() async {
    if (ids.toSet().length != ids.length) {
      throw const FormatException('分组排序包含重复项');
    }
    final rows = <DecorationRuleGroupRow>[];
    for (final id in ids) {
      final group = await _visibleGroup(id, writing: true);
      if (group == null) throw const FormatException('分组不存在');
      rows.add(group);
    }
    final scopes = rows.map((group) => group.bookId).toSet();
    for (final scope in scopes) {
      final others =
          await (_db.select(_db.decorationRuleGroups)
                ..where(
                  (table) => scope == null
                      ? table.bookId.isNull()
                      : table.bookId.equals(scope),
                )
                ..orderBy([(table) => OrderingTerm.asc(table.sortOrder)]))
              .get();
      final ordered = [
        ...rows.where((group) => group.bookId == scope && !group.isDefault),
        ...others.where((group) => !ids.contains(group.id) && !group.isDefault),
        ...others.where((group) => group.isDefault),
      ];
      await _writeGroupOrder(ordered);
    }
  });

  @override
  Future<void> reorderRules(String groupId, List<String> ids) =>
      _db.transaction(() async {
        if (await _visibleGroup(groupId, writing: true) == null) {
          throw const FormatException('分组不存在');
        }
        final rules =
            await (_db.select(_db.decorationRules)
                  ..where((table) => table.groupId.equals(groupId))
                  ..orderBy([(table) => OrderingTerm.asc(table.sortOrder)]))
                .get();
        if (ids.toSet().length != ids.length ||
            ids.any((id) => !rules.any((rule) => rule.id == id))) {
          throw const FormatException('规则排序包含无效项');
        }
        final ordered = [
          ...ids,
          ...rules
              .where((rule) => !ids.contains(rule.id))
              .map((rule) => rule.id),
        ];
        for (var order = 0; order < ordered.length; order++) {
          await (_db.update(
            _db.decorationRules,
          )..where((table) => table.id.equals(ordered[order]))).write(
            DecorationRulesCompanion(
              sortOrder: Value(order),
              updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
            ),
          );
        }
      });

  Future<void> _writeGroupOrder(List<DecorationRuleGroupRow> ordered) async {
    for (var order = 0; order < ordered.length; order++) {
      final group = ordered[order];
      await (_db.update(
        _db.decorationRuleGroups,
      )..where((table) => table.id.equals(group.id))).write(
        DecorationRuleGroupsCompanion(
          sortOrder: Value(group.isDefault ? 0x7fffffff : order),
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );
    }
  }

  Future<DecorationRuleGroupRow> _ensureDefault(int? bookId) async {
    final id = bookId == null
        ? 'dec-default-global'
        : 'dec-default-book-$bookId';
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db
        .into(_db.decorationRuleGroups)
        .insert(
          DecorationRuleGroupsCompanion.insert(
            id: id,
            bookId: Value(bookId),
            name: '默认组',
            isDefault: const Value(true),
            sortOrder: const Value(0x7fffffff),
            createdAt: now,
            updatedAt: now,
          ),
          mode: InsertMode.insertOrIgnore,
        );
    return (_db.select(
      _db.decorationRuleGroups,
    )..where((table) => table.id.equals(id))).getSingle();
  }

  Future<BookRow> _requireBook(String id) async {
    final book = await _binding.writable();
    if (book == null || book.uuid != id) {
      throw const FormatException('书籍内容已更新，请重新打开阅读');
    }
    return book;
  }

  Future<DecorationRuleGroupRow?> _visibleGroup(
    String id, {
    bool writing = false,
  }) async {
    final group = await (_db.select(
      _db.decorationRuleGroups,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    if (group == null || group.bookId == null) return group;
    final book = writing ? await _binding.writable() : await _binding.read();
    return group.bookId == book?.id ? group : null;
  }

  ReaderDecorationRuleStyle _style(String raw) {
    try {
      return ReaderDecorationRuleStyle.fromJson(jsonDecode(raw));
    } on FormatException {
      return const ReaderDecorationRuleStyle();
    }
  }

  Future<void> _ensureBuiltIns() => _db.transaction(() async {
    final existing = await (_db.select(
      _db.settingsTable,
    )..where((t) => t.key.equals('decoration.defaults.v1'))).getSingleOrNull();
    if (existing != null) return;
    final group = await _ensureDefault(null);
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final rule in readerDecorationDefaultRules(group.id)) {
      await _db
          .into(_db.decorationRules)
          .insert(
            DecorationRulesCompanion.insert(
              id: rule.id,
              groupId: group.id,
              name: Value(rule.name),
              pattern: rule.pattern,
              enabled: Value(rule.enabled),
              styleJson: jsonEncode({
                ...rule.style.toJson(),
                'matchType': rule.effectiveType.name,
                'styleId': rule.styleId,
                'darkStyleId': rule.darkStyleId,
              }),
              sortOrder: Value(rule.sortOrder),
              createdAt: now,
              updatedAt: now,
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
    await _db
        .into(_db.settingsTable)
        .insertOnConflictUpdate(
          SettingsTableCompanion.insert(
            key: 'decoration.defaults.v1',
            value: '1',
          ),
        );
  });

  Future<Map<String, Object?>> _settingsStyles() async {
    final row = await (_db.select(
      _db.settingsTable,
    )..where((t) => t.key.equals('decoration.styles'))).getSingleOrNull();
    return row == null ? {} : jsonDecode(row.value) as Map<String, Object?>;
  }

  @override
  Future<List<ReaderDecorationNamedStyle>> listStyles() async {
    final saved = await _settingsStyles();
    return [
      for (final builtin in readerDecorationBuiltInStyles)
        if (!saved.containsKey(builtin.id)) builtin,
      for (final entry in saved.entries)
        ReaderDecorationNamedStyle(
          id: entry.key,
          name: (entry.value as Map<String, Object?>)['name']! as String,
          style: ReaderDecorationRuleStyle.fromJson(
            (entry.value as Map<String, Object?>)['style'],
          ),
          builtIn: readerDecorationBuiltInStyles.any((s) => s.id == entry.key),
        ),
    ];
  }

  @override
  Future<void> saveStyle(ReaderDecorationNamedStyle style) =>
      _db.transaction(() async {
        final next = await _settingsStyles();
        next[style.id] = {'name': style.name, 'style': style.style.toJson()};
        await _db
            .into(_db.settingsTable)
            .insertOnConflictUpdate(
              SettingsTableCompanion.insert(
                key: 'decoration.styles',
                value: jsonEncode(next),
              ),
            );
      });

  @override
  Future<void> removeStyle(String id) => _db.transaction(() async {
    if (readerDecorationBuiltInStyles.any((s) => s.id == id)) {
      throw const FormatException('内置样式不能删除，可编辑或复制');
    }
    final rules = await _db.select(_db.decorationRules).get();
    if (rules.any((r) {
      final json = jsonDecode(r.styleJson) as Map<String, Object?>;
      return json['styleId'] == id || json['darkStyleId'] == id;
    })) {
      throw const FormatException('该样式仍被规则使用');
    }
    final next = await _settingsStyles()
      ..remove(id);
    await _db
        .into(_db.settingsTable)
        .insertOnConflictUpdate(
          SettingsTableCompanion.insert(
            key: 'decoration.styles',
            value: jsonEncode(next),
          ),
        );
  });

  @override
  Future<Set<String>?> loadGlobalRuleSelection() async {
    final book = await _binding.read();
    if (book == null) return null;
    final row =
        await (_db.select(_db.settingsTable)..where(
              (t) => t.key.equals('decoration.globalSelection.${book.id}'),
            ))
            .getSingleOrNull();
    if (row == null || row.value.isEmpty) return null;
    return (jsonDecode(row.value) as List<Object?>).cast<String>().toSet();
  }

  @override
  Future<void> saveGlobalRuleSelection(Set<String>? ids) async {
    final book = await _binding.writable();
    if (book == null) throw const FormatException('书籍不可用');
    await _db
        .into(_db.settingsTable)
        .insertOnConflictUpdate(
          SettingsTableCompanion.insert(
            key: 'decoration.globalSelection.${book.id}',
            value: ids == null ? '' : jsonEncode(ids.toList()),
          ),
        );
  }
}
