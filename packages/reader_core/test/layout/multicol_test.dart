import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/line_breaker.dart';

ComputedStyle _style(Map<String, String> overrides) =>
    ComputedStyle(<String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'Ahem',
      'margin': '8px 0',
      ...overrides,
    });

PageBlock _block(String text, ComputedStyle style, {double width = 350}) =>
    PageBlock.styled(
      layout: TextLayoutEngine.layout(text: text, style: style, maxWidth: width),
      style: style,
      containingWidth: width,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('列几何：350 宽 / 2 列 / gap 20 → 列宽 165', () {
    final geometry = MulticolGeometry.fromStyle(
      _style(const {'column-count': '2', 'column-gap': '20px'}),
      350,
    )!;
    expect(geometry.count, 2);
    expect(geometry.columnWidth, closeTo(165, 0.01));
    expect(geometry.gap, 20);
    expect(geometry.leftOf(1), closeTo(185, 0.01));
  });

  test('列宽折算列数：column-width 是小宽，count 取小', () {
    // 350 宽、gap 8、column-width 60 → floor((350+8)/(60+8)) = 5，声明 3 → 3 列。
    final geometry = MulticolGeometry.fromStyle(
      _style(const {'column-count': '3', 'column-width': '60px', 'column-gap': '8px'}),
      350,
    )!;
    expect(geometry.count, 3);
    expect(geometry.columnWidth, closeTo((350 - 16) / 3, 0.01));
  });

  test('只声明 column-width 时按可用宽折算列数', () {
    final geometry = MulticolGeometry.fromStyle(
      _style(const {'column-width': '100px', 'column-gap': '10px'}),
      350,
    )!;
    // floor((350+10)/(100+10)) = 3 → 列宽 (350-20)/3。
    expect(geometry.count, 3);
    expect(geometry.columnWidth, closeTo((350 - 20) / 3, 0.01));
  });

  test('gap: normal 按 1em', () {
    final geometry = MulticolGeometry.fromStyle(
      _style(const {'column-count': '2'}),
      350,
    )!;
    expect(geometry.gap, 16);
    expect(geometry.columnWidth, closeTo((350 - 16) / 2, 0.01));
  });

  test('未形成多列返回 null', () {
    expect(
      MulticolGeometry.fromStyle(_style(const {}), 350),
      isNull,
    );
    expect(
      MulticolGeometry.fromStyle(
        _style(const {'column-count': '1'}),
        350,
      ),
      isNull,
    );
  });

  test('分页：首列随流、次列覆盖切片，列顺序先左后右', () {
    final style = _style(const {'column-count': '2', 'column-gap': '20px'});
    // Ahem 16px：每字 16 宽，列宽 165 → 每行 10 字；34 字 = 4 行（均衡 2+2）。
    final block = _block(
      'abcdefghijabcdefghijabcdefghijkl',
      style,
    );
    final pages = Paginator(pageHeight: 400).measureChapter(blocks: [block]).pages;
    expect(pages, hasLength(1));
    final slices = pages.single.slices;
    expect(slices.length, 2, reason: '2 列 = 1 随流 + 1 覆盖');
    expect(slices[0].overlay, isFalse);
    expect(slices[0].block.layout.lineCount, 2);
    expect(slices[1].overlay, isTrue);
    expect(slices[1].block.layout.lineCount, 2);
    expect(slices[1].absoluteTop, closeTo(8, 0.01), reason: '覆盖列与首列同顶（含段前）');
    expect(slices[1].leftInset, closeTo(185, 0.01), reason: '第二列左偏移 = 列宽 + gap');
    // 列片段文本衔接：第二列文本 = 原文去掉首列片段后的尾部。
    final firstText = slices[0].block.layout.text;
    final secondText = slices[1].block.layout.text;
    expect(firstText + secondText, block.layout.text, reason: '列片段拼接等于原文');
    expect(secondText.length, greaterThan(0));
    // 占高取较高列（2 行 = 48）。
    expect(pages.single.usedHeight, closeTo(8 + 48 + 8, 0.01));
  });

  test('多列块不需要重排时不影响单列块', () {
    final plain = _block('abcdefghij', _style(const {}));
    final pages = Paginator(pageHeight: 400).measureChapter(blocks: [plain]).pages;
    expect(pages.single.slices, hasLength(1));
    expect(pages.single.slices.single.overlay, isFalse);
  });
}
