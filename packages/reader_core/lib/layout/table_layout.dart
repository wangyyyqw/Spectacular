import 'dart:math' as math;
import 'dart:ui';

import '../css/computed_style.dart';
import 'line_breaker.dart';

/// 表格单元格的渲染载荷（flat 管线接入）：一格的文字排版结果与
/// 计算样式，坐标为表格局部坐标系（含跨列合并区域）。
class TableCellRender {
  /// 创建渲染格。
  const TableCellRender({
    required this.row,
    required this.rect,
    required this.layout,
    required this.style,
  });

  /// 所在行号（全表行号）。
  final int row;

  /// 合并区域矩形（表格局部坐标）。
  final Rect rect;

  /// 格内文字排版结果（按列宽测量）。
  final TextLayoutResult layout;

  /// 格计算样式（对齐/字体等，绘制层消费）。
  final ComputedStyle style;
}

/// 一页表格切片的渲染规格：格载荷 + 网格线坐标 + 行区间。
/// 由章节源测量产出、PageBlock.table 携带、PageRenderer 绘制。
class TableRenderSpec {
  /// 创建渲染规格。
  const TableRenderSpec({
    required this.cells,
    required this.columnXs,
    required this.rowYs,
    required this.tableWidth,
  });

  /// 本切片内的格（行区间过滤 + 坐标已平移到切片顶）。
  final List<TableCellRender> cells;

  /// 列界坐标（含首 0 与末界，表格局部坐标）。
  final List<double> columnXs;

  /// 行界坐标（本切片内的行，含首 0 与末界，切片局部坐标）。
  final List<double> rowYs;

  /// 表格总宽。
  final double tableWidth;
}

/// 表格列宽两遍测量（P3-17，技术方案 §8.5、CSS Tables 3 的简化口径）。
///
/// 第一遍：单元格按全宽测出自然宽（max-content），列自然宽 = 行内最大；
/// 第二遍：按表格声明宽（固定 px / 百分比 / auto）分配列宽：
/// - 指定宽的列优先保留声明值（钳到表宽内）；
/// - 剩余空间分给未指定列（按自然宽比例）；无未指定列时全体等比缩放；
/// - 自然宽总和超表宽时，未指定列按比例压缩到可用空间；无未指定列时
///   全体等比压缩；
/// - auto 表宽 = min(自然宽总和, 容器宽)。
class TableMeasureResult {
  const TableMeasureResult({
    required this.columnWidths,
    required this.tableWidth,
  });

  /// 每列最终宽。
  final List<double> columnWidths;

  /// 表格最终宽（列宽之和）。
  final double tableWidth;
}

abstract final class TableMeasurer {
  /// 两遍测量列宽。
  ///
  /// [naturalWidths] 第一遍结果（行 × 列的自然宽，已按全宽测量）；
  /// [specifiedWidths] 列声明宽（CSS px，null 为 auto 列）；
  /// [tableWidthPx] 表格声明宽（`width: Npx`，null 未声明）；
  /// [tableWidthPercent] 表格声明宽百分比（`width: 80%`，0~1，null 未声明）；
  /// [containerWidth] 容器内容宽。
  static TableMeasureResult measureColumns({
    required List<List<double>> naturalWidths,
    required List<double?> specifiedWidths,
    double? tableWidthPx,
    double? tableWidthPercent,
    required double containerWidth,
    double borderSpacingX = 0,
    List<double>? minWidths,
  }) {
    final columnCount = specifiedWidths.length;
    if (columnCount == 0) {
      return const TableMeasureResult(
        columnWidths: <double>[],
        tableWidth: 0,
      );
    }
    // `border-spacing` 占表格内容区（列间 + 左右各一份，CSS Tables 3），
    // 列宽只在「表宽 - 间距」里分配；表宽与返回宽度都含间距。
    final spacingTotal = math.max(0.0, borderSpacingX) * (columnCount + 1);
    // 第一遍：列自然宽 = 行内最大。
    final natural = List<double>.filled(columnCount, 0);
    for (final row in naturalWidths) {
      for (var c = 0; c < columnCount && c < row.length; c++) {
        natural[c] = math.max(natural[c], row[c]);
      }
    }
    final naturalSum = natural.fold(0.0, (a, b) => a + b);

    // 表格宽：声明优先（百分比 → px），auto = min（自然和 + 间距, 容器）。
    var tableWidth = naturalSum + spacingTotal;
    if (tableWidthPercent != null) {
      tableWidth = containerWidth * tableWidthPercent.clamp(0.0, 1.0);
    } else if (tableWidthPx != null) {
      tableWidth = tableWidthPx;
    }
    tableWidth = tableWidth.clamp(0.0, containerWidth);
    // 列宽可分配宽（扣掉间距占位）。
    final available = math.max(0.0, tableWidth - spacingTotal);

    final widths = List<double>.filled(columnCount, 0);
    var specifiedTotal = 0.0;
    var autoIndices = <int>[];
    for (var c = 0; c < columnCount; c++) {
      final specified = specifiedWidths[c];
      if (specified != null) {
        // 声明列：钳到表宽内（多列声明超表宽时等比缩声明值）。
        widths[c] = specified;
        specifiedTotal += specified;
      } else {
        autoIndices.add(c);
      }
    }
    if (specifiedTotal > available && specifiedTotal > 0) {
      final scale = available / specifiedTotal;
      for (var c = 0; c < columnCount; c++) {
        if (specifiedWidths[c] != null) {
          widths[c] = widths[c] * scale;
        }
      }
      specifiedTotal = available;
    }
    var remaining = math.max(0.0, available - specifiedTotal);
    if (autoIndices.isEmpty) {
      // 无 auto 列：声明值（已按表宽等比缩）即最终宽，不强制铺满表宽。
    } else {
      // auto 列分剩余空间：按自然宽比例；无剩余则压缩到 0 下限均分。
      final autoNaturalSum =
          autoIndices.fold(0.0, (sum, c) => sum + natural[c]);
      if (autoNaturalSum <= 0) {
        final share = remaining / autoIndices.length;
        for (final c in autoIndices) {
          widths[c] = share;
        }
      } else if (autoNaturalSum <= remaining) {
        // auto 列保自然宽，剩余按比例加宽。
        for (final c in autoIndices) {
          widths[c] = natural[c] +
              (autoNaturalSum > 0
                  ? (remaining - autoNaturalSum) * natural[c] / autoNaturalSum
                  : 0);
        }
      } else {
        // 超表宽：auto 列按自然比例压缩。
        final scale = remaining / autoNaturalSum;
        for (final c in autoIndices) {
          widths[c] = natural[c] * scale;
        }
      }
    }
    // 最小宽保证（CSS 2.1 §17.5.2.2）：列宽不低于 min-content；最小宽之和
    // 超过可分配宽时按比例压缩（表格仍按声明宽，内容允许溢出/换行）。
    if (minWidths != null && minWidths.length >= columnCount) {
      var minTotal = 0.0;
      for (var c = 0; c < columnCount; c++) {
        minTotal += math.max(0.0, minWidths[c]);
      }
      if (minTotal > available && minTotal > 0) {
        final scale = available / minTotal;
        for (var c = 0; c < columnCount; c++) {
          widths[c] = math.max(0.0, minWidths[c]) * scale;
        }
      } else {
        for (var c = 0; c < columnCount; c++) {
          widths[c] = math.max(widths[c], math.max(0.0, minWidths[c]));
        }
      }
    }
    final total = widths.fold(0.0, (a, b) => a + b) + spacingTotal;
    return TableMeasureResult(columnWidths: widths, tableWidth: total);
  }
}

/// 单元格测量规格（P3-18）。
class TableCellSpec {
  const TableCellSpec({
    required this.naturalWidth,
    required this.measureHeight,
    this.minWidth,
    this.colspan = 1,
    this.rowspan = 1,
  });

  /// max-content 自然宽（第一遍按全宽测得，含 padding/border）。
  final double naturalWidth;

  /// min-content 最小宽（含 padding/border）；null 表示未测，按自然宽处理。
  final double? minWidth;

  /// 用于列宽摊派的 min-content 宽（未测时退回自然宽）。
  double get effectiveMinWidth => minWidth ?? naturalWidth;

  /// 内容在给定宽下的高度（含单元格 padding）。
  final double Function(double width) measureHeight;

  /// 跨列数（colspan，P3-19 消费；≥2 时宽度回填为跨列之和）。
  final int colspan;

  /// 跨行数（rowspan，≥2 时高度回填为跨行之和；跨页切开不拆分，见
  /// [TablePaginator.paginateRows] 的已知限制）。
  final int rowspan;
}

/// 单元格内容内缩（padding + 计入盒模型的边框）。
class TableCellInset {
  const TableCellInset({required this.horizontal, required this.vertical});

  /// 左右内缩之和。
  final double horizontal;

  /// 上下内缩之和。
  final double vertical;
}

/// 单元格内缩：`border-collapse: collapse` 时相邻边框合并成格线，单元格
/// 只分摊**半条**边框（Chrome 实测：cell rect 左右各含半条，格高/格宽 =
/// padding + 行高/内容 + border/2）；`separate` 时边框整条占位。
///
/// 边框不可见（`none`/`hidden`/宽度 0）时不计入。
TableCellInset tableCellInsetFor(
  ComputedStyle style, {
  bool collapse = false,
}) {
  final padding = style.padding;
  double side(CssBorderSide border) =>
      border.isVisible ? border.width * (collapse ? 0.5 : 1.0) : 0.0;
  final borders = CssEdges(
    top: side(style.borders.top),
    right: side(style.borders.right),
    bottom: side(style.borders.bottom),
    left: side(style.borders.left),
  );
  return TableCellInset(
    horizontal: padding.horizontal + borders.horizontal,
    vertical: padding.vertical + borders.vertical,
  );
}

/// 单元格在表格网格中的占位（rowspan 消费）。
class TableCellSlot {
  const TableCellSlot({
    required this.row,
    required this.cellIndex,
    required this.startColumn,
    required this.colspan,
    required this.rowspan,
  });

  /// 行号。
  final int row;

  /// 行内单元格序号。
  final int cellIndex;

  /// 起始列（0 起；上一行 rowspan 占用的列会被跳过）。
  final int startColumn;

  /// 跨列数（≥1）。
  final int colspan;

  /// 跨行数（≥1）。
  final int rowspan;

  /// 结束列（不含）。
  int get endColumn => startColumn + colspan;
}

/// 把「行 × 单元格」展开成网格占位：按 HTML 表格模型逐行分配起始列，
/// 上一行 rowspan 覆盖的列跳过（rowspan 上限钳到剩余行数）。
List<List<TableCellSlot>> tableCellSlots(
  List<List<TableCellSpec>> rows,
  int columnCount,
) {
  final occupied = <int, Set<int>>{}; // 行号 → 已被 rowspan 占用的列
  final result = <List<TableCellSlot>>[];
  for (var r = 0; r < rows.length; r++) {
    final taken = occupied.putIfAbsent(r, () => <int>{});
    final slots = <TableCellSlot>[];
    var column = 0;
    for (var i = 0; i < rows[r].length; i++) {
      final cell = rows[r][i];
      while (taken.contains(column)) {
        column += 1;
      }
      final colspan = math.max(1, cell.colspan);
      final rowspan = math.min(math.max(1, cell.rowspan), rows.length - r);
      slots.add(
        TableCellSlot(
          row: r,
          cellIndex: i,
          startColumn: column,
          colspan: colspan,
          rowspan: rowspan,
        ),
      );
      for (var k = 1; k < rowspan; k++) {
        final below = occupied.putIfAbsent(r + k, () => <int>{});
        for (var c = column; c < column + colspan; c++) {
          if (c < columnCount) {
            below.add(c);
          }
        }
      }
      column += colspan;
    }
    result.add(slots);
  }
  return result;
}

/// 表格整表测量结果。
class TableGridMeasureResult {
  const TableGridMeasureResult({
    required this.columnWidths,
    required this.rowHeights,
    required this.tableWidth,
  });

  /// 每列最终宽。
  final List<double> columnWidths;

  /// 每行最终高（行内最大，跨列单元格按回填宽度测高参与取大）。
  final List<double> rowHeights;

  /// 表格最终宽。
  final double tableWidth;
}

/// 整表测量：列宽（[TableMeasurer]）→ 行高（单元格按回填宽度测高取
/// 最大，P3-18，技术方案 §62.3～§62.4）。
abstract final class TableGridMeasurer {
  /// 测量整表。
  ///
  /// 单元格按 [tableCellSlots] 展开成网格占位：`colspan` 的宽度回填为
  /// 跨列之和（列宽分配时把自然宽溢出摊给跨列），`rowspan` 的高度回填
  /// 为跨行之和（内容超出已分配行高时按 CSS 17.5.3 均摊到跨行各行）。
  ///
  /// [borderSpacingX]/[borderSpacingY] 为 `border-spacing`（separate 模式），
  /// 横向进表宽与列宽分配、纵向进跨行高度与表高。
  static TableGridMeasureResult measureGrid({
    required List<List<TableCellSpec>> rows,
    required List<double?> columnSpecified,
    double? tableWidthPx,
    double? tableWidthPercent,
    required double containerWidth,
    double borderSpacingX = 0,
    double borderSpacingY = 0,
  }) {
    final columnCount = columnSpecified.length;
    final slots = tableCellSlots(rows, columnCount);
    final spacingX = math.max(0.0, borderSpacingX);
    final spacingY = math.max(0.0, borderSpacingY);

    // 列宽（CSS 2.1 §17.5.2.2 自动布局，与 Chrome 实测一致）：
    // 1. 先按**不跨列**的单元格取各列 min/max（跨行不影响列宽）；
    // 2. 跨列单元格的 max/min 超过跨列各列之和时，把差额按现有宽比例摊给
    //    跨列各列（「approximately the same amount」，Chrome 用比例摊派）；
    // 3. 表宽分配交给 TableMeasurer（按列 max 比例铺满 / 压缩）。
    final columnMax = List<double>.filled(columnCount, 0);
    final columnMin = List<double>.filled(columnCount, 0);
    for (var r = 0; r < rows.length; r++) {
      for (final slot in slots[r]) {
        if (slot.colspan != 1 || slot.startColumn >= columnCount) {
          continue;
        }
        final cell = rows[r][slot.cellIndex];
        columnMax[slot.startColumn] = math.max(
          columnMax[slot.startColumn],
          cell.naturalWidth,
        );
        columnMin[slot.startColumn] = math.max(
          columnMin[slot.startColumn],
          cell.effectiveMinWidth,
        );
      }
    }
    void spreadDeficit(
      List<double> values,
      int startColumn,
      int endColumn,
      double required,
    ) {
      final end = math.min(endColumn, columnCount);
      if (end <= startColumn) {
        return;
      }
      var current = 0.0;
      for (var c = startColumn; c < end; c++) {
        current += values[c];
      }
      if (required <= current) {
        return;
      }
      final deficit = required - current;
      if (current <= 0) {
        final share = deficit / (end - startColumn);
        for (var c = startColumn; c < end; c++) {
          values[c] += share;
        }
        return;
      }
      for (var c = startColumn; c < end; c++) {
        values[c] += deficit * values[c] / current;
      }
    }

    for (var r = 0; r < rows.length; r++) {
      for (final slot in slots[r]) {
        if (slot.colspan <= 1) {
          continue;
        }
        final cell = rows[r][slot.cellIndex];
        spreadDeficit(columnMax, slot.startColumn, slot.endColumn, cell.naturalWidth);
        spreadDeficit(
          columnMin,
          slot.startColumn,
          slot.endColumn,
          cell.effectiveMinWidth,
        );
      }
    }
    final columns = TableMeasurer.measureColumns(
      naturalWidths: <List<double>>[columnMax],
      specifiedWidths: columnSpecified,
      tableWidthPx: tableWidthPx,
      tableWidthPercent: tableWidthPercent,
      containerWidth: containerWidth,
      borderSpacingX: spacingX,
      minWidths: columnMin,
    );

    // 单元格宽：跨列宽度之和 + 列间距；越界/零宽时退回自然宽。
    double cellWidthOf(TableCellSlot slot) {
      final end = math.min(slot.endColumn, columnCount);
      var width = 0.0;
      for (var c = slot.startColumn; c < end; c++) {
        width += columns.columnWidths[c];
      }
      width += spacingX * math.max(0, end - slot.startColumn - 1);
      return width > 0 ? width : rows[slot.row][slot.cellIndex].naturalWidth;
    }

    // 行高：先按单行格取大。
    final rowHeights = List<double>.filled(rows.length, 0);
    for (var r = 0; r < rows.length; r++) {
      for (final slot in slots[r]) {
        if (slot.rowspan != 1) {
          continue;
        }
        rowHeights[r] = math.max(
          rowHeights[r],
          rows[r][slot.cellIndex].measureHeight(cellWidthOf(slot)),
        );
      }
    }
    // 跨行格：内容高超出「跨行行高之和 + 行间距」时，差值均摊给跨行各行。
    for (var r = 0; r < rows.length; r++) {
      for (final slot in slots[r]) {
        if (slot.rowspan <= 1) {
          continue;
        }
        final span = math.min(slot.rowspan, rows.length - r);
        final height = rows[r][slot.cellIndex].measureHeight(cellWidthOf(slot));
        var current = spacingY * (span - 1);
        for (var k = 0; k < span; k++) {
          current += rowHeights[r + k];
        }
        if (height <= current) {
          continue;
        }
        final extra = (height - current) / span;
        for (var k = 0; k < span; k++) {
          rowHeights[r + k] += extra;
        }
      }
    }
    return TableGridMeasureResult(
      columnWidths: columns.columnWidths,
      rowHeights: rowHeights,
      tableWidth: columns.tableWidth,
    );
  }
}

/// 表格单元格几何（P3-19：colspan 的绘制与命中按合并区域；rowspan 同理）。
class TableCellRect {
  const TableCellRect({
    required this.row,
    required this.cellIndex,
    required this.rect,
  });

  /// 行号。
  final int row;

  /// 行内单元格序号（合并区域指向该跨列/跨行单元格本身）。
  final int cellIndex;

  /// 合并区域矩形（表内坐标）。
  final Rect rect;
}

/// 表格布局几何：单元格矩形与命中测试。
///
/// 坐标口径（含 `border-spacing` 时与浏览器一致）：
/// - [columnXs] / [rowYs] 是「行/列带」边界，首项 0、末项为表宽/表高；
/// - 单元格矩形 = 带起点 + 一份间距，跨列/跨行时覆盖整块合并区域。
class TableGridLayout {
  /// 从测量结果构建。
  TableGridLayout({
    required List<List<TableCellSpec>> rows,
    required List<double> columnWidths,
    required List<double> rowHeights,
    double borderSpacingX = 0,
    double borderSpacingY = 0,
  }) : _columnWidths = List.unmodifiable(columnWidths),
       _rowHeights = List.unmodifiable(rowHeights),
       _spacingX = math.max(0.0, borderSpacingX),
       _spacingY = math.max(0.0, borderSpacingY),
       _slots = tableCellSlots(rows, columnWidths.length) {
    var x = 0.0;
    for (var c = 0; c < columnWidths.length; c++) {
      _columnX.add(x);
      x += _spacingX + columnWidths[c];
    }
    _columnX.add(x + _spacingX);
    var y = 0.0;
    for (var r = 0; r < rowHeights.length; r++) {
      _rowY.add(y);
      y += _spacingY + rowHeights[r];
    }
    _rowY.add(y + _spacingY);
  }

  final List<List<TableCellSlot>> _slots;
  final List<double> _columnWidths;
  final List<double> _rowHeights;
  final double _spacingX;
  final double _spacingY;
  final List<double> _columnX = <double>[];
  final List<double> _rowY = <double>[];

  /// 表格总尺寸（含 border-spacing 的首尾占位）。
  Size get size => Size(_columnX.last, _rowY.last);

  /// 列带边界坐标（含首 0 与末界）。
  List<double> get columnXs => List<double>.unmodifiable(_columnX);

  /// 行带边界坐标（含首 0 与末界，全表坐标）。
  List<double> get rowYs => List<double>.unmodifiable(_rowY);

  /// 边框间距（横向、纵向）。
  double get borderSpacingX => _spacingX;
  double get borderSpacingY => _spacingY;

  /// 单元格合并区域矩形；越界返回 null。
  TableCellRect? cellRectAt(int row, int cellIndex) {
    if (row < 0 || row >= _slots.length) {
      return null;
    }
    final rowSlots = _slots[row];
    if (cellIndex < 0 || cellIndex >= rowSlots.length) {
      return null;
    }
    final slot = rowSlots[cellIndex];
    if (slot.startColumn >= _columnWidths.length) {
      return null;
    }
    final endColumn = math.min(slot.endColumn, _columnWidths.length);
    final endRow = math.min(slot.row + slot.rowspan, _rowHeights.length);
    // 宽高按「跨列/跨行之和 + 中间的间距」算，避免把表尾的外侧间距算进格内。
    var width = 0.0;
    for (var c = slot.startColumn; c < endColumn; c++) {
      width += _columnWidths[c];
    }
    width += _spacingX * math.max(0, endColumn - slot.startColumn - 1);
    var height = 0.0;
    for (var r = slot.row; r < endRow; r++) {
      height += _rowHeights[r];
    }
    height += _spacingY * math.max(0, endRow - slot.row - 1);
    return TableCellRect(
      row: row,
      cellIndex: cellIndex,
      rect: Rect.fromLTWH(
        _columnX[slot.startColumn] + _spacingX,
        _rowY[slot.row] + _spacingY,
        width,
        height,
      ),
    );
  }

  /// 命中测试：返回 (行, 行内单元格序号)；表外返回 null。
  ///
  /// 跨列/跨行单元格按合并区域整体命中（HTML colspan/rowspan 语义）。
  (int, int)? hitTest(Offset point) {
    if (point.dy < 0 ||
        point.dy >= _rowY.last ||
        point.dx < 0 ||
        point.dx >= _columnX.last) {
      return null;
    }
    var row = 0;
    while (row + 1 < _rowY.length && point.dy >= _rowY[row + 1]) {
      row += 1;
    }
    if (row >= _slots.length) {
      return null;
    }
    final rowSlots = _slots[row];
    for (var i = 0; i < rowSlots.length; i++) {
      final rect = cellRectAt(row, i);
      if (rect != null && rect.rect.contains(point)) {
        return (row, i);
      }
    }
    // rowspan 覆盖区：命中上方行的合并格。
    for (var r = row - 1; r >= 0; r--) {
      final slots = _slots[r];
      for (var i = 0; i < slots.length; i++) {
        if (slots[i].row + slots[i].rowspan <= row) {
          continue;
        }
        final rect = cellRectAt(r, i);
        if (rect != null && rect.rect.contains(point)) {
          return (r, i);
        }
      }
    }
    return null;
  }
}

/// 一页内的表格切片（P3-20，§26.2）。
class TablePageSlice {
  const TablePageSlice({
    required this.firstRow,
    required this.lastRow,
    required this.drawnHeight,
    required this.clippedRowHeight,
  });

  /// 本页首行（含）。
  final int firstRow;

  /// 本页末行（不含）。
  final int lastRow;

  /// 本页表格占用的高度。
  final double drawnHeight;

  /// 本页末行被裁剪时的高度（行放不下按整页裁剪，绘制只画此高）；
  /// 行完整放入时为 0。
  final double clippedRowHeight;

  /// 行区间是否为空。
  bool get isEmpty => firstRow >= lastRow;
}

/// 表格跨页切分（P3-20，技术方案 §26.2 的一期口径）。
///
/// - 行放不下时在**行边界**切页（无重复行、无丢行）；
/// - 列宽由整表测量决定（P3-17），切页后各页不重算；
/// - 单行高于整页：独占一页并按页高裁剪（[TablePageSlice.clippedRowHeight]
///   记录已绘制高度，绘制只画裁剪段）；
/// - 表头不重复（一期，§26.4 P1 优化保留）；
/// - `rowspan` 单元格跨页时按行边界切开（不拆分合并区域，跨页片段的合并
///   区域收缩到本页行区间；真正的跨页合并留待后续，见 [TableRenderSpec]）。
abstract final class TablePaginator {
  /// 按页高切分行区间。
  static List<TablePageSlice> paginateRows({
    required List<double> rowHeights,
    required double pageHeight,
  }) {
    final slices = <TablePageSlice>[];
    var firstRow = 0;
    var used = 0.0;
    for (var row = 0; row < rowHeights.length; row++) {
      final height = rowHeights[row];
      if (height > pageHeight) {
        // 单行超页：先收掉前面的切片，再独占一页裁剪。
        if (row > firstRow) {
          slices.add(
            TablePageSlice(
              firstRow: firstRow,
              lastRow: row,
              drawnHeight: used,
              clippedRowHeight: 0,
            ),
          );
        }
        slices.add(
          TablePageSlice(
            firstRow: row,
            lastRow: row + 1,
            drawnHeight: pageHeight,
            clippedRowHeight: pageHeight,
          ),
        );
        firstRow = row + 1;
        used = 0;
        continue;
      }
      if (used + height > pageHeight && row > firstRow) {
        slices.add(
          TablePageSlice(
            firstRow: firstRow,
            lastRow: row,
            drawnHeight: used,
            clippedRowHeight: 0,
          ),
        );
        firstRow = row;
        used = 0;
      }
      used += height;
    }
    if (firstRow < rowHeights.length) {
      slices.add(
        TablePageSlice(
          firstRow: firstRow,
          lastRow: rowHeights.length,
          drawnHeight: used,
          clippedRowHeight: 0,
        ),
      );
    }
    return slices;
  }
}
