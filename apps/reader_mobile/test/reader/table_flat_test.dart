import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/reader/epub_chapter_source.dart';

/// 表格块接入 flat 管线的回归（渲染载荷 + 分页几何）。
Uint8List _buildTableEpub(String bodyHtml, {String css = ''}) {
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
    <dc:identifier id="uid">urn:uuid:table-flat-0001</dc:identifier>
    <dc:title>TableFlat</dc:title>
    <dc:language>zh</dc:language>
  </metadata>
  <manifest><item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/></manifest>
  <spine><itemref idref="c1"/></spine>
</package>''',
  );
  addText(
    'OEBPS/c1.xhtml',
    '<html xmlns="http://www.w3.org/1999/xhtml"><head><style>$css</style></head>'
        '<body>$bodyHtml</body></html>',
  );
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('两列表格产出渲染载荷：网格坐标 + 单元格文字', () async {
    final source = await EpubChapterSource.open(_buildTableEpub(
      '<table>'
      '<tr><td>名次</td><td>玩家</td></tr>'
      '<tr><td>1</td><td>程实</td></tr>'
      '<tr><td>2</td><td>眯眯眼</td></tr>'
      '</table><p>表格后正文。</p>',
    ));
    final blocks = (await source.loadChapter(0))
        .expand((page) => page.slices.map((s) => s.block))
        .toList();
    final tableBlocks = blocks.where((b) => b.table != null).toList();
    expect(tableBlocks, hasLength(1), reason: '单页表格一个渲染块');
    final spec = tableBlocks.single.table!;
    expect(spec.columnXs.length, 3, reason: '两列三个列界');
    expect(spec.rowYs.length, 4, reason: '三行四个行界');
    expect(spec.tableWidth, greaterThan(0));
    final texts = spec.cells.map((c) => c.layout.text).toSet();
    expect(texts, containsAll(<String>['名次', '程实', '眯眯眼']));
    // 表格后正文不受影响。
    expect(blocks.last.layout.text, contains('表格后正文'));
  });

  test('th 居中：表头单元格对齐来自 UA', () async {
    final source = await EpubChapterSource.open(_buildTableEpub(
      '<table><tr><th>列一</th><th>列二</th></tr>'
      '<tr><td>甲</td><td>乙</td></tr></table>',
    ));
    final blocks = (await source.loadChapter(0))
        .expand((page) => page.slices.map((s) => s.block))
        .toList();
    final spec = blocks.firstWhere((b) => b.table != null).table!;
    final header = spec.cells.firstWhere((c) => c.layout.text == '列一');
    expect(header.style.textAlign.toString(), contains('center'),
        reason: 'UA th 居中');
  });

  test('多行超页高：行边界切分为多页片', () async {
    final rows = <String>[
      for (var i = 1; i <= 40; i++) '<tr><td>第${i}2行</td><td>数据$i</td></tr>',
    ].join();
    final source = await EpubChapterSource.open(_buildTableEpub(
      '<table>$rows</table>',
    ));
    final blocks = (await source.loadChapter(0))
        .expand((page) => page.slices.map((s) => s.block))
        .toList();
    final tableBlocks = blocks.where((b) => b.table != null).toList();
    expect(tableBlocks.length, greaterThan(1), reason: '40 行超出 480px 页高');
    for (final block in tableBlocks) {
      expect(block.height, lessThanOrEqualTo(480 + 0.5),
          reason: '每片不超页高');
    }
  });

  test('caption-side 控制标题顺序，empty-cells 保留空格布局', () async {
    final source = await EpubChapterSource.open(
      _buildTableEpub(
        '<table class="bottom"><caption>底标题</caption>'
        '<tr><td>甲</td><td></td></tr></table>'
        '<table class="top"><caption>顶标题</caption>'
        '<tr><td>乙</td><td>丙</td></tr></table>',
        css:
            'body { margin: 0; } table { width: 180px; margin: 10px 0; } '
            'caption { font-size: 14px; } '
            'td { height: 38px; box-sizing: border-box; } '
            'caption { caption-side: inherit; } '
            '.bottom { caption-side: bottom; empty-cells: hide; } '
            '.top { caption-side: top; empty-cells: show; }',
      ),
    );
    final blocks = (await source.loadChapter(0))
        .expand((page) => page.slices.map((s) => s.block))
        .toList();

    final captions = blocks
        .where((block) => const {'底标题', '顶标题'}.contains(block.layout.text))
        .toList();
    expect(captions.map((block) => block.layout.text), ['底标题', '顶标题']);
    expect(captions.last.spaceBefore, 10, reason: '相邻表外边距只折叠一次');

    final tableBlocks = blocks.where((block) => block.table != null).toList();
    expect(tableBlocks, hasLength(2));
    expect(tableBlocks.first.spaceBefore, 10, reason: '首表上外边距在表外');
    expect(tableBlocks.first.spaceAfter, 0, reason: '下外边距由底标题承载');
    expect(tableBlocks.last.spaceBefore, 0);
    expect(tableBlocks.last.spaceAfter, 10, reason: '无底标题时下外边距留在表后');
    final emptyCell = tableBlocks.first.table!.cells.last;
    expect(emptyCell.layout.text, isEmpty, reason: '隐藏空格仍保留布局占位');
    expect(emptyCell.rect.height, closeTo(38, 0.01));
  });

  test('hr 分隔线：产出带下边框的空行块', () async {
    final source = await EpubChapterSource.open(_buildTableEpub(
      '<p>上段。</p><hr/><p>下段。</p>',
    ));
    final blocks = (await source.loadChapter(0))
        .expand((page) => page.slices.map((s) => s.block))
        .toList();
    final hr = blocks.firstWhere(
      (b) => b.layout.text.isEmpty && b.style?.borders.bottom.width == 1,
      orElse: () => throw StateError('未找到 hr 块'),
    );
    expect(hr.layout.text, isEmpty);
  });
}
