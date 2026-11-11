import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/scroll_layout.dart';
import 'package:reader_core/layout/line_breaker.dart';

ComputedStyle _style() => ComputedStyle(const <String, String>{
  'font-size': '16px',
  'line-height': '1.5',
  'font-family': 'Ahem',
});

PageBlock _block(String text) => PageBlock(
  layout: TextLayoutEngine.layout(text: text, style: _style(), maxWidth: 500),
);

void main() {
  test('连续滚动压缩页间空白并保留原切片', () {
    final pages = Paginator(
      pageHeight: 72,
      topPadding: 10,
    ).measureChapter(blocks: [_block('a'), _block('b'), _block('c')]).pages;
    expect(pages, hasLength(2));
    expect(pages.first.usedHeight, 48);
    expect(pages.last.usedHeight, 24);

    final layout = ScrollChapterLayout.fromPages(2, pages);
    expect(layout.segments, hasLength(2));
    expect(layout.segments.first.extent, 58);
    expect(layout.segments.last.extent, 24);
    expect(layout.segments.last.content.topPadding, 0);
    expect(layout.extent, 82);
    expect(layout.offsetOfPage(1), 58);
    expect(layout.pageAtOffset(57), 0);
    expect(layout.pageAtOffset(58), 1);
    expect(
      identical(layout.segments.first.content.slices, pages.first.slices),
      isTrue,
      reason: '滚动模式复用已测量的行切片，不重新断行',
    );
  });

  test('空页不进入滚动流', () {
    final page = Paginator(pageHeight: 72)
        .measureChapter(blocks: [_block('a')])
        .pages
        .single;
    final empty = PageContent(
      spineIndex: 0,
      pageIndex: 1,
      slices: const [],
      usedHeight: 0,
      pageHeight: 72,
      topPadding: 0,
    );

    final layout = ScrollChapterLayout.fromPages(7, [page, empty]);
    expect(layout.spineIndex, 7);
    expect(layout.segments, hasLength(1));
    expect(layout.segments.single.pageIndex, 0);
  });
}
