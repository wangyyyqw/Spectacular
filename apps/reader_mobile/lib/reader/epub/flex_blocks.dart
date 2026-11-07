import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/box_model.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/table_layout.dart';

import 'container_blocks.dart';

typedef _FlexSize = ({double container, double containing, double pageHeight});
typedef _ColumnSize = ({double width, double height});
typedef _CrossDistribution = ({double offset, double gap, double stretch});
typedef _MainDistribution = ({double offset, double gap});
typedef _CellPosition = ({
  double left,
  double top,
  double width,
  bool multipart,
});

/// 同步兼容入口与异步阅读作业共用同一阶段算法。
void _consumeSync(Iterable<int> steps) {
  for (final _ in steps) {
    // 同步驱动只消费边界；异步入口在同一位置检查预算。
  }
}

Future<void> _consumeAsync(
  Iterable<int> steps,
  Future<void> Function()? checkpoint,
) async {
  for (final _ in steps) {
    if (checkpoint != null) await checkpoint();
  }
  if (checkpoint != null) await checkpoint();
}

/// 页面根 column Flex 的主轴居中，不改变后代块的 CFI 与容器载荷。
void alignPageRootFlexColumn({
  required List<PageBlock> blocks,
  required int start,
  required ComputedStyle containerStyle,
  required double pageWidth,
  required double pageHeight,
}) {
  final job = _FlexColumnAlignment(blocks, start, containerStyle, (
    width: pageWidth,
    height: pageHeight,
  ));
  _consumeSync(job.steps());
  job.apply();
}

/// 参数沿用同步入口；新增的回调在扫描及提交垫片前核验取消。
Future<void> alignPageRootFlexColumnAsync({
  required List<PageBlock> blocks,
  required int start,
  required ComputedStyle containerStyle,
  required double pageWidth,
  required double pageHeight,
  Future<void> Function()? checkpoint,
}) async {
  final job = _FlexColumnAlignment(blocks, start, containerStyle, (
    width: pageWidth,
    height: pageHeight,
  ));
  await _consumeAsync(job.steps(), checkpoint);
  job.apply();
}

class _FlexColumnAlignment {
  _FlexColumnAlignment(this.blocks, this.start, this.style, this.size);

  final List<PageBlock> blocks;
  final int start;
  final ComputedStyle style;
  final _ColumnSize size;
  PageBlock? _spacer;

  Iterable<int> steps() sync* {
    final align = style.justifyContent;
    if (start >= blocks.length ||
        (align != CssJustifyContent.center &&
            align != CssJustifyContent.flexEnd)) {
      return;
    }
    var naturalHeight = 0.0;
    for (final block in blocks.skip(start)) {
      yield 0;
      if (block.absolute || block.floatSide != null) continue;
      naturalHeight +=
          block.leadingExtent + block.height + block.trailingExtent;
    }
    final offset = _columnOffset(style, size, naturalHeight);
    if (offset <= 0.01) return;
    _spacer = _flexSpacer(size.width, offset);
  }

  void apply() {
    final spacer = _spacer;
    if (spacer != null) blocks.insert(start, spacer);
  }
}

double _columnOffset(ComputedStyle style, _ColumnSize size, double natural) {
  final model = BoxModel.fromStyle(style, containingWidth: size.width);
  final available = math.max(0.0, size.height - model.verticalInset);
  final declared = math.min(
    model.resolveContentHeight(natural, containingHeight: size.height),
    available,
  );
  final free = math.max(0.0, declared - natural);
  return model.padding.top +
      model.borders.top +
      (style.justifyContent == CssJustifyContent.center ? free / 2 : free);
}

PageBlock _flexSpacer(double width, double height) => PageBlock(
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

/// 单行与换行 Flex 的兼容入口，复用表格格载荷保留子块与绘制样式。
///
/// 公开命名参数保留调用契约；内部的单次作业按尺寸、分行、分配与放置拆分。
PageBlock? buildFlexRowBlock({
  required ComputedStyle containerStyle,
  required double containerWidth,
  required List<List<PageBlock>> items,
  required double containingWidth,
  required double pageContentHeight,
  int groupId = 0,
}) {
  final job = _FlexRowLayout(containerStyle, items, (
    container: containerWidth,
    containing: containingWidth,
    pageHeight: pageContentHeight,
  ), groupId);
  _consumeSync(job.steps());
  return job.result;
}

/// 阅读入口在各子项、分行、尺寸分配和逐格放置的边界检查时间预算。
Future<PageBlock?> buildFlexRowBlockAsync({
  required ComputedStyle containerStyle,
  required double containerWidth,
  required List<List<PageBlock>> items,
  required double containingWidth,
  required double pageContentHeight,
  int groupId = 0,
  Future<void> Function()? checkpoint,
}) async {
  final job = _FlexRowLayout(containerStyle, items, (
    container: containerWidth,
    containing: containingWidth,
    pageHeight: pageContentHeight,
  ), groupId);
  await _consumeAsync(job.steps(), checkpoint);
  return job.result;
}

/// 一次 Flex 容器的临时几何，不读取可变章节源，也不提交宿主缓存。
class _FlexRowLayout {
  _FlexRowLayout(this.style, this.items, this.size, this.groupId);

  final ComputedStyle style;
  final List<List<PageBlock>> items;
  final _FlexSize size;
  final int groupId;
  final widths = <double>[];
  final heights = <double>[];
  List<List<int>> rows = [];
  final rowHeights = <double>[];
  final rowTops = <double>[];
  final cells = <TableCellRender>[];
  final text = StringBuffer();
  PageBlock? first;
  PageBlock? last;
  PageBlock? result;
  double layoutHeight = 0;
  double naturalHeight = 0;
  double rowGap = 0;
  double contentOffset = 0;
  double lineGap = 0;
  double rowEnd = 0;
  double get gap => math.max(0.0, style.columnGap ?? 0);
  bool get wraps => style.flexWrap != CssFlexWrap.nowrap;

  Iterable<int> steps() sync* {
    yield* _measureItems();
    if (first == null) return;
    yield* _partitionRows();
    yield* _distributeMainAxis();
    yield* _measureCrossAxis();
    yield* _alignCrossAxis();
    yield* _placeRowTops();
    for (var row = 0; row < rows.length; row++) {
      yield* _placeRow(row);
    }
    yield 0;
    _finish();
  }

  Iterable<int> _measureItems() sync* {
    for (final item in items) {
      yield 0;
      var width = 0.0;
      var height = 0.0;
      for (final block in item) {
        yield 0;
        first ??= block;
        last = block;
        text.write(block.layout.text);
        width = math.max(width, _baseWidth(block));
        height +=
            block.spaceBefore +
            block.topInset +
            block.height +
            block.bottomInset +
            block.spaceAfter;
      }
      widths.add(width);
      heights.add(height);
    }
  }

  double _horizontalInset(PageBlock block) {
    final style = block.style;
    return style == null
        ? 0
        : style.padding.horizontal +
              style.borders.left.width +
              style.borders.right.width;
  }

  double _intrinsicWidth(PageBlock block, {bool ignoreDeclared = false}) {
    final available = block.layout.maxWidth.isFinite
        ? block.layout.maxWidth
        : block.layout.width;
    final style = block.style;
    if (!ignoreDeclared && style?.width != null) {
      return BoxModel.fromStyle(
        style!,
        containingWidth: size.containing,
      ).resolveContentWidth(size.container);
    }
    if (block.table != null) return available;
    final measured = block.layout.width;
    return measured.isFinite && measured > 0
        ? math.min(measured, available)
        : available;
  }

  double _baseWidth(PageBlock block) {
    final style = block.style;
    if (style?.flexBasisIsContent ?? false) {
      return _intrinsicWidth(block, ignoreDeclared: true) +
          _horizontalInset(block);
    }
    final basis = style?.flexBasis;
    if (style != null && basis != null && !basis.isAuto) {
      final resolved = basis.resolve(size.container);
      if (resolved != null) {
        return math.max(
          0,
          style.boxSizing == CssBoxSizing.borderBox
              ? resolved
              : resolved + _horizontalInset(block),
        );
      }
    }
    return _intrinsicWidth(block) + _horizontalInset(block);
  }

  Iterable<int> _partitionRows() sync* {
    var row = <int>[];
    var rowWidth = 0.0;
    for (var i = 0; i < items.length; i++) {
      yield 0;
      final next = row.isEmpty ? widths[i] : rowWidth + gap + widths[i];
      if (wraps && row.isNotEmpty && next > size.container + 0.5) {
        rows.add(row);
        row = [];
        rowWidth = widths[i];
      } else {
        rowWidth = next;
      }
      row.add(i);
    }
    if (row.isNotEmpty) rows.add(row);
    if (style.flexWrap == CssFlexWrap.wrapReverse) {
      final reversed = <List<int>>[];
      for (final row in rows.reversed) {
        yield 0;
        reversed.add(row);
      }
      rows = reversed;
    }
  }

  Iterable<int> _distributeMainAxis() sync* {
    for (final row in rows) {
      var baseTotal = 0.0;
      for (final index in row) {
        yield 0;
        baseTotal += widths[index];
      }
      baseTotal += gap * math.max(0, row.length - 1);
      final free = size.container - baseTotal;
      if (free > 0) {
        yield* _growRow(row, free);
      } else if (free < 0) {
        yield* _shrinkRow(row, free);
      }
    }
  }

  Iterable<int> _growRow(List<int> row, double free) sync* {
    var total = 0.0;
    for (final index in row) {
      yield 0;
      total += items[index].first.style?.flexGrow ?? 0;
    }
    if (!(total > 0)) return;
    for (final index in row) {
      yield 0;
      final grow = items[index].first.style?.flexGrow ?? 0;
      widths[index] += free * grow / total;
    }
  }

  Iterable<int> _shrinkRow(List<int> row, double free) sync* {
    final weights = <int, double>{};
    for (final index in row) {
      yield 0;
      weights[index] =
          (items[index].first.style?.flexShrink ?? 1) * widths[index];
    }
    var total = 0.0;
    for (final weight in weights.values) {
      yield 0;
      total += weight;
    }
    if (!(total > 0)) return;
    for (final index in row) {
      yield 0;
      final reduction = -free * weights[index]! / total;
      widths[index] = math.max(0, widths[index] - reduction);
    }
  }

  Iterable<int> _measureCrossAxis() sync* {
    for (final row in rows) {
      var height = 0.0;
      for (final index in row) {
        yield 0;
        height = math.max(height, heights[index]);
      }
      rowHeights.add(height);
      naturalHeight += height;
    }
    rowGap = wraps && rows.length > 1 ? math.max(0.0, style.rowGap ?? 0) : 0;
    naturalHeight += rowGap * math.max(0, rows.length - 1);
    final declared = BoxModel.fromStyle(
      style,
      containingWidth: size.containing,
    ).resolveContentHeight(naturalHeight, containingHeight: size.pageHeight);
    layoutHeight = math.max(declared, naturalHeight);
    if (!wraps) rowHeights[0] = math.max(rowHeights[0], declared);
  }

  Iterable<int> _alignCrossAxis() sync* {
    lineGap = rowGap;
    if (!wraps || rows.length <= 1) return;
    final free = math.max(0.0, layoutHeight - naturalHeight);
    final distribution = _crossDistribution(style, free, rows.length);
    contentOffset = distribution.offset;
    lineGap += distribution.gap;
    if (style.alignContent == CssAlignContent.stretch) {
      for (var i = 0; i < rowHeights.length; i++) {
        yield 0;
        rowHeights[i] += distribution.stretch;
      }
    }
  }

  Iterable<int> _placeRowTops() sync* {
    var top = contentOffset;
    for (var i = 0; i < rowHeights.length; i++) {
      yield 0;
      rowTops.add(top);
      top += rowHeights[i];
      if (i + 1 < rowHeights.length) top += lineGap;
    }
    rowEnd = top;
  }

  Iterable<int> _placeRow(int rowIndex) sync* {
    final row = rows[rowIndex];
    var itemsWidth = 0.0;
    for (final index in row) {
      yield 0;
      itemsWidth += widths[index];
    }
    itemsWidth += gap * math.max(0, row.length - 1);
    final free = math.max(0.0, size.container - itemsWidth);
    final distribution = _mainDistribution(
      style.justifyContent,
      free,
      row.length,
    );
    var cursor = distribution.offset;
    for (final index in row) {
      yield* _placeItem(rowIndex, index, cursor);
      cursor += widths[index] + gap + distribution.gap;
    }
  }

  Iterable<int> _placeItem(int row, int index, double cursor) sync* {
    final item = items[index];
    final width = widths[index];
    final height = heights[index];
    final free = rowHeights[row] - height;
    var top =
        rowTops[row] +
        switch (style.alignItems) {
          CssAlignItems.flexEnd => math.max(0.0, free),
          CssAlignItems.center => math.max(0.0, free / 2),
          _ => 0.0,
        };
    yield 0;
    _addContainerCell(row, item, (cursor, top, width, height));
    for (final block in item) {
      yield 0;
      top += block.spaceBefore;
      cells.add(
        _blockCell(row, block, (
          left: cursor,
          top: top,
          width: width,
          multipart: item.length > 1,
        )),
      );
      top +=
          block.topInset + block.height + block.bottomInset + block.spaceAfter;
    }
  }

  void _addContainerCell(
    int row,
    List<PageBlock> item,
    (double, double, double, double) rect,
  ) {
    final container = commonFlexItemContainer(item);
    if (container == null) return;
    cells.add(
      TableCellRender(
        row: row,
        rect: Rect.fromLTWH(
          rect.$1,
          rect.$2,
          math.min(rect.$3, size.container),
          rect.$4,
        ),
        layout: TextLayoutEngine.layout(
          text: '',
          style: container.style,
          maxWidth: rect.$3,
        ),
        style: container.style,
      ),
    );
  }

  TableCellRender _blockCell(int row, PageBlock block, _CellPosition position) {
    final style = block.style ?? this.style;
    final width = position.width;
    final declared = style.width?.resolve(width);
    final ownWidth = position.multipart && declared != null
        ? math.min(
            width,
            BoxModel.fromStyle(
              style,
              containingWidth: width,
            ).borderBoxWidth(declared),
          )
        : width;
    final left =
        position.left +
        switch (style.resolvedTextAlign) {
          CssTextAlign.center => (width - ownWidth) / 2,
          CssTextAlign.end || CssTextAlign.right => width - ownWidth,
          _ => 0.0,
        };
    return TableCellRender(
      row: row,
      rect: Rect.fromLTWH(
        left,
        position.top,
        math.min(ownWidth, size.container),
        block.topInset + block.height + block.bottomInset,
      ),
      layout: block.layout,
      style: style,
      startCfi: block.startCfi,
    );
  }

  void _finish() {
    final value = text.toString();
    rowTops.add(rowEnd);
    result = PageBlock.styled(
      layout: TextLayoutResult(
        text: value,
        lines: [
          LineBox(
            start: 0,
            end: value.length,
            top: 0,
            height: layoutHeight,
            baseline: layoutHeight,
            width: size.container,
          ),
        ],
        width: size.container,
        height: layoutHeight,
        maxWidth: size.container,
        runs: const [],
      ),
      style: style,
      containingWidth: size.containing,
      groupId: groupId,
      startCfi: first!.startCfi,
      endCfi: last!.endCfi,
      table: TableRenderSpec(
        cells: cells,
        columnXs: const [0],
        rowYs: rowTops,
        tableWidth: size.container,
        flex: true,
      ),
      declaredContentHeight: layoutHeight,
    );
  }
}

_CrossDistribution _crossDistribution(
  ComputedStyle style,
  double free,
  int count,
) => switch (style.alignContent) {
  CssAlignContent.stretch => (offset: 0, gap: 0, stretch: free / count),
  CssAlignContent.flexEnd => (
    offset: style.flexWrap == CssFlexWrap.wrapReverse ? 0 : free,
    gap: 0,
    stretch: 0,
  ),
  CssAlignContent.center => (offset: free / 2, gap: 0, stretch: 0),
  CssAlignContent.spaceBetween => (
    offset: 0,
    gap: free / (count - 1),
    stretch: 0,
  ),
  CssAlignContent.spaceAround => (
    offset: free / count / 2,
    gap: free / count,
    stretch: 0,
  ),
  CssAlignContent.spaceEvenly => (
    offset: free / (count + 1),
    gap: free / (count + 1),
    stretch: 0,
  ),
  CssAlignContent.flexStart => (
    offset: style.flexWrap == CssFlexWrap.wrapReverse ? free : 0,
    gap: 0,
    stretch: 0,
  ),
};

_MainDistribution _mainDistribution(
  CssJustifyContent align,
  double free,
  int count,
) {
  final gap = switch (align) {
    CssJustifyContent.spaceBetween when count > 1 => free / (count - 1),
    CssJustifyContent.spaceAround when count > 0 => free / count,
    CssJustifyContent.spaceEvenly => free / (count + 1),
    _ => 0.0,
  };
  final offset = switch (align) {
    CssJustifyContent.flexEnd => free,
    CssJustifyContent.center => free / 2,
    CssJustifyContent.spaceAround => gap / 2,
    CssJustifyContent.spaceEvenly => gap,
    _ => 0.0,
  };
  return (offset: offset, gap: gap);
}
