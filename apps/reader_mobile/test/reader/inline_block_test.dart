import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';

import 'support/css_chapter_book.dart';

/// `display: inline-block`（W17 × T1 task-28）：章节源把行内块测成
/// [InlineBoxSpec]（宽高含 padding/border），交给行排版当行内盒放置；
/// payload 是盒子内部已构建好的块（背景/边框/文字都在里面），
/// 绘制层按 placement 矩形绘制。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<List<LineBox>> linesOf(String body, String css) async {
    final source = await openCssChapter(
      body: body,
      css: css,
      contentWidth: 350,
      contentHeight: 900,
    );
    final pages = await source.loadChapter(0);
    return [
      for (final slice in pages.expand((page) => page.slices))
        ...slice.block.layout.lines,
    ];
  }

  test('行内块按行内盒放置：宽高含 padding/border，在行内文字之后', () async {
    final lines = await linesOf(
      '<p>行内块对照：<span class="inl">inline-block 120×34</span> 结束</p>',
      'p { margin: 6px 0; line-height: 1.6; } '
          '.inl { display: inline-block; width: 120px; height: 34px; '
          'padding: 2px; border: 3px solid #333; }',
    );
    expect(lines, hasLength(1), reason: '一行放得下');
    final placements = lines.single.inlineBoxes;
    expect(placements, hasLength(1));
    final box = placements.single;
    expect(box.width, closeTo(130, 0.01), reason: '120 + padding 4 + border 6');
    expect(box.height, closeTo(44, 0.01), reason: '34 + padding 4 + border 6');
    expect(box.left, greaterThan(50), reason: '排在行内前置文字之后');
    final payload = box.spec.payload;
    expect(payload, isA<PageBlock>());
    expect((payload! as PageBlock).layout.text, 'inline-block 120×34');
  });

  test('放不下时整块换行（盒子不跨行）', () async {
    final lines = await linesOf(
      '<p>这是一段很长的前置文字，用来把行宽占满一些以便观察换行行为。'
          '<span class="wide">宽盒</span>后续</p>',
      'p { margin: 0; line-height: 1.6; } '
          '.wide { display: inline-block; width: 200px; height: 40px; }',
    );
    final boxes = [for (final line in lines) ...line.inlineBoxes];
    expect(boxes, hasLength(1));
    // 盒不在第一行（第一行剩余宽不够），且整块只出现在一个行里。
    final lineIndex = lines.indexWhere((line) => line.inlineBoxes.isNotEmpty);
    expect(lineIndex, greaterThan(0), reason: '放不下换到下一行');
    expect(
      lines[lineIndex].inlineBoxes.single.width,
      closeTo(200, 0.01),
      reason: '整块不跨行',
    );
  });

  test('vertical-align: middle 时上行/下行延伸平分盒高', () async {
    final lines = await linesOf(
      '<p>文字<span class="mid">盒</span></p>'
          '<p>文字<span class="top">盒</span></p>',
      'p { margin: 0; line-height: 1.6; } '
          '.mid { display: inline-block; width: 40px; height: 60px; '
          'vertical-align: middle; } '
          '.top { display: inline-block; width: 40px; height: 60px; '
          'vertical-align: top; }',
    );
    final boxes = [
      for (final line in lines)
        if (line.inlineBoxes.isNotEmpty) line.inlineBoxes.single,
    ];
    expect(boxes, hasLength(2));
    expect(boxes[0].ascent, closeTo(30, 0.01));
    expect(boxes[0].descent, closeTo(30, 0.01));
    expect(boxes[1].ascent, closeTo(60, 0.01), reason: 'top 对齐：全部在基线上方');
    expect(boxes[1].descent, closeTo(0, 0.01));
  });

  test('两个行内块按文本偏移升序、同处一行', () async {
    final lines = await linesOf(
      '<p><span class="a">甲</span>中间<span class="b">乙</span>尾巴</p>',
      'p { margin: 0; line-height: 1.6; } '
          '.a { display: inline-block; width: 40px; height: 20px; } '
          '.b { display: inline-block; width: 60px; height: 20px; }',
    );
    final boxes = [for (final line in lines) ...line.inlineBoxes];
    expect(boxes, hasLength(2));
    expect(boxes[0].offset, lessThan(boxes[1].offset));
    expect(boxes[0].left, lessThan(boxes[1].left));
    expect(boxes[0].width, closeTo(40, 0.01));
    expect(boxes[1].width, closeTo(60, 0.01));
  });

  test('固定高的行内盒：payload 标记内容溢出（供绘制层裁剪）', () async {
    final source = await openCssChapter(
      body:
          '<p>前缀<span class="boxed">这一盒内容很长会超过固定高度，'
          '用来验证 payload 的溢出标记。</span>后缀</p>',
      css:
          'p { margin: 0; line-height: 1.6; } '
          '.boxed { display: inline-block; width: 60px; height: 20px; '
          'overflow: hidden; }',
      contentWidth: 350,
      contentHeight: 900,
    );
    final pages = await source.loadChapter(0);
    final placements = [
      for (final slice in pages.expand((page) => page.slices))
        for (final line in slice.block.layout.lines) ...line.inlineBoxes,
    ];
    expect(placements, hasLength(1));
    final payload = placements.single.spec.payload! as PageBlock;
    // 声明高 20 < 内容高且 overflow: hidden → 绘制层按内容盒裁剪。
    expect(payload.clipsContent, isTrue, reason: '声明高 20 < 内容高');
    expect(
      payload.style!.overflow,
      CssOverflow.hidden,
      reason: '显式裁剪',
    );
  });

  test('没有 inline-block 的段落不产生行内盒', () async {
    final lines = await linesOf(
      '<p>普通<br/>段落</p>',
      'p { margin: 0; line-height: 1.6; }',
    );
    expect(lines.every((line) => line.inlineBoxes.isEmpty), isTrue);
  });

  test('无尺寸标签按内容收缩，完整边框与外边距参与行宽', () async {
    final lines = await linesOf(
      '<div><p><span class="tag">【虚无】命途 / 主动</span>后续正文</p></div>',
      'div { font-size: 20px; } p { font-size: .8em; margin: 0; } '
          '.tag { display: inline-block; font-size: .8em; white-space: nowrap; '
          'padding: 1px 4px; border: 1px solid black; margin-right: 5px; }',
    );
    final boxes = [for (final line in lines) ...line.inlineBoxes];
    expect(boxes, hasLength(1));
    final box = boxes.single;
    final payload = box.spec.payload! as PageBlock;
    expect(payload.layout.text, '【虚无】命途 / 主动');
    expect(payload.style!.fontSize, closeTo(12.8, .001));
    expect(payload.layout.lineCount, 1);
    expect(box.width, closeTo(payload.layout.width + 10, .01));
    expect(box.width, lessThan(300));
    expect(box.height, closeTo(payload.layout.height + 4, .01));
    expect(box.spec.marginRight, 5);
  });

  test('行内样式和属性选择器保留，内层字重不被外层盖掉', () async {
    final source = await openCssChapter(
      body:
          '<p><span id="outer" style="color: red">外层'
          '<b data-tone="strong">加粗</b></span>'
          '<span style="display: inline-block; padding: 2px">标签</span></p>',
      css: '[data-tone="strong"] { color: blue; }',
    );
    final block = (await source.loadChapter(0)).first.slices.first.block;
    final bold = block.layout.runs.firstWhere((run) => run.start == 2);
    expect(bold.style.fontWeight, greaterThanOrEqualTo(700));
    expect(bold.style.color.toARGB32(), 0xff0000ff);
    expect(block.layout.lines.expand((line) => line.inlineBoxes), hasLength(1));
  });

  test('一段超过八个自动宽标签仍全部产生原子盒', () async {
    final lines = await linesOf(
      '<p>${List.generate(10, (i) => '<span class="tag">$i</span>').join()}</p>',
      '.tag { display: inline-block; padding: 1px; }',
    );
    final boxes = [for (final line in lines) ...line.inlineBoxes];
    expect(boxes, hasLength(10));
    expect([
      for (final box in boxes) (box.spec.payload! as PageBlock).layout.text,
    ], List.generate(10, (i) => '$i'));
  });

  test('固定布局表格的标签盒与内层文字共同决定行高', () async {
    final source = await openCssChapter(
      body:
          '<table><tr><td>名称</td><td><span class="rank">RANK: '
          '<b>SSS</b></span></td></tr></table>',
      css:
          'table { width: 100%; table-layout: fixed; } '
          'td { padding: 0; border: none; font-size: 12px; } '
          '.rank { display: inline-block; padding: 2px 4px; '
          'border: 1px solid black; } .rank b { font-size: 24px; }',
    );
    final block = (await source.loadChapter(0)).first.slices.first.block;
    final cell = block.table!.cells.last;
    final box = cell.layout.lines.single.inlineBoxes.single;
    final payload = box.spec.payload! as PageBlock;
    expect(payload.layout.text, 'RANK: SSS');
    final runs = payload.layout.runs;
    expect(runs, hasLength(2));
    expect(runs.first.start, 0);
    expect(runs.first.end, 6);
    expect(runs.first.style.fontSize, 12);
    expect(runs.last.start, 6);
    expect(runs.last.end, 9);
    expect(runs.last.style.fontSize, 24);
    expect(
      runs.last.style.fontWeight,
      greaterThanOrEqualTo(700),
    );
    expect(cell.rect.height, greaterThanOrEqualTo(box.height));
  });
}
