import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../util/bounded_cache.dart';

/// 编辑会话共享的纯数据缓存，不拥有归档、worker 或源的关闭权限。
/// 每项记录实际资源版本；旧快照即使晚完成也不能命中新版本。
class ChapterPreviewCache<T extends Object> {
  static const maxEntries = 3;
  final _entries = BoundedCache<String, _PreviewEntry<T>>(maxEntries);
  int get length => _entries.length;

  T? get(String key, Map<String, String> versions) {
    final entry = _entries[key];
    if (entry == null ||
        entry.versions.entries.any(
          (item) => item.value != (versions[item.key] ?? ''),
        )) {
      return null;
    }
    return entry.value;
  }

  void put(
    String key,
    T value,
    Set<String> paths,
    Map<String, String> versions,
  ) {
    _entries[key] = _PreviewEntry(value, {
      for (final path in paths) path: versions[path] ?? '',
    });
  }

  void clear() => _entries.clear();

  static String fingerprint(Set<String> paths, Map<String, String> versions) {
    final sorted = paths.toList()..sort();
    return sha256
        .convert(
          utf8.encode(
            jsonEncode([
              for (final path in sorted) [path, versions[path] ?? ''],
            ]),
          ),
        )
        .toString();
  }
}

class _PreviewEntry<T> {
  const _PreviewEntry(this.value, this.versions);
  final T value;
  final Map<String, String> versions;
}
