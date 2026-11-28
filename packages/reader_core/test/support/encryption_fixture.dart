import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

const encryptionIdentifier = 'urn:uuid:12345678-1234-1234-1234-123456789abc';

String encryptionXml(String algorithm, {String path = 'OEBPS/font.ttf'}) =>
    '''
<encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container"
 xmlns:enc="http://www.w3.org/2001/04/xmlenc#">
 <enc:EncryptedData><enc:EncryptionMethod Algorithm="$algorithm"/>
 <enc:CipherData><enc:CipherReference URI="$path"/></enc:CipherData>
 </enc:EncryptedData>
</encryption>''';

Uint8List encryptionEpub({
  String? declaration,
  Uint8List? font,
  String? marker,
  String? password,
  bool brokenOpf = false,
}) {
  final files = <String, String>{
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml': '''
<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
 <rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles>
</container>''',
    'OEBPS/content.opf': brokenOpf
        ? '<broken'
        : '''
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
 <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
 <dc:identifier id="uid">$encryptionIdentifier</dc:identifier>
 <dc:title>加密检测样书</dc:title><dc:language>zh</dc:language></metadata>
 <manifest><item id="c" href="chapter.xhtml" media-type="application/xhtml+xml"/>
 ${font == null ? '' : '<item id="f" href="font.ttf" media-type="font/ttf"/>'}
 </manifest><spine><itemref idref="c"/></spine></package>''',
    'OEBPS/chapter.xhtml': '<html xmlns="http://www.w3.org/1999/xhtml"><body><p>检测正文</p></body></html>',
    'META-INF/encryption.xml': ?declaration,
    ?marker: '<标记/>',
    'OEBPS/style.css': 'body { color: black; }',
  };
  final archive = Archive();
  for (final entry in files.entries) {
    final bytes = utf8.encode(entry.value);
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  if (font != null) {
    archive.addFile(ArchiveFile('OEBPS/font.ttf', font.length, font));
  }
  return ZipEncoder(password: password).encodeBytes(archive);
}

/// 独立构造 cmap/post，不依赖检测器实现；字形编号和字形名可分别指定。
Uint8List mappingFont(
  Map<int, int> mappings, {
  Map<int, String>? names,
  bool format4 = false,
  bool rangeOffsets = false,
}) {
  final ordered = mappings.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  final subtable = format4
      ? _format4(ordered, rangeOffsets)
      : _format12(ordered);
  final cmap = ByteData(12 + subtable.length)
    ..setUint16(2, 1)
    ..setUint16(4, 3)
    ..setUint16(6, format4 ? 1 : 10)
    ..setUint32(8, 12);
  cmap.buffer.asUint8List().setAll(12, subtable);
  final tables = <String, Uint8List>{
    'cmap': cmap.buffer.asUint8List(),
    if (names != null) 'post': _post(names),
  };
  var offset = 12 + tables.length * 16;
  final data =
      ByteData(
          offset + tables.values.fold(0, (size, bytes) => size + bytes.length),
        )
        ..setUint32(0, 0x00010000)
        ..setUint16(4, tables.length);
  var record = 12;
  for (final entry in tables.entries) {
    data.buffer.asUint8List().setAll(record, ascii.encode(entry.key));
    data.setUint32(record + 8, offset);
    data.setUint32(record + 12, entry.value.length);
    data.buffer.asUint8List().setAll(offset, entry.value);
    offset += entry.value.length;
    record += 16;
  }
  return data.buffer.asUint8List();
}

Uint8List _format12(List<MapEntry<int, int>> mappings) {
  final data = ByteData(16 + mappings.length * 12)
    ..setUint16(0, 12)
    ..setUint32(4, 16 + mappings.length * 12)
    ..setUint32(12, mappings.length);
  for (var i = 0; i < mappings.length; i++) {
    data.setUint32(16 + i * 12, mappings[i].key);
    data.setUint32(20 + i * 12, mappings[i].key);
    data.setUint32(24 + i * 12, mappings[i].value);
  }
  return data.buffer.asUint8List();
}

Uint8List _format4(List<MapEntry<int, int>> mappings, bool rangeOffsets) {
  final count = mappings.length + 1;
  final glyphStart = 16 + count * 8;
  final length = glyphStart + (rangeOffsets ? mappings.length * 2 : 0);
  final data = ByteData(length)
    ..setUint16(0, 4)
    ..setUint16(2, length)
    ..setUint16(6, count * 2);
  for (var i = 0; i < count; i++) {
    final code = i < mappings.length ? mappings[i].key : 0xffff;
    final glyph = i < mappings.length ? mappings[i].value : 0;
    data.setUint16(14 + i * 2, code);
    data.setUint16(16 + count * 2 + i * 2, code);
    final delta = 16 + count * 4 + i * 2;
    final range = 16 + count * 6 + i * 2;
    if (rangeOffsets && i < mappings.length) {
      data.setUint16(delta, 3);
      data.setUint16(range, glyphStart + i * 2 - range);
      data.setUint16(glyphStart + i * 2, (glyph - 3) & 0xffff);
    } else {
      data.setUint16(delta, (glyph - code) & 0xffff);
    }
  }
  return data.buffer.asUint8List();
}

Uint8List _post(Map<int, String> names) {
  final count = names.keys.reduce((a, b) => a > b ? a : b) + 1;
  final strings = BytesBuilder();
  final data = ByteData(34 + count * 2)
    ..setUint32(0, 0x00020000)
    ..setUint16(32, count);
  var index = 258;
  for (var glyph = 0; glyph < count; glyph++) {
    final name = names[glyph];
    if (name == null) continue;
    final bytes = ascii.encode(name);
    data.setUint16(34 + glyph * 2, index++);
    strings.addByte(bytes.length);
    strings.add(bytes);
  }
  return (BytesBuilder()
        ..add(data.buffer.asUint8List())
        ..add(strings.takeBytes()))
      .takeBytes();
}
