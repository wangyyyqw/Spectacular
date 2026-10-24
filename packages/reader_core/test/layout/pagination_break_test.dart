import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout.dart';

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
    expect(pages[0].slices.single.endLine, 3);
    expect(pages[1].slices.single.startLine, 3);
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
}
