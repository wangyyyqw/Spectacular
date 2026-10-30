import 'package:flutter/painting.dart';

import '../css/computed_style.dart';
import '../layout/line_breaker.dart';
import '../layout/paginator.dart';
import '../layout/text_layout.dart';
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

  /// 是否落在行首（x 在行左缘之外）。
  final bool atLineStart;

  /// 是否落在行尾（x 在行右缘之外）。
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
  /// 页内坐标 → 命中位置。
  ///
  /// [position] 是相对页内容区左上角（已扣除页边距）的坐标。超出内容时
  /// 钳到最近的行与字符，不会返回页外位置。
  static TextHit? hitTest(PageContent page, Offset position) {
    final boxes = lineBoxes(page);
    if (boxes.isEmpty) {
      return null;
    }
    var target = boxes.first;
    for (final box in boxes) {
      if (position.dy < box.rect.bottom) {
        target = box;
        break;
      }
      target = box;
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
    final painter = _painterFor(box);
    final line = box.slice.block.layout.lines[box.lineIndex];
    final clamped = TextPosition(
      offset: position.offset.clamp(0, box.text.length),
      affinity: position.affinity,
    );
    final caret = painter.getOffsetForCaret(clamped, Rect.zero);
    final baselineOffset =
        (box.textTop ?? box.rect.top) -
        box.rect.top +
        textLineBaselineOffset(box.slice.block.layout, line, painter);
    painter.dispose();
    return caret.translate(inlineBoxAdvanceAt(line, clamped), baselineOffset);
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
