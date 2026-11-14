import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/multicol_flow.dart';
import 'package:reader_core/layout/paginator.dart';

import 'container_blocks.dart';

/// 先按单列包含块测量后代，再将原块流保存在一个完整容器中。
Future<PageBlock?> buildMulticolContainer({
  required List<PageBlock> children,
  required PageContainer container,
  required ComputedStyle style,
  required double containingWidth,
  Future<void> Function()? checkpoint,
}) async {
  if (children.isEmpty ||
      MulticolGeometry.fromStyle(container.style, container.contentWidth) ==
          null) {
    return null;
  }
  final sliced = await configureContainerDecorationAsync(
    children,
    checkpoint: checkpoint,
  );
  final blocks = await collapseMarginsIgnoringFloatsAsync(
    sliced,
    checkpoint: checkpoint,
  );
  final content = PageMulticolContent(
    container: PageContainer(
      style: container.style,
      left: container.left,
      width: container.width,
      isPageRoot: container.isPageRoot,
    ),
    blocks: blocks,
  );
  return PageBlock.styled(
    layout: _multicolLayout(content),
    style: style,
    containingWidth: containingWidth,
    startCfi: blocks.first.startCfi,
    endCfi: blocks.last.endCfi,
    multicolContent: content,
  );
}

TextLayoutResult _multicolLayout(PageMulticolContent content) =>
    TextLayoutResult(
      text: '',
      lines: const [],
      width: content.container.contentWidth,
      height: MulticolFlow(content).balancedHeight(),
      maxWidth: content.container.contentWidth,
    );
