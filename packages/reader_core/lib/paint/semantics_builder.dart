import 'dart:ui';

import '../layout/paginator.dart';
import 'hit_test.dart';

/// 语义节点角色（P4-27，§67.2）。
enum PageSemanticsRole {
  /// 页面整体。
  page,

  /// 正文段落。
  paragraph,

  /// 标题。
  heading,

  /// 列表项。
  listItem,

  /// 表格。
  table,
}

/// 一页里一个块的语义节点（P4-27）。
///
/// [sortOrder] 是朗读顺序（块在页内的先后），[rect] 是该块在页内的包围盒。
class PageSemanticsNode {
  /// 创建节点。
  const PageSemanticsNode({
    required this.rect,
    required this.label,
    required this.role,
    required this.sortOrder,
  });

  /// 页内包围盒。
  final Rect rect;

  /// 朗读文本。
  final String label;

  /// 角色。
  final PageSemanticsRole role;

  /// 朗读顺序（从 0 递增）。
  final double sortOrder;

  /// 是否标题。
  bool get isHeader => role == PageSemanticsRole.heading;
}

/// 页语义树构建（P4-27，§67.1～§67.2）：每页排版完成后构建一次。
///
/// 块角色只能从样式推断（块树暂未暴露 HTML 标签）：表格看 table 规格、
/// 列表项看 listMarker、标题看粗体且较短的块；其余按段落处理。
abstract final class PageSemanticsBuilder {
  /// 标题判定的最大字数（粗体短块视为标题）。
  static const int headingMaxLength = 40;

  /// 构建一页的语义节点（第一个是页面级节点）。
  ///
  /// [pageWidth] 是正文区宽度（页面级节点的矩形用），缺省时按行并集推导。
  static List<PageSemanticsNode> build(PageContent page, {double pageWidth = 0}) {
    final nodes = <PageSemanticsNode>[];
    final boxes = TextHitTester.lineBoxes(page);
    final bySlice = <int, List<PageLineBox>>{};
    for (final box in boxes) {
      bySlice.putIfAbsent(box.sliceIndex, () => <PageLineBox>[]).add(box);
    }
    final width = pageWidth > 0
        ? pageWidth
        : (boxes.isEmpty
              ? 0.0
              : boxes
                    .map((box) => box.rect.right)
                    .reduce((a, b) => a > b ? a : b));
    nodes.add(
      PageSemanticsNode(
        rect: Rect.fromLTWH(0, 0, width, page.pageHeight),
        label: '第 ${page.pageIndex + 1} 页',
        role: PageSemanticsRole.page,
        sortOrder: 0,
      ),
    );
    var order = 1;
    for (var sliceIndex = 0; sliceIndex < page.slices.length; sliceIndex++) {
      final slice = page.slices[sliceIndex];
      final block = slice.block;
      final text = block.layout.text.trim();
      if (text.isEmpty) {
        continue;
      }
      final lines = bySlice[sliceIndex];
      final rect = lines == null || lines.isEmpty
          ? Rect.fromLTWH(0, 0, width, slice.height)
          : lines
                .map((line) => line.rect)
                .reduce((a, b) => a.expandToInclude(b));
      nodes.add(
        PageSemanticsNode(
          rect: rect,
          label: text,
          role: _roleOf(block, text),
          sortOrder: order.toDouble(),
        ),
      );
      order++;
    }
    return nodes;
  }

  static PageSemanticsRole _roleOf(PageBlock block, String text) {
    if (block.table != null) {
      return PageSemanticsRole.table;
    }
    if (block.listMarker != null) {
      return PageSemanticsRole.listItem;
    }
    final weight = block.style?.fontWeight ?? 400;
    if (weight >= 600 && text.length <= headingMaxLength) {
      return PageSemanticsRole.heading;
    }
    return PageSemanticsRole.paragraph;
  }
}
