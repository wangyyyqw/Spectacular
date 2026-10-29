import 'package:path/path.dart' as p;

import 'parser.dart';

/// 按出现顺序展开样式表及导入；解析和资源缓存由宿主提供。
class CssStylesheetLoader {
  /// 创建加载器，内嵌表与外链表均由宿主解析资源相对路径。
  const CssStylesheetLoader({
    required this.readSheet,
    required this.resolveUrl,
    required this.prepareInline,
  });

  /// 读取已解析的外链样式表；可以由宿主缓存。
  final CssStylesheet Function(String url) readSheet;

  /// 按来源目录解析地址。
  final String Function(String url, String baseDir) resolveUrl;

  /// 解析内嵌 CSS 并归一化声明内的资源地址。
  final CssStylesheet Function(String css, String baseDir) prepareInline;

  /// 保留重复引用，只阻断当前导入链中的循环。
  List<CssStylesheet> load(List<CssStyleSource> sources, String baseDir) => [
    for (final source in sources)
      ..._loadSource(source, baseDir, const [], const {}),
  ];

  List<CssStylesheet> _loadSource(
    CssStyleSource source,
    String baseDir,
    List<String> conditions,
    Set<String> active,
  ) {
    final media = source.media?.trim();
    final combined = <String>[
      ...conditions,
      if (media != null && media.isNotEmpty) media,
    ];
    final href = source.href;
    if (href == null) {
      return _expand(
        prepareInline(source.css!, baseDir),
        baseDir,
        combined,
        active,
      );
    }
    final url = resolveUrl(href, baseDir);
    if (active.length >= 9 || active.contains(url)) {
      return const [];
    }
    return _expand(readSheet(url), p.posix.dirname(url), combined, {
      ...active,
      url,
    });
  }

  List<CssStylesheet> _expand(
    CssStylesheet sheet,
    String baseDir,
    List<String> conditions,
    Set<String> active,
  ) => [
    for (final imported in sheet.imports)
      ..._loadSource(
        CssStyleSource.linked(imported.url, media: imported.media),
        baseDir,
        conditions,
        active,
      ),
    CssStylesheet(
      rules: sheet.rules,
      imports: const [],
      warnings: sheet.warnings,
      fontFaces: sheet.fontFaces,
      mediaConditions: List.unmodifiable(conditions),
    ),
  ];
}
