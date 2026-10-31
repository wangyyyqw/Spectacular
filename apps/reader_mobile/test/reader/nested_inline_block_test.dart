import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';

import 'support/css_chapter_book.dart';

Future<PageBlock> _block(String body, [String css = '']) async {
  final source = await openCssChapter(
    body: body,
    css:
        'p { margin: 0; font-size: 24px; line-height: 2; } '
        '.box { display: inline-block; width: 60px; } $css',
    contentWidth: 350,
    contentHeight: 900,
  );
  return (await source.loadChapter(0)).first.slices.first.block;
}

List<InlineBoxPlacement> _boxes(PageBlock block) =>
    block.layout.lines.expand((line) => line.inlineBoxes).toList();

PageBlock _payload(InlineBoxPlacement box) => box.spec.payload! as PageBlock;

int _colorAt(PageBlock block, int offset) => block.layout.runs
    .firstWhere((run) => run.start <= offset && offset < run.end)
    .style
    .color
    .toARGB32();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('非空盒摘除后前后文字保留外层颜色与字重', () async {
    final block = await _block(
      '<p><b style="color:red">前<span class="box">盒内</span>后</b>尾</p>',
    );
    expect(block.layout.text, '前后尾');
    expect(_colorAt(block, 0), 0xffff0000);
    expect(_colorAt(block, 1), 0xffff0000);
    expect(block.layout.runs.first.style.fontWeight, greaterThanOrEqualTo(700));
    final payload = _payload(_boxes(block).single);
    expect(payload.layout.text, '盒内');
    expect(payload.style!.color.toARGB32(), 0xffff0000);
  });

  test('跨盒的多层样式按摘除后坐标覆盖正确区间', () async {
    final block = await _block(
      '<p><span style="color:red">甲<span style="color:green">'
      '乙<span class="box">盒</span>丙</span>丁</span>尾</p>',
    );
    expect(block.layout.text, '甲乙丙丁尾');
    expect(
      [for (var i = 0; i < 4; i++) _colorAt(block, i)],
      [0xffff0000, 0xff008000, 0xff008000, 0xffff0000],
    );
    expect(_boxes(block).single.offset, 2);
  });

  test('嵌套盒仅由外盒占据正文，内盒进入外盒载荷', () async {
    final block = await _block(
      '<p>头<span class="box outer">前<span class="box inner">芯</span>'
          '后</span>尾</p>',
      '.outer { width: 140px; padding: 2px; } '
          '.inner { width: 36px; background: red; }',
    );
    expect(block.layout.text, '头尾');
    final outer = _boxes(block).single;
    expect(outer.width, 144);
    final payload = _payload(outer);
    expect(payload.layout.text, '前后');
    final inner = _boxes(payload).single;
    expect(inner.offset, 1);
    expect(inner.width, 36);
    expect(_payload(inner).layout.text, '芯');
    expect(
      outer.spec.contentBaseline,
      closeTo(2 + payload.layout.lines.last.baseline, .01),
    );
  });

  test('嵌套相对字号只解算一次，父盒宽作为子盒百分比基准', () async {
    final block = await _block(
      '<p><span class="box outer">甲<span class="box inner">'
          '<b style="color:blue">乙</b></span>丙</span></p>',
      '.outer { width: 160px; font-size: .8em; } '
          '.inner { width: 50%; font-size: .5em; }',
    );
    final outer = _payload(_boxes(block).single);
    expect(outer.style!.fontSize, closeTo(19.2, .001));
    final innerBox = _boxes(outer).single;
    expect(innerBox.width, closeTo(80, .001));
    final inner = _payload(innerBox);
    expect(inner.style!.fontSize, closeTo(9.6, .001));
    expect(inner.layout.runs.single.style.fontSize, closeTo(9.6, .001));
    expect(inner.layout.runs.single.style.color.toARGB32(), 0xff0000ff);
  });

  test('共享偏移的空嵌套盒与相邻同形元素不会互相吞并', () async {
    final block = await _block(
      '<p><span class="box outer"><span class="box inner"></span></span>'
          '<span class="box outer"><span class="box inner"></span></span>'
          '<span class="box inner"></span>尾</p>',
      '.outer { width: 70px; } .inner { width: 20px; height: 18px; }',
    );
    final boxes = _boxes(block);
    expect(block.layout.text, '尾');
    expect(boxes.map((box) => box.width), [70, 70, 20]);
    for (final outer in boxes.take(2)) {
      final payload = _payload(outer);
      expect(payload.layout.text, isEmpty);
      expect(_boxes(payload).single.width, 20);
      expect(payload.layout.lines, hasLength(1));
    }
    expect(_boxes(_payload(boxes.last)), isEmpty);
  });

  test('auto 外盒宽度包含内盒、边框与外层文字', () async {
    final block = await _block(
      '<p><span class="box outer">前<span class="box inner">芯</span>'
          '后</span></p>',
      '.outer { width: auto; padding: 2px; border: 1px solid black; } '
          '.inner { width: 36px; }',
    );
    final outer = _boxes(block).single;
    expect(outer.width, closeTo(90, .01));
    expect(_payload(outer).layout.lines.single.width, closeTo(84, .01));
  });

  test('嵌套空盒位于内容边界时，盒与文字之间的空格不被 trim 丢掉', () async {
    final block = await _block(
      '<p><span class="box outer"><span class="box inner"></span> '
          '前 <span class="box inner"></span></span>尾</p>',
      '.outer { width: 140px; } .inner { width: 20px; height: 18px; }',
    );
    final outer = _payload(_boxes(block).single);
    expect(outer.layout.text, ' 前 ');
    expect(_boxes(outer).map((box) => box.offset), [0, 3]);
  });

  test('表格单元格的外层样式与嵌套盒采用相同提取边界', () async {
    final block = await _block(
      '<table><tr><td><span style="color:red">前<span class="box outer">'
          '甲<span class="box inner">乙</span>丙</span>后</span></td></tr></table>',
      'td { font-size: 24px; padding: 0; border: none; } '
          '.outer { width: 140px; } .inner { width: 36px; }',
    );
    final cell = block.table!.cells.single;
    expect(cell.layout.text, '前后');
    expect(cell.layout.runs.single.style.color.toARGB32(), 0xffff0000);
    final outer = _payload(cell.layout.lines.single.inlineBoxes.single);
    expect(outer.layout.text, '甲丙');
    expect(_payload(_boxes(outer).single).layout.text, '乙');
  });
}
