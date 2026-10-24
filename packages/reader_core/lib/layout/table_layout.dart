import 'dart:math' as math;

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
  }) {
    final columnCount = specifiedWidths.length;
    if (columnCount == 0) {
      return const TableMeasureResult(
        columnWidths: <double>[],
        tableWidth: 0,
      );
    }
    // 第一遍：列自然宽 = 行内最大。
    final natural = List<double>.filled(columnCount, 0);
    for (final row in naturalWidths) {
      for (var c = 0; c < columnCount && c < row.length; c++) {
        natural[c] = math.max(natural[c], row[c]);
      }
    }
    final naturalSum = natural.fold(0.0, (a, b) => a + b);

    // 表格宽：声明优先（百分比 → px），auto = min(自然和, 容器)。
    var tableWidth = naturalSum;
    if (tableWidthPercent != null) {
      tableWidth = containerWidth * tableWidthPercent.clamp(0.0, 1.0);
    } else if (tableWidthPx != null) {
      tableWidth = tableWidthPx;
    }
    tableWidth = tableWidth.clamp(0.0, containerWidth);

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
    if (specifiedTotal > tableWidth && specifiedTotal > 0) {
      final scale = tableWidth / specifiedTotal;
      for (var c = 0; c < columnCount; c++) {
        if (specifiedWidths[c] != null) {
          widths[c] = widths[c] * scale;
        }
      }
      specifiedTotal = tableWidth;
    }
    var remaining = math.max(0.0, tableWidth - specifiedTotal);
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
    final total = widths.fold(0.0, (a, b) => a + b);
    return TableMeasureResult(columnWidths: widths, tableWidth: total);
  }
}

/// 单元格测量规格（P3-18）。
class TableCellSpec {
  const TableCellSpec({
    required this.naturalWidth,
    required this.measureHeight,
    this.colspan = 1,
  });

  /// max-content 自然宽（第一遍按全宽测得）。
  final double naturalWidth;

  /// 内容在给定宽下的高度（含单元格 padding）。
  final double Function(double width) measureHeight;

  /// 跨列数（colspan，P3-19 消费；≥2 时宽度回填为跨列之和）。
  final int colspan;
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
  /// [rows] 行 × 单元格；列宽分配只统计 colspan==1 的单元格自然宽，
  /// 跨列单元格宽度回填为跨列之和并按该宽度测高参与行高取大——内容
  /// 在回填宽度下的高度即其行内占高，保证内容不溢出。
  static TableGridMeasureResult measureGrid({
    required List<List<TableCellSpec>> rows,
    required List<double?> columnSpecified,
    double? tableWidthPx,
    double? tableWidthPercent,
    required double containerWidth,
  }) {
    // 列宽：只取单列单元格的自然宽。
    final columnCount = columnSpecified.length;
    final naturalWidths = <List<double>>[];
    for (final row in rows) {
      final natural = List<double>.filled(columnCount, 0);
      for (var c = 0; c < row.length && c < columnCount; c++) {
        final cell = row[c];
        if (cell.colspan == 1) {
          natural[c] = cell.naturalWidth;
        }
      }
      naturalWidths.add(natural);
    }
    final columns = TableMeasurer.measureColumns(
      naturalWidths: naturalWidths,
      specifiedWidths: columnSpecified,
      tableWidthPx: tableWidthPx,
      tableWidthPercent: tableWidthPercent,
      containerWidth: containerWidth,
    );

    // 行高：逐行取单元格高度最大值；跨列单元格宽度回填为跨列之和。
    final rowHeights = <double>[];
    for (final row in rows) {
      var height = 0.0;
      for (var c = 0; c < row.length; c++) {
        final cell = row[c];
        var width = 0.0;
        var ok = true;
        for (var k = 0; k < cell.colspan && ok; k++) {
          final index = c + k;
          if (index >= columnCount) {
            ok = false; // 跨列越界按已知列回填，不崩溃。
            break;
          }
          width += columns.columnWidths[index];
        }
        if (!ok || width <= 0) {
          width = cell.naturalWidth; // 越界/零宽兜底用自然宽。
        }
        height = math.max(height, cell.measureHeight(width));
      }
      rowHeights.add(height);
    }
    return TableGridMeasureResult(
      columnWidths: columns.columnWidths,
      rowHeights: rowHeights,
      tableWidth: columns.tableWidth,
    );
  }
}
