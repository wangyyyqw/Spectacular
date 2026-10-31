import 'dart:collection';

/// 按最近访问顺序淘汰的定长缓存。
class BoundedCache<K extends Object, V extends Object> {
  /// 创建最多保存 [capacity] 项的缓存。
  BoundedCache(this.capacity) : assert(capacity > 0, '缓存容量必须大于 0');

  /// 最大条目数。
  final int capacity;

  final LinkedHashMap<K, V> _entries = LinkedHashMap<K, V>();

  /// 当前条目数。
  int get length => _entries.length;

  /// 是否包含 [key]；不会提升其最近使用顺序。
  bool containsKey(K key) => _entries.containsKey(key);

  /// 读取并提升 [key] 的最近使用顺序。
  V? operator [](K key) {
    if (!_entries.containsKey(key)) {
      return null;
    }
    final value = _entries.remove(key) as V;
    _entries[key] = value;
    return value;
  }

  /// 写入 [key] 并淘汰最久未使用的条目。
  void operator []=(K key, V value) {
    _entries
      ..remove(key)
      ..[key] = value;
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
  }

  /// 命中时提升顺序；未命中时调用 [create] 并写入结果。
  V putIfAbsent(K key, V Function() create) {
    final cached = this[key];
    if (cached != null) {
      return cached;
    }
    final value = create();
    this[key] = value;
    return value;
  }

  /// 删除并返回 [key] 对应的值。
  V? remove(K key) => _entries.remove(key);

  /// 清空全部条目。
  void clear() => _entries.clear();
}
