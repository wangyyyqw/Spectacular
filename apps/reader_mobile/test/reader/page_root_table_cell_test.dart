import 'package:flutter_test/flutter_test.dart';

import 'support/css_chapter_book.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final alignment in ['middle', 'bottom']) {
    test('页面根 table-cell 的 $alignment 对齐覆盖完整制作说明块', () async {
      final source = await openCssChapter(
        body:
            '<div class="cell"><table><tr><td>来源</td></tr></table>'
            '<table><tr><td>制作说明</td></tr></table></div>',
        css:
            'body {display:table; height:100vh; margin:0; padding:0;} '
            '.cell {display:table-cell; vertical-align:$alignment;} '
            'table {margin:0; border-spacing:0;} td {padding:0;}',
      );
      addTearDown(source.close);
      final page = (await source.loadChapter(0)).single;
      final tables = page.slices
          .where((slice) => slice.block.table != null)
          .toList();
      expect(tables, hasLength(2));
      final natural = tables.fold(0.0, (sum, slice) => sum + slice.height);
      expect(page.slices.first.block.table, isNull);
      final top = page.slices.first.height;
      expect(
        top,
        closeTo((500 - natural) / (alignment == 'middle' ? 2 : 1), .01),
      );
      expect(page.usedHeight, lessThanOrEqualTo(500));
    });
  }

  test('未声明根表格的普通容器不受 table-cell 居中影响', () async {
    final source = await openCssChapter(
      body: '<div class="cell"><p>正常正文</p></div>',
      css: '.cell {display:table-cell; vertical-align:middle;} p {margin:0;}',
    );
    addTearDown(source.close);
    final page = (await source.loadChapter(0)).single;
    expect(page.slices.first.block.layout.text, '正常正文');
    expect(page.usedHeight, lessThan(50));
  });

  test('根盒不对称内边距参与 table-cell 居中位置', () async {
    final source = await openCssChapter(
      body: '<div class="cell"><p>居中正文</p></div>',
      css:
          'body {display:table; height:100vh; padding:20px 0 0; margin:0;} '
          '.cell {display:table-cell; vertical-align:middle;} p {margin:0;}',
    );
    addTearDown(source.close);
    final page = (await source.loadChapter(0)).single;
    final text = page.slices.singleWhere(
      (slice) => slice.block.layout.text == '居中正文',
    );
    expect(
      page.slices.first.height,
      closeTo(20 + (480 - text.height) / 2, .01),
    );
  });
}
