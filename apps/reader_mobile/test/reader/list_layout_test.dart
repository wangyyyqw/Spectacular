import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';

import 'support/css_chapter_book.dart';

/// 列表几何（g）：缩进跟列表容器的级联盒走、容器段距由首末项承担、
/// `list-style-position: inside` 的首行让出标记宽。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<List<PageBlock>> blocksOf(String body, String css) async {
    final source = await openCssChapter(
      body: body,
      css: css,
      contentWidth: 300,
      contentHeight: 800,
    );
    final pages = await source.loadChapter(0);
    return [for (final slice in pages.expand((page) => page.slices)) slice.block];
  }

  test('li 缩进跟随 ul 的 padding-left（不再写死 40px）', () async {
    final blocks = await blocksOf(
      '<ul><li>列表项一</li></ul>',
      'ul { padding-left: 24px; margin: 0; }',
    );
    final item = blocks.firstWhere(
      (block) => block.layout.text.startsWith('列表项一'),
    );
    expect(item.style!.margin.left, closeTo(24, 0.01));
    expect(item.listMarker, isNotNull);
  });

  test('嵌套列表按层累加缩进', () async {
    final blocks = await blocksOf(
      '<ul><li>外层项<ul><li>内层项</li></ul></li></ul>',
      'ul { padding-left: 20px; margin: 0; }',
    );
    final outer = blocks.firstWhere(
      (block) => block.layout.text.startsWith('外层项'),
    );
    final inner = blocks.firstWhere(
      (block) => block.layout.text.startsWith('内层项'),
    );
    expect(outer.style!.margin.left, closeTo(20, 0.01));
    expect(inner.style!.margin.left, closeTo(40, 0.01));
  });

  test('列表容器外边距落到首项的段前距', () async {
    final blocks = await blocksOf(
      '<p>前一段</p><ul><li>列表项</li></ul>',
      'p { margin: 0; } ul { margin: 8px 0; padding-left: 20px; }',
    );
    final item = blocks.firstWhere(
      (block) => block.layout.text.startsWith('列表项'),
    );
    expect(item.spaceBefore, greaterThanOrEqualTo(8));
  });

  test('list-style-position: inside 首行让出标记宽，后续行回到内容边', () async {
    final blocks = await blocksOf(
      '<ul class="in"><li>inside 标记在内容框内，文字换行会绕到标记下方</li></ul>',
      'ul { padding-left: 20px; margin: 0; } '
          '.in { list-style-position: inside; }',
    );
    final item = blocks.firstWhere(
      (block) => block.layout.text.startsWith('inside'),
    );
    final lines = item.layout.lines;
    expect(lines.length, greaterThan(1), reason: '需要多行才能观察后续行');
    expect(lines.first.offsetX, greaterThan(0), reason: '首行让出标记宽');
    expect(
      lines.skip(1).map((line) => line.offsetX),
      everyElement(0),
      reason: '后续行回到内容左缘',
    );
    // 计算样式里的 text-indent 保持 0（缩进来自标记，不是 text-indent）。
    expect(item.style!.textIndent, 0);
  });

  test('outside 每项都有标记且首行不缩进', () async {
    final blocks = await blocksOf(
      '<ul><li>甲项</li><li>乙项</li></ul>',
      'ul { padding-left: 20px; margin: 0; }',
    );
    final items = blocks
        .where((block) => block.layout.text.contains('项'))
        .toList();
    expect(items, hasLength(2));
    for (final item in items) {
      expect(item.listMarker, isNotNull);
      expect(item.layout.lines.first.offsetX, 0);
      expect(item.style!.listStylePosition, CssListStylePosition.outside);
    }
  });
}
