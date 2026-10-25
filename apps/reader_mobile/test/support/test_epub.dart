import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// 测试用最小 EPUB 构造（应用层测试共享）。
///
/// [cover] 为 true 时附带一张 JPEG 封面并在 OPF 里按
/// `<meta name="cover">` 声明（§37.3 第 2 级）。
Uint8List buildTestEpub({
  String title = '测试书',
  String author = '测试作者',
  bool cover = false,
  String? identifier,
}) {
  final chapter =
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>$title</title>'
      '</head><body><h1>第一章 简单正文</h1>'
      '<p>这是用于应用壳测试的段落，内容足够长以便分页。</p>'
      '<p>第二章稍后展开。</p></body></html>';
  final opf =
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
      'unique-identifier="bid"><metadata '
      'xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="bid">'
      '${identifier ?? 'urn:uuid:test-${title.hashCode}'}</dc:identifier>'
      '<dc:title>$title</dc:title>'
      '<dc:creator>$author</dc:creator>'
      '<dc:language>zh</dc:language>'
      '<meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>'
      '${cover ? '<meta name="cover" content="cover-img"/>' : ''}'
      '</metadata><manifest>'
      '<item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>'
      '${cover ? '<item id="cover-img" href="cover.jpg" '
          'media-type="image/jpeg"/>' : ''}'
      '</manifest><spine><itemref idref="c1"/></spine></package>';
  final container =
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<container version="1.0" '
      'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
      '<rootfiles><rootfile full-path="OEBPS/content.opf" '
      'media-type="application/oebps-package+xml"/></rootfiles></container>';
  final files = <String, String>{
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml': container,
    'OEBPS/content.opf': opf,
    'OEBPS/c1.xhtml': chapter,
  };
  final archive = Archive();
  files.forEach((name, content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  if (cover) {
    final bytes = Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);
    archive.addFile(ArchiveFile('OEBPS/cover.jpg', bytes.length, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

/// 构造带导入告警的 EPUB：manifest 项缺 media-type（按扩展名推断），
/// 触发 `E_MANIFEST_MEDIA_TYPE_INFERRED`。
Uint8List buildWarningEpub({
  String title = '告警书',
  String identifier = 'urn:uuid:warning-book',
}) {
  final chapter =
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>$title</title>'
      '</head><body><p>正文</p></body></html>';
  final opf =
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
      'unique-identifier="uid"><metadata '
      'xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="uid">$identifier</dc:identifier>'
      '<dc:title>$title</dc:title><dc:language>zh</dc:language></metadata>'
      '<manifest><item id="c1" href="c1.xhtml"/></manifest>'
      '<spine><itemref idref="c1"/></spine></package>';
  final container =
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<container version="1.0" '
      'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
      '<rootfiles><rootfile full-path="OEBPS/content.opf" '
      'media-type="application/oebps-package+xml"/></rootfiles></container>';
  final files = <String, String>{
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml': container,
    'OEBPS/content.opf': opf,
    'OEBPS/c1.xhtml': chapter,
  };
  final archive = Archive();
  files.forEach((name, content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}
