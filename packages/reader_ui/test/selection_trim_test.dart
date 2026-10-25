import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/paint/line_spans.dart';
import 'package:reader_ui/selection/selection.dart';

PageContent _page(String text, {required bool trim}) {
  final style = ComputedStyle(<String, String>{
    'font-size': '16px',
    'line-height': '1.5',
    'font-family': 'Ahem',
    if (trim) 'text-spacing-trim': 'trim-adjacent',
  });
  final layout = TextLayoutEngine.layout(
    text: text,
    style: style,
    maxWidth: 400,
  );
  final block = PageBlock(layout: layout, style: style);
  final slice = PageBlockSlice(
    block: block,
    startLine: 0,
    endLine: layout.lineCount,
    height: layout.height,
  );
  return PageContent(
    spineIndex: 0,
    pageIndex: 0,
    slices: <PageBlockSlice>[slice],
    usedHeight: layout.height,
    pageHeight: 400,
    topPadding: 0,
  );
}

double _width(List<Rect> rects) =>
    rects.fold<double>(0, (sum, rect) => sum + rect.width);

void main() {
  test('标点挤压行：高亮矩形与绘制层同一 span 计算（P4-18 修复）', () {
    // 相邻全角标点触发 trim-adjacent；选区必须走绘制层的 buildLineSpan，
    // 否则字距不同会导致矩形偏移。
    const text = '他说：“你来了。”然后走了。';
    final trimmed = _page(text, trim: true);
    final box = TextHitTester.lineBoxes(trimmed).first;
    final rects = SelectionOps.lineRectsFor(box, 0, box.text.length);
    expect(rects, isNotEmpty);

    final slice = trimmed.slices.first;
    final style = slice.block.style!;
    final layout = slice.block.layout;
    final painter = TextPainter(
      text: buildLineSpan(
        layout: layout,
        line: layout.lines[box.lineIndex],
        baseStyle: TextLayoutEngine.textStyleFor(style),
        punctCompression: style.textSpacingTrim == CssTextSpacingTrim.trimAdjacent,
        textAutospace: style.textAutospace == CssTextAutospace.normal,
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final expected = painter.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: box.text.length),
    );
    final expectedWidth = expected.fold<double>(
      0,
      (sum, item) => sum + (item.right - item.left),
    );
    painter.dispose();
    expect(
      _width(rects),
      closeTo(expectedWidth, 0.01),
      reason: '高亮宽度等于绘制层字符框宽度',
    );
  });

  test('无挤压样式：高亮矩形与纯文本布局一致', () {
    const text = 'abcdefghij';
    final page = _page(text, trim: false);
    final box = TextHitTester.lineBoxes(page).first;
    final rects = SelectionOps.lineRectsFor(box, 2, 6);
    expect(rects, hasLength(1));
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextLayoutEngine.textStyleFor(
          page.slices.first.block.style!,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final boxes = painter.getBoxesForSelection(
      const TextSelection(baseOffset: 2, extentOffset: 6),
    );
    painter.dispose();
    final expected = boxes.first.toRect();
    expect(rects.single.left, closeTo(box.rect.left + expected.left, 0.01));
    expect(rects.single.width, closeTo(expected.width, 0.01));
  });
}
