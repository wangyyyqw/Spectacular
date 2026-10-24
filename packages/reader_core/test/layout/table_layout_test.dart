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

    group('colspan 参与列宽、几何与命中（P3-19）', () {
      TableCellSpec cell(
        double naturalWidth, {
        int colspan = 1,
        double Function(double)? measureHeight,
      }) =>
          TableCellSpec(
            naturalWidth: naturalWidth,
            measureHeight: measureHeight ?? (w) => 24,
            colspan: colspan,
          );

      test('colspan 自然宽溢出按比例摊给跨列', () {
        // 三列单列自然 50；第二行跨三列自然 300 → 溢出 150 摊给三列。
        final rows = <List<TableCellSpec>>[
          [cell(50), cell(50), cell(50)],
          [cell(300, colspan: 3)],
        ];
        final result = TableGridMeasurer.measureGrid(
          rows: rows,
          columnSpecified: [null, null, null],
          containerWidth: 480,
        );
        expect(result.columnWidths[0], closeTo(100, 0.01));
        expect(result.columnWidths[1], closeTo(100, 0.01));
        expect(result.columnWidths[2], closeTo(100, 0.01));
      });

      test('colspan=3 合并区域矩形：x 为前列前缀和，宽为跨列之和', () {
        final rows = <List<TableCellSpec>>[
          [cell(100), cell(100), cell(100)],
          [cell(300, colspan: 3)],
        ];
        final result = TableGridMeasurer.measureGrid(
          rows: rows,
          columnSpecified: [null, null, null],
          containerWidth: 480,
        );
        final layout = TableGridLayout(
          rows: rows,
          columnWidths: result.columnWidths,
          rowHeights: result.rowHeights,
        );
        final merged = layout.cellRectAt(1, 0)!;
        expect(merged.rect.left, 0);
        expect(merged.rect.width, closeTo(300, 0.01));
        final single = layout.cellRectAt(0, 2)!;
        expect(single.rect.left, closeTo(200, 0.01));
        expect(single.rect.width, closeTo(100, 0.01));
      });

      test('命中测试按合并区域：span 内的点命中跨列单元格本身', () {
        final rows = <List<TableCellSpec>>[
          [cell(100), cell(100), cell(100)],
          [cell(300, colspan: 3)],
        ];
        final result = TableGridMeasurer.measureGrid(
          rows: rows,
          columnSpecified: [null, null, null],
          containerWidth: 480,
        );
        final layout = TableGridLayout(
          rows: rows,
          columnWidths: result.columnWidths,
          rowHeights: result.rowHeights,
        );
        // 第 2 行中部（合并区域中间）→ (1, 0)。
        expect(layout.hitTest(const Offset(150, 36)), (1, 0));
        // 第 1 行第三列 → (0, 2)。
        expect(layout.hitTest(const Offset(250, 12)), (0, 2));
        // 表外 → null。
        expect(layout.hitTest(const Offset(500, 12)), isNull);
      });
    });

    group('表格跨页切分（P3-20）', () {
      test('长表格跨 3 页：行区间衔接无重复、无丢行', () {
        // 9 行 × 30 高，页高 80（每页 2 行）→ 5 页。
        final heights = List<double>.filled(9, 30);
        final slices = TablePaginator.paginateRows(
          rowHeights: heights,
          pageHeight: 80,
        );
        // 行区间连续衔接：每片 first == 上一片 last。
        for (var i = 1; i < slices.length; i++) {
          expect(slices[i].firstRow, slices[i - 1].lastRow,
              reason: '无重复行、无丢行');
        }
        expect(slices.first.firstRow, 0);
        expect(slices.last.lastRow, 9);
        expect(slices.every((s) => s.drawnHeight <= 80.01), isTrue);
        expect(slices.every((s) => s.clippedRowHeight == 0), isTrue);
      });

      test('单行高于整页：独占一页并记录裁剪高度', () {
        final slices = TablePaginator.paginateRows(
          rowHeights: [250, 30, 30],
          pageHeight: 100,
        );
        expect(slices, hasLength(2));
        expect(slices[0].firstRow, 0);
        expect(slices[0].lastRow, 1);
        expect(slices[0].clippedRowHeight, 100, reason: '裁剪段记录已绘制高度');
        expect(slices[0].drawnHeight, 100);
        expect(slices[1].firstRow, 1);
        expect(slices[1].lastRow, 3);
        expect(slices[1].drawnHeight, 60);
      });

      test('恰好填满与空表边界', () {
        // 3 行 × 30，页高 90 → 恰好 1 页。
        final exact = TablePaginator.paginateRows(
          rowHeights: [30, 30, 30],
          pageHeight: 90,
        );
        expect(exact, hasLength(1));
        expect(exact.single.lastRow, 3);
        expect(exact.single.drawnHeight, 90);

        expect(TablePaginator.paginateRows(rowHeights: [], pageHeight: 90),
            isEmpty);
      });
    });
  });
}
