import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart'
    show CustomSemanticsAction, OrdinalSortKey;
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
    this.onNextPage,
    this.onPreviousPage,
    this.onCopyBlock,
  });

  /// 当前页。
  final PageContent page;

  /// 正文区宽度（页面级节点用）。
  final double pageWidth;

  /// 首块节点的焦点（P4-28）：翻页后由阅读页请求，让键盘/读屏焦点落到新页
  /// 第一个块；为 null 时节点不可聚焦。
  final FocusNode? firstNodeFocus;

  /// 下一页 / 上一页（P4-29，§67.4）：挂在页面级节点上。
  final VoidCallback? onNextPage;
  final VoidCallback? onPreviousPage;

  /// 复制本段（P4-29）：挂在块级节点上。
  final ValueChanged<String>? onCopyBlock;

  /// 页级动作（§67.4）。
  static final CustomSemanticsAction nextPageAction = CustomSemanticsAction(
    label: '下一页',
  );
  static final CustomSemanticsAction previousPageAction =
      CustomSemanticsAction(label: '上一页');
  static final CustomSemanticsAction copyBlockAction = CustomSemanticsAction(
    label: '复制本段',
  );

  /// 节点动作（§67.4）：页级给翻页，块级给复制本段。
  Map<CustomSemanticsAction, VoidCallback> _actionsFor(
    PageSemanticsNode node,
  ) {
    final actions = <CustomSemanticsAction, VoidCallback>{};
    if (node.role == PageSemanticsRole.page) {
      final next = onNextPage;
      final previous = onPreviousPage;
      if (next != null) {
        actions[nextPageAction] = next;
      }
      if (previous != null) {
        actions[previousPageAction] = previous;
      }
      return actions;
    }
    final copy = onCopyBlock;
    if (copy != null) {
      actions[copyBlockAction] = () => copy(node.label);
    }
    return actions;
  }

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
                    customSemanticsActions: _actionsFor(node),
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
