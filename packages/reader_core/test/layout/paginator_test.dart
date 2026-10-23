import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';

ComputedStyle _style() => ComputedStyle(const <String, String>{
  'font-size': '16px',
  'line-height': '1.5',
  'font-family': 'Ahem',
});

PageBlock _block(String text, {bool before = false, bool after = false}) =>
    PageBlock(
      layout: TextLayoutEngine.layout(
        text: text,
        style: _style(),
        maxWidth: 500,
      ),
      pageBreakBefore: before,
      pageBreakAfter: after,
    );

void main() {
  test('纯文本章节按块分页且无空页', () {
    final blocks = <PageBlock>[for (var i = 0; i < 7; i++) _block('line$i')];
    final result = Paginator(pageHeight: 72).measureChapter(blocks: blocks);
    expect(result.pages, hasLength(3));
    expect(result.pages.map((page) => page.usedHeight), <double>[72, 72, 24]);
    for (var i = 0; i < result.pages.length; i++) {
      final page = result.pages[i];
      expect(page.pageIndex, i);
      expect(page.isEmpty, isFalse);
      expect(page.slices, isNotEmpty);
      expect(page.slices.every((slice) => slice.height == 24), isTrue);
    }
    expect(result.totalHeight, 168);
    expect(result.pages.first.spineIndex, 0);
  });

  test('pageBreakBefore 开启新页', () {
    final result = Paginator(pageHeight: 48).measureChapter(
      blocks: [_block('a'), _block('b', before: true), _block('c')],
    );
    expect(result.pages, hasLength(2));
    expect(result.pages[0].slices, hasLength(1));
    expect(result.pages[1].slices, hasLength(2));
  });

  test('pageBreakAfter 结束当前页', () {
    final result = Paginator(pageHeight: 72)
        .measureChapter(blocks: [_block('a', after: true), _block('b')]);
    expect(result.pages, hasLength(2));
    expect(result.pages[0].slices, hasLength(1));
    expect(result.pages[1].slices, hasLength(1));
  });

  test('连续强制分页不产生零长度页', () {
    final result = Paginator(pageHeight: 72).measureChapter(
      blocks: [
        _block('a', after: true),
        _block('b', before: true),
        _block('c', before: true),
      ],
    );
    expect(result.pages, hasLength(3));
    expect(result.pages.every((page) => page.slices.isNotEmpty), isTrue);
  });

  test('2px 容差允许刚好差 2px 的块', () {
    final result = Paginator(
      pageHeight: 46,
      tolerance: 2,
    ).measureChapter(blocks: [_block('a'), _block('b')]);
    expect(result.pages, hasLength(1));
    expect(result.pages.single.usedHeight, 48);
  });

  test('首页顶部留白只扣一次', () {
    final result = Paginator(pageHeight: 72, topPadding: 10).measureChapter(
      blocks: [_block('a'), _block('b'), _block('c'), _block('d')],
    );
    expect(result.pages, hasLength(2));
    expect(result.pages[0].topPadding, 10);
    expect(result.pages[0].usedHeight, 48);
    expect(result.pages[1].topPadding, 0);
    expect(result.pages[1].usedHeight, 48);
  });

  test('空块被跳过且切片行范围完整', () {
    final empty = PageBlock(
      layout: TextLayoutEngine.layout(text: '', style: _style(), maxWidth: 500),
    );
    final result = Paginator(pageHeight: 72)
        .measureChapter(blocks: [empty, _block('a'), empty]);
    expect(result.pages, hasLength(1));
    final slice = result.pages.single.slices.single;
    expect(slice.startLine, 0);
    expect(slice.endLine, 1);
    expect(slice.lines, hasLength(1));
  });
}
