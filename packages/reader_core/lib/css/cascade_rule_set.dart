import 'dart:collection';

import 'cascade_rule.dart';
import 'selector.dart';

/// 已按文档顺序排列的只读规则集，可在一次章节布局中复用候选索引。
///
/// 索引仅筛选末端的 id/class/tag；祖先、兄弟、属性和媒体条件仍由层叠器
/// 逐元素检查，不能按这些主体条件缓存最终计算样式。
class CascadeRuleSet extends UnmodifiableListView<CascadeRule> {
  /// 复制规则并稳定排序；相同 order 保持输入顺序。
  factory CascadeRuleSet(List<CascadeRule> rules) {
    final entries = rules.indexed.toList()
      ..sort((a, b) {
        final order = a.$2.order.compareTo(b.$2.order);
        return order != 0 ? order : a.$1.compareTo(b.$1);
      });
    return CascadeRuleSet._([for (final entry in entries) entry.$2]);
  }

  CascadeRuleSet._(super.source);

  static final _whitespace = RegExp(r'\s+');
  late final _buckets = _buildBuckets();
  final _candidates = <(String, String?, String), CascadeRuleSet>{};

  /// 任一规则依赖兄弟位置时，宿主不得按相同标签/属性共享计算样式。
  late final bool usesTreePosition = any(
    (rule) =>
        rule.selectors.selectors.any((selector) => selector.usesTreePosition),
  );

  Map<(String, String), List<int>> _buildBuckets() {
    final buckets = <(String, String), List<int>>{};
    for (final (index, rule) in indexed) {
      for (final selector in rule.selectors.selectors) {
        if (selector.parts.isEmpty) continue;
        final part = selector.parts.last;
        final key = part.id != null
            ? ('id', part.id!)
            : part.classes.isNotEmpty
            ? ('class', part.classes.first)
            : part.tag != null
            ? ('tag', part.tag!.toLowerCase())
            : ('*', '');
        buckets.putIfAbsent(key, () => []).add(index);
      }
    }
    return buckets;
  }

  /// 返回可能匹配的规则，去重且保持原顺序；不会持有元素或文档树。
  CascadeRuleSet candidatesFor(SelectorElement element) {
    final tag = element.tag.toLowerCase();
    final id = element.attributes['id'];
    final classes =
        (element.attributes['class'] ?? '')
            .split(_whitespace)
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return _candidates.putIfAbsent((tag, id, classes.join(' ')), () {
      final positions = <int>{};
      for (final key in [
        ('*', ''),
        ('tag', tag),
        if (id != null) ('id', id),
        for (final name in classes) ('class', name),
      ]) {
        positions.addAll(_buckets[key] ?? const <int>[]);
      }
      final ordered = positions.toList()..sort();
      return CascadeRuleSet._([for (final index in ordered) this[index]]);
    });
  }
}
