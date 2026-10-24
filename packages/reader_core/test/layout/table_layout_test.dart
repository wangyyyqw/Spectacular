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
}
