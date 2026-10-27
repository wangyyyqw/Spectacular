import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';

/// 分页孤行/寡行（CSS 2.1 §13.3）：块被切开时本页至少 orphans 行、
/// 下一页至少 widows 行。
ComputedStyle _style(Map<String, String> overrides) =>
    ComputedStyle(<String, String>{
      'font-size': '16px',
      'line-height': '1',
      'font-family': 'Ahem',
      ...overrides,
    });

/// 硬换行保证行数可控（每行 1 字，行高 16）。
PageBlock _block(String text, {Map<String, String> overrides = const {}}) {
  final style = _style(overrides);
  return PageBlock.styled(
    layout: TextLayoutEngine.layout(
      text: text,
      style: style,
      maxWidth: 16,
    ),
    style: style,
    containingWidth: 16,
  );
}

List<int> _linesPerPage(List<PageContent> pages) => [
  for (final page in pages)
    for (final slice in page.slices) slice.endLine - slice.startLine,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('默认 widows=2：5 行容量的页上 6 行段落断成 4+2', () {
    final block = _block('a\nb\nc\nd\ne\nf');
    expect(block.layout.lineCount, 6);
    // 页高 80 → 第 1 页能排 5 行 → 若不控制会断成 5+1（页尾 1 行）。
    final pages = Paginator(pageHeight: 80).measureChapter(blocks: [block]).pages;
    expect(_linesPerPage(pages), [4, 2], reason: '允许 5+1 会产生寡行');
  });

  test('widows: 3 时把两三行推到下一页', () {
    final block = _block('a\nb\nc\nd\ne\nf', overrides: {'widows': '3'});
    final pages = Paginator(pageHeight: 80).measureChapter(blocks: [block]).pages;
    expect(_linesPerPage(pages), [3, 3]);
  });

  test('orphans: 4 时页尾只剩 3 行则整块下移', () {
    // 先放一个占 2 行的块，再放 6 行块：第 1 页剩余只够 3 行。
    final first = _block('x\ny');
    final second = _block('a\nb\nc\nd\ne\nf', overrides: {'orphans': '4'});
    final pages = Paginator(
      pageHeight: 80,
    ).measureChapter(blocks: [first, second]).pages;
    // 第 1 页只剩 3 行 < orphans 4 → 整块推到第 2 页；96 高的 6 行块在
    // 80 高的页上断成 4+2（widows 2 满足）。
    expect(_linesPerPage(pages), [2, 4, 2], reason: '孤行约束应把整块推到下一页');
  });

  test('约束不可满足时不产生空页死循环', () {
    // 页高只放得下 1 行：orphans=3 无法满足，必须仍能分页。
    final block = _block('a\nb\nc\nd\ne\nf', overrides: {'orphans': '3', 'widows': '3'});
    final pages = Paginator(pageHeight: 16).measureChapter(blocks: [block]).pages;
    expect(pages.length, 6);
    expect(_linesPerPage(pages), [1, 1, 1, 1, 1, 1]);
  });
}
