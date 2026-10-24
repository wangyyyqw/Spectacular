import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/ua_stylesheet.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';

Uint8List _buildEpub(String bodyHtml) {
  final archive = Archive();
  void addText(String name, String content) {
    final bytes = Uint8List.fromList(utf8.encode(content));
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  archive.addFile(
    ArchiveFile('mimetype', 20, 'application/epub+zip'.codeUnits),
  );
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
    <dc:identifier id="uid">urn:uuid:8765-4321</dc:identifier>
    <dc:title>Lists</dc:title>
    <dc:language>zh</dc:language>
  </metadata>
  <manifest><item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/></manifest>
  <spine><itemref idref="c1"/></spine>
</package>''',
  );
  addText(
    'OEBPS/c1.xhtml',
    '<html xmlns="http://www.w3.org/1999/xhtml"><body>$bodyHtml</body></html>',
  );
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ul 列表：li 块带 • 标记与 40px 缩进', () async {
    final source = await EpubChapterSource.open(_buildEpub(
      '<ul><li>第一项内容</li><li>第二项内容</li></ul>',
    ));
    final blocks = (await source.loadChapter(0))
        .expand((page) => page.slices.map((s) => s.block))
        .toList();
    expect(blocks, hasLength(2));
    expect(blocks[0].listMarker, '•');
    expect(blocks[1].listMarker, '•');
    expect(blocks[0].style?.margin.left, closeTo(40, 0.5),
        reason: 'UA li 默认缩进（flat 管线近似 ul padding）');
  });

  test('ol 列表：序号标记 1. 2. 3. 递增', () async {
    final source = await EpubChapterSource.open(_buildEpub(
      '<ol><li>甲</li><li>乙</li><li>丙</li></ol>',
    ));
    final blocks = (await source.loadChapter(0))
        .expand((page) => page.slices.map((s) => s.block))
        .toList();
    expect(
      blocks.map((b) => b.listMarker).toList(),
      ['1.', '2.', '3.'],
    );
  });

  test('嵌套列表：内层 ul 深度 1 用 ○', () async {
    final source = await EpubChapterSource.open(_buildEpub(
      '<ul><li>外层项'
      '<ul><li>内层项</li></ul>'
      '</li></ul>',
    ));
    final blocks = (await source.loadChapter(0))
        .expand((page) => page.slices.map((s) => s.block))
        .toList();
    expect(blocks.map((b) => b.listMarker).toList(), ['•', '○']);
  });

  test('诗歌行保留：br 硬换行在分页后仍按行呈现', () async {
    final source = await EpubChapterSource.open(_buildEpub(
      '<p>白日依山尽<br/>黄河入海流<br/>欲穷千里目</p>',
    ));
    final pages = await source.loadChapter(0);
    final allBlocks = pages
        .expand((page) => page.slices.map((s) => s.block))
        .toList();
    final poemBlock = allBlocks.firstWhere(
      (b) => b.layout.text.contains('白日依山尽'),
    );
    expect(poemBlock.layout.lineCount, 3, reason: '三行诗各自成行');
  });

  test('blockquote 缩进与左边框：UA margin + 作者 border-left 生效', () {
    final blockquoteStyle = UaBlockDefaults.apply(
      ComputedStyle(const <String, String>{
        'font-size': '16px',
        'line-height': '1.5',
      }),
      'blockquote',
      containingWidth: 320,
    );
    expect(blockquoteStyle, isNotNull);
    expect(blockquoteStyle!.margin.left, closeTo(40, 0.5),
        reason: 'WHATWG blockquote 左右 40px');

    // 作者 border-left：盒模型内缩与边框几何（P2-14 管线）。
    final bordered = ComputedStyle(const <String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'border-left': '4px solid #888888',
    });
    expect(bordered.borders.left.width, 4);
  });
}
