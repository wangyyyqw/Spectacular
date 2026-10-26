import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/table_layout.dart';

import 'support/css_chapter_book.dart';

/// 表格接线（a~e）：rowspan、border-collapse/border-spacing、切片高。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<List<BlockOrTable>> tablesOf(String body, String css) async {
    final source = await openCssChapter(
      body: body,
      css: css,
      contentWidth: 320,
      contentHeight: 800,
    );
    final pages = await source.loadChapter(0);
    return [
      for (final slice in pages.expand((page) => page.slices))
        if (slice.block.table != null)
          BlockOrTable(slice.block.table!, slice.block.layout.height),
    ];
  }

  test('rowspan 让跨行格高等于跨越行高之和', () async {
    final tables = await tablesOf(
      '<table><tr><td rowspan="2">跨两行</td><td>甲</td></tr>'
          '<tr><td>乙</td></tr></table>',
      'table { width: 100%; border-collapse: collapse; } '
          'td { border: 1px solid #000; padding: 2px; font-size: 13px; }',
    );
    final spec = tables.single.spec;
    final spanned = spec.cells.firstWhere((cell) => cell.row == 0);
    final secondRow = spec.cells.where((cell) => cell.row == 1).toList();
    expect(secondRow, isNotEmpty);
    expect(
      spanned.rect.height,
      closeTo(
        secondRow.first.rect.height +
            spec.cells
                .firstWhere((c) => c.row == 0 && c != spanned)
                .rect
                .height,
        0.6,
      ),
      reason: '跨行格高 = 跨过的两行之和',
    );
  });

  test('collapse 时单元格不再加整条边框（只分摊一半）', () async {
    final collapsed = await tablesOf(
      '<table><tr><td>格</td></tr></table>',
      'table { width: 100%; border-collapse: collapse; } '
          'td { border: 2px solid #000; padding: 4px; font-size: 13px; }',
    );
    final separate = await tablesOf(
      '<table><tr><td>格</td></tr></table>',
      'table { width: 100%; border-collapse: separate; border-spacing: 0; } '
          'td { border: 2px solid #000; padding: 4px; font-size: 13px; }',
    );
    final collapseHeight = collapsed.single.spec.cells.first.rect.height;
    final separateHeight = separate.single.spec.cells.first.rect.height;
    // collapse：相邻格共用边线，每格只分摊半条（上下合计 2px）；
    // separate：上下各 2px 共 4px。差值 = 2px。
    expect(
      separateHeight - collapseHeight,
      closeTo(2, 0.6),
      reason: 'collapse 只分摊半条边框',
    );
  });

  test('border-spacing 进单元格坐标与表格尺寸', () async {
    final tables = await tablesOf(
      '<table><tr><td>甲</td><td>乙</td></tr></table>',
      'table { width: 100%; border-collapse: separate; '
          'border-spacing: 6px 8px; } '
          'td { border: 1px solid #000; padding: 2px; font-size: 13px; }',
    );
    final spec = tables.single.spec;
    final first = spec.cells.first;
    expect(first.rect.left, closeTo(6, 0.01), reason: '左端留一份横向间距');
    expect(first.rect.top, closeTo(8, 0.01), reason: '上端留一份纵向间距');
    final secondColumn = spec.cells.firstWhere(
      (cell) => cell.rect.left > first.rect.left,
    );
    expect(
      secondColumn.rect.left - first.rect.right,
      closeTo(6, 0.01),
      reason: '列间距取自 border-spacing',
    );
  });

  test('table-layout: fixed 的百分比列以「表宽 − 间距」为基准', () async {
    final tables = await tablesOf(
      '<table class="fixed"><tr><td class="w">40%</td><td>余下</td></tr></table>',
      'table { width: 100%; font-size: 13px; } '
          '.fixed { table-layout: fixed; border-collapse: separate; '
          'border-spacing: 4px; } '
          'td { border: 1px solid #000; padding: 2px 4px; } '
          '.w { width: 40%; }',
    );
    final spec = tables.single.spec;
    // 320 表宽、3 份 4px 间距 → 列内容区 308；40% = 123.2，
    // 加内缩（padding 8 + border 2）= 133.2 边框盒宽。
    final firstWidth = spec.cells.first.rect.width;
    expect(firstWidth, closeTo(0.4 * 308 + 10, 1.0));
    expect(
      spec.cells.first.rect.right,
      lessThan(tables.single.spec.tableWidth),
    );
  });
}

/// 表格块的最小视图（渲染规格 + 块高）。
class BlockOrTable {
  BlockOrTable(this.spec, this.blockHeight);

  final TableRenderSpec spec;
  final double blockHeight;
}
