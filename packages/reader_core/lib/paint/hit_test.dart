import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../css/computed_style.dart';
import '../layout/line_breaker.dart';
import '../layout/paginator.dart';
import '../layout/table_layout.dart' show TableCellRender;
import 'line_spans.dart';

/// 一行的页内几何（P4-14 命中测试输出；P4-15 选区手柄复用）。
class PageLineBox {
  /// 创建行几何。
  const PageLineBox({
    required this.sliceIndex,
    required this.lineIndex,
    required this.rect,
    required this.text,
    required this.textOffset,
    required this.blockTextOffset,
    required this.slice,
    this.textTop,
    this.sliceTop = 0,
    this.sliceBottom = 0,
  });

  /// 页内切片下标。
  final int sliceIndex;

  /// 块内行下标。
  final int lineIndex;

  /// 行在页内坐标系中的矩形。
  final Rect rect;

  /// 未回收行高留白前的绘制原点；首尾可见行框与文字原点分开保存。
  final double? textTop;

  /// 行文本。
  final String text;

  /// 行首在整页文本中的字符下标（选区/全选/复制用，P9-28）。
  final int textOffset;

  /// 行首在所属块文本中的字符下标（CFI 与块内映射用）。
  final int blockTextOffset;

  /// 所属切片。
  final PageBlockSlice slice;

  /// 所属切片在页内的纵向范围（跨块选择时区分上下堆叠的竖排块）。
  final double sliceTop;
  final double sliceBottom;

  /// 本行是否是竖排列。
  bool get isVertical =>
      slice.block.isVertical ||
      (lineIndex < slice.block.layout.lines.length &&
          slice.block.layout.lines[lineIndex].vertical);
}

/// 命中结果（P4-14）。
class TextHit {
  /// 创建命中结果。
  const TextHit({
    required this.lineBox,
    required this.charOffset,
    required this.textOffset,
    required this.atLineStart,
    required this.atLineEnd,
  });

  /// 命中行。
  final PageLineBox lineBox;

  /// 行内字符偏移（0..行长度）。
  final int charOffset;

  /// 块文本中的绝对字符下标。
  final int textOffset;

  /// 是否落在行首（横排为行左缘之外，竖排为列顶之上）。
  final bool atLineStart;

  /// 是否落在行尾（横排为行右缘之外，竖排为列底之下）。
  final bool atLineEnd;

  /// 页内切片下标。
  int get sliceIndex => lineBox.sliceIndex;

  /// 块内行下标。
  int get lineIndex => lineBox.lineIndex;
}

/// 字符级命中测试（P4-14，§63.1）。
///
/// 只依赖 [PageContent] 的公开几何（切片高度、首行留白、左内缩）与
/// [TextLayout] 的行框，不读绘制层私有状态；行内字符位置用
/// [TextPainter.getPositionForOffset] 精确映射（与断行同一套引擎）。
abstract final class TextHitTester {
  /// 注号通常只有一两个字，按实际几何命中时保留少量触摸容差。
  static const double _footnoteHitSlop = 6;

  /// 页内坐标 → 命中位置。
  ///
  /// [position] 是相对页内容区左上角（已扣除页边距）的坐标。超出内容时
  /// 钳到最近的行与字符，不会返回页外位置。
  static TextHit? hitTest(PageContent page, Offset position) {
    final boxes = lineBoxes(page);
    if (boxes.isEmpty) {
      return null;
    }
    if (boxes.first.isVertical) {
      return _hitTestVertical(position, boxes);
    }
    var target = boxes.first;
    for (final box in boxes) {
      if (position.dy < box.rect.bottom) {
        target = box;
        break;
      }
      target = box;
    }
    if (boxes.any((box) => box.slice.block.multicol != null)) {
      target = _multicolLineAt(position, boxes);
    }
    final lineText = target.text;
    if (lineText.isEmpty) {
      return TextHit(
        lineBox: target,
        charOffset: 0,
        textOffset: target.textOffset,
        atLineStart: true,
        atLineEnd: true,
      );
    }
    final painter = _painterFor(target);
    final line = target.slice.block.layout.lines[target.lineIndex];
    final local = Offset(position.dx - target.rect.left, 0);
    final atLineStart = local.dx < 0;
    final width =
        painter.width +
        inlineBoxAdvanceAt(line, TextPosition(offset: lineText.length));
    final atLineEnd = local.dx > width;
    final charOffset = _charOffsetFor(
      painter,
      line,
      local.dx.clamp(0.0, width),
    );
    painter.dispose();
    return TextHit(
      lineBox: target,
      charOffset: charOffset,
      textOffset: target.textOffset + charOffset,
      atLineStart: atLineStart,
      atLineEnd: atLineEnd,
    );
  }

  static PageLineBox _multicolLineAt(Offset position, List<PageLineBox> boxes) {
    var target = boxes.first;
    var nearestRow = double.infinity;
    var nearestColumn = double.infinity;
    for (final box in boxes) {
      final rowDistance = position.dy < box.rect.top
          ? box.rect.top - position.dy
          : position.dy > box.rect.bottom
          ? position.dy - box.rect.bottom
          : 0.0;
      final columnDistance = position.dx < box.rect.left
          ? box.rect.left - position.dx
          : position.dx > box.rect.right
          ? position.dx - box.rect.right
          : 0.0;
      if (rowDistance < nearestRow - 0.5 ||
          ((rowDistance - nearestRow).abs() <= 0.5 &&
              columnDistance < nearestColumn)) {
        target = box;
        nearestRow = rowDistance;
        nearestColumn = columnDistance;
      }
    }
    return target;
  }

  /// 竖排命中：先按所属切片的纵向范围选块，再按 x 选列、按 y 选字符。
  static TextHit _hitTestVertical(Offset position, List<PageLineBox> boxes) {
    var target = boxes.first;
    var bestSliceDistance = double.infinity;
    var bestColumnDistance = double.infinity;
    for (final box in boxes) {
      final sliceDistance = position.dy < box.sliceTop
          ? box.sliceTop - position.dy
          : position.dy > box.sliceBottom
          ? position.dy - box.sliceBottom
          : 0.0;
      final columnDistance = position.dx < box.rect.left
          ? box.rect.left - position.dx
          : position.dx > box.rect.right
          ? position.dx - box.rect.right
          : 0.0;
      if (sliceDistance < bestSliceDistance - 0.5 ||
          ((sliceDistance - bestSliceDistance).abs() <= 0.5 &&
              columnDistance < bestColumnDistance)) {
        target = box;
        bestSliceDistance = sliceDistance;
        bestColumnDistance = columnDistance;
      }
    }
    final lineText = target.text;
    if (lineText.isEmpty) {
      return TextHit(
        lineBox: target,
        charOffset: 0,
        textOffset: target.textOffset,
        atLineStart: true,
        atLineEnd: true,
      );
    }
    final line = target.slice.block.layout.lines[target.lineIndex];
    final localY = (position.dy - target.rect.top).clamp(
      0.0,
      target.rect.height,
    );
    final metrics = _verticalMetrics(target);
    var cursor = 0.0;
    var charOffset = 0;
    for (final metric in metrics) {
      if (metric.end <= line.start) {
        continue;
      }
      if (metric.start >= line.end) {
        break;
      }
      final segmentStart = math.max(metric.start, line.start);
      final segmentEnd = math.min(metric.end, line.end);
      final metricLength = math.max(1, metric.end - metric.start);
      final segmentStartY =
          cursor +
          metric.advance * (segmentStart - metric.start) / metricLength;
      final segmentEndY =
          cursor + metric.advance * (segmentEnd - metric.start) / metricLength;
      if (localY < segmentStartY) {
        charOffset = segmentStart - line.start;
        break;
      }
      if (localY <= segmentEndY) {
        final middle = (segmentStartY + segmentEndY) / 2;
        charOffset = localY <= middle
            ? segmentStart - line.start
            : segmentEnd - line.start;
        break;
      }
      cursor += metric.advance;
      charOffset = segmentEnd - line.start;
    }
    return TextHit(
      lineBox: target,
      charOffset: charOffset,
      textOffset: target.textOffset + charOffset,
      atLineStart: position.dy < target.rect.top,
      atLineEnd: position.dy > target.rect.bottom,
    );
  }

  /// 页内坐标命中的注释引用；没有注释时返回 null。
  static PageFootnote? footnoteAt(PageContent page, Offset position) {
    for (final lineBox in lineBoxes(page)) {
      for (final footnote in lineBox.slice.block.footnotes) {
        if (_footnoteHitRects(
          lineBox,
          footnote,
        ).any((rect) => rect.inflate(_footnoteHitSlop).contains(position))) {
          return footnote;
        }
      }
    }
    return _tableFootnoteAt(page, position);
  }

  static PageFootnote? _tableFootnoteAt(PageContent page, Offset position) {
    var flowY = page.topPadding;
    for (final slice in page.slices) {
      final sliceY = slice.overlay ? (slice.absoluteTop ?? flowY) : flowY;
      final origin = Offset(
        slice.leftInset + (slice.block.style?.margin.left ?? 0),
        sliceY + slice.leadingExtent,
      );
      final local = position - origin;
      for (final cell
          in slice.block.table?.cells ?? const <TableCellRender>[]) {
        if (cell.footnotes.isEmpty ||
            !cell.rect.inflate(_footnoteHitSlop).contains(local)) {
          continue;
        }
        final note = _cellFootnoteAt(cell, local - cell.textOrigin);
        if (note != null) return note;
      }
      if (!slice.overlay) flowY += slice.height;
    }
    return null;
  }

  /// 格内原点已消耗 margin、padding 和对齐，注号复用普通行的命中路径。
  static PageFootnote? _cellFootnoteAt(TableCellRender cell, Offset position) {
    final block = PageBlock(
      layout: cell.layout,
      style: cell.style.withMargins(CssEdges.zero),
      footnotes: cell.footnotes,
    );
    final page = PageContent(
      spineIndex: 0,
      pageIndex: 0,
      slices: [
        PageBlockSlice(
          block: block,
          startLine: 0,
          endLine: cell.layout.lineCount,
          height: cell.layout.height,
        ),
      ],
      usedHeight: cell.layout.height,
      pageHeight: cell.layout.height,
      topPadding: 0,
    );
    return footnoteAt(page, position);
  }

  /// 注号在页内的实际可点击矩形：普通文字按字形框，图片/空标签按行内盒。
  static List<Rect> _footnoteHitRects(PageLineBox box, PageFootnote footnote) {
    final line = box.slice.block.layout.lines[box.lineIndex];
    final start = math.max(footnote.start, line.start);
    final end = math.min(footnote.end, line.end);
    final result = <Rect>[
      if (end > start)
        for (final rect in selectionRects(
          box,
          start - line.start,
          end - line.start,
        ))
          rect.shift(box.rect.topLeft),
      for (final inlineBox in line.inlineBoxes)
        if (footnote.contains(inlineBox.offset))
          Rect.fromLTWH(
            box.rect.left + inlineBox.left,
            (box.textTop ?? box.rect.top) +
                inlineBox.topIn(line.baseline - line.top),
            inlineBox.width,
            inlineBox.height,
          ),
    ];
    return result;
  }

  /// 页内所有行几何（按阅读顺序）。
  static List<PageLineBox> lineBoxes(PageContent page) {
    final boxes = <PageLineBox>[];
    var flowY = page.topPadding;
    // 页内文本偏移（P9-28）：选区/全选/复制用的是「整页文本坐标系」，
    // 之前每块都从 line.start 起算，多块页面上偏移互相重叠，全选范围会
    // 小于已选范围、跨块复制也会错位。
    var pageOffset = 0;
    for (var sliceIndex = 0; sliceIndex < page.slices.length; sliceIndex++) {
      final slice = page.slices[sliceIndex];
      final sliceY = slice.overlay ? (slice.absoluteTop ?? flowY) : flowY;
      final layout = slice.block.layout;
      final leftInset = slice.leftInset + (slice.block.style?.margin.left ?? 0);
      if (slice.block.isVertical) {
        final contentTop = sliceY + slice.leadingExtent;
        final columnOffset = slice.block.verticalColumnOffset;
        final last = slice.endLine.clamp(0, layout.lines.length);
        for (var lineIndex = slice.startLine; lineIndex < last; lineIndex++) {
          final line = layout.lines[lineIndex];
          final text = layout.text.substring(line.start, line.end);
          boxes.add(
            PageLineBox(
              sliceIndex: sliceIndex,
              lineIndex: lineIndex,
              rect: Rect.fromLTWH(
                leftInset + (line.columnX ?? line.offsetX) + columnOffset,
                contentTop,
                line.width,
                line.height,
              ),
              textTop: contentTop,
              text: text,
              textOffset: pageOffset + line.start,
              blockTextOffset: line.start,
              slice: slice,
              sliceTop: sliceY,
              sliceBottom: sliceY + slice.height,
            ),
          );
        }
        if (!slice.overlay) {
          flowY += slice.height;
        }
        pageOffset += layout.text.length;
        continue;
      }
      var lineY = sliceY + slice.leadingExtent;
      final last = slice.endLine.clamp(0, layout.lines.length);
      for (var lineIndex = slice.startLine; lineIndex < last; lineIndex++) {
        final line = layout.lines[lineIndex];
        final text = layout.text.substring(line.start, line.end);
        final lineLeft = leftInset + line.offsetX;
        final visibleTop =
            lineY + (lineIndex == slice.startLine ? slice.textTopTrim : 0);
        final lineBottom = lineY + line.height;
        final visibleBottom =
            lineBottom - (lineIndex == last - 1 ? slice.textBottomTrim : 0);
        boxes.add(
          PageLineBox(
            sliceIndex: sliceIndex,
            lineIndex: lineIndex,
            rect: Rect.fromLTRB(
              lineLeft,
              visibleTop,
              lineLeft + line.advanceWidth,
              visibleBottom,
            ),
            textTop: lineY,
            text: text,
            textOffset: pageOffset + line.start,
            blockTextOffset: line.start,
            slice: slice,
            sliceTop: sliceY,
            sliceBottom: sliceY + slice.height,
          ),
        );
        lineY += line.height;
      }
      if (!slice.overlay) {
        flowY += slice.height;
      }
      pageOffset += layout.text.length;
    }
    return boxes;
  }

  /// 与正文绘制共用行内字体、对齐与字距。
  static TextPainter _painterFor(PageLineBox box) {
    final layout = box.slice.block.layout;
    final style = box.slice.block.style ?? ComputedStyle(const {});
    return TextPainter(
      text: buildLineSpan(
        layout: layout,
        line: layout.lines[box.lineIndex],
        baseStyle: TextLayoutEngine.textStyleFor(style),
        punctCompression:
            style.textSpacingTrim == CssTextSpacingTrim.trimAdjacent,
        textAutospace: style.textAutospace == CssTextAutospace.normal,
      ),
      textDirection: layout.isRtl ? TextDirection.rtl : TextDirection.ltr,
    )..layout();
  }

  /// 行内原文区间的局部矩形；标签不占原文字符，也不染入正文选区。
  static List<Rect> selectionRects(PageLineBox box, int start, int end) {
    if (box.isVertical) {
      final line = box.slice.block.layout.lines[box.lineIndex];
      final metrics = _verticalMetrics(box);
      final from = _verticalOffsetFor(
        metrics,
        line,
        line.start + start.clamp(0, box.text.length),
      );
      final to = _verticalOffsetFor(
        metrics,
        line,
        line.start + end.clamp(0, box.text.length),
      );
      if (to <= from) {
        return const <Rect>[];
      }
      return <Rect>[Rect.fromLTWH(0, from, box.rect.width, to - from)];
    }
    final painter = _painterFor(box);
    final line = box.slice.block.layout.lines[box.lineIndex];
    final baselineOffset =
        (box.textTop ?? box.rect.top) -
        box.rect.top +
        textLineBaselineOffset(box.slice.block.layout, line, painter);
    final result = <Rect>[];
    for (final part in lineTextFragments(line, start: start, end: end)) {
      for (final rect in painter.getBoxesForSelection(
        TextSelection(baseOffset: part.start, extentOffset: part.end),
      )) {
        result.add(rect.toRect().shift(Offset(part.advance, baselineOffset)));
      }
    }
    painter.dispose();
    return result;
  }

  /// 原文光标位置映射到行内坐标，边界亲和决定落在标签之前还是之后。
  static Offset caretOffset(PageLineBox box, TextPosition position) {
    if (box.isVertical) {
      final line = box.slice.block.layout.lines[box.lineIndex];
      final offset = position.offset.clamp(0, box.text.length);
      return Offset(
        0,
        _verticalOffsetFor(_verticalMetrics(box), line, line.start + offset),
      );
    }
    final painter = _painterFor(box);
    final line = box.slice.block.layout.lines[box.lineIndex];
    final clamped = TextPosition(
      offset: position.offset.clamp(0, box.text.length),
      affinity: position.affinity,
    );
    final trailing = line.spacing?.trailingSpaceStart;
    // 折叠空白仍保留原文下标，但平台不能从零尺寸尾字形求光标；锚到可见边缘。
    final caret = trailing != null && clamped.offset >= trailing
        ? (trailing == 0
              ? Offset.zero
              : painter.getOffsetForCaret(
                  TextPosition(
                    offset: trailing,
                    affinity: TextAffinity.upstream,
                  ),
                  Rect.zero,
                ))
        : painter.getOffsetForCaret(clamped, Rect.zero);
    final baselineOffset =
        (box.textTop ?? box.rect.top) -
        box.rect.top +
        textLineBaselineOffset(box.slice.block.layout, line, painter);
    painter.dispose();
    return caret.translate(inlineBoxAdvanceAt(line, clamped), baselineOffset);
  }

  /// 竖排逐字度量。绘制层使用同一份度量，命中/选区不能再用横排 TextPainter。
  static List<VerticalGlyphMetric> _verticalMetrics(PageLineBox box) {
    final style = box.slice.block.style ?? ComputedStyle(const {});
    return TextLayoutEngine.verticalGlyphMetrics(
      box.slice.block.layout.text,
      style,
    );
  }

  /// 列内字符偏移 → 距列顶的纵向距离。
  static double _verticalOffsetFor(
    List<VerticalGlyphMetric> metrics,
    LineBox line,
    int absoluteOffset,
  ) {
    var cursor = 0.0;
    for (final metric in metrics) {
      if (metric.end <= line.start) {
        continue;
      }
      if (metric.start >= line.end) {
        break;
      }
      if (absoluteOffset <= math.max(metric.start, line.start)) {
        return cursor;
      }
      if (absoluteOffset < math.min(metric.end, line.end)) {
        final metricLength = math.max(1, metric.end - metric.start);
        return cursor +
            metric.advance * (absoluteOffset - metric.start) / metricLength;
      }
      cursor += metric.advance;
    }
    return cursor;
  }

  static int _charOffsetFor(TextPainter painter, LineBox line, double x) {
    var nearest = double.infinity;
    var offset = 0;
    for (final part in lineTextFragments(line)) {
      for (final box in painter.getBoxesForSelection(
        TextSelection(baseOffset: part.start, extentOffset: part.end),
      )) {
        final left = box.left + part.advance;
        final right = box.right + part.advance;
        final distance = x < left ? left - x : (x > right ? x - right : 0.0);
        if (distance >= nearest) continue;
        nearest = distance;
        offset = painter
            .getPositionForOffset(Offset(x - part.advance, painter.height / 2))
            .offset
            .clamp(part.start, part.end);
      }
    }
    return offset;
  }
}
