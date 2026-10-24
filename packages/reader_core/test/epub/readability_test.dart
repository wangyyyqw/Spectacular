import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/epub/importer.dart';

Uint8List _buildEpub(Map<String, Object> files) {
  final archive = Archive();
  files.forEach((name, content) {
    final bytes =
        content is String ? utf8.encode(content) : content as List<int>;
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

const _chapterA = '<html><body><p>章节甲</p></body></html>';
const _chapterB = '<html><body><p>章节乙</p></body></html>';

/// 样本 A（§55.4）：大小写全错 + 反斜杠 + query 引用 → 期望 L1。
Uint8List _sampleA() => _buildEpub(<String, Object>{
      'mimetype': 'application/epub+zip',
      'META-INF/container.xml': '''
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>''',
      'OEBPS/content.opf': '''
<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="uid">urn:uuid:a</dc:identifier>
    <dc:title>A</dc:title><dc:language>zh</dc:language>
  </metadata>
  <manifest>
    <item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>
    <item id="pic" href="IMAGES/PIC.PNG" media-type="image/png"/>
  </manifest>
  <spine><itemref idref="c1"/></spine>
</package>''',
      'OEBPS/c1.xhtml': _chapterA,
      'OEBPS/images/pic.png': <int>[
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0,
      ],
    });

/// 样本 B：一个 spine 项指向不存在的文件 → 期望 L2。
Uint8List _sampleB() => _buildEpub(<String, Object>{
      'mimetype': 'application/epub+zip',
      'META-INF/container.xml': '''
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>''',
      'content.opf': '''
<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="uid">urn:uuid:b</dc:identifier>
    <dc:title>B</dc:title><dc:language>zh</dc:language>
  </metadata>
  <manifest>
    <item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>
    <item id="c2" href="c2-missing.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine><itemref idref="c1"/><itemref idref="c2"/></spine>
</package>''',
      'c1.xhtml': _chapterA,
    });

/// 样本 C：无 OPF，只有按序命名的 XHTML → 期望 L3。
Uint8List _sampleC() => _buildEpub(<String, Object>{
      'mimetype': 'application/epub+zip',
      'chapter1.xhtml': _chapterA,
      'chapter2.xhtml': _chapterB,
    });

/// 样本 D：不是 ZIP → 期望 L4。
Uint8List _sampleD() => Uint8List.fromList(List.filled(64, 0x21));

void main() {
  group('破损书可读性分级（P3-26，§55）', () {
    test('样本 A（引用可修复）→ L1，含修复提示', () async {
      final result = await openEpub(_sampleA());
      expect(result.ok, isTrue);
      expect(result.report.readabilityLevel, EpubReadability.l1);
      expect(
        result.report.warnings.any((w) => w.contains('E_RESOURCE_REPAIRED')),
        isTrue,
      );
    });

    test('样本 B（spine 项缺失）→ L2', () async {
      final result = await openEpub(_sampleB());
      expect(result.ok, isTrue);
      expect(result.report.readabilityLevel, EpubReadability.l2);
      expect(
        result.report.warnings.any((w) => w.contains('E_SPINE_MISSING')),
        isTrue,
      );
    });

    test('样本 C（无 OPF 按文件名拼章节）→ L3，可读两个章节', () async {
      final result = await openEpub(_sampleC());
      expect(result.ok, isTrue, reason: 'L3 拼装后应可打开');
      expect(result.report.readabilityLevel, EpubReadability.l3);
      expect(result.document!.spine.length, 2, reason: '两个 XHTML 按序拼章');
      expect(
        result.report.warnings.any(
          (w) => w.contains('E_CONTAINER_FALLBACK') && w.contains('排序'),
        ),
        isTrue,
      );
    });

    test('样本 D（非 ZIP）→ L4 拒绝', () async {
      final result = await openEpub(_sampleD());
      expect(result.ok, isFalse);
      expect(result.report.readabilityLevel, EpubReadability.l4);
      expect(result.report.errorCode, 'E_ARCHIVE');
    });

    test('完整书 → L0', () async {
      final result = await openEpub(_buildEpub(<String, Object>{
        'mimetype': 'application/epub+zip',
        'META-INF/container.xml': '''
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>''',
        'content.opf': '''
<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="uid">urn:uuid:ok</dc:identifier>
    <dc:title>OK</dc:title><dc:language>zh</dc:language>
  </metadata>
  <manifest><item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/></manifest>
  <spine><itemref idref="c1"/></spine>
</package>''',
        'c1.xhtml': _chapterA,
      }));
      expect(result.ok, isTrue);
      expect(result.report.readabilityLevel, EpubReadability.l0);
    });

    test('grader 纯函数：spine 过半失效 → L3；目录退化 → L2', () {
      expect(
        EpubReadability.grade(
          ok: true,
          warnings: const <String>[],
          spineCount: 4,
          missingSpineItems: 3,
          missingResources: 0,
          repairedRefs: 0,
          tocFallbackUsed: false,
        ),
        EpubReadability.l3,
      );
      expect(
        EpubReadability.grade(
          ok: true,
          warnings: const <String>[],
          spineCount: 4,
          missingSpineItems: 0,
          missingResources: 0,
          repairedRefs: 0,
          tocFallbackUsed: true,
        ),
        EpubReadability.l2,
      );
    });
  });
}
