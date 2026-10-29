import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_ui/selection/selection.dart';

PageContent _page(
  List<InlineBoxSpec> boxes, {
  String text = 'ABCD',
  bool rtl = false,
}) {
  final style = ComputedStyle({
    'font-size': '16px',
    'font-family': 'Ahem',
    if (rtl) 'direction': 'rtl',
  });
  return Paginator(pageHeight: 100)
      .measureChapter(
        blocks: [
          PageBlock(
            layout: TextLayoutEngine.layout(
              text: text,
              style: style,
              maxWidth: 300,
              inlineBoxes: boxes,
            ),
            style: style,
          ),
        ],
      )
      .pages
      .single;
}

ReaderSelection _selection(PageContent page, int start, int end) {
  final line = TextHitTester.lineBoxes(page).single;
  TextHit at(int offset) => TextHit(
    lineBox: line,
    charOffset: offset,
    textOffset: line.textOffset + offset,
    atLineStart: offset == 0,
    atLineEnd: offset == line.text.length,
  );
  return ReaderSelection.normalized(at(start), at(end));
}

void main() {
  test('同位置多个标签和外边距累计，正文高亮及手柄一致偏移', () {
    final page = _page(const [
      InlineBoxSpec(
        offset: 0,
        width: 20,
        height: 20,
        marginLeft: 2,
        marginRight: 3,
      ),
      InlineBoxSpec(offset: 0, width: 30, height: 20),
    ]);
    final selected = _selection(page, 0, 1);
    final geometry = SelectionOps.geometryOf(page, selected);
    expect(geometry.lineRects.single.left, 55);
    expect(geometry.lineRects.single.right, 71);
    expect(geometry.startHandle.dx, 55);
    expect(geometry.endHandle.dx, 71);
    expect(SelectionOps.textOf(page, selected), 'A');
  });

  test('标签边界按选区亲和处理，跨标签高亮拆开且不修改复制文本', () {
    final page = _page(const [InlineBoxSpec(offset: 2, width: 40, height: 20)]);
    final before = SelectionOps.geometryOf(page, _selection(page, 0, 2));
    final after = SelectionOps.geometryOf(page, _selection(page, 2, 4));
    expect(before.endHandle.dx, 32);
    expect(after.startHandle.dx, 72);
    final all = _selection(page, 0, 4);
    final rects = SelectionOps.geometryOf(page, all).lineRects;
    expect(rects.map((rect) => (rect.left, rect.right)), [
      (0.0, 32.0),
      (72.0, 104.0),
    ]);
    expect(SelectionOps.textOf(page, all), 'ABCD');
  });

  test('混合方向选区使用布局声明的RTL方向', () {
    final page = _page(const [], text: 'Aאב', rtl: true);
    final line = TextHitTester.lineBoxes(page).single;
    final style = TextLayoutEngine.textStyleFor(line.slice.block.style!);
    final painter = TextPainter(
      text: TextSpan(text: line.text, style: style),
      textDirection: TextDirection.rtl,
    )..layout();
    final expected = painter
        .getBoxesForSelection(
          const TextSelection(baseOffset: 0, extentOffset: 1),
        )
        .single;
    final actual = SelectionOps.lineRectsFor(line, 0, 1).single;
    expect(actual.left, closeTo(line.rect.left + expected.left, 0.01));
    expect(actual.right, closeTo(line.rect.left + expected.right, 0.01));
    painter.dispose();
  });
}
