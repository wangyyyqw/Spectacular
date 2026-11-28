import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';

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

  test('三列自动表格保留声明 nowrap 的首列，其余列按 min/max-content 分配', () async {
    final source = await EpubChapterSource.open(
      _buildTableEpub(
        '<table class="wz">'
        '<tr><th class="world">世界</th><th>种族</th><th>代表角色</th></tr>'
        '<tr><td class="world">载酒</td><td>人族</td><td>寻歌</td></tr>'
        '<tr><td class="world" rowspan="2">泽兰</td><td>亡灵</td>'
        '<td>枯覆、骨影、语律、喑哑</td></tr>'
        '<tr><td>月狐(雪乡)</td>'
        '<td>雾刃、花殊、燃瓶、空涂、问风、涂风</td></tr>'
        '</table>',
        css:
            'body { margin: 0; font-family: serif; font-size: 17px; } '
            'table.wz { width: 100%; border-collapse: collapse; '
            'margin: 20px 0; background: #fff; } '
            'table.wz td, table.wz th { border: 1px solid #000; '
            'padding: 8px 12px; vertical-align: middle; '
            'font-size: .8em; text-align: center; }'
            'table.wz .world { white-space: nowrap; }',
      ),
      contentWidth: 350,
      contentHeight: 700,
    );
    final spec = (await source.loadChapter(0))
        .expand((page) => page.slices)
        .firstWhere((slice) => slice.block.table != null)
        .block
        .table!;
    final widths = <double>[
      spec.columnXs[1] - spec.columnXs[0],
      spec.columnXs[2] - spec.columnXs[1],
      spec.columnXs[3] - spec.columnXs[2],
    ];
    expect(widths[0], greaterThanOrEqualTo(2 * 13.6 + 24 + 1 - .01));
    expect(widths[1], greaterThan(70));
    expect(widths[2], greaterThan(widths[1] * 2));
    final world = spec.cells.firstWhere((cell) => cell.layout.text == '世界');
    expect(world.layout.lineCount, 1, reason: '首列不能被压成逐字竖排');
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

  test('前置提示后的大表从当前页开始，并按行续排', () async {
    final rows = <String>[
      for (var i = 1; i <= 24; i++) '<tr><td>第$i行</td><td>数据$i</td></tr>',
    ].join();
    final source = await EpubChapterSource.open(
      _buildTableEpub(
        '<p class="tips">表格提示</p><table>$rows</table>',
        css:
            'body { margin: 0; } p { margin: 0; } '
            '.tips { break-after: avoid; } '
            'td { height: 32px; box-sizing: border-box; }',
      ),
      contentWidth: 320,
      contentHeight: 480,
    );
    final pages = await source.loadChapter(0);
    final firstPageTables = pages.first.slices
        .where((slice) => slice.block.table != null)
        .toList();
    expect(firstPageTables, isNotEmpty, reason: '提示后的大表不应整表下移到下一页');
    expect(
      firstPageTables.first.block.table!.rowYs.last,
      lessThan(24 * 32),
      reason: '首页只排当前页能容纳的表格行',
    );

    final tableBlocks = pages
        .expand((page) => page.slices)
        .where((slice) => slice.block.table != null)
        .map((slice) => slice.block)
        .toList();
    expect(tableBlocks.length, greaterThan(firstPageTables.length));
    final texts = tableBlocks
        .expand((block) => block.table!.cells)
        .map((cell) => cell.layout.text)
        .toSet();
    for (var i = 1; i <= 24; i++) {
      expect(texts, contains('第$i行'));
    }
    expect(
      tableBlocks.every((block) => block.height <= 480.5),
      isTrue,
      reason: '续排切片不得越过页面高度',
    );
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
