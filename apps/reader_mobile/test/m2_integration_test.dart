import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';

import 'support/test_epub.dart';

/// P3-29 M2 集成测试：字体/图片/浮动/表格/容错的端到端用例。
///
/// 说明：块级浮动与表格的精确排版属引擎层（block_flow/table_layout
/// 各自的用例已覆盖）；生产章节源尚未级联书籍 CSS（M3），因此这里
/// 验证「打开→分页→重放→容错导入」的端到端行为与 M2 各能力的
/// 用户可见路径。

Uint8List _buildMixedEpub(Uint8List pngBytes) {
  final archive = Archive();
  void addText(String name, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  addText('mimetype', 'application/epub+zip');
  addText(
    'META-INF/container.xml',
    '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>''',
  );
  addText(
    'OEBPS/content.opf',
    '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="uid">urn:uuid:m2</dc:identifier>
    <dc:title>M2 混合书</dc:title><dc:language>zh</dc:language>
  </metadata>
  <manifest>
    <item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>
    <item id="c2" href="c2.xhtml" media-type="application/xhtml+xml"/>
    <item id="pic" href="images/pic.png" media-type="image/png"/>
  </manifest>
  <spine><itemref idref="c1"/><itemref idref="c2"/></spine>
</package>''',
  );
  addText(
    'OEBPS/c1.xhtml',
    '<html xmlns="http://www.w3.org/1999/xhtml"><body>'
    '${'<p>文字章节，内容足够长以便产生多页分页结果供重放对比。</p>' * 15}'
    '${'<p>第二段继续填充篇幅，确保页数大于一。</p>' * 15}'
    '</body></html>',
  );
  addText(
    'OEBPS/c2.xhtml',
    '<html xmlns="http://www.w3.org/1999/xhtml"><body>'
    '<img src="images/pic.png"/></body></html>',
  );
  archive.addFile(
    ArchiveFile('OEBPS/images/pic.png', pngBytes.length, pngBytes),
  );
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

Future<Uint8List> _pngBytes(int width, int height) async {
  // 不依赖 dart:ui（纯 Dart 构造 PNG 魔数头即可满屏判定——判定只看
  // img 结构与正文，不解码）。
  return Uint8List.fromList(<int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0,
  ]);
}

Uint8List _buildBrokenA() {
  final archive = Archive();
  void addText(String name, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  addText('mimetype', 'application/epub+zip');
  addText(
    'META-INF/container.xml',
    '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>''',
  );
  addText(
    'OEBPS/content.opf',
    '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="uid">urn:uuid:ba</dc:identifier>
    <dc:title>引用破损书</dc:title><dc:language>zh</dc:language>
  </metadata>
  <manifest>
    <item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>
    <item id="pic" href="IMAGES/PIC.PNG" media-type="image/png"/>
  </manifest>
  <spine><itemref idref="c1"/></spine>
</package>''',
  );
  addText(
    'OEBPS/c1.xhtml',
    '<html xmlns="http://www.w3.org/1999/xhtml"><body><p>正文</p></body></html>',
  );
  archive.addFile(
    ArchiveFile(
      'OEBPS/images/pic.png',
      12,
      <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0],
    ),
  );
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

Uint8List _buildBrokenC() {
  final archive = Archive();
  void addText(String name, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  addText('mimetype', 'application/epub+zip');
  addText(
    'chapter1.xhtml',
    '<html xmlns="http://www.w3.org/1999/xhtml"><body><p>拼章一</p></body></html>',
  );
  addText(
    'chapter2.xhtml',
    '<html xmlns="http://www.w3.org/1999/xhtml"><body><p>拼章二</p></body></html>',
  );
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('M2 集成：同书两次打开页序列一致，页缓存重放零重排', () async {
    final bytes = buildTestEpub(title: 'M2 集成书');
    final source1 = await EpubChapterSource.open(bytes);
    final source2 = await EpubChapterSource.open(bytes);

    final first = await source1.loadChapter(0);
    expect(first, isNotEmpty);
    // 独立实例（模拟二次打开）：分页确定性——页数与几何逐页一致。
    final second = await source2.loadChapter(0);
    expect(second, hasLength(first.length));
    for (var i = 0; i < first.length; i++) {
      expect(second[i].pageIndex, first[i].pageIndex);
      expect(second[i].usedHeight, closeTo(first[i].usedHeight, 0.01));
    }
    // 同实例页缓存重放（P7-23）：清页缓存后按页索引直接出页，零重排。
    source1.clearPaginationCache();
    final replayed = await source1.loadChapter(0);
    expect(replayed, hasLength(first.length));
    for (var i = 0; i < first.length; i++) {
      expect(replayed[i].pageIndex, first[i].pageIndex);
      expect(replayed[i].usedHeight, closeTo(first[i].usedHeight, 0.01));
    }
  });

  test('M2 集成：混合书文字章多页 + 满屏图章单页', () async {
    final source = await EpubChapterSource.open(
      _buildMixedEpub(await _pngBytes(64, 48)),
    );
    final textPages = await source.loadChapter(0);
    expect(textPages.length, greaterThan(1), reason: '文字章多页');
    final imagePages = await source.loadChapter(1);
    expect(imagePages, hasLength(1), reason: '满屏图章单页（P3-10）');
    expect(
      imagePages.single.slices.single.block.style?.backgroundImage,
      'OEBPS/images/pic.png',
    );
  });

  test('M2 集成：容错书经书库导入分级落库', () async {
    final tempDir = await Directory.systemTemp.createTemp('m2_library');
    addTearDown(() => tempDir.delete(recursive: true));
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final store = LibraryStore(
      database: db,
      directoryProvider: () async => tempDir,
    );

    // 样本 A（引用可修复）→ L1。
    final entryA = await store.importBytes(
      _buildBrokenA(),
      fallbackTitle: '破损A',
    );
    expect(entryA.readabilityLevel, 1);
    // 样本 C（无 OPF 拼章）→ L3。
    final entryC = await store.importBytes(
      _buildBrokenC(),
      fallbackTitle: '破损C',
    );
    expect(entryC.readabilityLevel, 3);
    // 样本 D（非 ZIP）→ 拒绝。
    expect(
      () => store.importBytes(
        Uint8List.fromList(List.filled(64, 0x21)),
        fallbackTitle: '破损D',
      ),
      throwsA(isA<LibraryImportException>()),
    );
  });
}
