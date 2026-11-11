import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/line_breaker.dart';

/// 竖排跨页列流：列长 = 页高，一页容纳 floor(页宽/列宽) 列，剩余列顺延下一页。
ComputedStyle _style(Map<String, String> overrides) =>
    ComputedStyle(<String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'Ahem',
      'writing-mode': 'vertical-rl',
      ...overrides,
    });

PageBlock _verticalBlock(String text, {double height = 1200}) {
  final style = _style(<String, String>{'height': '${height}px'});
  return PageBlock.styled(
    layout: TextLayoutEngine.layout(text: text, style: style, maxWidth: height),
    style: style,
    containingWidth: height,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('60 列 / 页高 400 / 页宽 480 → 每页 20 列、共 3 页', () {
    // Ahem 16px：1500 字 = 24000px；列长 400 → 60 列；列宽 24。
    final block = _verticalBlock('一二三四五六七八九十' * 150);
    final pages = Paginator(pageHeight: 400, pageWidth: 480)
        .measureChapter(blocks: [block])
        .pages;
    expect(pages, hasLength(3));
    for (var i = 0; i < pages.length; i++) {
      expect(pages[i].slices, hasLength(1), reason: '每页一整块竖排内容');
      final slice = pages[i].slices.single;
      expect(slice.endLine, 20, reason: 'floor(480 / 24) = 20 列/页');
      expect(slice.height, closeTo(400, 0.01), reason: '占满页高');
    }
  });

  test('列序连续、不丢不重（分页后覆盖全部列）', () {
    final block = _verticalBlock('一二三四五六七八九十' * 150);
    final pages = Paginator(pageHeight: 400, pageWidth: 480)
        .measureChapter(blocks: [block])
        .pages;
    var cursor = 0;
    for (final page in pages) {
      for (final slice in page.slices) {
        for (final column in slice.block.layout.lines) {
          expect(column.start, cursor, reason: '列区间首尾相接');
          cursor = column.end;
        }
      }
    }
    expect(cursor, block.layout.text.length, reason: '覆盖全文，无丢失/重复');
  });

  test('页内列从右向左推进（vertical-rl）：首列在最右', () {
    final block = _verticalBlock('一二三四五六七八九十' * 150);
    final page = Paginator(pageHeight: 400, pageWidth: 480)
        .measureChapter(blocks: [block])
        .pages
        .first;
    final columns = page.slices.single.block.layout.lines;
    expect(columns, hasLength(20));
    expect(columns.first.columnX, closeTo(19 * 24, 0.01), reason: '首列最右');
    expect(columns.last.columnX, closeTo(0, 0.01));
    for (var i = 1; i < columns.length; i++) {
      expect(columns[i].columnX!, lessThan(columns[i - 1].columnX!));
    }
  });

  test('vertical-lr 页内列从左向右推进', () {
    final style = _style(const {
      'writing-mode': 'vertical-lr',
      'height': '1200px',
    });
    final block = PageBlock.styled(
      layout: TextLayoutEngine.layout(
        text: '一二三四五六七八九十' * 150,
        style: style,
        maxWidth: 1200,
      ),
      style: style,
      containingWidth: 1200,
    );
    final page = Paginator(pageHeight: 400, pageWidth: 480)
        .measureChapter(blocks: [block])
        .pages
        .first;
    final columns = page.slices.single.block.layout.lines;
    expect(columns.first.columnX, closeTo(0, 0.01));
    expect(columns.last.columnX, closeTo(19 * 24, 0.01));
  });

  test('66 口径：2100 字 / 无 height / 800+topPadding14 → 43 列、4 页（末页 1 列）', () {
    final style = _style(const {});
    final block = PageBlock.styled(
      layout: TextLayoutEngine.layout(
        text: '字' * 2100,
        style: style,
        maxWidth: 350,
      ),
      style: style,
      containingWidth: 350,
    );
    final pages = Paginator(pageHeight: 800, pageWidth: 350, topPadding: 14)
        .measureChapter(blocks: [block])
        .pages;
    expect(pages, hasLength(4), reason: '列长 786 → 43 列 → ceil(43/14) = 4 页');
    final counts = pages
        .map((page) => page.slices.single.block.layout.lineCount)
        .toList();
    expect(counts, <int>[14, 14, 14, 1]);
    expect(counts.fold<int>(0, (a, b) => a + b), 43, reason: '总列数 43');
    // 页内容高 786（800 − topPadding 14），每列 49 字（16px）→ 列内实际高 784。
    final firstColumn = pages.first.slices.single.block.layout.lines.first;
    expect(firstColumn.height, closeTo(784, 1));
    expect((firstColumn.end - firstColumn.start), 49);
    expect(pages.first.slices.single.block.layout.width, closeTo(336, 0.01));
  });

  test('67 口径：300 字 / 无 height / 800+topPadding14 → 1 页 7 列、块宽 168', () {
    final style = _style(const {});
    final block = PageBlock.styled(
      layout: TextLayoutEngine.layout(
        text: '字' * 300,
        style: style,
        maxWidth: 350,
      ),
      style: style,
      containingWidth: 350,
    );
    final page = Paginator(pageHeight: 800, pageWidth: 350, topPadding: 14)
        .measureChapter(blocks: [block])
        .pages
        .single;
    final columns = page.slices.single.block.layout.lines;
    expect(columns, hasLength(7), reason: '300 字 / 每列 49 字 → 7 列');
    expect(page.slices.single.block.layout.width, closeTo(168, 0.01));
    expect(columns.first.height, closeTo(784, 1), reason: '49 字 × 16px');
    expect(columns.expand((c) => <int>[c.end - c.start]).first, 49);
  });

  test('跨页竖排块之后的普通块从新页开始', () {
    final vertical = _verticalBlock('一二三四五六七八九十' * 150);
    final normal = PageBlock.styled(
      layout: TextLayoutEngine.layout(
        text: '普通段落',
        style: ComputedStyle(<String, String>{
          'font-size': '16px',
          'line-height': '1.5',
          'font-family': 'Ahem',
        }),
        maxWidth: 300,
      ),
      style: ComputedStyle(<String, String>{
        'font-size': '16px',
        'line-height': '1.5',
        'font-family': 'Ahem',
      }),
      containingWidth: 300,
    );
    final pages = Paginator(pageHeight: 400, pageWidth: 480)
        .measureChapter(blocks: [vertical, normal])
        .pages;
    expect(pages, hasLength(4), reason: '3 页竖排 + 1 页普通段落');
    expect(pages.last.slices, hasLength(1));
    expect(pages.last.slices.single.overlay, isFalse);
    expect(pages.last.slices.single.block.layout.isVertical, isFalse);
  });
}
