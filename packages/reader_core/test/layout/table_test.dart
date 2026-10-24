import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/block_flow.dart';
import 'package:reader_core/layout/table_layout.dart';
import 'package:reader_core/parser/block_builder.dart';
import 'package:reader_core/parser/document_parser.dart';


BlockDocument _parse(String body) => BlockBuilder.build(
      DocumentParser.parse(
        xhtml: '<html><body>$body</body></html>',
        spineIndex: 0,
      ),
    );

/// 统计解析树里 table 标签的块节点数。
int _countTables(BlockNode node) {
  var count = node.tag == 'table' ? 1 : 0;
  for (final child in node.children) {
    if (child is BlockNode) {
      count += _countTables(child);
    }
  }
  return count;
}

/// 直接构造表格测量盒（解析树无样式，级联管线在 M3；测量口径与
/// createFlowBox 的表格分支一致）。
TableFlowBlock _tableOf(List<String> cellTexts, {int columns = 1}) {
  final rows = <BlockFlow>[];
  for (var i = 0; i < cellTexts.length; i += columns) {
    final cells = <BlockFlow>[];
    for (var c = 0; c < columns && i + c < cellTexts.length; c++) {
      cells.add(
        createFlowBox(
          style: ComputedStyle(const <String, String>{
            'font-size': '16px',
            'line-height': '1.5',
            'display': 'inline-block',
          }),
          text: cellTexts[i + c],
        ),
      );
    }
    rows.add(ColumnFlowBlock(cells));
  }
  return TableFlowBlock(ColumnFlowBlock(rows));
}

void main() {
  group('表格边界（P3-21）', () {
    test('空表：解析不崩溃，测量零尺寸', () {
      final doc = _parse('<table></table>');
      expect(_countTables(doc.root), 1, reason: 'table 进表格分支');
      final table = TableFlowBlock(ColumnFlowBlock([]));
      final size = table.measure(
        LayoutConstraints(maxWidth: 320, maxHeight: 10000),
      );
      expect(size.height.isFinite, isTrue);
    });

    test('单列表：解析到表格节点，测量宽度不越容器', () {
      final doc = _parse(
        '<table><tr><td>甲</td></tr><tr><td>乙</td></tr></table>',
      );
      expect(_countTables(doc.root), 1);
      final table = _tableOf(['甲', '乙']);
      final size = table.measure(
        LayoutConstraints(maxWidth: 320, maxHeight: 10000),
      );
      expect(size.width, lessThanOrEqualTo(320.5));
      expect(size.height, greaterThan(0));
    });

    test('超宽表：按容器收窄不越界', () {
      final longCell = List.filled(60, '宽').join();
      final doc = _parse('<table><tr><td>$longCell</td></tr></table>');
      expect(_countTables(doc.root), 1);
      final table = _tableOf([longCell]);
      final size = table.measure(
        LayoutConstraints(maxWidth: 320, maxHeight: 10000),
      );
      expect(size.width, lessThanOrEqualTo(320.5), reason: '宽表按容器收窄');
      expect(size.height.isFinite, isTrue);
    });

    test('嵌套表：内外都进表格分支且可测量', () {
      final doc = _parse(
        '<table><tr><td>'
        '<table><tr><td>内层</td></tr></table>'
        '</td></tr></table>',
      );
      expect(_countTables(doc.root), 2, reason: '内外两表都走表格分支');
      final inner = _tableOf(['内层']);
      final outerBox = TableFlowBlock(
        ColumnFlowBlock([inner]),
      );
      final size = outerBox.measure(
        LayoutConstraints(maxWidth: 320, maxHeight: 10000),
      );
      expect(size.height.isFinite, isTrue);
    });

    test('缺 tbody（裸 table，Reeden 630 最高频形态）：解析不崩溃', () {
      // 无任何属性/样式的裸表格；html 解析器对缺 tbody 自动补齐。
      final doc = _parse(
        '<table><tr><td>裸</td><td>表</td></tr></table>',
      );
      expect(_countTables(doc.root), 1);
      final table = _tableOf(['裸', '表']);
      final size = table.measure(
        LayoutConstraints(maxWidth: 320, maxHeight: 10000),
      );
      expect(size.height, greaterThan(0));
    });

    test('网格测量路径：裸表两列均匀数据列宽与分页正确', () {
      final rows = <List<TableCellSpec>>[];
      for (var r = 0; r < 3; r++) {
        rows.add([
          TableCellSpec(naturalWidth: 100, measureHeight: (w) => 24),
          TableCellSpec(naturalWidth: 100, measureHeight: (w) => 24),
        ]);
      }
      final result = TableGridMeasurer.measureGrid(
        rows: rows,
        columnSpecified: [null, null],
        containerWidth: 320,
      );
      expect(result.rowHeights, everyElement(closeTo(24, 0.01)));
      expect(result.tableWidth, closeTo(200, 0.01));
      // 分页：3 行 × 24，页高 60 → 2 页。
      final slices = TablePaginator.paginateRows(
        rowHeights: result.rowHeights,
        pageHeight: 60,
      );
      expect(slices, hasLength(2));
    });
  });
}
