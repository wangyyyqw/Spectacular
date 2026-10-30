import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/layout/paginator.dart';

import 'support/css_chapter_book.dart';

const _css =
    'p { margin: 0; font-size: 16px; line-height: 20px; } '
    '.card { padding: 6px; border: 1px solid black; }';
final _longText = '跨页说明正文。' * 45;

List<PageContainer> _containers(List<PageContent> pages) => [
  for (final page in pages)
    for (final slice in page.slices)
      for (final fragment in slice.block.containers) fragment.container,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('普通带框容器每页续框留出上下装饰，不吞正文', () async {
    final source = await openCssChapter(
      body: '<div class="card"><p>$_longText</p></div>',
      css: _css,
      contentWidth: 200,
      contentHeight: 120,
    );
    final pages = await source.loadChapter(0);
    expect(pages.length, greaterThan(2));
    expect(_containers(pages).every((box) => box.cloneDecoration), isTrue);
    for (final page in pages) {
      expect(page.usedHeight, lessThanOrEqualTo(120.01));
      expect(page.slices.first.leadingExtent, greaterThanOrEqualTo(7));
      expect(page.slices.last.trailingExtent, greaterThanOrEqualTo(7));
    }
    final slices = pages.expand((page) => page.slices).toList();
    for (var i = 1; i < slices.length; i++) {
      expect(slices[i].startLine, slices[i - 1].endLine);
    }
    expect(slices.last.endLine, slices.last.block.layout.lineCount);
  });

  test('作者显式 slice 保留切开语义，显式 clone 可用于无框容器', () async {
    for (final value in ['slice', 'clone']) {
      final source = await openCssChapter(
        body: '<div class="card"><p>$_longText</p></div>',
        css:
            '$_css .card { box-decoration-break: $value; '
            '${value == 'clone' ? 'border: none;' : ''} }',
        contentWidth: 200,
        contentHeight: 120,
      );
      final pages = await source.loadChapter(0);
      expect(
        _containers(pages).every((box) => box.cloneDecoration),
        value == 'clone',
      );
      expect(pages[1].slices.first.leadingExtent, value == 'clone' ? 6 : 0);
    }
  });

  for (final entry in <String, String>{
    '浮动': '.special { float: left; width: 20px; }',
    '竖排': '.special { writing-mode: vertical-rl; height: 40px; }',
    '分栏': '.special { column-count: 2; }',
    '绝对定位': '.special { position: absolute; top: 0; }',
    '固定定位': '.special { position: fixed; top: 0; }',
  }.entries) {
    test('${entry.key}章节的普通卡片保持原 slice 策略', () async {
      final source = await openCssChapter(
        body:
            '<p class="special">特殊排版正文。</p>'
            '<div class="card"><p>$_longText</p></div>',
        css: '$_css ${entry.value}',
        contentWidth: 200,
        contentHeight: 120,
      );
      final containers = _containers(await source.loadChapter(0));
      expect(containers, isNotEmpty);
      expect(containers.every((box) => !box.cloneDecoration), isTrue);
      expect(
        containers.every((box) => identical(box, containers.first)),
        isTrue,
      );
    });
  }

  for (final table in [false, true]) {
    test('${table ? '标题表' : '短标题'}不单独留在页底', () async {
      final heading = table
          ? '<table><tr><td>效果名称</td></tr></table>'
          : '<span>效果名称</span>';
      // 用声明盒高固定前置占位，不能依赖阅读模式会回收的行高留白。
      final source = await openCssChapter(
        body:
            '<p class="filler">前置内容</p>'
            '<div class="card">$heading<p>$_longText</p></div>',
        css:
            '$_css .filler { height: 76px; line-height: 76px; } '
            'table, td { padding: 0; border: none; margin: 0; } '
            'td { line-height: 20px; }',
        contentWidth: 200,
        contentHeight: 120,
      );
      final pages = await source.loadChapter(0);
      expect(pages.first.slices, hasLength(1));
      expect(pages[1].slices.first.block.breakAfterAvoid, isTrue);
      expect(pages[1].slices.length, greaterThan(1));
      expect(pages[1].slices[1].block.layout.text, startsWith('跨页说明'));
    });
  }

  test('含长正文的单行表格不按短标题锁定后文', () async {
    final source = await openCssChapter(
      body:
          '<div class="card"><table><tr><td>$_longText</td></tr></table>'
          '<p>后续正文</p></div>',
      css: '$_css td { padding: 0; line-height: 20px; }',
      contentWidth: 200,
      contentHeight: 120,
    );
    final pages = await source.loadChapter(0);
    final table = pages.expand((page) => page.slices).first.block;
    expect(table.table, isNotNull);
    expect(table.breakAfterAvoid, isFalse);
  });

  test('表格预切为祖先装饰和表自身盒预留高度', () async {
    final source = await openCssChapter(
      body:
          '<div class="card"><table>'
          '${List.generate(12, (i) => '<tr><td>第$i行</td></tr>').join()}'
          '</table></div>',
      css:
          '$_css table { border-collapse: collapse; margin: 4px 0; } '
          'td { padding: 0; border: none; line-height: 20px; }',
      contentWidth: 200,
      contentHeight: 120,
    );
    final pages = await source.loadChapter(0);
    expect(pages.length, greaterThan(1));
    for (final page in pages) {
      expect(page.usedHeight, lessThanOrEqualTo(120.01));
    }
    final cells = [
      for (final page in pages)
        for (final slice in page.slices)
          for (final cell in slice.block.table!.cells) cell.layout.text,
    ];
    expect(cells, List.generate(12, (i) => '第$i行'));
  });
}
