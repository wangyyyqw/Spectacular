import 'package:flutter/painting.dart' show TextPosition;
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/epub/footnote.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/hit_test.dart';

final _style = ComputedStyle({'font-size': '16px', 'font-family': 'Ahem'});

PageContent _page({
  List<StyledRun> runs = const [],
  List<InlineBoxSpec> boxes = const [],
  String text = 'ABCD',
  PageFootnote? footnote,
}) {
  final layout = TextLayoutEngine.layout(
    text: text,
    style: _style,
    maxWidth: 300,
    runs: runs,
    inlineBoxes: boxes,
  );
  return Paginator(pageHeight: 200)
      .measureChapter(
        blocks: [
          PageBlock(
            layout: layout,
            style: _style,
            footnotes: footnote == null
                ? const <PageFootnote>[]
                : <PageFootnote>[footnote],
          ),
        ],
      )
      .pages
      .single;
}

void main() {
  test('替换图不进入正文选区，图后命中和光标保持原文字符偏移', () {
    final page = _page(
      text: '\uFFFCAB\uFFFC',
      boxes: const [
        InlineBoxSpec(
          offset: 0,
          width: 40,
          height: 16,
          marginLeft: 10,
          marginRight: 10,
          replacesPlaceholder: true,
        ),
        InlineBoxSpec(
          offset: 3,
          width: 40,
          height: 16,
          marginLeft: 10,
          marginRight: 10,
          replacesPlaceholder: true,
        ),
      ],
    );
    final line = TextHitTester.lineBoxes(page).single;
    final selected = TextHitTester.selectionRects(line, 0, 4);
    expect(selected, hasLength(1));
    expect((selected.single.left, selected.single.right), (60.0, 92.0));
    expect(TextHitTester.selectionRects(line, 0, 1), isEmpty);
    expect(TextHitTester.selectionRects(line, 3, 4), isEmpty);
    for (final (offset, x) in [(0, 0.0), (1, 60.0), (2, 76.0), (4, 152.0)]) {
      expect(
        TextHitTester.caretOffset(line, TextPosition(offset: offset)).dx,
        closeTo(x, .01),
      );
    }
    expect(TextHitTester.hitTest(page, const Offset(62, 10))!.charOffset, 1);
    expect(TextHitTester.hitTest(page, const Offset(78, 10))!.charOffset, 2);
  });

  test('混合字号命中保留行内样式，不按段落字号估算', () {
    final page = _page(
      runs: [
        StyledRun(
          start: 0,
          end: 1,
          style: ComputedStyle({'font-size': '48px'}, parent: _style),
        ),
      ],
    );
    expect(TextHitTester.hitTest(page, const Offset(50, 10))!.charOffset, 1);
  });

  test('前置标签之后正文命中仍返回原文偏移', () {
    final page = _page(
      boxes: const [InlineBoxSpec(offset: 0, width: 40, height: 20)],
    );
    final hit = TextHitTester.hitTest(page, const Offset(42, 10))!;
    expect(hit.charOffset, 0);
    expect(hit.textOffset, 0);
    expect(hit.atLineEnd, isFalse);
  });

  test('行中标签和左右外边距占宽，不占正文字符数', () {
    final page = _page(
      boxes: const [
        InlineBoxSpec(
          offset: 2,
          width: 40,
          height: 20,
          marginLeft: 5,
          marginRight: 5,
        ),
      ],
    );
    final hit = TextHitTester.hitTest(page, const Offset(84, 10))!;
    expect(hit.charOffset, 2);
    expect(hit.atLineEnd, isFalse);
  });

  test('标签后上下标仍按自身字号计算横向命中与选区', () {
    final page = _page(
      boxes: const [InlineBoxSpec(offset: 0, width: 20, height: 20)],
      runs: [
        StyledRun(
          start: 1,
          end: 2,
          baselineShift: -6,
          style: ComputedStyle({'font-size': '8px'}, parent: _style),
        ),
      ],
    );
    expect(TextHitTester.hitTest(page, const Offset(46, 10))!.charOffset, 2);
    final box = TextHitTester.lineBoxes(page).single;
    final rect = TextHitTester.selectionRects(box, 1, 2).single;
    expect((rect.left, rect.right), (36.0, 44.0));
  });

  test('两端对齐命中包含分配到字间的留白', () {
    final layout = TextLayoutResult(
      text: '甲乙丙',
      width: 96,
      maxWidth: 96,
      height: 24,
      lines: const [
        LineBox(
          start: 0,
          end: 3,
          top: 0,
          height: 24,
          baseline: 16,
          width: 48,
          justifyExtra: 48,
        ),
      ],
    );
    final page = Paginator(pageHeight: 100)
        .measureChapter(
          blocks: [PageBlock(layout: layout, style: _style)],
        )
        .pages
        .single;
    expect(TextHitTester.hitTest(page, const Offset(42, 10))!.charOffset, 1);
    expect(TextHitTester.lineBoxes(page).single.rect.width, 96);
  });

  test('注释只命中实际注号，不把行外空白映射到最近字符', () {
    const footnote = PageFootnote(
      start: 1,
      end: 2,
      label: '1',
      kind: NoteKind.footnote,
      text: '注释正文',
    );
    final page = _page(text: '注1', footnote: footnote);
    final line = TextHitTester.lineBoxes(page).single;
    final glyph = TextHitTester.selectionRects(
      line,
      1,
      2,
    ).single.shift(line.rect.topLeft);

    expect(TextHitTester.footnoteAt(page, glyph.center), same(footnote));
    expect(
      TextHitTester.footnoteAt(
        page,
        Offset(glyph.center.dx, line.rect.bottom + 80),
      ),
      isNull,
    );
    expect(
      TextHitTester.footnoteAt(page, Offset(glyph.right + 20, glyph.center.dy)),
      isNull,
    );
  });
}
