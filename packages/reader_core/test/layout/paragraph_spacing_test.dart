import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/page_index.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/line_breaker.dart';

/// 正文段落样式（Ahem 字体，行高 24）。
ComputedStyle get _style => ComputedStyle(<String, String>{
  'font-size': '16px',
  'line-height': '1.5',
  'font-family': 'Ahem',
  'color': '#FF0000',
});

PageBlock _paragraph(
  String text, {
  double marginTop = 0,
  double marginBottom = 0,
}) {
  final style = _style;
  return PageBlock.styled(
    layout: TextLayoutEngine.layout(text: text, style: style, maxWidth: 180),
    style: style,
    containingWidth: 200,
    spaceBefore: marginTop,
    spaceAfter: marginBottom,
  );
}

void main() {
  test('正文相邻段落上下外边距折叠：段距取 max，不再两段相加', () {
    final pages = Paginator(pageHeight: 1000)
        .measureChapter(
          blocks: [
            _paragraph('第一段。', marginTop: 16, marginBottom: 16),
            _paragraph('第二段。', marginTop: 16, marginBottom: 16),
          ],
        )
        .pages;
    final slices = pages.single.slices;
    expect(slices.length, 2);
    expect(slices[0].leadingExtent, 16, reason: '首段段前距保留 margin-top');
    expect(slices[0].trailingExtent, 0, reason: '段后距折叠并入下一段');
    expect(slices[1].leadingExtent, 16, reason: '段距 = max(16, 16) 而非 32');
    // 两段总占高 = 首段段前 16 + 两行 48 + 段距 16 + 末段段后 16。
    expect(pages.single.usedHeight, closeTo(96, 0.5));
  });

  test('不等边距折叠取较大者', () {
    final pages = Paginator(pageHeight: 1000)
        .measureChapter(
          blocks: [
            _paragraph('第一段。', marginTop: 8, marginBottom: 24),
            _paragraph('第二段。', marginTop: 16, marginBottom: 8),
          ],
        )
        .pages;
    expect(pages.single.slices[1].leadingExtent, 24, reason: 'max(24, 16)');
  });

  test('负外边距按 CSS 规则折叠：正取最大 + 负取最小', () {
    final pages = Paginator(pageHeight: 1000)
        .measureChapter(
          blocks: [
            _paragraph('普通段。', marginBottom: 16),
            _paragraph('上提段。', marginTop: -12),
          ],
        )
        .pages;
    expect(pages.single.slices[1].leadingExtent, 4, reason: '16 + (−12) = 4');
  });

  test('折叠幂等且不重建块对象（页索引按身份映射块序号）', () {
    final blocks = [
      _paragraph('第一段。', marginTop: 16, marginBottom: 16),
      _paragraph('第二段。', marginTop: 16, marginBottom: 16),
      _paragraph('第三段。', marginTop: 8, marginBottom: 8),
    ];
    final once = PageBlock.collapseAdjacentMargins(blocks);
    final twice = PageBlock.collapseAdjacentMargins(once);
    expect(once[1].spaceBefore, 16, reason: 'max(16, 16)');
    expect(once[2].spaceBefore, 16, reason: 'max(16, 8)');
    for (var i = 0; i < once.length; i++) {
      expect(identical(twice[i], once[i]), isTrue, reason: '幂等不重建对象 $i');
    }
  });

  test('页索引重放与实时分页的段距一致', () {
    final blocks = [
      _paragraph('第一段。', marginTop: 16, marginBottom: 16),
      _paragraph('第二段。', marginTop: 16, marginBottom: 16),
    ];
    // 章节源在分页前折叠，PageIndex.from 按块身份映射块序号。
    final flow = PageBlock.collapseAdjacentMargins(blocks);
    final pagination = Paginator(pageHeight: 60).measureChapter(blocks: flow);
    final index = PageIndex.from(pagination, flow);
    final replayed = PageIndex.apply(index, flow, spineIndex: 0);
    expect(replayed, isNotNull);
    final live = pagination.pages
        .expand((page) => page.slices)
        .map((slice) => slice.leadingExtent)
        .toList();
    final again = replayed!
        .expand((page) => page.slices)
        .map((slice) => slice.leadingExtent)
        .toList();
    expect(again, live);
  });
}
