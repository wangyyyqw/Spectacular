import 'dart:math' as math;

import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/box_model.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';

/// 页面根表格只有一个单元格时，按根盒高度放置单元格内的块流。
/// 超过页面的内容保留正常分页，不用居中垫片挤掉正文。
Future<void> alignPageRootTableCell({
  required List<PageBlock> blocks,
  required int start,
  required ComputedStyle rootStyle,
  required CssVerticalAlign alignment,
  required ({double width, double height, Future<void> Function() checkpoint})
  page,
}) async {
  if (start >= blocks.length ||
      (alignment != CssVerticalAlign.middle &&
          alignment != CssVerticalAlign.bottom)) {
    return;
  }
  var natural = 0.0;
  for (final block in blocks.skip(start)) {
    await page.checkpoint();
    if (block.absolute || block.floatSide != null) continue;
    natural += block.leadingExtent + block.height + block.trailingExtent;
  }
  final model = BoxModel.fromStyle(rootStyle, containingWidth: page.width);
  final height = math.min(
    page.height - model.verticalInset,
    model.resolveContentHeight(natural, containingHeight: page.height),
  );
  final free = math.max(0.0, height - natural);
  final offset =
      model.padding.top +
      model.borders.top +
      (alignment == CssVerticalAlign.middle ? free / 2 : free);
  await page.checkpoint();
  if (offset > .01) blocks.insert(start, _spacer(page.width, offset));
}

PageBlock _spacer(double width, double height) => PageBlock(
  layout: TextLayoutResult(
    text: '',
    lines: [
      LineBox(
        start: 0,
        end: 0,
        top: 0,
        height: height,
        baseline: height,
        width: width,
      ),
    ],
    width: width,
    height: height,
    maxWidth: width,
    runs: const [],
  ),
);
