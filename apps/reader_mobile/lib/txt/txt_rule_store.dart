import 'dart:convert';

import 'package:reader_core/txt.dart';

import '../library/library_store.dart';

/// 个人规则与书籍中的规则快照分开保存，编辑规则不会自动改书。
class TxtRuleStore {
  const TxtRuleStore(this.library);

  final LibraryStore library;
  static const key = txtChapterRulesSettingKey;

  Future<List<ChapterRule>> load() async {
    final value = await library.getSetting(key);
    if (value == null) return [];
    return [
      for (final item in jsonDecode(value) as List)
        ChapterRule.fromJson(item as Map<String, dynamic>),
    ];
  }

  Future<void> save(ChapterRule rule) async {
    if (rule.name.trim().isEmpty || rule.pattern.trim().isEmpty) {
      throw const FormatException('规则名称和章节正则不能为空');
    }
    ChapterDetector.validateRule(rule);
    final rules = await load();
    final index = rules.indexWhere((item) => item.id == rule.id);
    if (index < 0) {
      rules.add(rule);
    } else {
      rules[index] = rule;
    }
    await library.setSetting(
      key,
      jsonEncode(rules.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> delete(String id) async {
    final rules = await load();
    rules.removeWhere((rule) => rule.id == id);
    await library.setSetting(
      key,
      jsonEncode(rules.map((item) => item.toJson()).toList()),
    );
  }
}
