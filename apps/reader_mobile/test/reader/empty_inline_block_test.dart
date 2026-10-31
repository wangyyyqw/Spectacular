import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/paginator.dart';

import 'support/css_chapter_book.dart';

Future<PageBlock> _paragraph(String body, [String extraCss = '']) async {
  final source = await openCssChapter(
    body: '<p>$body</p>',
    css:
        'p { margin: 0; font-size: 24px; line-height: 2; } '
        '.box { display: inline-block; width: 36px; height: 18px; } $extraCss',
    contentWidth: 350,
    contentHeight: 900,
  );
  return (await source.loadChapter(0)).first.slices.first.block;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('空盒保留声明尺寸、基线和外层样式，不增加正文字数', () async {
    final block = await _paragraph(
      '<span class="red">盒前<span class="box"></span>盒后</span>普通。',
      '.red { color: red; text-emphasis: circle red; }',
    );
    expect(block.layout.text, '盒前盒后普通。');
    final line = block.layout.lines.single;
    final box = line.inlineBoxes.single;
    expect(box.offset, 2);
    expect(box.width, 36);
    expect(box.height, 18);
    expect(box.ascent, 18, reason: '无内容行时，下外边距边缘对齐基线');
    expect(box.descent, 0);
    expect(line.width, closeTo(204, .01));
    final payload = box.spec.payload! as PageBlock;
    expect(payload.layout.text, isEmpty);
    expect(payload.layout.lines, isEmpty);
    final runs = block.layout.runs;
    expect(runs, hasLength(2));
    expect(runs.first.start, 0);
    expect(runs.first.end, 4);
    expect(runs.first.style.color.toARGB32(), 0xffff0000);
    expect(runs.last.start, 4);
    expect(runs.last.end, 7);
    expect(runs.last.style.color.toARGB32(), isNot(0xffff0000));
  });

  test('只有空行内盒的段落仍参与排版和分页', () async {
    final block = await _paragraph('<span class="box"></span>');
    expect(block.layout.text, isEmpty);
    final line = block.layout.lines.single;
    expect(line.start, 0);
    expect(line.end, 0);
    expect(line.width, closeTo(36, .01));
    expect(line.inlineBoxes.single.height, 18);
  });

  test('同一偏移处的多个空盒只提取一次，保持文档顺序', () async {
    final block = await _paragraph(
      '前${List.generate(40, (i) => '<span class="box" '
          'style="width:${i + 1}px"></span>').join()}后',
    );
    final boxes = block.layout.lines
        .expand((line) => line.inlineBoxes)
        .toList();
    expect(block.layout.text, '前后');
    expect(boxes, hasLength(40));
    expect(boxes.map((box) => box.offset), everyElement(1));
    expect(boxes.map((box) => box.width), List.generate(40, (i) => i + 1));
    expect(block.layout.lines, hasLength(3), reason: '相同偏移的空盒按需换行，不逐盒强制换行');
  });

  test('空盒 auto 尺寸为零，padding、border、margin 与 min-width 生效', () async {
    final block = await _paragraph(
      '前<span class="box"></span>后',
      '.box { width: auto; height: auto; padding: 2px 3px; '
          'border: 1px solid black; margin: 4px 5px; min-width: 10px; }',
    );
    final box = block.layout.lines.single.inlineBoxes.single;
    expect(box.width, 18);
    expect(box.height, 6);
    expect(box.spec.outerWidth, 28);
    expect(box.ascent, 14);
    expect(box.descent, 0);
    expect(box.spec.contentHeight, 0);
  });

  test('显式零宽盒不被强制撑成 1px', () async {
    final block = await _paragraph(
      '前<span class="box"></span>后',
      '.box { width: 0; height: 0; }',
    );
    final box = block.layout.lines.single.inlineBoxes.single;
    expect(box.width, 0);
    expect(box.height, 0);
    expect(block.layout.lines.single.width, closeTo(48, .01));
  });

  test('空盒内部折叠空白不泄漏，盒前后空格仍保留', () async {
    final block = await _paragraph(
      '<span class="box">  </span> 前 <span class="box"> </span> 后',
    );
    expect(block.layout.text, ' 前  后');
    final boxes = block.layout.lines.single.inlineBoxes;
    expect(boxes.map((box) => box.offset), [0, 3]);
    expect(boxes.map((box) => box.width), [36, 36]);
  });

  test('行尾放不下的空盒整体换行，不丢失尾部插入点', () async {
    final block = await _paragraph(
      '前前前<span class="box"></span>',
      'p { width: 100px; }',
    );
    expect(block.layout.text, '前前前');
    expect(block.layout.lines, hasLength(2));
    final box = block.layout.lines.last.inlineBoxes.single;
    expect(box.offset, 3);
    expect(box.width, 36);
  });

  test('普通空 span 和 display:none 不产生行内盒', () async {
    final block = await _paragraph(
      '前<span></span><span class="box" style="display:none"></span>后',
    );
    expect(block.layout.text, '前后');
    expect(block.layout.lines.single.inlineBoxes, isEmpty);
  });

  test('空盒在纯空和图文单元格中保留，尺寸参与表格行高', () async {
    final source = await openCssChapter(
      body:
          '<table><tr><td><span class="box"></span></td>'
          '<td><span class="box"></span> 后</td>'
          '<td>前<span class="box"></span>后</td></tr></table>',
      css:
          'table { width: 100%; table-layout: fixed; } '
          'td { padding: 0; border: none; } '
          '.box { display: inline-block; width: 36px; height: 60px; }',
      contentWidth: 350,
      contentHeight: 900,
    );
    final table = (await source.loadChapter(0)).first.slices.first.block.table!;
    final empty = table.cells.first;
    final mixed = table.cells.last;
    expect(empty.layout.text, isEmpty);
    expect(empty.layout.lines.single.inlineBoxes.single.width, 36);
    expect(empty.layout.lines.single.inlineBoxes.single.ascent, 60);
    expect(empty.rect.height, greaterThanOrEqualTo(60));
    expect(table.cells[1].layout.text, ' 后');
    expect(table.cells[1].layout.lines.single.inlineBoxes.single.offset, 0);
    expect(mixed.layout.text, '前后');
    expect(mixed.layout.lines.single.inlineBoxes.single.offset, 1);
  });
}
