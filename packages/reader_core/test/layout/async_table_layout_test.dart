import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/table_layout.dart';

void main() {
  test('异步格高保留跨列、跨行及边框间距的几何结果', () async {
    final random = Random(17);
    for (var sample = 0; sample < 120; sample++) {
      final heights = List.generate(4, (_) => 15.0 + random.nextInt(60));
      List<List<TableCellSpec>> cells({required bool asynchronous}) => [
        [
          for (var index = 0; index < 2; index++)
            TableCellSpec(
              naturalWidth: 70 + index * 20,
              minWidth: 20 + index * 10,
              rowspan: index == 0 ? 2 : 1,
              measureHeight: (width) => asynchronous
                  ? Future.value(heights[index] + 120 / width)
                  : heights[index] + 120 / width,
            ),
        ],
        [
          TableCellSpec(
            naturalWidth: 90,
            minWidth: 30,
            measureHeight: (width) => asynchronous
                ? Future.value(heights[2] + 100 / width)
                : heights[2] + 100 / width,
          ),
        ],
        [
          TableCellSpec(
            naturalWidth: 220,
            minWidth: 80,
            colspan: 2,
            measureHeight: (width) => asynchronous
                ? Future.value(heights[3] + 160 / width)
                : heights[3] + 160 / width,
          ),
        ],
      ];
      final width = 100.0 + sample;
      final expected = TableGridMeasurer.measureGrid(
        rows: cells(asynchronous: false),
        columnSpecified: const [null, null],
        containerWidth: width,
        borderSpacingX: 3,
        borderSpacingY: 2,
      );
      var checkpoints = 0;
      final actual = await TableGridMeasurer.measureGridAsync(
        rows: cells(asynchronous: true),
        columnSpecified: const [null, null],
        containerWidth: width,
        borderSpacingX: 3,
        borderSpacingY: 2,
        checkpoint: () async => checkpoints++,
      );
      expect(actual.columnWidths, expected.columnWidths);
      expect(actual.rowHeights, expected.rowHeights);
      expect(actual.tableWidth, expected.tableWidth);
      expect(checkpoints, greaterThan(12));
    }
  });

  test('预算取消后不会继续测量剩余单元格', () async {
    var cancelled = false;
    var measured = 0;
    final rows = [
      for (var row = 0; row < 30; row++)
        [
          TableCellSpec(
            naturalWidth: 100,
            measureHeight: (_) async {
              measured++;
              cancelled = true;
              return 20;
            },
          ),
        ],
    ];
    final result = TableGridMeasurer.measureGridAsync(
      rows: rows,
      columnSpecified: const [null],
      containerWidth: 100,
      checkpoint: () async {
        if (cancelled) throw const _Cancelled();
      },
    );
    await expectLater(result, throwsA(isA<_Cancelled>()));
    expect(measured, 1);
  });

  test('同步入口明确拒绝异步格高', () {
    expect(
      () => TableGridMeasurer.measureGrid(
        rows: [
          [TableCellSpec(naturalWidth: 80, measureHeight: (_) async => 20)],
        ],
        columnSpecified: const [null],
        containerWidth: 80,
      ),
      throwsStateError,
    );
  });
}

class _Cancelled implements Exception {
  const _Cancelled();
}
