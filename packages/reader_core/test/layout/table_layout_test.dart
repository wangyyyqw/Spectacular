import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
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
      expect(result.columnWidths, [100, 80], reason: '无 auto 列时不强制铺满表宽');
    });

    test('min-content 抬高列宽后仍受声明表宽约束', () {
      const minWidths = <double>[115.2, 28.4, 64, 42.6];
      final result = TableMeasurer.measureColumns(
        naturalWidths: [
          minWidths,
        ],
        specifiedWidths: const [88.2, 58.8, 73.5, 73.5],
        tableWidthPercent: 1,
        containerWidth: 294,
        minWidths: minWidths,
      );
      expect(result.tableWidth, closeTo(294, 0.01));
      expect(
        result.columnWidths.fold(0.0, (a, b) => a + b),
        closeTo(294, 0.01),
      );
      for (var c = 0; c < 4; c++) {
        expect(
          result.columnWidths[c],
          greaterThanOrEqualTo(minWidths[c] - 0.01),
        );
      }
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
            measureHeight: (w) =>
                textHeight('跨两列的长内容会在回填后的宽度下计算行数，宽度足够则行数更少', 16, w),
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
      expect(result.rowHeights[1], closeTo(48, 0.01), reason: '回填宽度 300 下两行放下');
    });

    test('单元格内容不溢出：行高 ≥ 内容高', () {
      final rows = <List<TableCellSpec>>[
        [
          TableCellSpec(
            naturalWidth: 200,
            measureHeight: (w) =>
                textHeight('很长很长的内容会折成多行，行高必须包住全部内容高度', 16, w),
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
        greaterThanOrEqualTo(rows.first.single.measureHeight(width) - 0.01),
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
      }) => TableCellSpec(
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
          expect(slices[i].firstRow, slices[i - 1].lastRow, reason: '无重复行、无丢行');
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

        expect(
          TablePaginator.paginateRows(rowHeights: [], pageHeight: 90),
          isEmpty,
        );
      });
    });
  });

  group('border-spacing（separate 边框模型）', () {
    test('列宽在「表宽 - 间距」内分配，表宽含间距', () {
      final result = TableMeasurer.measureColumns(
        naturalWidths: [
          [100, 100],
        ],
        specifiedWidths: [null, null],
        tableWidthPx: 350,
        containerWidth: 350,
        borderSpacingX: 4,
      );
      // 350 - 4*(2+1) = 338 → 两列各 169。
      expect(result.columnWidths[0], closeTo(169, 0.01));
      expect(result.columnWidths[1], closeTo(169, 0.01));
      expect(result.tableWidth, closeTo(350, 0.01), reason: '表宽含首尾与中间间距');
    });

    test('auto 表宽 = 自然宽和 + 间距', () {
      final result = TableMeasurer.measureColumns(
        naturalWidths: [
          [80, 60],
        ],
        specifiedWidths: [null, null],
        containerWidth: 320,
        borderSpacingX: 5,
      );
      expect(result.tableWidth, closeTo(80 + 60 + 5 * 3, 0.01));
      expect(result.columnWidths[0], closeTo(80, 0.01));
      expect(result.columnWidths[1], closeTo(60, 0.01));
    });

    test('网格几何：单元格内缩间距，表尺寸含首尾间距', () {
      final layout = TableGridLayout(
        rows: [
          [
            const TableCellSpec(naturalWidth: 100, measureHeight: _h20),
            const TableCellSpec(naturalWidth: 100, measureHeight: _h20),
          ],
          [
            const TableCellSpec(naturalWidth: 100, measureHeight: _h20),
            const TableCellSpec(naturalWidth: 100, measureHeight: _h20),
          ],
        ],
        columnWidths: const [145.2, 192.8],
        rowHeights: const [44, 25],
        borderSpacingX: 4,
        borderSpacingY: 6,
      );
      expect(layout.size.width, closeTo(4 + 145.2 + 4 + 192.8 + 4, 0.01));
      expect(layout.size.height, closeTo(6 + 44 + 6 + 25 + 6, 0.01));
      final first = layout.cellRectAt(0, 0)!;
      expect(first.rect.left, closeTo(4, 0.01));
      expect(first.rect.top, closeTo(6, 0.01));
      expect(first.rect.width, closeTo(145.2, 0.01));
      final second = layout.cellRectAt(0, 1)!;
      expect(second.rect.left, closeTo(4 + 145.2 + 4, 0.01));
      final below = layout.cellRectAt(1, 0)!;
      expect(below.rect.top, closeTo(6 + 44 + 6, 0.01));
    });
  });

  group('rowspan（跨行合并）', () {
    test('跨行格把内容高溢出均摊到跨行各行', () {
      final result = TableGridMeasurer.measureGrid(
        rows: [
          [
            const TableCellSpec(naturalWidth: 100, measureHeight: _h20),
            const TableCellSpec(naturalWidth: 100, measureHeight: _h20),
          ],
          [
            // 跨两行，内容 100 高 > 两行 20+20。
            TableCellSpec(
              naturalWidth: 100,
              measureHeight: (_) => 100,
              rowspan: 2,
            ),
            const TableCellSpec(naturalWidth: 100, measureHeight: _h20),
          ],
          [
            const TableCellSpec(naturalWidth: 100, measureHeight: _h20),
            const TableCellSpec(naturalWidth: 100, measureHeight: _h20),
          ],
        ],
        columnSpecified: const [null, null],
        containerWidth: 200,
      );
      expect(
        result.rowHeights[1] + result.rowHeights[2],
        closeTo(100, 0.01),
        reason: '跨行格高度回填为两行之和',
      );
      expect(result.rowHeights[1], closeTo(50, 0.01));
      expect(result.rowHeights[2], closeTo(50, 0.01));
      expect(result.rowHeights[0], closeTo(20, 0.01), reason: '其它行不受影响');
    });

    test('跨行格占用列：下一行的单元格跳过被占列', () {
      final rows = [
        [
          TableCellSpec(naturalWidth: 50, measureHeight: (_) => 30, rowspan: 2),
          const TableCellSpec(naturalWidth: 80, measureHeight: _h20),
          const TableCellSpec(naturalWidth: 80, measureHeight: _h20),
        ],
        [
          const TableCellSpec(naturalWidth: 80, measureHeight: _h20),
          const TableCellSpec(naturalWidth: 80, measureHeight: _h20),
        ],
        [
          const TableCellSpec(naturalWidth: 80, measureHeight: _h20),
          const TableCellSpec(naturalWidth: 80, measureHeight: _h20),
          const TableCellSpec(naturalWidth: 80, measureHeight: _h20),
        ],
      ];
      final slots = tableCellSlots(rows, 3);
      expect(slots[0][0].startColumn, 0);
      expect(slots[0][0].rowspan, 2);
      // 第 2 行首格跳过列 0，落在列 1；第 3 行回到列 0。
      expect(slots[1][0].startColumn, 1);
      expect(slots[1][1].startColumn, 2);
      expect(slots[2][0].startColumn, 0);
    });

    test('行高与合并区域：跨行格矩形覆盖两行', () {
      final rows = [
        [
          const TableCellSpec(naturalWidth: 100, measureHeight: _h20),
          const TableCellSpec(naturalWidth: 100, measureHeight: _h20),
        ],
        [
          TableCellSpec(
            naturalWidth: 100,
            measureHeight: (_) => 60,
            rowspan: 2,
          ),
          const TableCellSpec(naturalWidth: 100, measureHeight: _h20),
        ],
        [const TableCellSpec(naturalWidth: 100, measureHeight: _h20)],
      ];
      final measured = TableGridMeasurer.measureGrid(
        rows: rows,
        columnSpecified: const [null, null],
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
      expect(
        spanned.rect.height,
        greaterThanOrEqualTo(60 - 0.01),
        reason: '合并区域不少于内容高',
      );
      // 命中落在合并区域内 → 命中跨行格本身。
      final hit = layout.hitTest(
        Offset(spanned.rect.left + 5, spanned.rect.top + 5),
      );
      expect(hit, (1, 0));
      final lower = layout.hitTest(
        Offset(spanned.rect.left + 5, spanned.rect.bottom - 5),
      );
      expect(lower, (1, 0), reason: '合并区域下半段仍归跨行格');
    });
  });

  group('自动布局列宽摊派（Chrome 实测口径）', () {
    test('不跨列列取 min/max，跨列格只补差额（32 用例三列）', () {
      // 32-table-colspan-rowspan 的自然宽（含 padding/border）：
      // 列 0 = 跨两行 50；列 1 = 格A 33.34；列 2 = 第三列 50；
      // 跨列表头 76 < 50+33.34，不产生差额；表宽 350 按列比例铺满。
      final measured = TableGridMeasurer.measureGrid(
        rows: <List<TableCellSpec>>[
          <TableCellSpec>[
            TableCellSpec(
              naturalWidth: 76,
              measureHeight: (_) => 26,
              colspan: 2,
            ),
            TableCellSpec(naturalWidth: 50, measureHeight: (_) => 26),
          ],
          <TableCellSpec>[
            TableCellSpec(
              naturalWidth: 50,
              measureHeight: (_) => 52,
              rowspan: 2,
            ),
            TableCellSpec(naturalWidth: 33.34, measureHeight: (_) => 26),
            TableCellSpec(naturalWidth: 50, measureHeight: (_) => 26),
          ],
          <TableCellSpec>[
            TableCellSpec(naturalWidth: 33.34, measureHeight: (_) => 26),
            TableCellSpec(naturalWidth: 50, measureHeight: (_) => 26),
          ],
        ],
        columnSpecified: const <double?>[null, null, null],
        tableWidthPercent: 1,
        containerWidth: 350,
      );
      // 浏览器：130.86 / 87.27 / 130.88（容差 1px）。
      expect(measured.columnWidths[0], closeTo(130.86, 1));
      expect(measured.columnWidths[1], closeTo(87.27, 1));
      expect(measured.columnWidths[2], closeTo(130.88, 1));
      expect(measured.tableWidth, closeTo(350, 0.01));
    });

    test('跨列格超宽时按现有列宽比例补差额', () {
      // 列自然宽 18.25 / 19.3，跨列表 170.89 → 差额 133.34 按比例摊派，
      // 两列变为 83.06 / 87.83；表宽 349 再按比例铺满（浏览器 169.63/179.38）。
      final measured = TableGridMeasurer.measureGrid(
        rows: <List<TableCellSpec>>[
          <TableCellSpec>[
            TableCellSpec(
              naturalWidth: 170.89,
              measureHeight: (_) => 26,
              colspan: 2,
            ),
          ],
          <TableCellSpec>[
            TableCellSpec(naturalWidth: 18.25, measureHeight: (_) => 26),
            TableCellSpec(naturalWidth: 19.3, measureHeight: (_) => 26),
          ],
        ],
        columnSpecified: const <double?>[null, null],
        tableWidthPercent: 1,
        containerWidth: 349,
      );
      expect(measured.columnWidths[0], closeTo(169.63, 1));
      expect(measured.columnWidths[1], closeTo(179.38, 1));
    });

    test('跨列格比跨列列宽更窄时不改变列宽', () {
      final measured = TableGridMeasurer.measureGrid(
        rows: <List<TableCellSpec>>[
          <TableCellSpec>[
            TableCellSpec(
              naturalWidth: 40,
              measureHeight: (_) => 26,
              colspan: 2,
            ),
          ],
          <TableCellSpec>[
            TableCellSpec(naturalWidth: 80, measureHeight: (_) => 26),
            TableCellSpec(naturalWidth: 80, measureHeight: (_) => 26),
          ],
        ],
        columnSpecified: const <double?>[null, null],
        tableWidthPercent: 1,
        containerWidth: 200,
      );
      expect(measured.columnWidths[0], closeTo(100, 0.01));
      expect(measured.columnWidths[1], closeTo(100, 0.01));
    });

    test('rowspan 与 colspan 同时出现：网格占位与合并区域一致', () {
      final rows = <List<TableCellSpec>>[
        <TableCellSpec>[
          TableCellSpec(
            naturalWidth: 80,
            measureHeight: (_) => 60,
            colspan: 2,
            rowspan: 2,
          ),
          TableCellSpec(naturalWidth: 50, measureHeight: (_) => 26),
        ],
        <TableCellSpec>[
          TableCellSpec(naturalWidth: 50, measureHeight: (_) => 26),
        ],
        <TableCellSpec>[
          TableCellSpec(naturalWidth: 40, measureHeight: (_) => 26),
          TableCellSpec(naturalWidth: 40, measureHeight: (_) => 26),
          TableCellSpec(naturalWidth: 40, measureHeight: (_) => 26),
        ],
      ];
      final slots = tableCellSlots(rows, 3);
      expect(slots[0][0].startColumn, 0);
      expect(slots[0][0].colspan, 2);
      expect(slots[0][0].rowspan, 2);
      // 第 2 行首格跳过被 rowspan 占用的 0、1 列，落在第 3 列。
      expect(slots[1][0].startColumn, 2);
      expect(slots[2][0].startColumn, 0);

      final measured = TableGridMeasurer.measureGrid(
        rows: rows,
        columnSpecified: const <double?>[null, null, null],
        tableWidthPercent: 1,
        containerWidth: 300,
      );
      final layout = TableGridLayout(
        rows: rows,
        columnWidths: measured.columnWidths,
        rowHeights: measured.rowHeights,
      );
      final merged = layout.cellRectAt(0, 0)!;
      expect(
        merged.rect.width,
        closeTo(measured.columnWidths[0] + measured.columnWidths[1], 0.01),
      );
      expect(
        merged.rect.height,
        closeTo(measured.rowHeights[0] + measured.rowHeights[1], 0.01),
      );
      expect(merged.rect.height, greaterThanOrEqualTo(60 - 0.01));
    });

    test('min-content 宽保证列不被压到内容以下', () {
      final measured = TableGridMeasurer.measureGrid(
        rows: <List<TableCellSpec>>[
          <TableCellSpec>[
            TableCellSpec(
              naturalWidth: 200,
              minWidth: 120,
              measureHeight: (_) => 26,
            ),
            TableCellSpec(
              naturalWidth: 100,
              minWidth: 60,
              measureHeight: (_) => 26,
            ),
          ],
        ],
        columnSpecified: const <double?>[null, null],
        tableWidthPercent: 1,
        containerWidth: 140,
      );
      // 表宽 140 < 自然宽和 300：两列仍不低于 min（120+60=180 > 140 →
      // 按 min 比例压缩到 140）。
      expect(measured.columnWidths[0], closeTo(140 * 120 / 180, 1));
      expect(measured.columnWidths[1], closeTo(140 * 60 / 180, 1));
    });
  });

  group('单元格内缩（border-collapse 半边框）', () {
    ComputedStyle cellStyle(Map<String, String> overrides) =>
        ComputedStyle(<String, String>{
          'font-size': '13px',
          'padding': '2px 4px',
          'border': '4px solid #000',
          ...overrides,
        });

    test('collapse：边框只分摊半条（水平/垂直各自减半）', () {
      final inset = tableCellInsetFor(cellStyle(const {}), collapse: true);
      // padding 水平 8、垂直 4；border 4px → 半条 2px/侧。
      expect(inset.horizontal, closeTo(8 + 2 * 2, 0.01));
      expect(inset.vertical, closeTo(4 + 2 * 2, 0.01));
    });

    test('separate：边框整条占位', () {
      final inset = tableCellInsetFor(cellStyle(const {}), collapse: false);
      expect(inset.horizontal, closeTo(8 + 4 * 2, 0.01));
      expect(inset.vertical, closeTo(4 + 4 * 2, 0.01));
    });

    test('不可见边框（none/hidden）两种模式下都不计入', () {
      for (final style in <String>['none', 'hidden']) {
        final computed = cellStyle(<String, String>{'border-style': style});
        for (final collapse in <bool>[true, false]) {
          final inset = tableCellInsetFor(computed, collapse: collapse);
          expect(
            inset.horizontal,
            closeTo(8, 0.01),
            reason: '$style/$collapse',
          );
          expect(inset.vertical, closeTo(4, 0.01), reason: '$style/$collapse');
        }
      }
    });

    test('半边框与 cellRect 对齐（32 用例：格宽/格高各少 1px）', () {
      // border 1px + padding 3px 5px：separate 下格高 = 行高 + 8，collapse
      // 下 = 行高 + 8 + 1（每侧半条 0.5）。浏览器 cell rect 含左右各半条。
      final style = cellStyle(const <String, String>{
        'padding': '3px 5px',
        'border': '1px solid #000',
      });
      final separate = tableCellInsetFor(style);
      final collapse = tableCellInsetFor(style, collapse: true);
      expect(separate.horizontal - collapse.horizontal, closeTo(1, 0.01));
      expect(separate.vertical - collapse.vertical, closeTo(1, 0.01));
    });
  });
}

double _h20(double width) => 20;
