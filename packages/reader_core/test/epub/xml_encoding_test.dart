import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/epub/xml_encoding.dart';

Uint8List _utf16(String text, Endian endian, {bool bom = true}) {
  final output = BytesBuilder(copy: false);
  if (bom) {
    output.add(
      endian == Endian.little
          ? const <int>[0xFF, 0xFE]
          : const <int>[0xFE, 0xFF],
    );
  }
  for (final unit in text.codeUnits) {
    if (endian == Endian.little) {
      output.add(<int>[unit & 0xFF, (unit >> 8) & 0xFF]);
    } else {
      output.add(<int>[(unit >> 8) & 0xFF, unit & 0xFF]);
    }
  }
  return output.toBytes();
}

Uint8List _buildUtf16Epub({
  required Endian containerEndian,
  required Endian opfEndian,
  required Endian chapterEndian,
}) {
  final archive = Archive();
  void add(String name, Uint8List bytes) {
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  add('mimetype', Uint8List.fromList(utf8.encode('application/epub+zip')));
  add(
    'META-INF/container.xml',
    _utf16(
      '<?xml version="1.0" encoding="UTF-16"?>'
      '<container version="1.0" '
      'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
      '<rootfiles><rootfile full-path="OEBPS/content.opf" '
      'media-type="application/oebps-package+xml"/></rootfiles></container>',
      containerEndian,
    ),
  );
  add(
    'OEBPS/content.opf',
    _utf16(
      '<?xml version="1.0" encoding="UTF-16"?>'
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
      'unique-identifier="b"><metadata '
      'xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="b">urn:uuid:utf16</dc:identifier>'
      '<dc:title>编码书</dc:title><dc:language>zh</dc:language>'
      '<meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>'
      '</metadata><manifest>'
      '<item id="c" href="Text/c.xhtml" media-type="application/xhtml+xml"/>'
      '</manifest><spine><itemref idref="c"/></spine></package>',
      opfEndian,
    ),
  );
  add(
    'OEBPS/Text/c.xhtml',
    _utf16(
      '<?xml version="1.0" encoding="UTF-16"?>'
      '<html xmlns="http://www.w3.org/1999/xhtml"><body>'
      '<p>中文正文 UTF-16</p></body></html>',
      chapterEndian,
    ),
  );
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

void main() {
  test('统一解码支持 UTF-8 BOM、UTF-16LE/BE BOM 与无 BOM 识别', () {
    const text = '<?xml version="1.0"?><p>中文 &amp; 正文</p>';
    expect(
      decodeXmlBytes(
        Uint8List.fromList(<int>[0xEF, 0xBB, 0xBF, ...utf8.encode(text)]),
      ),
      text,
    );
    expect(decodeXmlBytes(_utf16(text, Endian.little)), text);
    expect(decodeXmlBytes(_utf16(text, Endian.big)), text);
    expect(decodeXmlBytes(_utf16(text, Endian.little, bom: false)), text);
    expect(decodeXmlBytes(_utf16(text, Endian.big, bom: false)), text);
  });

  test('UTF-16 的 container、OPF 与章节可真实打开并读取正文', () async {
    final bytes = _buildUtf16Epub(
      containerEndian: Endian.little,
      opfEndian: Endian.big,
      chapterEndian: Endian.little,
    );
    final opened = await openEpub(bytes);
    final document = opened.document;
    expect(document, isNotNull, reason: opened.report.message);
    expect(document!.opfPath, 'OEBPS/content.opf');
    expect(document.spine, hasLength(1));
    final parsed = document.parseDocument(0);
    expect(parsed.plainText, contains('中文正文 UTF-16'));
    expect(document.characterCountOf(0), greaterThan(0));
  });
}
