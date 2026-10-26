import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';

/// 竖排分页：`lines` 是「列」，列沿横轴并排、整块同高，不能按纵向切页。
ComputedStyle _style(Map<String, String> overrides) =>
    ComputedStyle(<String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'Ahem',
      ...overrides,
    });

PageBlock _verticalBlock(String text, {double height = 100}) {
  final style = _style(<String, String>{
    'writing-mode': 'vertical-rl',
    'height': '${height}px',
  });
  return PageBlock.styled(
    layout: TextLayoutEngine.layout(
      text: text,
      style: style,
      maxWidth: height,
    ),
    style: style,
    containingWidth: height,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('竖排列带超页宽：按列分页、列不丢不重（声明 height 保持为列长）', () {
    final block = _verticalBlock('一二三四五六' * 17); // 102 字 → 17 列
    final layout = block.layout;
    expect(layout.isVertical, isTrue);
    expect(layout.lineCount, 17);
    final pages = Paginator(pageHeight: 400, pageWidth: 300)
        .measureChapter(blocks: [block])
        .pages;
    // 声明 height 100 → 列长 100；17 列 × 24 = 408 > 页宽 300 → 12 列/页 → 2 页。
    expect(pages, hasLength(2));
    expect(pages.first.slices.single.block.layout.lineCount, 12);
    expect(pages.last.slices.single.block.layout.lineCount, 5);
    var cursor = 0;
    for (final page in pages) {
      for (final column in page.slices.single.block.layout.lines) {
        expect(column.start, cursor);
        cursor = column.end;
      }
    }
    expect(cursor, layout.text.length, reason: '列不丢不重');
  });

  test('竖排整块切片高度含上下段距（与横排同口径）', () {
    final style = _style(const {
      'writing-mode': 'vertical-rl',
      'height': '200px',
      'margin': '8px 0',
      'padding-top': '1px',
    });
    final block = PageBlock.styled(
      layout: TextLayoutEngine.layout(
        text: '一二三四五六' * 12,
        style: style,
        maxWidth: 200,
      ),
      style: style,
      containingWidth: 200,
    );
    final page = Paginator(pageHeight: 800, pageWidth: 300)
        .measureChapter(blocks: [block])
        .pages
        .single;
    final slice = page.slices.single;
    // 切片高 = 段前 + 内容高 + 段后（绘制按 slice.height 推进 y，对照工具
    // 按 slice.height − leading − trailing 折算盒高）。
    expect(
      slice.height,
      closeTo(slice.leadingExtent + slice.block.height + slice.trailingExtent, 0.01),
    );
    expect(page.usedHeight, closeTo(slice.height, 0.01));
  });

  test('竖排块放不下当前页时整体换页，不丢列', () {
    final first = PageBlock.styled(
      layout: TextLayoutEngine.layout(
        text: '横排一段文字',
        style: _style(const {}),
        maxWidth: 300,
      ),
      style: _style(const {}),
      containingWidth: 300,
    );
    // 竖排块高 200 > 页高 150：整块换到下一页（列仍完整）。
    final vertical = _verticalBlock('一二三四五六' * 17, height: 200);
    final pages = Paginator(pageHeight: 150, pageWidth: 300)
        .measureChapter(blocks: [first, vertical])
        .pages;
    expect(pages.length, greaterThanOrEqualTo(2));
    // 竖排跨页：按「列长 = 页高」重排后逐页分列，列区间首尾相接、覆盖全文。
    var cursor = 0;
    for (final page in pages) {
      for (final slice in page.slices.where((s) => s.block.layout.isVertical)) {
        for (final column in slice.block.layout.lines) {
          expect(column.start, cursor, reason: '列区间首尾相接');
          cursor = column.end;
        }
      }
    }
    expect(cursor, vertical.layout.text.length, reason: '列不丢不重');
  });

  test('两块竖排依次排列（页内纵向堆叠，列不串块）', () {
    final a = _verticalBlock('一二三四五六' * 9, height: 100); // 9 列
    final b = _verticalBlock('七八九十百千万' * 4, height: 100); // 6 列
    final page = Paginator(pageHeight: 400, pageWidth: 300)
        .measureChapter(blocks: [a, b])
        .pages
        .single;
    expect(page.slices, hasLength(2));
    expect(page.slices[0].block.layout.lineCount, a.layout.lineCount);
    expect(page.slices[1].block.layout.lineCount, b.layout.lineCount);
    expect(page.usedHeight, closeTo(a.height + b.height, 0.01));
  });
}
