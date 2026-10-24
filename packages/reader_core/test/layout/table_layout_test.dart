import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/table_layout.dart';

void main() {
  group('TableMeasurer 两遍测量（P3-17）', () {
    test('固定宽表：声明列保留，auto 列分剩余', () {
      // 自然宽：[80, 200, 120]；声明列 0 = 60；表宽 300。
      final result = TableMeasurer.measureColumns(
        naturalWidths: [
          [80, 200, 120],
          [60, 150, 100],
        ],
        specifiedWidths: [60, null, null],
        tableWidthPx: 300,
        containerWidth: 320,
      );
      expect(result.columnWidths[0], 60, reason: '声明列保留');
      // 剩余 240 分给两列（自然比 200:120 → 150:90）。
      expect(result.columnWidths[1], closeTo(150, 0.01));
      expect(result.columnWidths[2], closeTo(90, 0.01));
      expect(result.tableWidth, closeTo(300, 0.01));
    });

    test('百分比宽表：表宽 = 容器 × 百分比', () {
      final result = TableMeasurer.measureColumns(
        naturalWidths: [
          [100, 100],
          [80, 90],
        ],
        specifiedWidths: [null, null],
        tableWidthPercent: 0.5,
        containerWidth: 320,
      );
      expect(result.tableWidth, closeTo(160, 0.01));
      // 自然和 100 > 表宽 160？自然和 = 100+100=200 > 160 → 压缩。
      expect(result.columnWidths[0], closeTo(80, 0.01));
      expect(result.columnWidths[1], closeTo(80, 0.01));
    });

    test('auto 表：不超容器用自然宽，超容器等比压缩', () {
      final fits = TableMeasurer.measureColumns(
        naturalWidths: [
          [100, 120],
        ],
        specifiedWidths: [null, null],
        containerWidth: 320,
      );
      expect(fits.tableWidth, closeTo(220, 0.01));
      expect(fits.columnWidths, [100, 120]);

      final shrunk = TableMeasurer.measureColumns(
        naturalWidths: [
          [240, 240],
        ],
        specifiedWidths: [null, null],
        containerWidth: 320,
      );
      expect(shrunk.tableWidth, closeTo(320, 0.01));
      expect(shrunk.columnWidths[0], closeTo(160, 0.01));
      expect(shrunk.columnWidths[1], closeTo(160, 0.01));
    });

    test('声明列总和超表宽：声明值等比缩', () {
      final result = TableMeasurer.measureColumns(
        naturalWidths: [
          [100, 100],
        ],
        specifiedWidths: [200, 200],
        tableWidthPx: 200,
        containerWidth: 320,
      );
      expect(result.columnWidths[0], closeTo(100, 0.01));
      expect(result.columnWidths[1], closeTo(100, 0.01));
    });

    test('全部列有声明且总和不超表宽：保持声明值', () {
      final result = TableMeasurer.measureColumns(
        naturalWidths: [
          [80, 60],
        ],
        specifiedWidths: [100, 80],
        tableWidthPx: 240,
        containerWidth: 320,
      );
      expect(result.columnWidths, [100, 80],
          reason: '无 auto 列时不强制铺满表宽');
    });

    test('空表返回零宽不崩溃', () {
      final result = TableMeasurer.measureColumns(
        naturalWidths: const [],
        specifiedWidths: const [],
        containerWidth: 320,
      );
      expect(result.columnWidths, isEmpty);
      expect(result.tableWidth, 0);
    });
  });

  group('TableGridMeasurer 行高与回填（P3-18）', () {
    double textHeight(String text, double fontSize, double width) {
      // 近似：每行宽 = 字号 × 字数（全角），行高 = 1.5。
      final perLine = (width / fontSize).floor().clamp(1, 1 << 20);
      final lines = (text.length / perLine).ceil();
      return lines * fontSize * 1.5;
    }

    test('不同字号混排：行高取最大', () {
      final rows = <List<TableCellSpec>>[
        [
          TableCellSpec(
            naturalWidth: 100,
            measureHeight: (w) => textHeight('小字内容', 14, w),
          ),
          TableCellSpec(
            naturalWidth: 120,
            measureHeight: (w) => textHeight('大字标题', 22, w),
          ),
        ],
      ];
      final result = TableGridMeasurer.measureGrid(
        rows: rows,
        columnSpecified: [null, null],
        containerWidth: 320,
      );
      // auto 表保持自然宽 [100,120]：小字 1 行 21，大字 1 行 33 → 行高 33。
      expect(result.rowHeights.single, closeTo(33, 0.01));
    });

    test('跨列单元格宽度回填：按跨列之和测高', () {
      final rows = <List<TableCellSpec>>[
        [
          TableCellSpec(
            naturalWidth: 150,
            measureHeight: (w) => textHeight('甲', 16, w),
          ),
          TableCellSpec(
            naturalWidth: 150,
            measureHeight: (w) => textHeight('乙', 16, w),
          ),
        ],
        [
          TableCellSpec(
            naturalWidth: 120,
            measureHeight: (w) => textHeight(
                '跨两列的长内容会在回填后的宽度下计算行数，宽度足够则行数更少', 16, w),
            colspan: 2,
          ),
        ],
      ];
      final result = TableGridMeasurer.measureGrid(
        rows: rows,
        columnSpecified: [null, null],
        containerWidth: 320,
      );
      // 列各 150；第 2 行跨列回填宽 300 → 30 字每行 18 字 → 2 行 48。
      expect(result.rowHeights[0], closeTo(24, 0.01));
      expect(result.rowHeights[1], closeTo(48, 0.01),
          reason: '回填宽度 300 下两行放下');
    });

    test('单元格内容不溢出：行高 ≥ 内容高', () {
      final rows = <List<TableCellSpec>>[
        [
          TableCellSpec(
            naturalWidth: 200,
            measureHeight: (w) => textHeight('很长很长的内容会折成多行，行高必须包住全部内容高度', 16, w),
          ),
        ],
      ];
      final result = TableGridMeasurer.measureGrid(
        rows: rows,
        columnSpecified: [null],
        containerWidth: 320,
      );
      final width = result.columnWidths.single;
      expect(
        result.rowHeights.single,
        greaterThanOrEqualTo(
          rows.first.single.measureHeight(width) - 0.01,
        ),
      );
    });

    test('colspan 越界按已知列回填兜底，不崩溃', () {
      final rows = <List<TableCellSpec>>[
        [
          TableCellSpec(
            naturalWidth: 100,
            measureHeight: (w) => 24,
            colspan: 5,
          ),
        ],
      ];
      final result = TableGridMeasurer.measureGrid(
        rows: rows,
        columnSpecified: [null, null],
        containerWidth: 320,
      );
      expect(result.rowHeights.single, 24);
    });
  });
}
