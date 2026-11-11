import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/page_index.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/line_breaker.dart';

PageBlock _paragraph({
  double before = 0,
  double after = 30,
  double padding = 0,
}) {
  final style = ComputedStyle({
    'font-family': 'Ahem',
    'font-size': '10px',
    'line-height': '1',
    'white-space': 'pre',
    'margin-top': '${before}px',
    'margin-bottom': '${after}px',
    'padding-bottom': '${padding}px',
  });
  return PageBlock.styled(
    layout: TextLayoutEngine.layout(
      text: 'aa\nbb\ncc',
      style: style,
      maxWidth: 100,
    ),
    style: style,
    containingWidth: 100,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('页尾正外边距放不下时保留三行正文，切片高度不越界', () {
    final block = _paragraph(before: 30);
    final page = Paginator(pageHeight: 75)
        .measureChapter(blocks: [block])
        .pages
        .single;
    expect(page.slices.single.endLine, 3);
    expect(page.slices.single.leadingExtent, 30);
    expect(page.slices.single.trailingExtent, 15);
    expect(page.usedHeight, 75);
  });

  test('页内放得下的外边距和负外边距保持作者值', () {
    for (final after in [30.0, -5.0]) {
      final page = Paginator(pageHeight: 100)
          .measureChapter(blocks: [_paragraph(after: after)])
          .pages
          .single;
      expect(page.slices.single.trailingExtent, after);
      expect(page.usedHeight, 30 + after);
    }
  });

  test('页尾外边距截断仍保留内边距，不能挤占盒内留白', () {
    final pages = Paginator(pageHeight: 55)
        .measureChapter(blocks: [_paragraph(padding: 40)])
        .pages;
    expect(pages, hasLength(2));
    expect(pages.first.slices.single.endLine, 2);
    expect(pages.last.slices.single.startLine, 2);
    expect(pages.last.slices.single.trailingExtent, 45);
    expect(pages.last.usedHeight, 55);
  });

  for (final trim in [false, true]) {
    test('页尾截距后同步、流式分页及页索引重放一致，裁字边=$trim', () async {
      final blocks = [_paragraph(before: 30)];
      final paginator = Paginator(pageHeight: 75, trimTextEdges: trim);
      final measured = paginator.measureChapter(blocks: blocks);
      final streamed = await paginator.paginate(blocks: blocks).toList();
      final index = PageIndex.from(measured, blocks);
      final replayed = PageIndex.apply(
        PageIndex.decode(index.encode())!,
        blocks,
        spineIndex: 0,
        trimTextEdges: trim,
      )!;
      for (final pages in [streamed, replayed]) {
        expect(pages, hasLength(1));
        expect(pages.single.usedHeight, measured.pages.single.usedHeight);
        expect(
          pages.single.slices.single.trailingExtent,
          measured.pages.single.slices.single.trailingExtent,
        );
        expect(pages.single.slices.single.endLine, 3);
      }
    });
  }
}
