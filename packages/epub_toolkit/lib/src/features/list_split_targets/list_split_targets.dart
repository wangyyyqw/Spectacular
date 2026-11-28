import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:xml/xml.dart' as xml;

import 'epub_image_helper.dart';

/// 拆分目标条目
class SplitTarget {
  /// 章节标题
  final String title;

  /// 嵌套层级（从 1 开始）
  final int level;

  /// 章节 href（已规范化，无 fragment）
  final String href;

  SplitTarget({required this.title, required this.level, required this.href});

  Map<String, dynamic> toJson() => {
    'title': title,
    'level': level,
    'href': href,
  };
}

/// 列出拆分目标操作
///
/// 扫描 EPUB 的 TOC（nav 或 NCX），返回带层级的章节列表，
/// 供用户选择拆分点。每个条目包含标题、层级和 href。
class ListSplitTargetsOperation {
  ListSplitTargetsOperation._();

  /// 执行列出拆分目标
  ///
  /// [epubPath] 输入 EPUB 路径
  ///
  /// 返回 SplitTarget 列表
  static Future<List<SplitTarget>> execute({required String epubPath}) async {
    final archive = await EpubImageHelper.readArchive(epubPath);
    final opfPath = EpubImageHelper.findOpfPath(archive);
    if (opfPath == null) return [];

    final opfFile = archive.findFile(opfPath);
    if (opfFile == null) return [];

    final opfContent = utf8.decode(opfFile.content);
    final opfDir = EpubImageHelper.opfDir(opfPath);

    // 解析 OPF
    final manifest = <String, _ManifestInfo>{};
    String? navHref;
    String? ncxHref;

    try {
      final document = xml.XmlDocument.parse(opfContent);

      for (final item in document.findAllElements('item', namespaceUri: '*')) {
        final id = item.getAttribute('id') ?? '';
        final href = Uri.decodeComponent(
          Uri.parse(item.getAttribute('href') ?? '').path,
        );
        final mediaType = item.getAttribute('media-type') ?? '';
        final propsStr = item.getAttribute('properties') ?? '';

        manifest[id] = _ManifestInfo(href: href, mediaType: mediaType);

        if (propsStr.contains('nav')) {
          navHref = href;
        }
        if (mediaType == 'application/x-dtbncx+xml') {
          ncxHref = href;
        }
      }
    } catch (_) {
      return [];
    }

    // 优先 EPUB3 nav
    if (navHref != null) {
      final navPath = _normalizePath('$opfDir$navHref');
      final navFile = archive.findFile(navPath);
      if (navFile != null) {
        final content = utf8.decode(navFile.content);
        final targets = _parseTocNav(content);
        if (targets.isNotEmpty) {
          return _resolveTargets(targets, navPath, opfDir);
        }
      }
    }

    // 回退 NCX
    if (ncxHref != null) {
      final ncxPath = _normalizePath('$opfDir$ncxHref');
      final ncxFile = archive.findFile(ncxPath);
      if (ncxFile != null) {
        final content = utf8.decode(ncxFile.content);
        final targets = _parseTocNcx(content);
        if (targets.isNotEmpty) {
          return _resolveTargets(targets, ncxPath, opfDir);
        }
      }
    }

    // 回退 spine
    final targets = <SplitTarget>[];
    try {
      final document = xml.XmlDocument.parse(opfContent);
      for (final itemref in document.findAllElements(
        'itemref',
        namespaceUri: '*',
      )) {
        final idref = itemref.getAttribute('idref') ?? '';
        final info = manifest[idref];
        if (info != null) {
          targets.add(
            SplitTarget(
              title: p.basenameWithoutExtension(info.href),
              level: 1,
              href: info.href,
            ),
          );
        }
      }
    } catch (_) {}

    return targets;
  }

  static List<SplitTarget> _resolveTargets(
    List<SplitTarget> targets,
    String navigationPath,
    String opfDir,
  ) {
    return [
      for (final target in targets)
        SplitTarget(
          title: target.title,
          level: target.level,
          href: target.href.isEmpty
              ? ''
              : p.posix.relative(
                  _normalizePath(
                    p.posix.join(
                      p.posix.dirname(navigationPath),
                      Uri.decodeComponent(Uri.parse(target.href).path),
                    ),
                  ),
                  from: opfDir.isEmpty ? '.' : opfDir,
                ),
        ),
    ];
  }

  /// 格式化输出为字符串
  static String formatTargets(List<SplitTarget> targets) {
    final buf = StringBuffer();
    buf.writeln('扫描到 ${targets.length} 个拆分目标:');
    buf.writeln('');

    for (var i = 0; i < targets.length; i++) {
      final t = targets[i];
      final indent = '  ' * (t.level - 1);
      buf.writeln('[$i] $indent${t.title} (${t.href})');
    }

    return buf.toString();
  }

  /// 规范化路径
  static String _normalizePath(String path) {
    path = path.replaceAll('\\', '/');
    final parts = <String>[];
    for (final part in path.split('/')) {
      if (part == '..') {
        if (parts.isNotEmpty) parts.removeLast();
      } else if (part != '.' && part.isNotEmpty) {
        parts.add(part);
      }
    }
    return parts.join('/');
  }

  /// 解析 EPUB3 nav
  static List<SplitTarget> _parseTocNav(String content) {
    final entries = <SplitTarget>[];
    try {
      final document = xml.XmlDocument.parse(content);
      final nav = document.findAllElements('nav', namespaceUri: '*').where((n) {
        final type = n.getAttribute('epub:type') ?? n.getAttribute('type');
        return type == null || type == 'toc';
      }).firstOrNull;

      final ol = nav?.findElements('ol', namespaceUri: '*').firstOrNull;
      if (ol != null) {
        _walkNavList(ol, 1, entries);
      }
    } catch (_) {}
    return entries;
  }

  /// 递归遍历 nav 的 ol
  static void _walkNavList(
    xml.XmlElement ol,
    int level,
    List<SplitTarget> entries,
  ) {
    for (final li in ol.findElements('li', namespaceUri: '*')) {
      final a = li.findElements('a', namespaceUri: '*').firstOrNull;
      final span = li.findElements('span', namespaceUri: '*').firstOrNull;

      final title = a?.innerText ?? span?.innerText ?? '';
      var href = a?.getAttribute('href') ?? '';

      final fragIdx = href.indexOf('#');
      if (fragIdx >= 0) {
        href = href.substring(0, fragIdx);
      }

      entries.add(SplitTarget(title: title.trim(), level: level, href: href));

      final childOl = li.findElements('ol', namespaceUri: '*').firstOrNull;
      if (childOl != null) {
        _walkNavList(childOl, level + 1, entries);
      }
    }
  }

  /// 解析 EPUB2 NCX
  static List<SplitTarget> _parseTocNcx(String content) {
    final entries = <SplitTarget>[];
    try {
      final document = xml.XmlDocument.parse(content);
      final navMap = document
          .findAllElements('navMap', namespaceUri: '*')
          .firstOrNull;
      if (navMap != null) {
        _walkNavPoints(navMap, 1, entries);
      }
    } catch (_) {}
    return entries;
  }

  /// 递归遍历 NCX navPoint
  static void _walkNavPoints(
    xml.XmlElement parent,
    int level,
    List<SplitTarget> entries,
  ) {
    for (final navPoint in parent.findElements('navPoint', namespaceUri: '*')) {
      final label =
          navPoint
              .findElements('navLabel', namespaceUri: '*')
              .firstOrNull
              ?.findElements('text', namespaceUri: '*')
              .firstOrNull
              ?.innerText ??
          '';
      final content = navPoint
          .findElements('content', namespaceUri: '*')
          .firstOrNull;
      var src = content?.getAttribute('src') ?? '';

      final fragIdx = src.indexOf('#');
      if (fragIdx >= 0) {
        src = src.substring(0, fragIdx);
      }

      entries.add(SplitTarget(title: label.trim(), level: level, href: src));

      _walkNavPoints(navPoint, level + 1, entries);
    }
  }
}

/// Manifest 信息
class _ManifestInfo {
  final String href;
  final String mediaType;

  _ManifestInfo({required this.href, required this.mediaType});
}
