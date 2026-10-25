import 'package:flutter/painting.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/paint/hit_test.dart';

/// 页内选区（P4-15）：起止命中点，按阅读顺序归一。
///
/// 位置用 [TextHit]（行 + 行内字符偏移）表达，不依赖坐标；坐标只在绘制
/// 与拖拽时由 [selectionRects] 换算。
class ReaderSelection {
  /// 创建选区。
  const ReaderSelection({required this.start, required this.end});

  /// 起点（文档顺序在前）。
  final TextHit start;

  /// 终点（文档顺序在后）。
  final TextHit end;

  /// 空选区。
  bool get isCollapsed => _compare(start, end) == 0;

  /// 创建已归一（start 在前）的选区。
  factory ReaderSelection.normalized(TextHit a, TextHit b) =>
      _compare(a, b) <= 0
      ? ReaderSelection(start: a, end: b)
      : ReaderSelection(start: b, end: a);

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

  /// 长按选词（§63.2）：先按引擎分词取词，失败退到连续同类字符段。
  ///
  /// 只在命中行内取词（正文词不会跨行）；返回的选区两端吸附到词边界。
  static ReaderSelection wordAt(PageContent page, TextHit hit) {
    final box = hit.lineBox;
    final text = box.text;
    if (text.isEmpty) {
      return ReaderSelection(start: hit, end: hit);
    }
    final painter = _painterFor(box);
    final offset = hit.charOffset.clamp(0, text.length);
    final range = painter.getWordBoundary(TextPosition(offset: offset));
    painter.dispose();
    var start = range.start;
    var end = range.end;
    if (start == end) {
      // 引擎分词退化为空时，用连续同类字符段（CJK 或拉丁）。
      final fallback = _fallbackWord(text, offset);
      start = fallback.start;
      end = fallback.end;
    }
    if (start >= end) {
      return ReaderSelection(start: hit, end: hit);
    }
    return ReaderSelection.normalized(
      _hitAt(box, start),
      _hitAt(box, end),
    );
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

  /// 选区几何：逐行矩形 + 两个手柄中心（吸附到行起止，§63.3）。
  static SelectionGeometry geometryOf(
    PageContent page,
    ReaderSelection selection,
  ) {
    final boxes = TextHitTester.lineBoxes(page);
    final rects = <Rect>[];
    final covered = _coveredLines(boxes, selection);
    for (final entry in covered) {
      final box = entry.box;
      final style = _styleFor(box.slice);
      final painter = _painterFor(box, style: style);
      final start = entry.start;
      final end = entry.end;
      if (end > start) {
        final textBoxes = painter.getBoxesForSelection(
          TextSelection(baseOffset: start, extentOffset: end),
        );
        for (final textBox in textBoxes) {
          final top =
              box.rect.top +
              (box.rect.height - box.rect.height * lineHighlightScale) / 2;
          rects.add(
            Rect.fromLTWH(
              box.rect.left + textBox.left,
              top,
              textBox.right - textBox.left,
              box.rect.height * lineHighlightScale,
            ),
          );
        }
      }
      painter.dispose();
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

  static ({int start, int end}) _fallbackWord(String text, int offset) {
    if (offset < 0 || offset > text.length) {
      return (start: 0, end: 0);
    }
    final index = offset >= text.length ? text.length - 1 : offset;
    final isCjk = _isCjk(text.codeUnitAt(index));
    var start = index;
    var end = index + 1;
    while (start > 0 && _isCjk(text.codeUnitAt(start - 1)) == isCjk) {
      start -= 1;
    }
    while (end < text.length && _isCjk(text.codeUnitAt(end)) == isCjk) {
      end += 1;
    }
    return (start: start, end: end);
  }

  static bool _isCjk(int codeUnit) =>
      (codeUnit >= 0x4E00 && codeUnit <= 0x9FFF) ||
      (codeUnit >= 0x3400 && codeUnit <= 0x4DBF) ||
      (codeUnit >= 0x3040 && codeUnit <= 0x30FF);

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
