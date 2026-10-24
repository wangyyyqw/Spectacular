import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// 测试用最小 EPUB 构造（应用层测试共享）。
Uint8List buildTestEpub({String title = '测试书', String author = '测试作者'}) {
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
      '<dc:identifier id="bid">urn:uuid:app-shell-0001</dc:identifier>'
      '<dc:title>$title</dc:title>'
      '<dc:creator>$author</dc:creator>'
      '<dc:language>zh</dc:language>'
      '<meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>'
      '</metadata><manifest>'
      '<item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>'
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
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}
