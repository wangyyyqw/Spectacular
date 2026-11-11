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
  final Future<CssStylesheet> Function(String url) readSheet;

  /// 按来源目录解析地址。
  final String Function(String url, String baseDir) resolveUrl;

  /// 解析内嵌 CSS 并归一化声明内的资源地址。
  final Future<CssStylesheet> Function(String css, String baseDir)
  prepareInline;

  /// 保留重复引用，只阻断当前导入链中的循环。
  Future<List<CssStylesheet>> load(
    List<CssStyleSource> sources,
    String baseDir,
  ) async {
    final result = <CssStylesheet>[];
    for (final request in _requests(sources, baseDir, result)) {
      request.sheet = request.url == null
          ? await prepareInline(request.css!, request.baseDir)
          : await readSheet(request.url!);
    }
    return result;
  }

  Iterable<_SheetRequest> _requests(
    List<CssStyleSource> sources,
    String baseDir,
    List<CssStylesheet> result,
  ) sync* {
    for (final source in sources) {
      yield* _loadSource(source, baseDir, const [], const {}, result);
    }
  }

  Iterable<_SheetRequest> _loadSource(
    CssStyleSource source,
    String baseDir,
    List<String> conditions,
    Set<String> active,
    List<CssStylesheet> result,
  ) sync* {
    final media = source.media?.trim();
    final combined = <String>[
      ...conditions,
      if (media != null && media.isNotEmpty) media,
    ];
    final href = source.href;
    if (href == null) {
      final request = _SheetRequest.inline(source.css!, baseDir);
      yield request;
      yield* _expand(request.sheet, baseDir, combined, active, result);
      return;
    }
    final url = resolveUrl(href, baseDir);
    if (active.length >= 9 || active.contains(url)) {
      return;
    }
    final request = _SheetRequest.linked(url);
    yield request;
    yield* _expand(request.sheet, p.posix.dirname(url), combined, {
      ...active,
      url,
    }, result);
  }

  Iterable<_SheetRequest> _expand(
    CssStylesheet sheet,
    String baseDir,
    List<String> conditions,
    Set<String> active,
    List<CssStylesheet> result,
  ) sync* {
    for (final imported in sheet.imports) {
      yield* _loadSource(
        CssStyleSource.linked(imported.url, media: imported.media),
        baseDir,
        conditions,
        active,
        result,
      );
    }
    result.add(
      CssStylesheet(
        rules: sheet.rules,
        imports: const [],
        warnings: sheet.warnings,
        fontFaces: sheet.fontFaces,
        mediaConditions: List.unmodifiable(conditions),
      ),
    );
  }
}

/// 遍历在 yield 处等待宿主填入纯数据结果，再展开该表的导入。
class _SheetRequest {
  _SheetRequest.inline(this.css, this.baseDir) : url = null;
  _SheetRequest.linked(this.url) : css = null, baseDir = '';

  final String? css;
  final String? url;
  final String baseDir;
  late CssStylesheet sheet;
}
