import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/table_layout.dart';

TableCellSpec _cell({int colspan = 1, int rowspan = 1}) => TableCellSpec(
  naturalWidth: 100,
  measureHeight: (_) => 20,
  colspan: colspan,
  rowspan: rowspan,
);

Object _geometry(TableGridLayout grid, List<List<TableCellSpec>> rows) => [
  grid.columnXs,
  grid.rowYs,
  grid.size.width,
  grid.size.height,
  grid.borderSpacingX,
  grid.borderSpacingY,
  [
    for (var row = 0; row < rows.length; row++)
      [
        for (var cell = 0; cell < rows[row].length; cell++)
          if (grid.cellRectAt(row, cell) case final rect?)
            [
              rect.row,
              rect.cellIndex,
              rect.rect.left,
              rect.rect.top,
              rect.rect.width,
              rect.rect.height,
            ]
          else
            null,
      ],
  ],
];

class _Cancelled implements Exception {
  const _Cancelled();
}

class _ObservedCell extends TableCellSpec {
  _ObservedCell(this.onRead)
    : super(naturalWidth: 100, measureHeight: (_) => 20);

  final void Function() onRead;

  @override
  int get colspan {
    onRead();
    return 1;
  }
}

void main() {
  test('异步构造的槽位、合并格、坐标与命中几何严格保持', () async {
    final random = Random(23);
    for (var sample = 0; sample < 80; sample++) {
      final rows = [
        [_cell(colspan: 2, rowspan: 2), _cell()],
        [_cell()],
        [_cell(rowspan: 2), _cell(colspan: 2)],
        [_cell(), _cell()],
      ];
      final widths = List.generate(3, (_) => 20.0 + random.nextInt(120) / 4);
      final heights = List.generate(4, (_) => 10.0 + random.nextInt(60) / 4);
      final spacing = sample % 4 - 1.0;
      final expected = TableGridLayout(
        rows: rows,
        columnWidths: widths,
        rowHeights: heights,
        borderSpacingX: spacing,
        borderSpacingY: spacing,
      );
      final actual = await TableGridLayout.createAsync(
        rows: rows,
        columnWidths: widths,
        rowHeights: heights,
        borderSpacingX: spacing,
        borderSpacingY: spacing,
      );
      expect(_geometry(actual, rows), _geometry(expected, rows));
      for (var row = 0; row < rows.length; row++) {
        for (var cell = 0; cell < rows[row].length; cell++) {
          final rect = expected.cellRectAt(row, cell);
          if (rect == null) continue;
          expect(
            actual.hitTest(rect.rect.center),
            expected.hitTest(rect.rect.center),
          );
        }
      }
      expect(actual.hitTest(Offset(-1, -1)), isNull);
    }
  });

  test('空网格和超出列范围的槽位沿用同步边界', () async {
    for (final rows in [
      <List<TableCellSpec>>[],
      [_cell(colspan: 9)].map((c) => [c]).toList(),
    ]) {
      final expected = TableGridLayout(
        rows: rows,
        columnWidths: const [],
        rowHeights: const [],
        borderSpacingX: 3,
        borderSpacingY: 2,
      );
      final actual = await TableGridLayout.createAsync(
        rows: rows,
        columnWidths: const [],
        rowHeights: const [],
        borderSpacingX: 3,
        borderSpacingY: 2,
      );
      expect(_geometry(actual, rows), _geometry(expected, rows));
    }
  });

  test('跨行占位、被占列跳过及坐标循环中取消不返回半成品', () async {
    const count = 4096;
    var secondCellReads = 0;
    final rows = [
      [_cell(colspan: count, rowspan: 2)],
      [_ObservedCell(() => secondCellReads++)],
    ];
    final widths = List<double>.filled(count, 1);
    final heights = [20.0, 30.0];
    for (final stop in [20, 5000]) {
      var calls = 0;
      var committed = false;
      secondCellReads = 0;
      final result =
          TableGridLayout.createAsync(
            rows: rows,
            columnWidths: widths,
            rowHeights: heights,
            checkpoint: () async {
              if (++calls == stop) throw const _Cancelled();
            },
          ).then((value) {
            committed = true;
            return value;
          });
      await expectLater(result, throwsA(isA<_Cancelled>()));
      expect(committed, isFalse);
      expect(secondCellReads, 0, reason: '取消发生在第二行槽位完成之前');
      expect(widths, List<double>.filled(count, 1));
      expect(heights, [20.0, 30.0]);
    }
    var calls = 0;
    var committed = false;
    final coordinate =
        TableGridLayout.createAsync(
          rows: const [],
          columnWidths: widths,
          rowHeights: const [],
          checkpoint: () async {
            if (++calls == 20) throw const _Cancelled();
          },
        ).then((value) {
          committed = true;
          return value;
        });
    await expectLater(coordinate, throwsA(isA<_Cancelled>()));
    expect(committed, isFalse);
  });
}
