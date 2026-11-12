import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

const editingXhtml = '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>编辑测试</title>
<link rel="stylesheet" href="style.css"/></head><body>
<p id="p" class="note">甲&amp;<em id="e">乙😀</em>丙</p>
<p id="second">另一段</p></body></html>''';

Future<File> createEditingFixture(
  Directory directory, {
  Uint8List? chapterBytes,
  String? packageText,
}) async {
  final archive = Archive();
  final files = <String, List<int>>{
    'mimetype': utf8.encode('application/epub+zip'),
    'META-INF/container.xml': utf8.encode(
      '''<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">
<rootfiles><rootfile full-path="OPS/book.opf" media-type="application/oebps-package+xml"/></rootfiles></container>''',
    ),
    'OPS/book.opf': utf8.encode(
      packageText ??
          '''<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">edit-fixture</dc:identifier><dc:title>编辑测试</dc:title><dc:language>zh</dc:language></metadata>
<manifest><item id="c" href="chapter.xhtml" media-type="application/xhtml+xml"/><item id="css" href="style.css" media-type="text/css"/><item id="img" href="image.png" media-type="image/png"/></manifest>
<spine><itemref idref="c"/></spine></package>''',
    ),
    'OPS/chapter.xhtml': chapterBytes ?? utf8.encode(editingXhtml),
    'OPS/style.css': utf8.encode('p { font-size:16px; }'),
    'OPS/image.png': base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a5xkAAAAASUVORK5CYII=',
    ),
  };
  for (final entry in files.entries) {
    archive.addFile(
      entry.key == 'mimetype'
          ? ArchiveFile.noCompress(entry.key, entry.value.length, entry.value)
          : ArchiveFile.bytes(entry.key, entry.value),
    );
  }
  final file = File('${directory.path}/source.epub');
  await file.writeAsBytes(ZipEncoder().encodeBytes(archive));
  return file;
}
