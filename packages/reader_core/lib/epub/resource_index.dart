import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'archive_reader.dart';
import 'opf.dart';

/// 资源索引：按《技术方案》§54 的七级链路解析 href，不改写原书。
class ResourceIndex {
  ResourceIndex._(
    this._exact,
    this._lower,
    this._byBaseName,
    this._byMediaType,
    Set<String> conflicts,
  ) : conflicts = Set<String>.unmodifiable(conflicts);

  /// 从 ZIP 条目与 OPF manifest 构建索引。
  factory ResourceIndex.build({
    required EpubArchive archive,
    required List<OpfManifestItem> manifest,
    required String opfPath,
  }) {
    final opfDir = _dirOf(opfPath);
    final exact = <String, String>{};
    final lower = <String, String?>{};
    final byBaseName = <String, List<String>>{};
    final byMediaType = <String, List<String>>{};
    final conflicts = <String>{};

    for (final name in archive.names) {
      exact[name] = name;
      final lowerName = name.toLowerCase();
      if (lower.containsKey(lowerName) && lower[lowerName] != name) {
        lower[lowerName] = null;
        conflicts.add(lowerName);
      } else {
        lower[lowerName] = name;
      }
      byBaseName
          .putIfAbsent(p.posix.basename(name), () => <String>[])
          .add(name);
    }

    for (final item in manifest) {
      final resolved = _join(opfDir, _stripQueryAndFragment(item.href));
      byMediaType.putIfAbsent(item.mediaType, () => <String>[]).add(resolved);
    }

    return ResourceIndex._(exact, lower, byBaseName, byMediaType, conflicts);
  }

  final Map<String, String> _exact;
  final Map<String, String?> _lower;
  final Map<String, List<String>> _byBaseName;
  final Map<String, List<String>> _byMediaType;

  /// 大小写冲突的路径（小写形式）。
  final Set<String> conflicts;

  /// 索引条目数。
  int get length => _exact.length;

  /// 解析 href 到 ZIP 中的实际路径；未命中返回 null。
  String? resolve(String href, {String? baseDir, String? mediaType}) {
    final cleaned = _stripQueryAndFragment(href).replaceAll('\\', '/');
    if (cleaned.isEmpty) {
      return null;
    }

    final base = baseDir == null || baseDir.isEmpty
        ? ''
        : _stripQueryAndFragment(baseDir).replaceAll('\\', '/');
    final candidates = <String>[];
    final decoded = _decode(cleaned);
    if (cleaned.startsWith('/')) {
      candidates.add(_normalize(cleaned));
      candidates.add(_normalize(decoded));
    } else {
      candidates.add(_join(base, cleaned));
      candidates.add(_join(base, decoded));
      candidates.add(_normalize(cleaned));
      candidates.add(_normalize(decoded));
    }

    // 1～3：精确、URL 解码后精确。
    for (final candidate in candidates) {
      final hit = _exact[candidate];
      if (hit != null) {
        return hit;
      }
    }

    // 4：小写匹配（有冲突时跳过，避免误命中）。
    for (final candidate in candidates) {
      final lowerCandidate = candidate.toLowerCase();
      if (conflicts.contains(lowerCandidate)) {
        continue;
      }
      final hit = _lower[lowerCandidate];
      if (hit != null) {
        return hit;
      }
    }

    // 5：按文件名匹配，优先同目录。
    final baseName = p.posix.basename(candidates.first);
    final byName =
        _byBaseName[baseName] ?? _byBaseName[p.posix.basename(decoded)];
    if (byName != null && byName.isNotEmpty) {
      final sameDir = byName
          .where((path) => p.posix.dirname(path) == base || base.isEmpty)
          .toList(growable: false);
      if (sameDir.length == 1) {
        return sameDir.first;
      }
      if (sameDir.isEmpty && byName.length == 1) {
        return byName.first;
      }
    }

    // 6：按 media-type + 文件名尾匹配。
    final type = mediaType;
    if (type != null && type.isNotEmpty) {
      final typed = _byMediaType[type] ?? const <String>[];
      for (final path in typed) {
        if (p.posix.basename(path) == baseName) {
          return path;
        }
      }
      final tail = _extensionTail(baseName);
      if (tail != null) {
        for (final path in typed) {
          if (path.toLowerCase().endsWith(tail)) {
            return path;
          }
        }
      }
    }

    return null;
  }

  /// 解析并读取字节；未命中返回 null。
  Uint8List? read(EpubArchive archive, String href, {String? baseDir}) {
    final path = resolve(href, baseDir: baseDir);
    if (path == null) {
      return null;
    }
    return archive.readBytes(path);
  }

  static String _stripQueryAndFragment(String value) {
    var result = value;
    final hash = result.indexOf('#');
    if (hash >= 0) {
      result = result.substring(0, hash);
    }
    final query = result.indexOf('?');
    if (query >= 0) {
      result = result.substring(0, query);
    }
    return result.trim();
  }

  static String _decode(String value) {
    if (!value.contains('%')) {
      return value;
    }
    try {
      return Uri.decodeFull(value);
    } on FormatException {
      return value;
    }
  }

  static String _normalize(String path) {
    var result = path.replaceAll('\\', '/');
    while (result.startsWith('/')) {
      result = result.substring(1);
    }
    return p.posix.normalize(result);
  }

  static String _join(String base, String path) {
    if (base.isEmpty) {
      return _normalize(path);
    }
    return _normalize(p.posix.join(base, path));
  }

  static String _dirOf(String path) {
    final dir = p.posix.dirname(path.replaceAll('\\', '/'));
    return dir == '.' ? '' : dir;
  }

  static String? _extensionTail(String name) {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? null : name.substring(dot).toLowerCase();
  }
}
