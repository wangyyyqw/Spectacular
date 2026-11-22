import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// 破损书样本集（P3-28）：覆盖解析、编码、结构、资源引用和容量边界。
///
/// 全部内存构造、确定性输出；生成脚本与回归测试共用。
/// 期望分级见 [brokenExpectations]。

final Uint8List pngMagicBytes = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0,
]);

Uint8List buildZipFiles(Map<String, Object> files) {
  final archive = Archive();
  files.forEach((name, content) {
    final bytes =
        content is String ? utf8.encode(content) : content as List<int>;
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

const String _containerXml = '''
<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>''';

String _opf({
  required List<Map<String, String>> items,
  List<String> spineIds = const <String>[],
  String? tocId,
}) {
  final buffer = StringBuffer()
    ..writeln('<?xml version="1.0"?>')
    ..writeln(
      '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
      'unique-identifier="uid">',)
    ..writeln(
      '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="uid">urn:uuid:broken</dc:identifier>'
      '<dc:title>破损样本</dc:title><dc:language>zh</dc:language>'
      '</metadata>',)
    ..writeln('<manifest>');
  for (final item in items) {
    final properties = item['properties'];
    final propertiesAttr =
        properties == null ? '' : ' properties="$properties"';
    buffer.writeln(
      '<item id="${item['id']}" href="${item['href']}" '
      'media-type="${item['type']}"$propertiesAttr/>',
    );
  }
  buffer.writeln('</manifest>');
  if (spineIds.isNotEmpty || tocId != null) {
    buffer.write('<spine${tocId == null ? '' : ' toc="$tocId"'}>');
    for (final id in spineIds) {
      buffer.write('<itemref idref="$id"/>');
    }
    buffer.write('</spine>');
  }
  buffer.writeln('</package>');
  return buffer.toString();
}

const String _chapter = '<html><body><p>正文内容</p></body></html>';

const String _goodNav = '''
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<body><nav epub:type="toc"><ol><li><a href="c1.xhtml">一章</a></li></ol></nav></body></html>''';

const String _brokenNcx = '<ncx><navMap><navPoint>'; // 截断损坏

/// 10 本破损样本（确定性）。
final Map<String, Uint8List> brokenSamples = <String, Uint8List>{
  // A：引用级问题（大小写/反斜杠/query）→ L1。
  'A-refs-repair.epub': buildZipFiles(<String, Object>{
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml': _containerXml,
    'OEBPS/content.opf': _opf(items: const <Map<String, String>>[
      {'id': 'c1', 'href': 'c1.xhtml', 'type': 'application/xhtml+xml'},
      {'id': 'pic', 'href': 'IMAGES/PIC.PNG', 'type': 'image/png'},
    ], spineIds: <String>['c1']),
    'OEBPS/c1.xhtml': _chapter,
    'OEBPS/images/pic.png': pngMagicBytes,
  }),
  // B：spine 项缺失 → L2。
  'B-spine-missing.epub': buildZipFiles(<String, Object>{
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml': _containerXml,
    'OEBPS/content.opf': _opf(
      items: const <Map<String, String>>[
        {'id': 'c1', 'href': 'c1.xhtml', 'type': 'application/xhtml+xml'},
        {'id': 'c2', 'href': 'c2-missing.xhtml', 'type': 'application/xhtml+xml'},
      ],
      spineIds: <String>['c1', 'c2'],
    ),
    'OEBPS/c1.xhtml': _chapter,
  }),
  // C：无 OPF，按序 XHTML → L3。
  'C-no-opf.epub': buildZipFiles(<String, Object>{
    'mimetype': 'application/epub+zip',
    'chapter1.xhtml': _chapter,
    'chapter2.xhtml': _chapter,
  }),
  // D：非 ZIP → L4。
  'D-not-zip.epub': Uint8List.fromList(List.filled(64, 0x21)),
  // E：NCX 损坏（声明了 toc 但 NCX 截断）→ L2（目录退化）。
  'E-broken-ncx.epub': buildZipFiles(<String, Object>{
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml': _containerXml,
    'OEBPS/content.opf': _opf(
      items: <Map<String, String>>[
        const {'id': 'c1', 'href': 'c1.xhtml', 'type': 'application/xhtml+xml'},
        const {
          'id': 'nav', 'href': 'nav.xhtml',
          'type': 'application/xhtml+xml', 'properties': 'nav',
        },
        const {'id': 'ncx', 'href': 'toc.ncx', 'type': 'application/x-dtbncx+xml'},
      ],
      spineIds: <String>['c1'],
      tocId: 'ncx',
    ),
    'OEBPS/c1.xhtml': _chapter,
    'OEBPS/nav.xhtml': _goodNav,
    'OEBPS/toc.ncx': _brokenNcx,
  }),
  // F：manifest 图片资源缺失 → L2。
  'F-missing-resource.epub': buildZipFiles(<String, Object>{
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml': _containerXml,
    'OEBPS/content.opf': _opf(items: const <Map<String, String>>[
      {'id': 'c1', 'href': 'c1.xhtml', 'type': 'application/xhtml+xml'},
      {'id': 'pic', 'href': 'images/gone.png', 'type': 'image/png'},
    ], spineIds: <String>['c1']),
    'OEBPS/c1.xhtml': _chapter,
  }),
  // G：扩展名写错（gif 引用指向 png 文件）→ L1（嗅探修复）。
  'G-wrong-ext.epub': buildZipFiles(<String, Object>{
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml': _containerXml,
    'OEBPS/content.opf': _opf(items: const <Map<String, String>>[
      {'id': 'c1', 'href': 'c1.xhtml', 'type': 'application/xhtml+xml'},
      {'id': 'pic', 'href': 'images/pic.gif', 'type': 'image/gif'},
    ], spineIds: <String>['c1']),
    'OEBPS/c1.xhtml': _chapter,
    'OEBPS/images/pic.png': pngMagicBytes,
  }),
  // H：FairPlay 标记 + 混淆字体声明 → 可打开（informational）。
  'H-fairplay-font.epub': buildZipFiles(<String, Object>{
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml': _containerXml,
    'META-INF/sinf.xml': '<sinf/>',
    'META-INF/encryption.xml': '''
<?xml version="1.0"?>
<encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container"
    xmlns:enc="http://www.w3.org/2001/04/xmlenc#">
  <enc:EncryptedData>
    <enc:EncryptionMethod Algorithm="http://www.idpf.org/2008/embedding"/>
    <enc:CipherData><enc:CipherReference URI="OEBPS/fonts/body.otf"/></enc:CipherData>
  </enc:EncryptedData>
</encryption>''',
    'OEBPS/content.opf': _opf(items: const <Map<String, String>>[
      {'id': 'c1', 'href': 'c1.xhtml', 'type': 'application/xhtml+xml'},
      {
        'id': 'font', 'href': 'fonts/body.otf',
        'type': 'application/vnd.ms-opentype',
      },
    ], spineIds: <String>['c1']),
    'OEBPS/c1.xhtml': _chapter,
    'OEBPS/fonts/body.otf': <int>[
      0x4F, 0x54, 0x54, 0x4F, 0, 0, 0, 0, 0, 0, 0, 0,
    ],
  }),
  // I：截断 ZIP（中央目录损坏）→ P7-15 恢复或 L4，按实际口径。
  'I-truncated-zip.epub': () {
    final good = buildZipFiles(<String, Object>{
      'mimetype': 'application/epub+zip',
      'META-INF/container.xml': _containerXml,
      'OEBPS/content.opf': _opf(items: const <Map<String, String>>[
        {'id': 'c1', 'href': 'c1.xhtml', 'type': 'application/xhtml+xml'},
      ], spineIds: <String>['c1']),
      'OEBPS/c1.xhtml': _chapter,
    });
    return Uint8List.sublistView(good, 0, good.length - 24);
  }(),
  // J：裸表格书（无任何属性 table）→ L0 正常。
  'J-plain-table.epub': buildZipFiles(<String, Object>{
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml': _containerXml,
    'OEBPS/content.opf': _opf(items: const <Map<String, String>>[
      {'id': 'c1', 'href': 'c1.xhtml', 'type': 'application/xhtml+xml'},
    ], spineIds: <String>['c1']),
    'OEBPS/c1.xhtml':
        '<html><body><table><tr><td>裸表</td><td>格</td></tr></table></body></html>',
  }),
};

/// 期望分级（I 为「恢复或拒绝」两可，回归断言实际 ∈ 集合）。
const Map<String, List<int>> brokenExpectations = <String, List<int>>{
  'A-refs-repair.epub': <int>[1],
  'B-spine-missing.epub': <int>[2],
  'C-no-opf.epub': <int>[3],
  'D-not-zip.epub': <int>[4],
  'E-broken-ncx.epub': <int>[2],
  'F-missing-resource.epub': <int>[2],
  'G-wrong-ext.epub': <int>[1],
  'H-fairplay-font.epub': <int>[0, 1],
  'I-truncated-zip.epub': <int>[1, 2, 4],
  'J-plain-table.epub': <int>[0],
};
