import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/table_layout.dart';
import 'package:reader_core/paint/semantics_builder.dart';

ComputedStyle _style({
  int fontWeight = 400,
  String display = 'block',
}) => ComputedStyle(<String, String>{
  'font-size': '16px',
  'line-height': '1.5',
  'font-family': 'Ahem',
  'font-weight': '$fontWeight',
  'display': display,
});

PageBlock _block(
  String text, {
  required String cfi,
  int fontWeight = 400,
  TableRenderSpec? table,
  String? listMarker,
}) {
  final style = _style(fontWeight: fontWeight);
  return PageBlock(
    layout: TextLayoutEngine.layout(text: text, style: style, maxWidth: 320),
    style: style,
    startCfi: cfi,
    table: table,
    listMarker: listMarker,
  );
}

PageContent _page(List<PageBlock> blocks) {
  final slices = <PageBlockSlice>[
    for (final block in blocks)
      PageBlockSlice(
        block: block,
        startLine: 0,
        endLine: block.layout.lineCount,
        height: block.layout.height,
      ),
  ];
  return PageContent(
    spineIndex: 0,
    pageIndex: 0,
    slices: slices,
    usedHeight: slices.fold<double>(0, (sum, s) => sum + s.height),
    pageHeight: 800,
    topPadding: 8,
  );
}

void main() {
  group('页语义树（P4-27，§67）', () {
    test('节点数与内容块数匹配（页面节点 + 每块一个）', () {
      final page = _page(<PageBlock>[
        _block('第一章 标题', cfi: 'epubcfi(/6/4!/4/2/1)', fontWeight: 700),
        _block('这是一段正文。', cfi: 'epubcfi(/6/4!/4/2/3)'),
        _block('另一段正文。', cfi: 'epubcfi(/6/4!/4/2/5)'),
      ]);
      final nodes = PageSemanticsBuilder.build(page);
      expect(nodes, hasLength(4), reason: '1 页面节点 + 3 块');
      expect(nodes.first.role, PageSemanticsRole.page);
      expect(nodes.skip(1).every((n) => n.label.isNotEmpty), isTrue);
    });

    test('标题/段落角色：粗体短行判为标题（header）', () {
      final page = _page(<PageBlock>[
        _block('第一章 开局', cfi: 'epubcfi(/6/4!/4/2/1)', fontWeight: 700),
        _block('这是普通正文段落，字数明显多于标题。', cfi: 'epubcfi(/6/4!/4/2/3)'),
      ]);
      final nodes = PageSemanticsBuilder.build(page);
      expect(nodes[1].role, PageSemanticsRole.heading);
      expect(nodes[1].isHeader, isTrue);
      expect(nodes[2].role, PageSemanticsRole.paragraph);
      expect(nodes[2].isHeader, isFalse);
    });

    test('列表项与表格有各自角色', () {
      final page = _page(<PageBlock>[
        _block('第一项', cfi: 'epubcfi(/6/4!/4/2/1)', listMarker: '•'),
        _block(
          '表格内容',
          cfi: 'epubcfi(/6/4!/4/2/3)',
          table: const TableRenderSpec(
            cells: <TableCellRender>[],
            columnXs: <double>[0, 160, 320],
            rowYs: <double>[0, 20, 40],
            tableWidth: 320,
          ),
        ),
      ]);
      final nodes = PageSemanticsBuilder.build(page);
      expect(nodes[1].role, PageSemanticsRole.listItem);
      expect(nodes[2].role, PageSemanticsRole.table);
    });

    test('朗读顺序递增，块矩形来自行的并集', () {
      final page = _page(<PageBlock>[
        _block('第一段内容', cfi: 'epubcfi(/6/4!/4/2/1)'),
        _block('第二段内容', cfi: 'epubcfi(/6/4!/4/2/3)'),
      ]);
      final nodes = PageSemanticsBuilder.build(page);
      expect(nodes.map((n) => n.sortOrder), <double>[0, 1, 2]);
      final first = nodes[1].rect;
      final second = nodes[2].rect;
      expect(first.height, greaterThan(0));
      expect(second.top, greaterThanOrEqualTo(first.bottom - 0.01));
      expect(first.left, greaterThanOrEqualTo(0));
    });

    test('空块不产生节点', () {
      final page = _page(<PageBlock>[
        _block('有内容', cfi: 'epubcfi(/6/4!/4/2/1)'),
        _block('   ', cfi: 'epubcfi(/6/4!/4/2/3)'),
      ]);
      final nodes = PageSemanticsBuilder.build(page);
      expect(nodes, hasLength(2), reason: '页面节点 + 1 个有内容的块');
    });
  });
}
