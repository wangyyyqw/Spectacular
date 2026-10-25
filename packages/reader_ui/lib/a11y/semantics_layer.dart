import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show OrdinalSortKey;
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/semantics_builder.dart';

/// 正文语义层（P4-27）：给自绘正文挂语义节点，让读屏能读出内容。
///
/// 只提供语义、不接收指针事件；节点用块矩形定位，朗读顺序按页内块顺序
/// （[PageSemanticsNode.sortOrder]）。
class ReaderSemanticsLayer extends StatelessWidget {
  /// 创建语义层。
  const ReaderSemanticsLayer({
    super.key,
    required this.page,
    required this.pageWidth,
    this.firstNodeFocus,
  });

  /// 当前页。
  final PageContent page;

  /// 正文区宽度（页面级节点用）。
  final double pageWidth;

  /// 首块节点的焦点（P4-28）：翻页后由阅读页请求，让键盘/读屏焦点落到新页
  /// 第一个块；为 null 时节点不可聚焦。
  final FocusNode? firstNodeFocus;

  @override
  Widget build(BuildContext context) {
    final nodes = PageSemanticsBuilder.build(page, pageWidth: pageWidth);
    return IgnorePointer(
      child: Stack(
        children: <Widget>[
          for (final node in nodes)
            Positioned(
              left: node.rect.left,
              top: node.rect.top,
              width: node.rect.width <= 0 ? 1 : node.rect.width,
              height: node.rect.height <= 0 ? 1 : node.rect.height,
              child: FocusTraversalOrder(
                order: NumericFocusOrder(node.sortOrder),
                child: Focus(
                  focusNode: node.sortOrder == 1 ? firstNodeFocus : null,
                  child: Semantics(
                    key: ValueKey<String>(
                      'page-semantics-${node.sortOrder.toInt()}',
                    ),
                    container: true,
                    header: node.isHeader,
                    readOnly: true,
                    sortKey: OrdinalSortKey(node.sortOrder),
                    label: node.label,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
