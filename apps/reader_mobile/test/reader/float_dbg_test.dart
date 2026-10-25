import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('dbg3', () async {
    final archive = Archive();
    void addText(String name, String content) {
      final b = Uint8List.fromList(utf8.encode(content));
      archive.addFile(ArchiveFile(name, b.length, b));
    }
    archive.addFile(ArchiveFile('mimetype', 20, 'application/epub+zip'.codeUnits));
    addText('META-INF/container.xml',
        '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>');
    addText('OEBPS/content.opf',
        '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="uid">u</dc:identifier><dc:title>t</dc:title><dc:language>zh</dc:language></metadata><manifest><item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/><item id="css" href="style.css" media-type="text/css"/></manifest><spine><itemref idref="c1"/></spine></package>');
    addText('OEBPS/c1.xhtml',
        '<html xmlns="http://www.w3.org/1999/xhtml"><head><link href="style.css" type="text/css" rel="stylesheet"/></head><body><p><img src="img.png" class="side"/></p><p>文字。</p></body></html>');
    addText('OEBPS/style.css', 'img.side { float: left; }');
    archive.addFile(ArchiveFile('OEBPS/img.png', 4, [1, 2, 3, 4]));
    final source = await EpubChapterSource.open(
        Uint8List.fromList(ZipEncoder().encodeBytes(archive)));
    final pages = await source.loadChapter(0);
    // ignore: avoid_print
    print('DBG pages=${pages.length} slices0=${pages.first.slices.length} '
        'overlay=${pages.first.slices.where((s) => s.overlay).length}');
    for (final s in pages.first.slices) {
      // ignore: avoid_print
      print('DBG slice h=${s.height.toStringAsFixed(1)} overlay=${s.overlay} text="${s.block.layout.text}"');
    }
  });
}
