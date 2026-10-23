
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../src/api/models.dart';
import 'archive_reader.dart';
import 'epub_exception.dart';
import 'opf.dart';

/// 目录解析结果。
class TocResult {
  /// 创建结果。
  const TocResult({
    required this.entries,
    required this.source,
    this.warnings = const <String>[],
  });

  /// 目录项。
  final List<TocEntry> entries;

  /// 来源：`ncx` / `nav` / `spine`。
  final String source;

  /// 可恢复问题。
  final List<String> warnings;
}

/// 目录解析：NCX 与 NAV 两条分支。
abstract final class TocParser {
  /// 解析 NCX；找不到或为空时抛 [EpubException]。
  static TocResult parseNcx({
    required EpubArchive archive,
    required OpfPackage package,
    required String opfPath,
  }) {
    final item = findNcxItem(package);
    if (item == null) {
      throw const EpubException('E_TOC_NCX_MISSING', '未找到 NCX');
    }
    final ncxPath = _join(_dirOf(opfPath), item.href);
    final text = archive.readString(ncxPath);
    if (text == null) {
      throw EpubException('E_TOC_NCX_MISSING', 'NCX 文件不存在：$ncxPath');
    }
    return parseNcxText(
      text,
      ncxPath: ncxPath,
      package: package,
      opfPath: opfPath,
    );
  }

  /// 从 XML 文本解析 NCX（便于单测与回退）。
  static TocResult parseNcxText(
    String text, {
    required String ncxPath,
    required OpfPackage package,
    required String opfPath,
  }) {
    final XmlDocument document;
    try {
      document = XmlDocument.parse(_stripBom(text));
    } on FormatException catch (error) {
      throw EpubException('E_TOC_NCX_XML', 'NCX 解析失败：${error.message}');
    }

    final navMap = _firstElement(document, 'navMap');
    if (navMap == null) {
      throw const EpubException('E_TOC_NCX_EMPTY', 'NCX 缺少 navMap');
    }

    final resolver = _SpineResolver(package, opfPath);
    final warnings = <String>[];
    var sequence = 0;

    List<TocEntry> parsePoints(XmlElement parent) {
      final result = <TocEntry>[];
      for (final point in parent.childElements.where(
        (element) => element.name.local == 'navPoint',
      )) {
        final label = _firstElement(point, 'navLabel');
        final title =
            _firstElement(label, 'text')?.innerText.trim() ??
            point.getAttribute('id') ??
            '';
        final content = _firstElement(point, 'content');
        final src = content?.getAttribute('src')?.trim() ?? '';
        final playOrderValue = int.tryParse(
          point.getAttribute('playOrder')?.trim() ?? '',
        );
        sequence += 1;
        final playOrder = playOrderValue ?? sequence;

        final split = _splitHref(src);
        final spineIndex = resolver.resolve(split.path, _dirOf(ncxPath));
        if (spineIndex < 0 && src.isNotEmpty) {
          warnings.add('目录项无法定位到 spine：$src');
        }

        result.add(
          TocEntry(
            title: title.isEmpty ? '未命名章节' : title,
            spineIndex: spineIndex,
            fragment: split.fragment,
            children: parsePoints(point),
            playOrder: playOrder,
          ),
        );
      }
      return result;
    }

    final entries = parsePoints(navMap);
    if (entries.isEmpty) {
      throw const EpubException('E_TOC_NCX_EMPTY', 'NCX navMap 为空');
    }
    return TocResult(entries: entries, source: 'ncx', warnings: warnings);
  }

  /// 按 manifest 找 NCX 条目。
  static OpfManifestItem? findNcxItem(OpfPackage package) {
    for (final item in package.manifest) {
      if (item.mediaType == 'application/x-dtbncx+xml') {
        return item;
      }
    }
    for (final item in package.manifest) {
      if (item.href.toLowerCase().endsWith('.ncx')) {
        return item;
      }
    }
    final tocId = package.tocId;
    if (tocId != null && tocId.isNotEmpty) {
      return package.itemById(tocId);
    }
    return null;
  }
}

class _SpineResolver {
  _SpineResolver(OpfPackage package, String opfPath) {
    final opfDir = _dirOf(opfPath);
    for (final item in package.spine) {
      final absolute = _join(opfDir, item.href);
      _byPath[absolute] = item.index;
      _byLower[absolute.toLowerCase()] = item.index;
      _byBase
          .putIfAbsent(p.posix.basename(absolute), () => <int>[])
          .add(item.index);
    }
  }

  final Map<String, int> _byPath = <String, int>{};
  final Map<String, int> _byLower = <String, int>{};
  final Map<String, List<int>> _byBase = <String, List<int>>{};

  int resolve(String href, String baseDir) {
    if (href.isEmpty) {
      return -1;
    }
    final decoded = _decode(href);
    for (final value in <String>[href, decoded]) {
      final absolute = value.startsWith('/')
          ? _normalize(value)
          : _join(baseDir, value);
      final hit = _byPath[absolute] ?? _byLower[absolute.toLowerCase()];
      if (hit != null) {
        return hit;
      }
      final byBase = _byBase[p.posix.basename(absolute)];
      if (byBase != null && byBase.length == 1) {
        return byBase.first;
      }
    }
    return -1;
  }
}

({String path, String? fragment}) _splitHref(String src) {
  final hash = src.indexOf('#');
  if (hash < 0) {
    return (path: src, fragment: null);
  }
  final fragment = src.substring(hash + 1);
  return (
    path: src.substring(0, hash),
    fragment: fragment.isEmpty ? null : fragment,
  );
}

String _decode(String value) {
  if (!value.contains('%')) {
    return value;
  }
  try {
    return Uri.decodeFull(value);
  } on FormatException {
    return value;
  }
}

XmlElement? _firstElement(XmlNode? node, String localName) {
  if (node == null) {
    return null;
  }
  if (node is XmlElement && node.name.local == localName) {
    return node;
  }
  for (final element in node.descendants.whereType<XmlElement>()) {
    if (element.name.local == localName) {
      return element;
    }
  }
  return null;
}

String _stripBom(String text) =>
    text.startsWith('\uFEFF') ? text.substring(1) : text;

String _dirOf(String path) {
  final dir = p.posix.dirname(path.replaceAll('\\', '/'));
  return dir == '.' ? '' : dir;
}

String _join(String base, String path) {
  if (base.isEmpty) {
    return _normalize(path);
  }
  return _normalize(p.posix.join(base, path));
}

String _normalize(String path) {
  var result = path.replaceAll('\\', '/');
  while (result.startsWith('/')) {
    result = result.substring(1);
  }
  return p.posix.normalize(result);
}
