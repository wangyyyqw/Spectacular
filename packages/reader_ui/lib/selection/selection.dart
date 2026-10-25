import 'package:flutter/painting.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/position/cfi.dart';
import 'package:reader_core/text/segmenter.dart';

/// 页内选区（P4-15）：起止命中点，按阅读顺序归一。
///
/// 位置用 [TextHit]（行 + 行内字符偏移）表达，不依赖坐标；坐标只在绘制
/// 与拖拽时由 [selectionRects] 换算。
class ReaderSelection {
  /// 创建选区。
  const ReaderSelection({
    required this.start,
    required this.end,
    this.startPageIndex = 0,
    this.endPageIndex = 0,
  });

  /// 起点（文档顺序在前）。
  final TextHit start;

  /// 终点（文档顺序在后）。
  final TextHit end;

  /// 起点所在页（章内页序号，§63.5：选区数据与页无关，页码只标记所在页）。
  final int startPageIndex;

  /// 终点所在页。
  final int endPageIndex;

  /// 是否跨页。
  bool get isMultiPage => startPageIndex != endPageIndex;

  /// 空选区。
  bool get isCollapsed => _compare(start, end) == 0;

  /// 创建已归一（start 在前）的选区。
  factory ReaderSelection.normalized(TextHit a, TextHit b) =>
      _compare(a, b) <= 0
      ? ReaderSelection(start: a, end: b)
      : ReaderSelection(start: b, end: a);

  /// 创建跨页选区（按页序归一）。
  factory ReaderSelection.spanning({
    required TextHit start,
    required int startPageIndex,
    required TextHit end,
    required int endPageIndex,
  }) {
    if (startPageIndex < endPageIndex) {
      return ReaderSelection(
        start: start,
        end: end,
        startPageIndex: startPageIndex,
        endPageIndex: endPageIndex,
      );
    }
    if (startPageIndex > endPageIndex) {
      return ReaderSelection(
        start: end,
        end: start,
        startPageIndex: endPageIndex,
        endPageIndex: startPageIndex,
      );
    }
    final ordered = ReaderSelection.normalized(start, end);
    return ReaderSelection(
      start: ordered.start,
      end: ordered.end,
      startPageIndex: startPageIndex,
      endPageIndex: endPageIndex,
    );
  }

  static int _compare(TextHit a, TextHit b) {
    final slice = a.sliceIndex.compareTo(b.sliceIndex);
    if (slice != 0) {
      return slice;
    }
    final line = a.lineIndex.compareTo(b.lineIndex);
    if (line != 0) {
      return line;
    }
    return a.charOffset.compareTo(b.charOffset);
  }

  @override
  String toString() =>
      'ReaderSelection(${start.sliceIndex}/${start.lineIndex}:'
      '${start.charOffset} → ${end.sliceIndex}/${end.lineIndex}:'
      '${end.charOffset})';
}

/// 选区几何：逐行矩形 + 手柄位置（P4-15 / §63.3 / §63.4）。
class SelectionGeometry {
  /// 创建几何。
  const SelectionGeometry({
    required this.lineRects,
    required this.startHandle,
    required this.endHandle,
  });

  /// 选区覆盖的逐行矩形（页内坐标）。
  final List<Rect> lineRects;

  /// 起点手柄中心（行首左边缘、行顶）。
  final Offset startHandle;

  /// 终点手柄中心（行尾右边缘、行底）。
  final Offset endHandle;
}

/// 选区工具（P4-15）：词/字符归一、矩形与手柄几何。
abstract final class SelectionOps {
  /// 手柄视觉直径（§63.3）。
  static const double handleDot = 8;

  /// 手柄触摸热区扩展。
  static const double handleTouchPadding = 16;

  /// 选区高亮高度相对行高的比例（§63.4：1.1 倍，垂直居中）。
  static const double lineHighlightScale = 1.1;

  /// 长按/双击选词（§40.2）：CJK 连续段、拉丁数字连续段、其余单字符。
  ///
  /// 只在命中行内取词（正文词不会跨硬换行）；两端吸附到词边界。
  static ReaderSelection wordAt(PageContent page, TextHit hit) {
    final box = hit.lineBox;
    final text = box.text;
    if (text.isEmpty) {
      return ReaderSelection(start: hit, end: hit);
    }
    final range = TextSegmenter.wordRangeAt(text, hit.charOffset);
    if (range.isEmpty) {
      return ReaderSelection(start: hit, end: hit);
    }
    return ReaderSelection.normalized(
      _hitAt(box, range.start),
      _hitAt(box, range.end),
    );
  }

  /// 三击选句（§40.2）：按句末标点/换行切句，句子可跨排版软换行。
  static ReaderSelection sentenceAt(PageContent page, TextHit hit) {
    final boxes = TextHitTester.lineBoxes(page);
    final box = hit.lineBox;
    final blockText = box.slice.block.layout.text;
    final offset = (box.textOffset + hit.charOffset).clamp(0, blockText.length);
    final range = TextSegmenter.sentenceRangeAt(blockText, offset);
    if (range.isEmpty) {
      return ReaderSelection(start: hit, end: hit);
    }
    final start = _hitAtBlockOffset(boxes, box.sliceIndex, range.start, box);
    final end = _hitAtBlockOffset(boxes, box.sliceIndex, range.end, box);
    return ReaderSelection.normalized(start, end);
  }

  /// 块内字符偏移 → 页内命中（跨软换行时落在对应行）。
  static TextHit _hitAtBlockOffset(
    List<PageLineBox> boxes,
    int sliceIndex,
    int blockOffset,
    PageLineBox fallback,
  ) {
    for (final box in boxes) {
      if (box.sliceIndex != sliceIndex) {
        continue;
      }
      if (blockOffset >= box.textOffset &&
          blockOffset <= box.textOffset + box.text.length) {
        return _hitAt(box, blockOffset - box.textOffset);
      }
    }
    return _hitAt(fallback, blockOffset - fallback.textOffset);
  }

  /// 拖拽手柄时的字符级命中（不扩展，§63.2）。
  static TextHit charAt(PageContent page, Offset position) {
    final hit = TextHitTester.hitTest(page, position);
    if (hit != null) {
      return hit;
    }
    final boxes = TextHitTester.lineBoxes(page);
    if (boxes.isEmpty) {
      throw StateError('页面没有可命中的行');
    }
    final box = boxes.first;
    return TextHit(
      lineBox: box,
      charOffset: 0,
      textOffset: box.textOffset,
      atLineStart: true,
      atLineEnd: false,
    );
  }

  /// 行内字符区间的矩形（页内坐标，§63.4：1.1 倍行高垂直居中）。
  ///
  /// 选区高亮与标注高亮共用；[start]/[end] 是行内字符偏移（半开）。
  static List<Rect> lineRectsFor(PageLineBox box, int start, int end) {
    if (end <= start) {
      return const <Rect>[];
    }
    final style = _styleFor(box.slice);
    final painter = _painterFor(box, style: style);
    final textBoxes = painter.getBoxesForSelection(
      TextSelection(baseOffset: start, extentOffset: end),
    );
    painter.dispose();
    final top =
        box.rect.top + (box.rect.height - box.rect.height * lineHighlightScale) / 2;
    return <Rect>[
      for (final textBox in textBoxes)
        Rect.fromLTWH(
          box.rect.left + textBox.left,
          top,
          textBox.right - textBox.left,
          box.rect.height * lineHighlightScale,
        ),
    ];
  }

  /// 给定页的选区几何（跨页时只算与当前页的交集，§63.5）。
  ///
  /// 返回 null 表示该页不在选区范围内。单页选区等价于 [geometryOf]。
  static SelectionGeometry? geometryForPage(
    PageContent page,
    int pageIndex,
    ReaderSelection selection,
  ) {
    if (pageIndex < selection.startPageIndex ||
        pageIndex > selection.endPageIndex) {
      return null;
    }
    final local = localSelectionOf(page, pageIndex, selection);
    if (local == null) {
      return null;
    }
    return geometryOf(page, local);
  }

  /// 该页内的局部选区：起点页从起点到页末，终点页从页首到终点，
  /// 中间页整页；不在范围内返回 null。
  static ReaderSelection? localSelectionOf(
    PageContent page,
    int pageIndex,
    ReaderSelection selection,
  ) {
    if (pageIndex < selection.startPageIndex ||
        pageIndex > selection.endPageIndex) {
      return null;
    }
    final boxes = TextHitTester.lineBoxes(page);
    if (boxes.isEmpty) {
      return null;
    }
    final first = boxes.first;
    final last = boxes.last;
    final start = pageIndex == selection.startPageIndex
        ? selection.start
        : _hitAt(first, 0);
    final end = pageIndex == selection.endPageIndex
        ? selection.end
        : _hitAt(last, last.text.length);
    return ReaderSelection.normalized(start, end);
  }

  /// 跨页选区文本（按页顺序拼接，§63.5「复制文本完整有序」）。
  static String textAcrossPages(
    List<PageContent> pages,
    ReaderSelection selection,
  ) {
    final buffer = StringBuffer();
    for (var pageIndex = selection.startPageIndex;
        pageIndex <= selection.endPageIndex;
        pageIndex++) {
      if (pageIndex < 0 || pageIndex >= pages.length) {
        continue;
      }
      final local = localSelectionOf(pages[pageIndex], pageIndex, selection);
      if (local == null) {
        continue;
      }
      buffer.write(textOf(pages[pageIndex], local));
    }
    return buffer.toString();
  }

  /// 选区几何：逐行矩形 + 两个手柄中心（吸附到行起止，§63.3）。
  static SelectionGeometry geometryOf(
    PageContent page,
    ReaderSelection selection,
  ) {
    final boxes = TextHitTester.lineBoxes(page);
    final rects = <Rect>[];
    final covered = _coveredLines(boxes, selection);
    for (final entry in covered) {
      rects.addAll(lineRectsFor(entry.box, entry.start, entry.end));
    }

    final startBox = _boxFor(boxes, selection.start);
    final endBox = _boxFor(boxes, selection.end);
    final startRect = _caretRect(startBox, selection.start.charOffset);
    final endRect = _caretRect(endBox, selection.end.charOffset);
    return SelectionGeometry(
      lineRects: rects,
      startHandle: Offset(startRect.left, startBox.rect.top),
      endHandle: Offset(endRect.right, endBox.rect.bottom),
    );
  }

  /// 选区纯文本（跨行拼接；跨行且接拉丁字母时补空格）。
  static String textOf(PageContent page, ReaderSelection selection) {
    final boxes = TextHitTester.lineBoxes(page);
    final covered = _coveredLines(boxes, selection);
    final buffer = StringBuffer();
    String? lastChar;
    for (final entry in covered) {
      final text = entry.box.text.substring(entry.start, entry.end);
      if (text.isEmpty) {
        continue;
      }
      if (lastChar != null && _needsSpace(lastChar, text)) {
        buffer.write(' ');
      }
      buffer.write(text);
      lastChar = text.substring(text.length - 1);
    }
    return buffer.toString();
  }

  /// 选区起止 CFI（标注存储用，§30.2）：块级 CFI + 块内字符偏移。
  static ({String start, String end})? cfiOf(
    ReaderSelection selection,
  ) {
    final startCfi = selection.start.lineBox.slice.block.startCfi;
    final endCfi = selection.end.lineBox.slice.block.startCfi;
    if (startCfi == null || startCfi.isEmpty) {
      return null;
    }
    final startOffset =
        selection.start.lineBox.textOffset + selection.start.charOffset;
    final endOffset =
        selection.end.lineBox.textOffset + selection.end.charOffset;
    return (
      start: cfiWithCharOffset(startCfi, startOffset),
      end: cfiWithCharOffset(endCfi ?? startCfi, endOffset),
    );
  }

  /// 选区前后文（各约 20 字，重定位兜底用，§30.2）。
  static ({String? before, String? after}) contextOf(
    PageContent page,
    ReaderSelection selection,
  ) {
    final boxes = TextHitTester.lineBoxes(page);
    final startBox = _boxFor(boxes, selection.start);
    final endBox = _boxFor(boxes, selection.end);
    final text = startBox.slice.block.layout.text;
    final startOffset = (startBox.textOffset + selection.start.charOffset).clamp(
      0,
      text.length,
    );
    final endOffset = (endBox.textOffset + selection.end.charOffset).clamp(
      0,
      text.length,
    );
    final beforeStart = startOffset - 20 < 0 ? 0 : startOffset - 20;
    final afterEnd = endOffset + 20 > text.length ? text.length : endOffset + 20;
    return (
      before: startOffset > beforeStart
          ? text.substring(beforeStart, startOffset)
          : null,
      after: afterEnd > endOffset ? text.substring(endOffset, afterEnd) : null,
    );
  }

  /// 选区包围盒（页内坐标；菜单定位用）。
  static Rect boundsOf(PageContent page, ReaderSelection selection) {
    final rects = geometryOf(page, selection).lineRects;
    if (rects.isEmpty) {
      return Rect.zero;
    }
    return rects.reduce((a, b) => a.expandToInclude(b));
  }

  static bool _needsSpace(String previous, String next) {
    final a = previous.codeUnitAt(0);
    final b = next.codeUnitAt(0);
    final latinA = (a >= 0x30 && a <= 0x7A);
    final latinB = (b >= 0x30 && b <= 0x7A);
    return latinA && latinB;
  }

  static List<({PageLineBox box, int start, int end})> _coveredLines(
    List<PageLineBox> boxes,
    ReaderSelection selection,
  ) {
    final result = <({PageLineBox box, int start, int end})>[];
    for (final box in boxes) {
      final afterStart = _compareBoxToHit(box, selection.start) >= 0;
      final beforeEnd = _compareBoxToHit(box, selection.end) <= 0;
      if (!afterStart || !beforeEnd) {
        continue;
      }
      final startIsHere = box.sliceIndex == selection.start.sliceIndex &&
          box.lineIndex == selection.start.lineIndex;
      final endIsHere = box.sliceIndex == selection.end.sliceIndex &&
          box.lineIndex == selection.end.lineIndex;
      final start = startIsHere
          ? selection.start.charOffset.clamp(0, box.text.length)
          : 0;
      final end = endIsHere
          ? selection.end.charOffset.clamp(0, box.text.length)
          : box.text.length;
      if (end > start) {
        result.add((box: box, start: start, end: end));
      }
    }
    return result;
  }

  /// 行相对命中点的顺序：行在命中行之前 = -1，同行按字符偏移比较。
  static int _compareBoxToHit(PageLineBox box, TextHit hit) {
    if (box.sliceIndex != hit.sliceIndex) {
      return box.sliceIndex.compareTo(hit.sliceIndex);
    }
    if (box.lineIndex != hit.lineIndex) {
      return box.lineIndex.compareTo(hit.lineIndex);
    }
    return 0;
  }

  static PageLineBox _boxFor(List<PageLineBox> boxes, TextHit hit) {
    for (final box in boxes) {
      if (_compareBoxToHit(box, hit) == 0) {
        return box;
      }
    }
    return boxes.first;
  }

  /// 行内某字符位置的光标矩形（页内坐标）。
  static Rect _caretRect(PageLineBox box, int charOffset) {
    final style = _styleFor(box.slice);
    final painter = _painterFor(box, style: style);
    final offset = charOffset.clamp(0, box.text.length);
    final caret = painter.getOffsetForCaret(
      TextPosition(offset: offset),
      Rect.zero,
    );
    painter.dispose();
    return Rect.fromLTWH(
      box.rect.left + caret.dx,
      box.rect.top,
      0,
      box.rect.height,
    );
  }

  static TextHit _hitAt(PageLineBox box, int charOffset) => TextHit(
    lineBox: box,
    charOffset: charOffset,
    textOffset: box.textOffset + charOffset,
    atLineStart: charOffset == 0,
    atLineEnd: charOffset == box.text.length,
  );


  static TextPainter _painterFor(PageLineBox box, {TextStyle? style}) =>
      TextPainter(
        text: TextSpan(
          text: box.text,
          style: style ?? _styleFor(box.slice),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

  static TextStyle _styleFor(PageBlockSlice slice) =>
      TextLayoutEngine.textStyleFor(
        slice.block.style ?? ComputedStyle(const <String, String>{}),
      );
}
