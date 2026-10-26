
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/table_layout.dart';

/// rowspan 的表格几何与跨页边界（W1 布局盒模型）。
///
/// 口径：合并区域在整表坐标里是完整矩形；分页只在**行边界**切，跨页的
/// 合并格不做拆分（每页只画落在本页行区间内的片段），这是当前已知限制，
/// 用例把行为锁住。
TableCellSpec _cell(
  double width,
  double height, {
  int colspan = 1,
  int rowspan = 1,
}) => TableCellSpec(
  naturalWidth: width,
  measureHeight: (_) => height,
  colspan: colspan,
  rowspan: rowspan,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('简单跨行（不跨页）：合并区域覆盖两行，一页内完整可见', () {
    final rows = <List<TableCellSpec>>[
      <TableCellSpec>[_cell(100, 30), _cell(100, 30)],
      <TableCellSpec>[_cell(100, 40, rowspan: 2), _cell(100, 20)],
      <TableCellSpec>[_cell(100, 20)],
    ];
    final measured = TableGridMeasurer.measureGrid(
      rows: rows,
      columnSpecified: const <double?>[null, null],
      containerWidth: 200,
    );
    final layout = TableGridLayout(
      rows: rows,
      columnWidths: measured.columnWidths,
      rowHeights: measured.rowHeights,
    );
    final spanned = layout.cellRectAt(1, 0)!;
    expect(
      spanned.rect.height,
      closeTo(measured.rowHeights[1] + measured.rowHeights[2], 0.01),
    );

    final slices = TablePaginator.paginateRows(
      rowHeights: measured.rowHeights,
      pageHeight: 400,
    );
    expect(slices, hasLength(1), reason: '整表一页放下');
    expect(slices.single.firstRow, 0);
    expect(slices.single.lastRow, measured.rowHeights.length);
    // 合并区域完全落在这一页的行区间内。
    expect(
      layout.rowYs[slices.single.firstRow],
      lessThanOrEqualTo(spanned.rect.top),
    );
    expect(
      layout.rowYs[slices.single.lastRow],
      greaterThanOrEqualTo(spanned.rect.bottom - 0.01),
    );
  });

  test('跨页合并格：只在行边界切分，行号不丢不重（已知限制）', () {
    // 4 行（30/40/40/30），页高 70：首页放 30+40，次页放 40+30。
    final rowHeights = <double>[30, 40, 40, 30];
    final slices = TablePaginator.paginateRows(
      rowHeights: rowHeights,
      pageHeight: 70,
    );
    expect(slices, hasLength(2));
    expect(slices[0].firstRow, 0);
    expect(slices[0].lastRow, 2, reason: '只在行边界切分，不劈开行');
    expect(slices[1].firstRow, 2, reason: '行号衔接、无重复无丢行');
    expect(slices[1].lastRow, 4);

    final rows = <List<TableCellSpec>>[
      <TableCellSpec>[_cell(100, 30), _cell(100, 30)],
      <TableCellSpec>[_cell(100, 80, rowspan: 2), _cell(100, 40)],
      <TableCellSpec>[_cell(100, 40)],
      <TableCellSpec>[_cell(100, 30)],
    ];
    final measured = TableGridMeasurer.measureGrid(
      rows: rows,
      columnSpecified: const <double?>[null, null],
      containerWidth: 200,
    );
    final layout = TableGridLayout(
      rows: rows,
      columnWidths: measured.columnWidths,
      rowHeights: measured.rowHeights,
    );
    // 整表坐标里合并区域仍完整（跨第 1、2 行）。
    final spanned = layout.cellRectAt(1, 0)!;
    expect(
      spanned.rect.height,
      closeTo(measured.rowHeights[1] + measured.rowHeights[2], 0.01),
    );
    // 合并区（第 1、2 行）跨过页界：整表坐标里仍完整，绘制时按页片段裁剪。
    expect(spanned.rect.top, greaterThanOrEqualTo(layout.rowYs[1]));
    expect(spanned.rect.top, lessThan(layout.rowYs[2]));
    expect(
      spanned.rect.bottom,
      greaterThan(layout.rowYs[2]),
      reason: '合并区跨页（已知限制：每页只画本页行区间内的片段）',
    );
  });

  test('rowspan 越界：钳到最后一行，不越出表体', () {
    final rows = <List<TableCellSpec>>[
      <TableCellSpec>[_cell(80, 20, rowspan: 5), _cell(80, 20)],
      <TableCellSpec>[_cell(80, 20)],
    ];
    final slots = tableCellSlots(rows, 2);
    expect(slots[0][0].rowspan, 2, reason: '剩余行数不足时钳制');
    final measured = TableGridMeasurer.measureGrid(
      rows: rows,
      columnSpecified: const <double?>[null, null],
      containerWidth: 200,
    );
    final layout = TableGridLayout(
      rows: rows,
      columnWidths: measured.columnWidths,
      rowHeights: measured.rowHeights,
    );
    final spanned = layout.cellRectAt(0, 0)!;
    expect(spanned.rect.bottom, closeTo(layout.size.height, 0.01));
  });

  test('跨行格与 border-spacing：合并区域含行间距', () {
    final rows = <List<TableCellSpec>>[
      <TableCellSpec>[_cell(100, 30), _cell(100, 30)],
      <TableCellSpec>[_cell(100, 60, rowspan: 2), _cell(100, 20)],
      <TableCellSpec>[_cell(100, 20)],
    ];
    final measured = TableGridMeasurer.measureGrid(
      rows: rows,
      columnSpecified: const <double?>[null, null],
      containerWidth: 250,
      borderSpacingX: 4,
      borderSpacingY: 6,
    );
    final layout = TableGridLayout(
      rows: rows,
      columnWidths: measured.columnWidths,
      rowHeights: measured.rowHeights,
      borderSpacingX: 4,
      borderSpacingY: 6,
    );
    final spanned = layout.cellRectAt(1, 0)!;
    expect(
      spanned.rect.height,
      closeTo(measured.rowHeights[1] + measured.rowHeights[2] + 6, 0.01),
      reason: '跨行合并区含中间一份行间距',
    );
    expect(spanned.rect.left, closeTo(4, 0.01), reason: '左侧间距');
    expect(layout.size.height, closeTo(layout.rowYs.last, 0.01));
  });
}
