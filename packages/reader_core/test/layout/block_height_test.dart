import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/line_breaker.dart';

/// 块级盒高约束（CSS height/min-height/max-height）与分页几何。
///
/// Ahem 16px/1.5：每字 16 宽、行高 24；20 字在 320 宽下排 2 行（48 高）。
ComputedStyle _style([Map<String, String> overrides = const {}]) =>
    ComputedStyle(<String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'Ahem',
      ...overrides,
    });

PageBlock _block(
  ComputedStyle style, {
  String text = 'abcdefghijklmnopqrstuvwxyz0123456789ABCD',
  double containingWidth = 320,
}) => PageBlock.styled(
  layout: TextLayoutEngine.layout(
    text: text,
    style: style,
    maxWidth: containingWidth,
  ),
  style: style,
  containingWidth: containingWidth,
);

double _contentHeightOf(ComputedStyle style, {String text = 'abcdef'}) =>
    TextLayoutEngine.layout(text: text, style: style, maxWidth: 320).height;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('未声明高度：块高等于测量高（保持旧行为）', () {
    final block = _block(_style());
    expect(block.height, closeTo(block.layout.height, 0.01));
    expect(block.height, closeTo(48, 0.01));
  });

  test('height 声明：内容盒高取声明值（content-box + 边框进边框盒）', () {
    final style = _style(const {'height': '80px', 'border': '2px solid #000'});
    final block = _block(style);
    expect(block.height, closeTo(80, 0.01), reason: 'content-box 高 = 声明值');
    expect(
      block.leadingExtent + block.height + block.trailingExtent,
      closeTo(84, 0.01),
      reason: '边框盒高 = 内容 80 + 上下边框 4',
    );
  });

  test('min-height：内容矮时按最小高撑开，后续块顺延', () {
    final style = _style(const {'min-height': '60px', 'margin': '6px 0'});
    final short = _block(style, text: 'abc');
    expect(short.height, closeTo(60, 0.01));

    final next = _block(_style(const {'margin': '6px 0'}), text: 'abc');
    final pages = Paginator(pageHeight: 400)
        .measureChapter(blocks: <PageBlock>[short, next])
        .pages;
    final slices = pages.single.slices;
    expect(slices, hasLength(2));
    // 第一块占位 = 段前 6 + 盒高 60；第二块顶 = 66 + 折叠后 6 = 72。
    expect(slices[0].height, closeTo(6 + 60, 0.01));
    expect(slices[0].block.height, closeTo(60, 0.01));
  });

  test('max-height：内容超出盒高时按盒高裁剪切片', () {
    final style = _style(const {
      'height': '80px',
      'max-height': '40px',
      'overflow': 'hidden',
    });
    final block = _block(
      style,
      text:
          'abcdefghijklmnopqrstuvwxyz0123456789ABCD'
          'abcdefghijklmnopqrst',
    );
    expect(block.measuredHeight, closeTo(72, 0.01));
    expect(block.height, closeTo(40, 0.01), reason: 'min/max 钳制后内容盒高 40');
    final pages = Paginator(pageHeight: 400)
        .measureChapter(blocks: <PageBlock>[block])
        .pages;
    final slice = pages.single.slices.single;
    expect(slice.height, closeTo(40, 0.01));
    expect(slice.endLine, lessThan(block.layout.lineCount), reason: '溢出内容被裁掉');
  });

  test('空块声明高度仍占位', () {
    final empty = PageBlock.styled(
      layout: TextLayoutResult(
        text: '',
        lines: const <LineBox>[],
        width: 100,
        height: 0,
        maxWidth: 100,
      ),
      style: _style(const {'height': '30px'}),
      containingWidth: 320,
    );
    expect(empty.height, closeTo(30, 0.01));
    final pages = Paginator(pageHeight: 400)
        .measureChapter(blocks: <PageBlock>[empty])
        .pages;
    expect(pages.single.usedHeight, closeTo(30, 0.01));
  });

  test('调用方不传段距时按自身 margin 折（表格/图片块）', () {
    final style = _style(const {'margin': '8px 0'});
    final block = _block(style);
    expect(block.spaceBefore, closeTo(8, 0.01));
    expect(block.spaceAfter, closeTo(8, 0.01));
    final pages = Paginator(pageHeight: 400)
        .measureChapter(blocks: <PageBlock>[block])
        .pages;
    expect(pages.single.usedHeight, closeTo(8 + 48 + 8, 0.01));
  });

  test('显式段距优先于 margin', () {
    final style = _style(const {'margin': '8px 0'});
    final block = PageBlock.styled(
      layout: TextLayoutEngine.layout(text: 'abc', style: style, maxWidth: 320),
      style: style,
      containingWidth: 320,
      spaceBefore: 2,
      spaceAfter: 0,
    );
    expect(block.spaceBefore, 2);
    expect(block.spaceAfter, 0);
  });

  test('声明高度不改变测量高（行高之和仍可查）', () {
    final style = _style(const {'min-height': '60px'});
    final block = _block(style, text: 'abc');
    expect(_contentHeightOf(style, text: 'abc'), closeTo(24, 0.01));
    expect(block.measuredHeight, closeTo(24, 0.01));
    expect(block.height, closeTo(60, 0.01));
  });

  test('盒高裁剪：保留行顶在盒内的部分可见行（CFI 安全）', () {
    final style = _style(const {'height': '40px', 'overflow': 'hidden'});
    final text = 'abcdefghijklmnopqrstuvwxyz0123456789ABCD';
    final block = _block(style, text: text);
    final layout = block.layout;
    expect(layout.lineCount, 2, reason: '原文两行，第二行从盒内开始并部分可见');

    final pages = Paginator(pageHeight: 400)
        .measureChapter(blocks: <PageBlock>[block])
        .pages;
    final slice = pages.single.slices.single;
    expect(block.clipsContent, isTrue);
    expect(slice.endLine, 2, reason: '第二行从盒内开始，应画出盒底以上部分');
    expect(slice.continuesAfter, isFalse, reason: '被裁掉的行不进下一页');
    expect(slice.continuesBefore, isFalse);
    // 文本与行区间仍是原文坐标：第一行覆盖 text[0..end)。
    expect(layout.text, text);
    expect(layout.lines[0].start, 0);
    expect(
      layout.text.substring(0, layout.lines[0].end),
      text.substring(0, 20),
    );
    expect(slice.block.startCfi, isNull, reason: '块级 CFI 由章节源写入，裁剪不改');
    // 命中只落在可见行内。
    final hit = pages.single.hitTest(const Offset(1, 3));
    expect(hit, isNotNull);
    expect(hit!.lineIndex, 0);
  });

  test('overflow 默认 visible：盒高只影响流位置，溢出行仍保留在切片', () {
    final style = _style(const {'height': '24px'});
    final block = _block(style, text: 'abcdefghijklmnopqrstuvwxyz0123456789');
    expect(block.layout.lineCount, 2);
    expect(block.height, closeTo(24, 0.01));
    expect(block.hasContentOverflow, isTrue);
    expect(block.clipsContent, isFalse);

    final slice = Paginator(pageHeight: 400)
        .measureChapter(blocks: <PageBlock>[block])
        .pages
        .single
        .slices
        .single;
    expect(slice.height, closeTo(24, 0.01), reason: '后续块仍从盒底开始');
    expect(slice.endLine, 2, reason: '溢出的第二行仍应绘制');
    expect(slice.continuesAfter, isFalse);
  });

  test('min-height 留白随块占位：页尾放不下整盒时整块下移', () {
    final normal = _block(_style(const {'margin': '0'}), text: 'abc'); // 24 高
    final tall = _block(
      _style(const {'min-height': '60px', 'margin': '0'}),
      text: 'abc',
    );
    // 页高 70：24 + 60 > 70 → 第二块必须下移，首页留白。
    final pages = Paginator(pageHeight: 70)
        .measureChapter(blocks: <PageBlock>[normal, tall])
        .pages;
    expect(pages, hasLength(2));
    expect(pages[0].slices, hasLength(1));
    expect(pages[0].usedHeight, closeTo(24, 0.01));
    expect(pages[1].usedHeight, closeTo(60, 0.01), reason: '盒高留白计入页高');
    expect(pages[1].slices.single.block.height, closeTo(60, 0.01));
  });

  test('min-height 分页总和 = 各块盒高之和', () {
    final blocks = <PageBlock>[
      _block(_style(const {'min-height': '60px', 'margin': '0'}), text: 'abc'),
      _block(_style(const {'height': '40px', 'margin': '0'}), text: 'abc'),
    ];
    final result = Paginator(pageHeight: 40).measureChapter(blocks: blocks);
    var used = 0.0;
    for (final page in result.pages) {
      used += page.usedHeight;
    }
    expect(used, closeTo(60 + 40, 0.01));
    expect(result.totalHeight, closeTo(60 + 40, 0.01));
  });
}
