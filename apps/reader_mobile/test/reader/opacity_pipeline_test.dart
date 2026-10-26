import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/paginator.dart';

import 'support/css_chapter_book.dart';

/// 嵌套 opacity（W5）：flat 管线重建块样式会丢父链，章节源把
/// `chainStyle(chain).effectiveOpacity` 写进 `PageBlock.effectiveOpacity`，
/// 绘制层据此 saveLayer 合成。默认 1（不透明）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<List<PageBlock>> blocksOf(String body, String css) async {
    final source = await openCssChapter(
      body: body,
      css: css,
      contentWidth: 320,
      contentHeight: 800,
    );
    final pages = await source.loadChapter(0);
    return [for (final slice in pages.expand((page) => page.slices)) slice.block];
  }

  test('普通块默认不透明', () async {
    final blocks = await blocksOf('<p>不透明段落</p>', 'p { margin: 0; }');
    expect(blocks.single.effectiveOpacity, 1);
  });

  test('半透明容器的子块带父级 opacity', () async {
    final blocks = await blocksOf(
      '<div class="dim"><p>半透明段落</p></div>',
      '.dim { opacity: 0.5; }',
    );
    final paragraph = blocks.firstWhere(
      (block) => block.layout.text.startsWith('半透明段落'),
    );
    expect(paragraph.effectiveOpacity, closeTo(0.5, 0.001));
  });

  test('嵌套 opacity 相乘（0.5 × 0.5 = 0.25）', () async {
    final blocks = await blocksOf(
      '<div class="dim"><div class="dim2"><p>嵌套半透明</p></div></div>',
      '.dim { opacity: 0.5; } .dim2 { opacity: 0.5; }',
    );
    final paragraph = blocks.firstWhere(
      (block) => block.layout.text.startsWith('嵌套半透明'),
    );
    expect(paragraph.effectiveOpacity, closeTo(0.25, 0.001));
  });

  test('浮动块与表格块同样带祖先 opacity', () async {
    final blocks = await blocksOf(
      '<div class="dim">'
          '<div class="f">浮动块</div>'
          '<table><tr><td>格</td></tr></table>'
          '</div>',
      '.dim { opacity: 0.4; } '
          '.f { float: left; width: 80px; }',
    );
    final floated = blocks.firstWhere(
      (block) => block.floatSide != null && block.layout.text == '浮动块',
    );
    expect(floated.effectiveOpacity, closeTo(0.4, 0.001));
    final table = blocks.firstWhere((block) => block.table != null);
    expect(table.effectiveOpacity, closeTo(0.4, 0.001));
  });
}
