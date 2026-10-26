import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/paginator.dart';

import 'support/css_chapter_book.dart';

/// 嵌套列表（31-list-nested）：缩进逐层累加、标记按层级轮换、
/// `list-style` 的继承与重置要跟浏览器一致。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<List<PageBlock>> blocksOf(String body, String css) async {
    final source = await openCssChapter(
      body: body,
      css: css,
      contentWidth: 350,
      contentHeight: 900,
    );
    final pages = await source.loadChapter(0);
    return [for (final slice in pages.expand((page) => page.slices)) slice.block];
  }

  /// 按块文本精确取块（嵌套列表项前缀会互相包含，如「二级宿主」/「二级」）。
  PageBlock blockWith(List<PageBlock> blocks, String text) =>
      blocks.firstWhere((block) => block.layout.text == text);

  test('三层缩进按容器 padding-left 累加（24/48/72）', () async {
    final blocks = await blocksOf(
      '<ul><li>一级<ul><li>二级<ul><li>三级</li></ul></li></ul></li></ul>',
      'ul { margin: 4px 0; padding-left: 24px; line-height: 1.7; }',
    );
    expect(blockWith(blocks, '一级').style!.margin.left, closeTo(24, 0.01));
    expect(blockWith(blocks, '二级').style!.margin.left, closeTo(48, 0.01));
    expect(blockWith(blocks, '三级').style!.margin.left, closeTo(72, 0.01));
    // 行首 x 与 margin 一致（flat 管线：行 x = margin + offsetX）。
    expect(blockWith(blocks, '三级').layout.lines.first.offsetX, 0);
  });

  test('未声明 list-style-type 时标记按层级轮换 disc/circle/square', () async {
    final blocks = await blocksOf(
      '<ul><li>一级</li><li>二级宿主<ul><li>二级</li><li>三级宿主'
          '<ul><li>三级</li></ul></li></ul></li></ul>',
      'ul { margin: 4px 0; padding-left: 24px; }',
    );
    expect(blockWith(blocks, '一级').listMarker, '•');
    expect(blockWith(blocks, '二级宿主').listMarker, '•');
    expect(blockWith(blocks, '二级').listMarker, '○');
    expect(blockWith(blocks, '三级').listMarker, '▪');
  });

  test('作者样式表按层级指定 list-style-type 时以级联结果为准', () async {
    final blocks = await blocksOf(
      '<ul><li>一级<ul><li>二级<ul><li>三级</li></ul></li></ul></li></ul>',
      'ul { margin: 4px 0; padding-left: 24px; } '
          'ul ul { list-style-type: circle; } '
          'ul ul ul { list-style-type: square; }',
    );
    expect(blockWith(blocks, '一级').listMarker, '•');
    expect(blockWith(blocks, '二级').listMarker, '○');
    expect(blockWith(blocks, '三级').listMarker, '▪');
  });

  test('list-style: none 继承到子层，子层可重新打开', () async {
    final blocks = await blocksOf(
      '<ul class="plain"><li>无标记一项</li>'
          '<li class="host">无标记二项'
          '<ul class="dots"><li>重新打开</li></ul></li></ul>',
      'ul { margin: 4px 0; padding-left: 24px; } '
          '.plain { list-style: none; } '
          '.dots { list-style: disc; }',
    );
    expect(blockWith(blocks, '无标记一项').listMarker, isNull);
    expect(blockWith(blocks, '无标记二项').listMarker, isNull);
    expect(
      blockWith(blocks, '重新打开').listMarker,
      '○',
      reason: '子层的 disc 声明生效，符号随嵌套深度轮换',
    );
    // 缩进照旧累加（list-style 不影响盒模型）。
    expect(blockWith(blocks, '重新打开').style!.margin.left, closeTo(48, 0.01));
  });

  test('list-style: none 只作用当前层，兄弟列表不受影响', () async {
    final blocks = await blocksOf(
      '<ul class="plain"><li>静默</li></ul><ul><li>正常</li></ul>',
      'ul { margin: 4px 0; padding-left: 24px; } .plain { list-style: none; }',
    );
    expect(blockWith(blocks, '静默').listMarker, isNull);
    expect(blockWith(blocks, '正常').listMarker, '•');
  });

  test('嵌套有序列表按各自层号编号，外层序号不受内层影响', () async {
    final blocks = await blocksOf(
      '<ol><li>外层一<ol><li>内层一</li><li>内层二</li></ol></li>'
          '<li>外层二</li></ol>',
      'ol { margin: 4px 0; padding-left: 24px; }',
    );
    expect(blockWith(blocks, '外层一').listMarker, '1.');
    expect(blockWith(blocks, '内层一').listMarker, '1.');
    expect(blockWith(blocks, '内层二').listMarker, '2.');
    expect(blockWith(blocks, '外层二').listMarker, '2.');
    expect(blockWith(blocks, '内层一').style!.margin.left, closeTo(48, 0.01));
  });
}
