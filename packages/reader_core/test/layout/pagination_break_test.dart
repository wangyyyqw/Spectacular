import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/cascade.dart';
import 'package:reader_core/css/parser.dart';
import 'package:reader_core/css/selector.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/parser/document_parser.dart';

ComputedStyle _style(Map<String, String> overrides) =>
    ComputedStyle(<String, String>{
      'font-size': '16px',
      'line-height': '1.5',
      'font-family': 'Ahem',
      'color': '#000000',
      ...overrides,
    });

PageBlock _block(String text, ComputedStyle style) => PageBlock.styled(
  layout: TextLayoutEngine.layout(text: text, style: style, maxWidth: 180),
  style: style,
  containingWidth: 180,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('page-break-before: always 在新页开始', () {
    final page = Paginator(pageHeight: 200)
        .measureChapter(
          blocks: [
            _block('aa', _style(const {})),
            _block('bb', _style(const {'page-break-before': 'always'})),
          ],
        )
        .pages;
    expect(page, hasLength(2));
    expect(page[0].slices.single.block.layout.text, 'aa');
    expect(page[1].slices.single.block.layout.text, 'bb');
  });

  test('page-break-after: always 在其后换页', () {
    final page = Paginator(pageHeight: 200)
        .measureChapter(
          blocks: [
            _block('aa', _style(const {'page-break-after': 'always'})),
            _block('bb', _style(const {})),
          ],
        )
        .pages;
    expect(page, hasLength(2));
    expect(page[0].slices.single.block.layout.text, 'aa');
    expect(page[1].slices.single.block.layout.text, 'bb');
  });

  test('break-inside: avoid 能整块放下时不拆开', () {
    final pages = Paginator(pageHeight: 72)
        .measureChapter(
          blocks: [
            _block('aa', _style(const {})),
            _block('bb\ncc\ndd', _style(const {'break-inside': 'avoid'})),
          ],
        )
        .pages;
    expect(pages, hasLength(2));
    expect(pages[0].slices, hasLength(1));
    expect(pages[0].slices.single.block.layout.text, 'aa');
    expect(pages[1].slices, hasLength(1));
    expect(pages[1].slices.single.endLine, 3, reason: '整块 3 行都在第 2 页');
  });

  test('break-inside: avoid 但块高于整页时仍然拆分', () {
    final pages = Paginator(pageHeight: 72)
        .measureChapter(
          blocks: [
            _block('aa\nbb\ncc\ndd', _style(const {'break-inside': 'avoid'})),
          ],
        )
        .pages;
    expect(pages, hasLength(2), reason: '无法整块放下，退回按行拆分');
    // 电子书排版不做孤行/寡行约束（产品决策）：4 行块在 3 行容量的页上
    // 直接断成 3+1。
    expect(pages[0].slices.single.endLine, 3);
    expect(pages[1].slices.single.startLine, 3);
  });

  test('书内孤行寡行及 important 不把 3+1 改成 2+2', () async {
    final element = DocumentParser.parse(
      xhtml: '<html><body><p id="prose">正文</p></body></html>',
      spineIndex: 0,
    ).elementById('prose')!;
    final style = Cascade.compute(
      element: ParsedElementView.wrap(element, {}),
      ancestors: const [],
      rules: const [],
      inlineDeclarations: CssParser.parseInlineDeclarations(
        'font-family: Ahem; font-size: 16px; line-height: 1.5; '
        'orphans: 2 !important; widows: 2 !important;',
      ),
    );
    final blocks = [_block('aa\nbb\ncc\ndd', style)];
    final paginator = Paginator(pageHeight: 72);
    final measured = paginator.measureChapter(blocks: blocks).pages;
    final streamed = await paginator.paginate(blocks: blocks).toList();
    for (final pages in [measured, streamed]) {
      expect(pages, hasLength(2));
      expect(pages.first.slices.single.endLine, 3);
      expect(pages.last.slices.single.startLine, 3);
      expect(pages.last.slices.single.endLine, 4);
    }
  });

  test('样式驱动：PageBlock.styled 读取分页与 break-inside 标记', () {
    final style = _style(const {
      'break-before': 'page',
      'break-after': 'page',
      'page-break-inside': 'avoid',
    });
    final block = _block('aa', style);
    expect(block.pageBreakBefore, isTrue);
    expect(block.pageBreakAfter, isTrue);
    expect(block.breakInsideAvoid, isTrue);

    final auto = _block('aa', _style(const {}));
    expect(auto.pageBreakBefore, isFalse);
    expect(auto.pageBreakAfter, isFalse);
    expect(auto.breakInsideAvoid, isFalse);
  });

  // ---- avoid 档位（P3-22：标题不落页底）----

  test('break-after: avoid：标题不孤立在页底，与后文同页', () {
    // 页高 72：首段 2 行（48），标题只剩 24 可放——放完标题后剩余 0，
    // 不足正文首行 → avoid 把标题推到下一页与正文同页（标题不落页底）。
    final pages = Paginator(pageHeight: 72)
        .measureChapter(
          blocks: [
            _block('p1\np2', _style(const {})),
            _block('标题', _style(const {'break-after': 'avoid'})),
            _block('bb\ncc\ndd', _style(const {})),
          ],
        )
        .pages;
    expect(pages, hasLength(3));
    expect(pages[0].slices.single.block.layout.text, 'p1\np2');
    expect(pages[1].slices.first.block.layout.text, '标题',
        reason: '标题推到下一页与正文同页');
    expect(pages[2].slices.first.block.layout.text, 'bb\ncc\ndd');
  });

  test('break-after: avoid：后文首行放得下时不推页', () {
    final pages = Paginator(pageHeight: 200)
        .measureChapter(
          blocks: [
            _block('aa', _style(const {'break-after': 'avoid'})),
            _block('bb', _style(const {})),
          ],
        )
        .pages;
    expect(pages, hasLength(1));
    expect(pages.single.slices.first.block.layout.text, 'aa');
    expect(pages.single.slices.last.block.layout.text, 'bb');
  });

  test('avoid 优先级低于强制断页：avoid + before:always 仍强制断', () {
    final pages = Paginator(pageHeight: 96)
        .measureChapter(
          blocks: [
            _block('aa', _style(const {'break-after': 'avoid'})),
            _block('bb', _style(const {'page-break-before': 'always'})),
          ],
        )
        .pages;
    expect(pages, hasLength(2));
    expect(pages[0].slices.single.block.layout.text, 'aa',
        reason: '强制断页优先生效，标题留在首页');
  });
}
