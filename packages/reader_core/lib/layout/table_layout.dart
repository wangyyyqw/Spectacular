import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui';

import '../css/computed_style.dart';
import '../position/cfi.dart';
import '../position/text_cfi_map.dart';
import 'line_breaker.dart';
import 'paginator.dart' show PageFootnote;

/// 行背景共享原行的定位矩形，绘制范围由该行起始的单元格决定。
/// 跨行格和分页片段只裁剪绘制范围，不重新定位背景图片。
class TableRowBackground {
  const TableRowBackground({required this.rect, required this.style});

  final Rect rect;
  final ComputedStyle style;

  TableRowBackground shift(Offset offset) =>
      TableRowBackground(rect: rect.shift(offset), style: style);
}

/// 表格单元格的渲染载荷（flat 管线接入）：一格的文字排版结果与
/// 计算样式，坐标为表格局部坐标系（含跨列合并区域）。
class TableCellRender {
  /// 创建渲染格。
  const TableCellRender({
    required this.row,
    required this.rect,
    required this.layout,
    required this.style,
    this.startCfi,
    this.textCfis,
    this.footnotes = const <PageFootnote>[],
    this.rowBackground,
  });

  /// 所在行号（全表行号）。
  final int row;

  /// 合并区域矩形（表格局部坐标）。
  final Rect rect;

  /// 格内文字排版结果（按列宽测量）。
  final TextLayoutResult layout;

  /// 格计算样式（对齐/字体等，绘制层消费）。
  final ComputedStyle style;

  /// 独立于格样式的行背景层；背景不参与 CSS 继承。
  final TableRowBackground? rowBackground;

  /// 来源单元格元素（或 Flex 子块）的稳定 CFI，用于定位载荷所在页。
  final String? startCfi;
  final TextCfiMap? textCfis;

  TextCfiMap? get textCoordinates {
    if (textCfis != null) return textCfis;
    final point = startCfi == null ? null : EpubCfi.parse(startCfi!);
    return point == null
        ? null
        : TextCfiMap.linear(
            point,
            layout.inputOffsets?.inputLength ?? layout.text.length,
          ).transformed(layout.inputOffsets);
  }

  String? cfiAt(int offset, {bool end = false}) =>
      textCoordinates?.cfiAt(offset, end: end);

  int? offsetForCfi(String cfi, {bool end = false}) =>
      textCoordinates?.offsetFor(cfi, end: end);

  /// 注号区间沿用格内文本坐标；布局和分页转换不能丢失弹窗数据。
  final List<PageFootnote> footnotes;

  /// 格内文字原点，包含自身装饰与垂直对齐，供绘制和注号命中共用。
  Offset get textOrigin {
    final borders = style.borders;
    final topInset = style.padding.top + borders.top.width;
    final bottomInset = style.padding.bottom + borders.bottom.width;
    final freeSpace = math.max(
      0.0,
      rect.height - topInset - bottomInset - layout.height,
    );
    final alignOffset = switch (style.verticalAlign) {
      CssVerticalAlign.middle => freeSpace / 2,
      CssVerticalAlign.bottom => freeSpace,
      _ => 0.0,
    };
    return rect.topLeft.translate(
      style.padding.left + borders.left.width,
      topInset + alignOffset,
    );
  }
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
    this.headerRowCount = 0,
    this.headerHeight = 0,
    this.flex = false,
  });

  /// 本切片内的格（行区间过滤 + 坐标已平移到切片顶）。
  final List<TableCellRender> cells;

  /// 列界坐标（含首 0 与末界，表格局部坐标）。
  final List<double> columnXs;

  /// 行界坐标（本切片内的行，含首 0 与末界，切片局部坐标）。
  final List<double> rowYs;

  /// 表格总宽。
  final double tableWidth;

  /// 顶部可作为跨页表头重复的行数。
  final int headerRowCount;

  /// 表头占用的纵向高度（表格局部坐标）。
  final double headerHeight;

  /// 该载荷由 Flex 行生成：复用单元格绘制，但块角色仍是普通块。
  final bool flex;
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
      return const TableMeasureResult(columnWidths: <double>[], tableWidth: 0);
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
      final autoNaturalSum = autoIndices.fold(
        0.0,
        (sum, c) => sum + natural[c],
      );
      final hasMinWidths = minWidths != null && minWidths.length >= columnCount;
      final autoMinSum = hasMinWidths
          ? autoIndices.fold<double>(
              0,
              (sum, c) =>
                  sum + math.min(natural[c], math.max(0.0, minWidths[c])),
            )
          : 0.0;
      if (autoNaturalSum <= 0) {
        final share = remaining / autoIndices.length;
        for (final c in autoIndices) {
          widths[c] = share;
        }
      } else if (hasMinWidths && remaining < autoNaturalSum) {
        // 表宽落在 min/max-content 之间时，按每个 auto 列的可增长余量
        // 插值；只按 max 比例压缩会把短列直接压到 min-content 以下。
        final range = autoNaturalSum - autoMinSum;
        final fraction = range > 0
            ? ((remaining - autoMinSum) / range).clamp(0.0, 1.0)
            : 1.0;
        for (final c in autoIndices) {
          final minWidth = math.min(natural[c], math.max(0.0, minWidths[c]));
          widths[c] = minWidth + (natural[c] - minWidth) * fraction;
        }
      } else if (autoNaturalSum <= remaining) {
        // auto 列保自然宽，剩余按比例加宽。
        for (final c in autoIndices) {
          widths[c] =
              natural[c] +
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
        // 逐列抬到 min-content 后可能超过已声明的表宽。按各列高于最小宽的
        // 可压缩余量回收溢出，既保留 min-content 下限，也不让表格越界。
        final raisedTotal = widths.fold(0.0, (a, b) => a + b);
        final overflow = raisedTotal - available;
        if (overflow > 0) {
          var slack = 0.0;
          for (var c = 0; c < columnCount; c++) {
            slack += math.max(0.0, widths[c] - minWidths[c]);
          }
          if (slack > 0) {
            final scale = math.max(0.0, 1 - overflow / slack);
            for (var c = 0; c < columnCount; c++) {
              final minWidth = math.max(0.0, minWidths[c]);
              widths[c] = minWidth + (widths[c] - minWidth) * scale;
            }
          }
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
    required this._measureHeight,
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
  final FutureOr<double> Function(double width) _measureHeight;

  /// 原同步调用契约不变，异步格高应交给整表异步入口。
  double measureHeight(double width) {
    final value = _measureHeight(width);
    if (value is! double) {
      throw StateError('异步单元格测量必须使用 measureGridAsync');
    }
    return value;
  }

  FutureOr<double> measureHeightAsync(double width) => _measureHeight(width);

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
TableCellInset tableCellInsetFor(ComputedStyle style, {bool collapse = false}) {
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
  final work = _TableCellSlotWork(rows, columnCount);
  for (final _ in work.steps()) {}
  return work.result;
}

Future<List<List<TableCellSlot>>> _tableCellSlotsAsync(
  List<List<TableCellSpec>> rows,
  int columnCount,
  Future<void> Function()? checkpoint,
) async {
  final work = _TableCellSlotWork(rows, columnCount);
  for (final _ in work.steps()) {
    await checkpoint?.call();
  }
  await checkpoint?.call();
  return work.result;
}

class _TableCellSlotWork {
  _TableCellSlotWork(this.rows, this.columnCount);

  final List<List<TableCellSpec>> rows;
  final int columnCount;
  final result = <List<TableCellSlot>>[];

  Iterable<int> steps() sync* {
    for (final _ in rows) {
      yield 0;
      result.add(<TableCellSlot>[]);
    }
    for (final slot in _tableCellSlotSteps(rows, columnCount)) {
      yield 0;
      if (slot != null) result[slot.row].add(slot);
    }
  }
}

/// null 只表示预算边界，非空值才是完成的单元格槽位。
Iterable<TableCellSlot?> _tableCellSlotSteps(
  List<List<TableCellSpec>> rows,
  int columnCount,
) sync* {
  final occupied = <int, Set<int>>{};
  for (var row = 0; row < rows.length; row++) {
    yield null;
    final taken = occupied.putIfAbsent(row, () => <int>{});
    var column = 0;
    for (var index = 0; index < rows[row].length; index++) {
      yield null;
      while (taken.contains(column)) {
        yield null;
        column += 1;
      }
      final cell = rows[row][index];
      final span = math.max(1, cell.colspan);
      final rowSpan = math.min(math.max(1, cell.rowspan), rows.length - row);
      final slot = TableCellSlot(
        row: row,
        cellIndex: index,
        startColumn: column,
        colspan: span,
        rowspan: rowSpan,
      );
      yield* _occupySpan(occupied, slot, columnCount);
      column += span;
      yield slot;
    }
  }
}

Iterable<TableCellSlot?> _occupySpan(
  Map<int, Set<int>> occupied,
  TableCellSlot slot,
  int columnCount,
) sync* {
  for (var offset = 1; offset < slot.rowspan; offset++) {
    yield null;
    final below = occupied.putIfAbsent(slot.row + offset, () => <int>{});
    for (var column = slot.startColumn; column < slot.endColumn; column++) {
      yield null;
      if (column < columnCount) below.add(column);
    }
  }
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
  /// 同步与异步入口使用同一列宽及跨行回填算法；同步入口只接收同步格高。
  /// 命名参数保留现有几何契约，避免调用者重新拼装一套表格配置。
  static TableGridMeasureResult measureGrid({
    required List<List<TableCellSpec>> rows,
    required List<double?> columnSpecified,
    double? tableWidthPx,
    double? tableWidthPercent,
    required double containerWidth,
    double borderSpacingX = 0,
    double borderSpacingY = 0,
  }) {
    final input = _GridInput(rows, columnSpecified, (
      px: tableWidthPx,
      percent: tableWidthPercent,
      width: containerWidth,
      spacingX: math.max(0.0, borderSpacingX),
      spacingY: math.max(0.0, borderSpacingY),
    ));
    final work = _GridMeasurement(
      input,
      tableCellSlots(rows, columnSpecified.length),
    );
    for (final _ in work.columnSteps()) {}
    work.resolveColumns();
    for (final slot in work.heightSteps()) {
      final height = work.cell(slot).measureHeight(work.cellWidth(slot));
      work.recordHeight(slot, height);
    }
    return work.result;
  }

  /// 格内文字测量和每个网格工作步均可检查预算及取消，不阻塞整表完成。
  static Future<TableGridMeasureResult> measureGridAsync({
    required List<List<TableCellSpec>> rows,
    required List<double?> columnSpecified,
    double? tableWidthPx,
    double? tableWidthPercent,
    required double containerWidth,
    double borderSpacingX = 0,
    double borderSpacingY = 0,
    Future<void> Function()? checkpoint,
  }) async {
    await checkpoint?.call();
    final input = _GridInput(rows, columnSpecified, (
      px: tableWidthPx,
      percent: tableWidthPercent,
      width: containerWidth,
      spacingX: math.max(0.0, borderSpacingX),
      spacingY: math.max(0.0, borderSpacingY),
    ));
    final slots = await _tableCellSlotsAsync(
      rows,
      columnSpecified.length,
      checkpoint,
    );
    final work = _GridMeasurement(input, slots);
    for (final _ in work.columnSteps()) {
      await checkpoint?.call();
    }
    work.resolveColumns();
    for (final slot in work.heightSteps()) {
      await checkpoint?.call();
      final height = await work
          .cell(slot)
          .measureHeightAsync(work.cellWidth(slot));
      await checkpoint?.call();
      work.recordHeight(slot, height);
    }
    return work.result;
  }
}

typedef _GridGeometry = ({
  double? px,
  double? percent,
  double width,
  double spacingX,
  double spacingY,
});

class _GridInput {
  const _GridInput(this.rows, this.specified, this.geometry);
  final List<List<TableCellSpec>> rows;
  final List<double?> specified;
  final _GridGeometry geometry;
}

class _GridMeasurement {
  _GridMeasurement(this.input, this.slots)
    : columnMax = List.filled(input.specified.length, 0.0),
      columnMin = List.filled(input.specified.length, 0.0),
      rowHeights = List.filled(input.rows.length, 0.0);
  final _GridInput input;
  final List<List<TableCellSlot>> slots;
  final List<double> columnMax;
  final List<double> columnMin;
  final List<double> rowHeights;
  late final TableMeasureResult columns;
  int get columnCount => input.specified.length;
  TableCellSpec cell(TableCellSlot slot) =>
      input.rows[slot.row][slot.cellIndex];

  Iterable<TableCellSlot> columnSteps() sync* {
    for (final row in slots) {
      for (final slot in row) {
        if (slot.colspan == 1 && slot.startColumn < columnCount) {
          final value = cell(slot);
          columnMax[slot.startColumn] = math.max(
            columnMax[slot.startColumn],
            value.naturalWidth,
          );
          columnMin[slot.startColumn] = math.max(
            columnMin[slot.startColumn],
            value.effectiveMinWidth,
          );
        }
        yield slot;
      }
    }
    for (final row in slots) {
      for (final slot in row) {
        if (slot.colspan > 1) {
          _spreadDeficit(columnMax, slot, cell(slot).naturalWidth);
          _spreadDeficit(columnMin, slot, cell(slot).effectiveMinWidth);
        }
        yield slot;
      }
    }
  }

  void _spreadDeficit(
    List<double> values,
    TableCellSlot slot,
    double required,
  ) {
    final end = math.min(slot.endColumn, columnCount);
    if (end <= slot.startColumn) return;
    var current = 0.0;
    for (var column = slot.startColumn; column < end; column++) {
      current += values[column];
    }
    if (required <= current) return;
    final deficit = required - current;
    for (var column = slot.startColumn; column < end; column++) {
      values[column] += current <= 0
          ? deficit / (end - slot.startColumn)
          : deficit * values[column] / current;
    }
  }

  void resolveColumns() {
    columns = TableMeasurer.measureColumns(
      naturalWidths: [columnMax],
      specifiedWidths: input.specified,
      tableWidthPx: input.geometry.px,
      tableWidthPercent: input.geometry.percent,
      containerWidth: input.geometry.width,
      borderSpacingX: input.geometry.spacingX,
      minWidths: columnMin,
    );
  }

  double cellWidth(TableCellSlot slot) {
    final end = math.min(slot.endColumn, columnCount);
    var width = 0.0;
    for (var column = slot.startColumn; column < end; column++) {
      width += columns.columnWidths[column];
    }
    width += input.geometry.spacingX * math.max(0, end - slot.startColumn - 1);
    return width > 0 ? width : cell(slot).naturalWidth;
  }

  Iterable<TableCellSlot> heightSteps() sync* {
    // 保留先单行、后跨行且按文档序回填的原算法。
    for (final row in slots) {
      yield* row.where((slot) => slot.rowspan == 1);
    }
    for (final row in slots) {
      yield* row.where((slot) => slot.rowspan > 1);
    }
  }

  void recordHeight(TableCellSlot slot, double height) {
    if (slot.rowspan == 1) {
      rowHeights[slot.row] = math.max(rowHeights[slot.row], height);
      return;
    }
    final span = math.min(slot.rowspan, input.rows.length - slot.row);
    var current = input.geometry.spacingY * (span - 1);
    for (var offset = 0; offset < span; offset++) {
      current += rowHeights[slot.row + offset];
    }
    if (height <= current) return;
    final extra = (height - current) / span;
    for (var offset = 0; offset < span; offset++) {
      rowHeights[slot.row + offset] += extra;
    }
  }

  TableGridMeasureResult get result => TableGridMeasureResult(
    columnWidths: columns.columnWidths,
    rowHeights: rowHeights,
    tableWidth: columns.tableWidth,
  );
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
  }) : this._(
         _prepareTableGrid(rows, columnWidths, rowHeights, (
           borderSpacingX,
           borderSpacingY,
         )),
       );

  TableGridLayout._(_TableGridBuild work)
    : _columnWidths = UnmodifiableListView<double>(work.columnWidths),
      _rowHeights = UnmodifiableListView<double>(work.rowHeights),
      _spacingX = work.spacingX,
      _spacingY = work.spacingY,
      _slots = work.slots.result,
      _columnX = work.columnXs,
      _rowY = work.rowYs;

  /// 沿用同步构造参数；跨行占位、被占列跳过与行列坐标都检查预算。
  /// 全部步骤完成前不返回网格，取消时不会泄露半成品。
  static Future<TableGridLayout> createAsync({
    required List<List<TableCellSpec>> rows,
    required List<double> columnWidths,
    required List<double> rowHeights,
    double borderSpacingX = 0,
    double borderSpacingY = 0,
    Future<void> Function()? checkpoint,
  }) async {
    final work = _TableGridBuild(rows, columnWidths, rowHeights, (
      borderSpacingX,
      borderSpacingY,
    ));
    await checkpoint?.call();
    for (final _ in work.steps()) {
      await checkpoint?.call();
    }
    await checkpoint?.call();
    return TableGridLayout._(work);
  }

  final List<List<TableCellSlot>> _slots;
  final List<double> _columnWidths;
  final List<double> _rowHeights;
  final double _spacingX;
  final double _spacingY;
  final List<double> _columnX;
  final List<double> _rowY;

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

_TableGridBuild _prepareTableGrid(
  List<List<TableCellSpec>> rows,
  List<double> widths,
  List<double> heights,
  (double, double) spacing,
) {
  final work = _TableGridBuild(rows, widths, heights, spacing);
  for (final _ in work.steps()) {}
  return work;
}

/// 槽位与坐标只属于当前一次构造；同步和异步入口共用运算顺序。
class _TableGridBuild {
  _TableGridBuild(
    List<List<TableCellSpec>> rows,
    this.widths,
    this.heights,
    (double, double) spacing,
  ) : slots = _TableCellSlotWork(rows, widths.length),
      spacingX = math.max(0.0, spacing.$1),
      spacingY = math.max(0.0, spacing.$2);

  final _TableCellSlotWork slots;
  final List<double> widths;
  final List<double> heights;
  final double spacingX;
  final double spacingY;
  final columnWidths = <double>[];
  final rowHeights = <double>[];
  final columnXs = <double>[];
  final rowYs = <double>[];

  Iterable<int> steps() sync* {
    yield* slots.steps();
    yield* _axisSteps(widths, columnWidths, columnXs, spacingX);
    yield* _axisSteps(heights, rowHeights, rowYs, spacingY);
  }

  Iterable<int> _axisSteps(
    List<double> source,
    List<double> sizes,
    List<double> edges,
    double spacing,
  ) sync* {
    var position = 0.0;
    for (final size in source) {
      yield 0;
      sizes.add(size);
      edges.add(position);
      position += spacing + size;
    }
    edges.add(position + spacing);
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
/// - 预切本身不插入表头；跨页分页器会按 [TableRenderSpec.headerRowCount]
///   在续片顶部重复表头；
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
