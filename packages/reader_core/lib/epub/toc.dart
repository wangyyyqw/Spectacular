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

/// NAV 与回退链（P1-07）。
extension TocFallback on TocParser {
  /// 按任务口径：NAV → NCX → spine 兜底，绝不返回空目录。
  static TocResult build({
    required EpubArchive archive,
    required OpfPackage package,
    required String opfPath,
  }) {
    final warnings = <String>[];
    final navItem = findNavItem(package);
    if (navItem != null) {
      try {
        final result = parseNav(
          archive: archive,
          package: package,
          opfPath: opfPath,
          item: navItem,
        );
        final sanitized = _sanitize(result, package);
        if (sanitized.entries.isNotEmpty) {
          return TocResult(
            entries: sanitized.entries,
            source: sanitized.source,
            warnings: <String>[...warnings, ...sanitized.warnings],
          );
        }
        warnings.addAll(sanitized.warnings);
        warnings.add('NAV 目录为空，尝试 NCX');
      } on EpubException catch (error) {
        warnings.add('NAV 解析失败（${error.code}），尝试 NCX');
      }
    }

    final ncxItem = TocParser.findNcxItem(package);
    if (ncxItem != null) {
      try {
        final result = TocParser.parseNcx(
          archive: archive,
          package: package,
          opfPath: opfPath,
        );
        final sanitized = _sanitize(result, package);
        if (sanitized.entries.isNotEmpty) {
          return TocResult(
            entries: sanitized.entries,
            source: sanitized.source,
            warnings: <String>[...warnings, ...sanitized.warnings],
          );
        }
        warnings.addAll(sanitized.warnings);
        warnings.add('NCX 目录为空，使用 spine 兜底');
      } on EpubException catch (error) {
        warnings.add('NCX 解析失败（${error.code}），使用 spine 兜底');
      }
    }

    warnings.add('未找到可用目录，使用 spine 兜底');
    return _sanitize(
      TocResult(
        entries: fallbackToc(package.spine),
        source: 'spine',
        warnings: warnings,
      ),
      package,
    );
  }

  static TocResult _sanitize(TocResult result, OpfPackage package) {
    final stats = TocSanitizeStats();
    final entries = TocSanitizer.sanitize(
      result.entries,
      spineCount: package.spine.length,
      stats: stats,
    );
    final warnings = <String>[...result.warnings];
    if (stats.duplicates > 0) {
      warnings.add('目录去重：${stats.duplicates} 项重复目标');
    }
    if (stats.dropped > 0) {
      warnings.add('目录移除：${stats.dropped} 项目标无效');
    }
    return TocResult(
      entries: entries,
      source: result.source,
      warnings: warnings,
    );
  }

  /// 找 EPUB3 NAV 条目。
  static OpfManifestItem? findNavItem(OpfPackage package) {
    for (final item in package.manifest) {
      if (item.properties.contains('nav')) {
        return item;
      }
    }
    for (final item in package.manifest) {
      if (item.id.toLowerCase().contains('nav') &&
          item.mediaType.contains('xhtml')) {
        return item;
      }
    }
    return null;
  }

  /// 解析 NAV 文档。
  static TocResult parseNav({
    required EpubArchive archive,
    required OpfPackage package,
    required String opfPath,
    required OpfManifestItem item,
  }) {
    final navPath = _join(_dirOf(opfPath), item.href);
    final text = archive.readString(navPath);
    if (text == null) {
      throw EpubException('E_TOC_NAV_MISSING', 'NAV 文件不存在：$navPath');
    }

    final XmlDocument document;
    try {
      document = XmlDocument.parse(_stripBom(_sanitizeEntities(text)));
    } on FormatException catch (error) {
      throw EpubException('E_TOC_NAV_XML', 'NAV 解析失败：${error.message}');
    }

    XmlElement? nav;
    for (final element in document.descendants.whereType<XmlElement>()) {
      if (element.name.local != 'nav') {
        continue;
      }
      final type = element.attributes
          .where((attribute) => attribute.name.local == 'type')
          .map((attribute) => attribute.value)
          .join(' ');
      if (type.split(RegExp(r'\s+')).contains('toc') ||
          element.getAttribute('id') == 'toc') {
        nav = element;
        break;
      }
    }
    if (nav == null) {
      throw const EpubException('E_TOC_NAV_EMPTY', 'NAV 中未找到 toc');
    }

    final resolver = _SpineResolver(package, opfPath);
    final warnings = <String>[];
    final baseDir = _dirOf(navPath);

    List<TocEntry> parseList(XmlElement list) {
      final entries = <TocEntry>[];
      for (final li in list.childElements.where((e) => e.name.local == 'li')) {
        final anchor = li.childElements
            .where((e) => e.name.local == 'a')
            .firstOrNull;
        final label = li.childElements
            .where((e) => e.name.local == 'span')
            .firstOrNull;
        final title = (anchor ?? label)?.innerText.trim() ?? '';
        final href = anchor?.getAttribute('href')?.trim() ?? '';
        final split = _splitHref(href);
        final spineIndex = split.path.isEmpty
            ? -1
            : resolver.resolve(split.path, baseDir);
        if (spineIndex < 0 && href.isNotEmpty) {
          warnings.add('目录项无法定位到 spine：$href');
        }
        final nested = li.childElements
            .where((e) => e.name.local == 'ol')
            .firstOrNull;
        entries.add(
          TocEntry(
            title: title.isEmpty ? '未命名章节' : title,
            spineIndex: spineIndex,
            fragment: split.fragment,
            children: nested == null ? const <TocEntry>[] : parseList(nested),
          ),
        );
      }
      return entries;
    }

    final list = nav.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'ol')
        .firstOrNull;
    if (list == null) {
      throw const EpubException('E_TOC_NAV_EMPTY', 'NAV toc 缺少 ol');
    }
    final entries = parseList(list);
    if (entries.isEmpty) {
      throw const EpubException('E_TOC_NAV_EMPTY', 'NAV toc 为空');
    }
    return TocResult(entries: entries, source: 'nav', warnings: warnings);
  }

  /// spine 兜底目录。
  static List<TocEntry> fallbackToc(List<SpineItem> spine) {
    final entries = <TocEntry>[];
    for (final item in spine) {
      if (!item.linear) {
        continue;
      }
      final name = item.href.split('/').last;
      final title = name.isEmpty ? '第 ${item.index + 1} 节' : name;
      entries.add(TocEntry(title: title, spineIndex: item.index));
    }
    return entries;
  }
}

String _sanitizeEntities(String text) {
  return text.replaceAllMapped(RegExp(r'&([a-zA-Z][a-zA-Z0-9]+);'), (match) {
    const known = <String, String>{
      'amp': '&',
      'lt': '<',
      'gt': '>',
      'quot': '"',
      'apos': "'",
      'nbsp': ' ',
    };
    final replacement = known[match[1]];
    return replacement ?? match[0]!;
  });
}

/// 目录清洗统计。
class TocSanitizeStats {
  /// 被移除的目标无效项。
  int dropped = 0;

  /// 被合并的重复目标项。
  int duplicates = 0;
}

/// 目录清洗：去重、过滤无效 spine、归一化 fragment，保留层级。
abstract final class TocSanitizer {
  /// 清洗目录；重复目标合并到首次出现项的子项。
  static List<TocEntry> sanitize(
    List<TocEntry> entries, {
    required int spineCount,
    TocSanitizeStats? stats,
  }) {
    final counter = stats ?? TocSanitizeStats();
    final seen = <String, _TocNode>{};

    _TocNode? convert(TocEntry entry) {
      final fragment = _normalizeFragment(entry.fragment);
      final valid = entry.spineIndex >= 0 && entry.spineIndex < spineCount;
      final key = valid ? '${entry.spineIndex}#${fragment ?? ''}' : null;

      if (key != null && seen.containsKey(key)) {
        counter.duplicates += 1;
        final existing = seen[key]!;
        for (final child in entry.children) {
          final converted = convert(child);
          if (converted != null) {
            existing.children.add(converted);
          }
        }
        return null;
      }

      if (!valid && entry.children.isEmpty) {
        counter.dropped += 1;
        return null;
      }

      final node = _TocNode(
        title: entry.title,
        spineIndex: entry.spineIndex,
        fragment: fragment,
        playOrder: entry.playOrder,
      );
      if (key != null) {
        seen[key] = node;
      }
      for (final child in entry.children) {
        final converted = convert(child);
        if (converted != null) {
          node.children.add(converted);
        }
      }
      return node;
    }

    final roots = <_TocNode>[];
    for (final entry in entries) {
      final node = convert(entry);
      if (node != null) {
        roots.add(node);
      }
    }
    return roots.map((node) => node.toEntry()).toList(growable: false);
  }

  static String? _normalizeFragment(String? fragment) {
    if (fragment == null) {
      return null;
    }
    var value = fragment.trim();
    if (value.startsWith('#')) {
      value = value.substring(1);
    }
    if (value.contains('%')) {
      try {
        value = Uri.decodeFull(value);
      } on FormatException {
        // 保留原值。
      }
    }
    return value.isEmpty ? null : value;
  }
}

class _TocNode {
  _TocNode({
    required this.title,
    required this.spineIndex,
    required this.fragment,
    required this.playOrder,
  });

  final String title;
  final int spineIndex;
  final String? fragment;
  final int? playOrder;
  final List<_TocNode> children = <_TocNode>[];

  TocEntry toEntry() => TocEntry(
    title: title,
    spineIndex: spineIndex,
    fragment: fragment,
    playOrder: playOrder,
    children: children.map((child) => child.toEntry()).toList(growable: false),
  );
}
