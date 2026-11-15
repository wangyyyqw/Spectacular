import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/line_breaker.dart';

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
  test('跨页列流：内容超出一页时列顺延下一页、不丢内容', () {
    final style = _style(const {'column-count': '2', 'column-gap': '20px'});
    // 200 字 → 20 行（每行 10 字，行高 24）；页高 120 只容 5 行/列
    // → 每页 2 列共 10 行 → 2 页（10 + 10）。
    final block = _block('abcdefghij' * 20, style);
    final pages = Paginator(pageHeight: 120)
        .measureChapter(blocks: [block])
        .pages;
    // 页高 120、段前距 8 → 每列 4 行、每页 2 列 = 8 行 → 20 行需 3 页。
    expect(pages.length, greaterThanOrEqualTo(2));
    for (final page in pages) {
      expect(page.slices.length, lessThanOrEqualTo(2), reason: '每页最多两列');
      expect(page.slices, isNotEmpty);
    }
    expect(pages.first.slices, hasLength(2), reason: '首屏应排满两列');
    // 两页块数之和 = 4（2 页 × 2 列），列内行数与原文行数一致。
    var lines = 0;
    for (final page in pages) {
      for (final slice in page.slices) {
        lines += slice.endLine - slice.startLine;
      }
    }
    expect(lines, 20, reason: '跨页列流不丢不重行');
    // 第二页首列内容应接在第 10 行之后（续排而非重排）。
    final second = pages[1].slices.first.block.layout.text;
    expect(second.contains('abcd'), isTrue);
    expect(pages[1].slices.first.continuesBefore, isFalse);
  });

  test('多列首页可用高度为零时强制容行且不丢正文', () {
    final style = _style(const {'column-count': '2', 'column-gap': '20px'});
    final block = _block('abcdefghij' * 20, style);
    final result = Paginator(
      pageHeight: 120,
      topPadding: 120,
    ).measureChapter(blocks: [block], maxPages: 10);

    expect(result.truncated, isFalse);
    expect(result.pages.length, lessThanOrEqualTo(10));
    expect(result.pages.every((page) => page.slices.isNotEmpty), isTrue);
    expect(
      result.pages
          .expand((page) => page.slices)
          .map((slice) => slice.block.layout.text)
          .join(),
      block.layout.text,
      reason: '空页仍至少推进一行，超出页面的部分交由绘制层裁切',
    );
  });

  test('多列段前留白超过页高时强制推进首行', () {
    final style = _style(const {
      'column-count': '2',
      'column-gap': '20px',
      'padding-top': '160px',
    });
    final block = _block('abcdefghij' * 20, style);
    final result = Paginator(
      pageHeight: 120,
    ).measureChapter(blocks: [block], maxPages: 10);

    expect(result.truncated, isFalse);
    expect(result.pages.length, lessThanOrEqualTo(10));
    expect(
      result.pages
          .expand((page) => page.slices)
          .map((slice) => slice.block.layout.text)
          .join(),
      block.layout.text,
    );
  });

  test('多列列流达到页数上限后保留已有页并截断', () {
    final style = _style(const {'column-count': '2', 'column-gap': '20px'});
    final block = _block('abcdefghij' * 20, style);
    final result = Paginator(
      pageHeight: 120,
    ).measureChapter(blocks: [block], maxPages: 1);

    expect(result.pages, hasLength(1));
    expect(result.pages.single.slices, hasLength(2));
    expect(result.truncated, isTrue);
    expect(
      result.pages.single.slices
          .map((slice) => slice.block.layout.text)
          .join(),
      block.layout.text.substring(0, 80),
    );
  });

  test('不可容行的多列列流在有限检查点内完成流式分页', () async {
    final style = _style(const {'column-count': '2', 'column-gap': '20px'});
    final block = _block('abcdefghij' * 20, style);
    final paginator = Paginator(pageHeight: 1);
    var checkpoints = 0;
    final pages = await paginator
        .paginate(
          blocks: [block],
          maxPages: 3,
          budgetCheck: () async {
            expect(++checkpoints, lessThanOrEqualTo(10));
          },
        )
        .toList();

    expect(pages, hasLength(3));
    expect(pages.every((page) => page.slices.isNotEmpty), isTrue);
    final synchronous = paginator.measureChapter(blocks: [block], maxPages: 3);
    expect(synchronous.truncated, isTrue);
    expect(
      pages.expand((page) => page.slices).map((slice) => slice.block.layout.text),
      synchronous.pages
          .expand((page) => page.slices)
          .map((slice) => slice.block.layout.text),
    );
  });

  test('列内保留行内样式 runs（加粗/斜体不丢）', () {
    final style = _style(const {'column-count': '2', 'column-gap': '20px'});
    final block = PageBlock.styled(
      layout: TextLayoutEngine.layout(
        text: 'abcdefghijabcdefghijabcdefghijkl',
        style: style,
        maxWidth: 350,
        runs: <StyledRun>[
          StyledRun(
            start: 0,
            end: 10,
            style: ComputedStyle(<String, String>{'font-weight': '700'}),
          ),
          StyledRun(
            start: 10,
            end: 20,
            style: ComputedStyle(<String, String>{'font-style': 'italic'}),
          ),
        ],
      ),
      style: style,
      containingWidth: 350,
    );
    final page = Paginator(pageHeight: 400)
        .measureChapter(blocks: [block])
        .pages
        .single;
    expect(page.slices.length, 2);
    // 各列分别持有自己文本区间内的 run，偏移必须是片段内坐标。
    final allRuns = <StyledRun>[
      for (final slice in page.slices) ...slice.block.layout.runs,
    ];
    for (final slice in page.slices) {
      final length = slice.block.layout.text.length;
      for (final run in slice.block.layout.runs) {
        expect(run.start, greaterThanOrEqualTo(0));
        expect(run.end, lessThanOrEqualTo(length));
      }
    }
    expect(allRuns, isNotEmpty, reason: '列内应保留行内样式 run');
    expect(allRuns.any((run) => run.style.fontWeight == 700), isTrue);
    expect(allRuns.any((run) => run.style.italic), isTrue);
  });

}
