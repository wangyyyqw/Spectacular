import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/line_breaker.dart';

/// `position: absolute` 的页内偏移解算（包含块 = 页面内容盒）。
///
/// Ahem 每字 1em：16px 字号下每字 16 宽、行高 24。
ComputedStyle _style(Map<String, String> overrides) =>
    ComputedStyle(<String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'Ahem',
      ...overrides,
    });

PageBlock _absBlock(String text, Map<String, String> css) {
  final style = _style(<String, String>{
    'position': 'absolute',
    ...css,
  });
  return PageBlock.styled(
    layout: TextLayoutEngine.layout(
      text: text,
      style: style,
      maxWidth: css['width'] == null
          ? 350
          : double.tryParse(css['width']!.replaceAll('px', '')) ?? 350,
    ),
    style: style,
    containingWidth: 350,
    absolute: true,
  );
}

PageBlock _flowBlock(String text) {
  final style = _style(const {});
  return PageBlock.styled(
    layout: TextLayoutEngine.layout(text: text, style: style, maxWidth: 350),
    style: style,
    containingWidth: 350,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('right: 10px → 右边距包含块右缘 10', () {
    final block = _absBlock('abcdefgh', const {'right': '10px', 'width': '80px'});
    final page = Paginator(pageHeight: 800, pageWidth: 300)
        .measureChapter(blocks: [block])
        .pages
        .single;
    final slice = page.slices.single;
    expect(slice.overlay, isTrue);
    // 内容宽 = min(声明宽 80, ...)；left = 300 - 10 - 内容宽。
    expect(slice.leftInset, closeTo(300 - 10 - slice.block.layout.width, 0.5));
  });

  test('声明宽参与 right 解算：right 10 + width 80 → left = 包含块宽 − 90', () {
    final block = _absBlock('abcdefgh', const {'right': '10px', 'width': '80px'});
    final page = Paginator(pageHeight: 800, pageWidth: 300)
        .measureChapter(blocks: [block])
        .pages
        .single;
    expect(page.slices.single.leftInset, closeTo(300 - 10 - 80, 0.01));
    expect(page.slices.single.block.layout.maxWidth, closeTo(80, 0.01));
  });

  test('bottom 用声明宽下重排后的块高：bottom 20 + width 80', () {
    final block = _absBlock('abcdefgh', const {'bottom': '20px', 'width': '80px'});
    final page = Paginator(pageHeight: 400, pageWidth: 300)
        .measureChapter(blocks: [block])
        .pages
        .single;
    final slice = page.slices.single;
    expect(slice.absoluteTop, closeTo(400 - 20 - slice.block.height, 0.01));
  });

  test('bottom: 20px → 底边距页底 20', () {
    final block = _absBlock('abcdefgh', const {'bottom': '20px', 'width': '80px'});
    final page = Paginator(pageHeight: 400, pageWidth: 300)
        .measureChapter(blocks: [block])
        .pages
        .single;
    final slice = page.slices.single;
    // 两行（8 字 / 5 字每行）→ 高 48；top = 400 - 20 - 48。
    expect(
      slice.absoluteTop,
      closeTo(400 - 20 - slice.block.height, 0.5),
    );
  });

  test('over-constrained：left/top 优先，right/bottom 被忽略', () {
    final block = _absBlock(
      'abcdefgh',
      const {
        'left': '30px',
        'right': '10px',
        'top': '40px',
        'bottom': '20px',
        'width': '80px',
      },
    );
    final page = Paginator(pageHeight: 400, pageWidth: 300)
        .measureChapter(blocks: [block])
        .pages
        .single;
    final slice = page.slices.single;
    expect(slice.leftInset, closeTo(30, 0.5));
    expect(slice.absoluteTop, closeTo(40, 0.5));
  });

  test('百分比定位相对包含块宽/高', () {
    final block = _absBlock(
      'abcdefgh',
      const {'left': '50%', 'top': '25%', 'width': '80px'},
    );
    final page = Paginator(pageHeight: 400, pageWidth: 300)
        .measureChapter(blocks: [block])
        .pages
        .single;
    final slice = page.slices.single;
    expect(slice.leftInset, closeTo(150, 0.5));
    expect(slice.absoluteTop, closeTo(100, 0.5));
  });

  test('未声明 left/top → 静态位置（当前流游标、左缘）', () {
    final flow = _flowBlock('abcdefgh');
    final block = _absBlock('ab', const {});
    final page = Paginator(pageHeight: 800, pageWidth: 300)
        .measureChapter(blocks: [flow, block])
        .pages
        .single;
    expect(page.slices, hasLength(2));
    final overlay = page.slices.last;
    expect(overlay.overlay, isTrue);
    expect(overlay.absoluteTop, closeTo(24, 0.5), reason: '跟随前一块之后的流游标');
    expect(overlay.leftInset, closeTo(0, 0.5));
  });

  test('宽:auto 且内容超宽 → shrink-to-fit（不铺满包含块）', () {
    final block = _absBlock('abcdefghij', const {'left': '10px'});
    final page = Paginator(pageHeight: 800, pageWidth: 300)
        .measureChapter(blocks: [block])
        .pages
        .single;
    final slice = page.slices.single;
    // 10 字 × 16 = 160 < 300 → shrink-to-fit 到 160（max-content）。
    expect(slice.block.layout.width, closeTo(160, 1));
    expect(slice.block.layout.maxWidth, closeTo(160, 1));
  });

  test('宽:auto 且长文本超包含块 → 折到包含块宽', () {
    // 有空格才能让 min-content 小于可用宽（否则单个长词按 CSS 会溢出）。
    final block = _absBlock(
      'abcde fghij ' * 4,
      const {'left': '10px'},
    );
    final page = Paginator(pageHeight: 800, pageWidth: 300)
        .measureChapter(blocks: [block])
        .pages
        .single;
    final slice = page.slices.single;
    expect(slice.block.layout.maxWidth, closeTo(300, 1));
    expect(slice.block.layout.lineCount, greaterThan(1));
  });

  test('宽:auto 声明值也参与 shrink-to-fit', () {
    final block = _absBlock(
      'abcdefgh',
      const {'left': '10px', 'width': 'auto'},
    );
    final page = Paginator(pageHeight: 800, pageWidth: 300)
        .measureChapter(blocks: [block])
        .pages
        .single;
    final slice = page.slices.single;
    expect(slice.block.layout.maxWidth, closeTo(128, 1));
    expect(slice.leftInset, closeTo(10, 0.01));
  });

  test('border-box 宽高扣除 padding/border，right/bottom 按边框盒解算', () {
    final block = _absBlock(
      'abcdefgh',
      const {
        'box-sizing': 'border-box',
        'width': '80px',
        'height': '40px',
        'padding': '5px',
        'border': '3px solid red',
        'margin': '4px 6px',
        'right': '10px',
        'bottom': '20px',
      },
    );
    final page = Paginator(pageHeight: 400, pageWidth: 300)
        .measureChapter(blocks: [block])
        .pages
        .single;
    final slice = page.slices.single;
    expect(slice.block.layout.maxWidth, closeTo(64, 0.01));
    expect(slice.block.height, closeTo(24, 0.01));
    expect(
      slice.leftInset,
      closeTo(300 - 10 - 80 - 12, 0.01),
      reason: 'right 定位包含左右外边距',
    );
    expect(
      slice.absoluteTop,
      closeTo(400 - 20 - 40 - 8, 0.01),
      reason: 'bottom 定位包含上下外边距',
    );
    expect(slice.leadingExtent, closeTo(12, 0.01));
    expect(slice.trailingExtent, closeTo(12, 0.01));
    expect(slice.height, closeTo(48, 0.01), reason: '段距 + 边框盒高 + 段距');
  });

  test('绝对定位切片不推进流高（后续块 y 不受影响）', () {
    final before = _flowBlock('abcd');
    final absolute = _absBlock('abcdefgh', const {'top': '300px', 'left': '0px'});
    final after = _flowBlock('abcd');
    final page = Paginator(pageHeight: 800, pageWidth: 300)
        .measureChapter(blocks: [before, absolute, after])
        .pages
        .single;
    expect(page.usedHeight, closeTo(24 + 24, 0.01), reason: 'overlay 不计流高');
    expect(page.slices, hasLength(3));
    expect(page.slices.last.overlay, isFalse);
    // 后续块仍在第二块位置（y=24）。
    final lastSlice = page.slices.last;
    expect(lastSlice.absoluteTop, isNull);
  });
}
