import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

const auditFirstText = '甲章正文你好。';
const auditSecondText = '乙章正文再见。';

/// 新审计用的独立 EPUB 样本，全程在内存构造，不依赖本地书库。
Uint8List auditEpub({
  String imageHref = 'images/pic.png',
  bool missingSecondChapter = false,
}) => auditZip({
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml': '''
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>''',
  'OEBPS/content.opf':
      '''
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="uid">urn:uuid:audit-20261104</dc:identifier>
    <dc:title>审计样本</dc:title><dc:creator>审计作者</dc:creator><dc:language>zh</dc:language>
  </metadata>
  <manifest>
    <item id="c1" href="text/c1.xhtml" media-type="application/xhtml+xml"/>
    <item id="c2" href="text/c2.xhtml" media-type="application/xhtml+xml"/>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="pic" href="$imageHref" media-type="image/png"/>
  </manifest>
  <spine><itemref idref="c1"/><itemref idref="c2"/></spine>
</package>''',
  'OEBPS/nav.xhtml': '''
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
  <body><nav epub:type="toc"><ol>
    <li><a href="text/c1.xhtml#first">甲章</a></li>
    <li><a href="text/c2.xhtml#second">乙章</a></li>
  </ol></nav></body>
</html>''',
  'OEBPS/text/c1.xhtml': auditChapter('first', auditFirstText),
  if (!missingSecondChapter)
    'OEBPS/text/c2.xhtml': auditChapter('second', auditSecondText),
  'OEBPS/images/pic.png': Uint8List.fromList([
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    0,
    0,
    0,
    0,
  ]),
});

/// 构造带稳定 ID 的正文，供目录与 CFI 定位交叉验证。
String auditChapter(String id, String text) =>
    '<html xmlns="http://www.w3.org/1999/xhtml"><body>'
    '<p id="$id">$text</p></body></html>';

/// 构造 ZIP；调用方可明确移除 OPF 或章节测试损坏恢复。
Uint8List auditZip(Map<String, Object> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    final content = entry.value;
    final bytes = content is String
        ? utf8.encode(content)
        : content as List<int>;
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}
