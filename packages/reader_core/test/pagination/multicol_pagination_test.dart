import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';

/// 多列布局在分页层的几何（列拆分 / 覆盖定位 / 占高 / 换页）。
ComputedStyle _style(Map<String, String> overrides) =>
    ComputedStyle(<String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'Ahem',
      ...overrides,
    });

PageBlock _block(String text, ComputedStyle style, {double width = 350}) =>
    PageBlock.styled(
      layout: TextLayoutEngine.layout(
        text: text,
        style: style,
        maxWidth: width,
      ),
      style: style,
      containingWidth: width,
      spaceBefore: 8,
      spaceAfter: 8,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('两列：列宽 165、gap 20，列高取较高列，占高含段距', () {
    final style = _style(const {'column-count': '2', 'column-gap': '20px'});
    // 34 字 → 每列 10 字、共 4 行 → 均衡 2+2（每行 24 高）。
    final block = _block('abcdefghijabcdefghijabcdefghijkl', style);
    final page = Paginator(pageHeight: 400)
        .measureChapter(blocks: [block])
        .pages
        .single;
    expect(page.slices, hasLength(2));
    final flow = page.slices.first;
    final overlay = page.slices.last;
    expect(flow.block.layout.maxWidth, closeTo(165, 0.01));
    expect(flow.block.layout.width, closeTo(350, 0.01), reason: '块宽 = 列带总宽');
    expect(
      overlay.block.layout.width,
      closeTo(160, 0.01),
      reason: '列块宽 = 列内行宽（10 字 × 16）',
    );
    expect(overlay.leftInset, closeTo(185, 0.01));
    expect(overlay.absoluteTop, closeTo(8, 0.01), reason: '覆盖列与首列首行同顶');
    expect(page.usedHeight, closeTo(8 + 48 + 8, 0.01));
  });

  test('列内行数均衡（先填满首列再进次列）', () {
    final style = _style(const {'column-count': '2', 'column-gap': '20px'});
    // 70 字 → 7 行（每行 10 字）→ 均衡 4+3 或 3+4。
    final block = _block('abcdefghij' * 7, style);
    final page = Paginator(pageHeight: 400)
        .measureChapter(blocks: [block])
        .pages
        .single;
    final counts = page.slices
        .map((slice) => slice.block.layout.lineCount)
        .toList();
    expect(counts.first, greaterThanOrEqualTo(counts.last));
    expect(counts.first - counts.last, lessThanOrEqualTo(1));
    expect(counts.first + counts.last, 7, reason: '行不丢不重');
    // 列片段拼接等于原文（每列文本是原文的一段）。
    expect(
      page.slices.map((slice) => slice.block.layout.text).join(),
      block.layout.text,
    );
  });

  test('三列：column-count 与 column-width 折小，列位置依次右移', () {
    final style = _style(const {
      'column-count': '3',
      'column-width': '60px',
      'column-gap': '8px',
    });
    final block = _block('abcdefghij' * 9, style);
    final page = Paginator(pageHeight: 400)
        .measureChapter(blocks: [block])
        .pages
        .single;
    expect(page.slices, hasLength(3));
    final width = (350 - 16) / 3;
    for (var i = 0; i < 3; i++) {
      expect(page.slices[i].block.layout.maxWidth, closeTo(width, 0.01));
    }
    expect(page.slices[0].overlay, isFalse);
    expect(page.slices[1].leftInset, closeTo(width + 8, 0.01));
    expect(page.slices[2].leftInset, closeTo((width + 8) * 2, 0.01));
  });

  test('多列块放不下当前页时整体下移（不与前块交叠）', () {
    final style = _style(const {'column-count': '2', 'column-gap': '20px'});
    final before = _block('abcdefghij' * 3, _style(const {}));
    final multicol = _block('abcdefghij' * 8, style);
    final pages = Paginator(pageHeight: 120)
        .measureChapter(blocks: [before, multicol])
        .pages;
    expect(pages.length, greaterThanOrEqualTo(2));
    expect(pages.first.slices, hasLength(1), reason: '多列块整体下移');
    final second = pages[1];
    expect(second.slices, hasLength(2));
    expect(second.slices.first.overlay, isFalse);
    expect(second.slices.last.overlay, isTrue);
  });

  test('首列块携带完整多列几何（给绘制层画 column-rule）', () {
    final style = _style(const {'column-count': '2', 'column-gap': '20px'});
    final block = _block('abcdefghij' * 3, style);
    final page = Paginator(pageHeight: 400)
        .measureChapter(blocks: [block])
        .pages
        .single;
    final geometry = page.slices.first.block.multicol;
    expect(geometry, isNotNull);
    expect(geometry!.count, 2);
    expect(geometry.columnWidth, closeTo(165, 0.01));
    expect(geometry.gap, 20);
    expect(geometry.leftOf(1), closeTo(185, 0.01));
    expect(page.slices.last.block.multicol, isNull, reason: '其余列块不带几何');
    // 边距折叠重建块（withSpacing）时几何仍透传。
    final respaced = page.slices.first.block.withSpacing(spaceBefore: 0);
    expect(respaced.multicol, isNotNull);
    expect(respaced.multicol!.count, 2);
  });

  test('多列块宽度不足以形成两列时退回单列', () {
    final style = _style(const {
      'column-count': '2',
      'column-width': '400px',
      'column-gap': '20px',
    });
    final block = _block('abcdefghij' * 2, style);
    final page = Paginator(pageHeight: 400)
        .measureChapter(blocks: [block])
        .pages
        .single;
    expect(page.slices, hasLength(1), reason: '折算列数 < 2 → 不拆列');
    expect(page.slices.single.overlay, isFalse);
  });
}
