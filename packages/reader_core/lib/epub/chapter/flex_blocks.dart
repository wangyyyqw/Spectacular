import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/box_model.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/table_layout.dart';

import 'container_blocks.dart';

typedef _FlexSize = ({double container, double containing, double pageHeight});
typedef _ColumnSize = ({double width, double height, double retainedTopInset});
typedef _CrossDistribution = ({double offset, double gap, double stretch});
typedef _MainDistribution = ({double offset, double gap});
typedef _CellPosition = ({
  double left,
  double top,
  double width,
  bool multipart,
  PageContainer? container,
});

Future<void> _consume(
  Iterable<int> steps,
  Future<void> Function()? checkpoint,
) async {
  for (final _ in steps) {
    if (checkpoint != null) await checkpoint();
  }
  if (checkpoint != null) await checkpoint();
}

/// 页面根 column Flex 的主轴对齐与顶部内缩，保留后代块的 CFI 和容器载荷。
/// 已保留根盒的顶部装饰由容器路径占位，垫片只补未消费的部分。
/// 在扫描及提交垫片前核验取消，复用同一阶段算法。
Future<void> alignPageRootFlexColumn({
  required List<PageBlock> blocks,
  required int start,
  required ComputedStyle containerStyle,
  required ({double width, double height, double retainedTopInset}) page,
  Future<void> Function()? checkpoint,
}) async {
  final job = _FlexColumnAlignment(blocks, start, containerStyle, page);
  await _consume(job.steps(), checkpoint);
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
    if (start >= blocks.length) return;
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
      switch (style.justifyContent) {
        CssJustifyContent.center => free / 2,
        CssJustifyContent.flexEnd => free,
        _ => 0,
      } -
      size.retainedTopInset;
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

/// 阅读入口在各子项、分行、尺寸分配和逐格放置的边界检查时间预算。
Future<PageBlock?> buildFlexRowBlock({
  required ComputedStyle containerStyle,
  required double containerWidth,
  required List<List<PageBlock>> items,
  required double containingWidth,
  required double pageContentHeight,
  int groupId = 0,
  Future<void> Function()? checkpoint,
}) async {
  final normalized = <List<PageBlock>>[];
  for (final item in items) {
    // Flex 子项之间不折叠 margin；子项内部的普通块仍走正式块流折叠。
    normalized.add(
      commonFlexItemContainer(item) == null
          ? item
          : await collapseMarginsIgnoringFloatsAsync(
              item,
              checkpoint: checkpoint,
            ),
    );
  }
  final job = _FlexRowLayout(containerStyle, normalized, (
    container: containerWidth,
    containing: containingWidth,
    pageHeight: pageContentHeight,
  ), groupId);
  await _consume(job.steps(), checkpoint);
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
  final containers = <PageContainer?>[];
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
      final container = commonFlexItemContainer(item);
      containers.add(container);
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
      widths.add(_itemWidth(container, width));
      heights.add(height);
    }
  }

  double _itemWidth(PageContainer? container, double measured) {
    if (container == null) return measured;
    final style = container.style;
    final model = BoxModel.fromStyle(style, containingWidth: size.container);
    if (style.flexBasisIsContent) return measured + model.horizontalInset;
    final basis = style.flexBasis.resolve(size.container);
    if (basis != null) {
      return math.max(
        0,
        style.boxSizing == CssBoxSizing.borderBox
            ? basis
            : model.borderBoxWidth(basis),
      );
    }
    // 保留盒的声明宽已包含 padding 与 border；auto 则仍按自然内容收缩。
    if (style.intrinsicWidth != null ||
        (style.width != null && !style.width!.isAuto)) {
      return container.width;
    }
    return model.borderBoxWidth(
      model.resolveContentWidth(
        measured + model.horizontalInset + style.margin.horizontal,
      ),
    );
  }

  ComputedStyle? _itemStyle(int index) =>
      containers[index]?.style ?? items[index].first.style;

  double _outerWidth(int index) =>
      widths[index] + (containers[index]?.style.margin.horizontal ?? 0);

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
      final next = row.isEmpty
          ? _outerWidth(i)
          : rowWidth + gap + _outerWidth(i);
      if (wraps && row.isNotEmpty && next > size.container + 0.5) {
        rows.add(row);
        row = [];
        rowWidth = _outerWidth(i);
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
        baseTotal += _outerWidth(index);
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
      total += _itemStyle(index)?.flexGrow ?? 0;
    }
    if (!(total > 0)) return;
    for (final index in row) {
      yield 0;
      final grow = _itemStyle(index)?.flexGrow ?? 0;
      widths[index] += free * grow / total;
    }
  }

  Iterable<int> _shrinkRow(List<int> row, double free) sync* {
    final weights = <int, double>{};
    for (final index in row) {
      yield 0;
      weights[index] = (_itemStyle(index)?.flexShrink ?? 1) * widths[index];
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
      itemsWidth += _outerWidth(index);
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
      yield* _placeItem(
        rowIndex,
        index,
        cursor + (containers[index]?.style.margin.left ?? 0),
      );
      cursor += _outerWidth(index) + gap + distribution.gap;
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
          container: containers[index],
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
          rect.$2 + container.style.margin.top,
          math.min(rect.$3, size.container),
          math.max(0, rect.$4 - container.style.margin.vertical),
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
    if (position.container != null) {
      return _containedBlockCell(row, block, position);
    }
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
      layout: _cellTextLayout(block.layout, style, ownWidth),
      style: style,
      startCfi: block.startCfi,
      footnotes: block.footnotes,
    );
  }

  TableCellRender _containedBlockCell(
    int row,
    PageBlock block,
    _CellPosition position,
  ) {
    final container = position.container!;
    final style = block.style ?? container.style;
    // 后代 margin 是章节坐标投影，转为子项局部坐标时只扣盒外的空间。
    final leftInset = style.margin.left - container.left;
    final rightInset =
        style.margin.right -
        (size.containing - container.left - container.width);
    final available = math.max(0.0, position.width - leftInset - rightInset);
    final parentModel = BoxModel.fromStyle(
      container.style,
      containingWidth: size.container,
    );
    final model = BoxModel.fromStyle(
      style.withMargins(CssEdges.zero),
      containingWidth: math.max(
        0.0,
        position.width - parentModel.horizontalInset,
      ),
    );
    final width = model.borderBoxWidth(model.resolveContentWidth(available));
    return TableCellRender(
      row: row,
      rect: Rect.fromLTWH(
        position.left + leftInset,
        position.top + block.topInset - model.padding.top - model.borders.top,
        width,
        block.height + model.verticalInset,
      ),
      layout: _cellTextLayout(block.layout, style, width),
      style: style,
      startCfi: block.startCfi,
      footnotes: block.footnotes,
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

/// 收到自然宽的 Flex 文字沿用断行与行内载荷，只迁移原内容宽的对齐坐标。
/// 已有行放不下或需要重新拉伸时，保持原布局；收缩重排需另行计算行高。
TextLayoutResult _cellTextLayout(
  TextLayoutResult layout,
  ComputedStyle style,
  double borderWidth,
) {
  final width = math.max(
    0.0,
    borderWidth -
        style.padding.horizontal -
        style.borders.left.width -
        style.borders.right.width,
  );
  if (layout.isVertical ||
      !layout.maxWidth.isFinite ||
      (width - layout.maxWidth).abs() < .01 ||
      layout.lines.any(
        (line) => line.indent + line.advanceWidth > width + .01,
      )) {
    return layout;
  }
  return TextLayoutResult(
    text: layout.text,
    lines: [
      for (final line in layout.lines)
        line.copyWith(
          offsetX:
              line.offsetX +
              _cellAlignShift(line, style, width - layout.maxWidth),
        ),
    ],
    width: layout.width,
    height: layout.height,
    maxWidth: width,
    runs: layout.runs,
    isRtl: layout.isRtl,
    writingMode: layout.writingMode,
    plainTextLayout: layout.plainTextLayout,
  );
}

double _cellAlignShift(LineBox line, ComputedStyle style, double delta) {
  final align = line.isLastLine || line.isHardBreak
      ? style.textAlignLast ??
            (style.textAlign == CssTextAlign.justify
                ? CssTextAlign.start
                : style.textAlign)
      : style.textAlign;
  return switch (align) {
    CssTextAlign.center => delta / 2,
    CssTextAlign.right => delta,
    CssTextAlign.start => style.isRtl ? delta : 0,
    CssTextAlign.end => style.isRtl ? 0 : delta,
    _ => 0,
  };
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
