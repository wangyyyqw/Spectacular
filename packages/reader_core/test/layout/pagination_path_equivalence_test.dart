import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/table_layout.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/src/api/models.dart' show CancelToken;

ComputedStyle _style([Map<String, String> values = const {}]) => ComputedStyle({
  'font-family': 'Ahem',
  'font-size': '10px',
  'line-height': '1',
  'white-space': 'pre',
  ...values,
});

TextLayoutResult _layout(String text, ComputedStyle style) =>
    TextLayoutEngine.layout(text: text, style: style, maxWidth: 100);

PageBlock _text(
  int id,
  int lines, {
  Map<String, String> style = const {},
  int group = 0,
}) {
  final computed = _style(style);
  final text = List.filled(lines, 'aa').join('\n');
  return PageBlock.styled(
    layout: _layout(text, computed),
    style: computed,
    containingWidth: 100,
    startCfi: 'epubcfi(/6/2!/4/${id * 2}/1:0)',
    endCfi: 'epubcfi(/6/2!/4/${id * 2}/1:${text.length})',
    groupId: group,
    absolute: computed.position == CssPosition.absolute,
  );
}

PageBlock _mixedText() {
  final base = _style({'text-align': 'justify'});
  const text = '正文：“混合字体，保持锚点。”\n第二行夹有 small 和加粗正文。';
  return PageBlock.styled(
    layout: TextLayoutEngine.layout(
      text: text,
      style: base,
      maxWidth: 100,
      runs: [
        StyledRun(
          start: 4,
          end: 9,
          style: base.withInlineTypography(fontSize: 7, fontWeight: 700),
        ),
      ],
    ),
    style: base,
    containingWidth: 100,
    startCfi: 'epubcfi(/6/2!/4/2/1:0)',
    endCfi: 'epubcfi(/6/2!/4/2/1:${text.length})',
  );
}

List<PageBlock> _framed(List<PageBlock> blocks) {
  final box = PageContainer(
    style: _style({'padding': '3px', 'border': '2px solid red'}),
    left: 0,
    width: 100,
    cloneDecoration: true,
  );
  return [
    for (var i = 0; i < blocks.length; i++)
      blocks[i].withSpacing(
        topInset: i == 0 ? 5 : 0,
        bottomInset: i == blocks.length - 1 ? 5 : 0,
        containers: [
          PageContainerFragment(
            container: box,
            startsHere: i == 0,
            endsHere: i == blocks.length - 1,
          ),
        ],
      ),
  ];
}

PageBlock _table(int rows) {
  final style = _style();
  final cellLayout = _layout('格', style);
  final height = rows * 10.0;
  return PageBlock(
    style: style,
    startCfi: 'epubcfi(/6/2!/4/20)',
    layout: TextLayoutResult(
      text: '',
      lines: [
        LineBox(
          start: 0,
          end: 0,
          top: 0,
          height: height,
          baseline: height,
          width: 100,
        ),
      ],
      width: 100,
      height: height,
      maxWidth: 100,
    ),
    table: TableRenderSpec(
      cells: [
        for (var row = 0; row < rows; row++)
          TableCellRender(
            row: row,
            rect: Rect.fromLTWH(0, row * 10.0, 100, 10),
            layout: cellLayout,
            style: style,
            startCfi: 'epubcfi(/6/2!/4/20/${row * 2 + 2})',
          ),
      ],
      columnXs: const [0, 100],
      rowYs: [for (var row = 0; row <= rows; row++) row * 10.0],
      tableWidth: 100,
      headerRowCount: 1,
      headerHeight: 10,
    ),
  );
}

Object _layoutKey(TextLayoutResult layout) => [
  layout.text,
  layout.width,
  layout.height,
  layout.maxWidth,
  layout.writingMode.name,
  layout.isRtl,
  for (final line in layout.lines)
    [
      line.start,
      line.end,
      line.top,
      line.height,
      line.baseline,
      line.width,
      line.indent,
      line.offsetX,
      line.justifyExtra,
      line.vertical,
    ],
  for (final run in layout.runs)
    [run.start, run.end, run.style.layoutFingerprint, run.baselineShift],
];

Object? _tableKey(TableRenderSpec? table) => table == null
    ? null
    : [
        table.columnXs,
        table.rowYs,
        table.tableWidth,
        table.headerRowCount,
        table.headerHeight,
        for (final cell in table.cells)
          [cell.row, cell.rect, cell.startCfi, _layoutKey(cell.layout)],
      ];

Object _sliceKey(PageBlockSlice slice) => [
  slice.startLine,
  slice.endLine,
  slice.height,
  slice.leadingExtent,
  slice.trailingExtent,
  slice.leftInset,
  slice.overlay,
  slice.absoluteTop,
  slice.textTopTrim,
  slice.textBottomTrim,
  slice.block.startCfi,
  slice.block.endCfi,
  _layoutKey(slice.block.layout),
  _tableKey(slice.block.table),
  for (final frame in slice.block.containers)
    [
      frame.startsHere,
      frame.endsHere,
      frame.topInset,
      frame.bottomInset,
      frame.container.left,
      frame.container.width,
    ],
];

Object _pageKey(PageContent page) => [
  page.spineIndex,
  page.pageIndex,
  page.usedHeight,
  page.pageHeight,
  page.topPadding,
  [for (final slice in page.slices) _sliceKey(slice)],
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fixtures = <String, List<PageBlock>>{
    '标题避页底与显式强制断页': [
      _text(1, 4),
      _text(2, 1, style: {'break-after': 'avoid'}),
      _text(3, 5),
      _text(4, 1, style: {'page-break-before': 'always'}),
    ],
    '块内避断与图题成组': [
      _text(1, 3),
      _text(2, 3, style: {'break-inside': 'avoid-page'}),
      _text(3, 3),
      _text(4, 2, group: 1),
      _text(5, 1, group: 1),
    ],
    '跨页容器续框与段距': _framed([
      _text(1, 7),
      _text(2, 3, style: {'margin': '4px 0'}),
    ]),
    '声明盒高与绝对覆盖': [
      _text(1, 2, style: {'height': '35px'}),
      _text(2, 1, style: {'position': 'absolute', 'top': '5px'}),
      _text(3, 3, style: {'height': '12px', 'overflow': 'hidden'}),
      _text(4, 1),
    ],
    '重复表头与其后正文': [_text(1, 2), _table(12), _text(2, 1)],
    '多列跨页与 CFI': [
      _text(1, 13, style: {'column-count': '2', 'column-gap': '5px'}),
      _text(2, 1),
    ],
    '混合字体与标点': [_mixedText(), _text(2, 2)],
    '竖排块与强制断页': [
      _text(
        1,
        3,
        style: {'writing-mode': 'vertical-rl', 'page-break-after': 'always'},
      ),
      _text(2, 2),
    ],
    '超高行仍然推进': [
      _text(1, 2, style: {'font-size': '70px'}),
    ],
  };
  for (final entry in fixtures.entries) {
    for (final trim in [false, true]) {
      test('同步／流式等价：${entry.key}（留白回收 $trim）', () async {
        final paginator = Paginator(
          pageHeight: 50,
          pageWidth: 100,
          topPadding: 3,
          trimTextEdges: trim,
        );
        final measured = paginator
            .measureChapter(blocks: entry.value, spineIndex: 3)
            .pages;
        final streamed = await paginator
            .paginate(blocks: entry.value, spineIndex: 3)
            .toList();
        expect(streamed.map(_pageKey), measured.map(_pageKey));
      });
    }
  }

  for (final geometry in [
    {'column-count': '2', 'column-gap': '5px'},
    {'writing-mode': 'vertical-rl'},
  ]) {
    test('多列／竖排完成后仍消费强制断页 $geometry', () async {
      final blocks = [
        _text(1, 2, style: {...geometry, 'page-break-after': 'always'}),
        _text(2, 1),
      ];
      final paginator = Paginator(pageHeight: 100, pageWidth: 100);
      final measured = paginator.measureChapter(blocks: blocks).pages;
      final streamed = await paginator.paginate(blocks: blocks).toList();
      for (final pages in [measured, streamed]) {
        expect(pages, hasLength(2));
        expect(pages.last.slices.single.block.layout.text, 'aa');
      }
    });
  }

  test('页内检查点可取消，未提交的表格切片不产出', () async {
    final token = CancelToken();
    var checks = 0;
    final pages = await Paginator(pageHeight: 10000)
        .paginate(
          blocks: [_table(128)],
          token: token,
          budgetCheck: () async {
            if (++checks == 2) token.cancel();
          },
        )
        .toList();
    expect(checks, 2);
    expect(pages, isEmpty);
  });

  test('表格候选只读几何，异步切片与同步结果严格一致', () async {
    final table = _framed([_table(12)]).single;
    for (final start in [0, 1, 5]) {
      for (var end = start + 1; end <= 12; end++) {
        final sync = Paginator.tablePiece(table, start, end);
        final async = await Paginator.tablePieceAsync(table, start, end);
        expect(_tableKey(async.table), _tableKey(sync.table));
        final metrics = Paginator.tablePieceMetrics(table, start, end);
        expect(metrics.height, sync.height);
        expect(metrics.leading, sync.leadingExtent);
        expect(metrics.trailing, sync.trailingExtent);
        expect(metrics.topDecoration, sync.containerTopInset(0));
        expect(metrics.bottomDecoration, sync.containerBottomInset(1));
      }
    }
  });

  test('单片表格遍历单元格途中取消，调用方收不到部分切片', () async {
    final table = _table(100);
    var checks = 0;
    await expectLater(
      Paginator.tablePieceAsync(
        table,
        0,
        100,
        checkpoint: () async {
          if (++checks == 30) throw StateError('测试取消');
        },
      ),
      throwsStateError,
    );
    expect(checks, 30);
  });

  test('同步／流式同样遵守章节页数上限', () async {
    final blocks = [_text(1, 30)];
    final paginator = Paginator(pageHeight: 20);
    final measured = paginator.measureChapter(blocks: blocks, maxPages: 2);
    final streamed = await paginator
        .paginate(blocks: blocks, maxPages: 2)
        .toList();
    expect(measured.truncated, isTrue);
    expect(streamed, hasLength(2));
    expect(streamed.map(_pageKey), measured.pages.map(_pageKey));
  });
}
