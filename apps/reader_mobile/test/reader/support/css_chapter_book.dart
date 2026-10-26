import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';

/// 单章 CSS 用例书：把 [body] 与 [css] 装成最小 EPUB。
///
/// [binaryFiles] 为附加的二进制资源（键 = 包内路径，如 `OEBPS/Fonts/mm.otf`），
/// 供 `@font-face` 等需要真实字节日志的用例使用。
///
/// 供章节源侧回归测试直接走「解析 → 聚合 → 级联 → 排版」全链路，
/// 断言的是真实管线结果而不是某个中间结构。
Uint8List buildCssChapterBook({
  required String body,
  String css = '',
  Map<String, List<int>> binaryFiles = const <String, List<int>>{},
}) {
  final chapter =
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>t</title>'
      '${css.isEmpty ? '' : '<link rel="stylesheet" type="text/css" href="../Styles/s.css"/>'}'
      '</head><body>$body</body></html>';
  const opf =
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
      'unique-identifier="b"><metadata '
      'xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="b">urn:uuid:css-chapter</dc:identifier>'
      '<dc:title>t</dc:title><dc:language>zh</dc:language>'
      '<meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>'
      '</metadata><manifest>'
      '<item id="c" href="Text/c.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="s" href="Styles/s.css" media-type="text/css"/>'
      '</manifest><spine><itemref idref="c"/></spine></package>';
  const container =
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<container version="1.0" '
      'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
      '<rootfiles><rootfile full-path="OEBPS/content.opf" '
      'media-type="application/oebps-package+xml"/></rootfiles></container>';
  final files = <String, String>{
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml': container,
    'OEBPS/content.opf': opf,
    'OEBPS/Text/c.xhtml': chapter,
    'OEBPS/Styles/s.css': css,
  };
  final archive = Archive();
  // `mimetype` 必须是首个条目（EPUB 容器契约），二进制资源排在后面。
  files.forEach((name, content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  binaryFiles.forEach((name, bytes) {
    final data = Uint8List.fromList(bytes);
    archive.addFile(ArchiveFile(name, data.length, data));
  });
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

/// 打开单章用例书并施加阅读器覆盖（默认空覆盖 = 纯书籍样式）。
Future<EpubChapterSource> openCssChapter({
  required String body,
  String css = '',
  Map<String, List<int>> binaryFiles = const <String, List<int>>{},
  double contentWidth = 300,
  double contentHeight = 500,
  ReaderOverrides overrides = const ReaderOverrides(),
}) async {
  final source = await EpubChapterSource.open(
    buildCssChapterBook(body: body, css: css, binaryFiles: binaryFiles),
    contentWidth: contentWidth,
    contentHeight: contentHeight,
    verifyCrc: false,
  );
  await source.applyOverrides(overrides);
  return source;
}
