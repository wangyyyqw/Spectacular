import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/page_index.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/line_breaker.dart';

PageBlock _text(int lines, {bool heading = false, int group = 0}) {
  final style = ComputedStyle({
    'font-family': 'Ahem',
    'font-size': '10px',
    'line-height': '1',
    'white-space': 'pre',
    if (heading) 'break-after': 'avoid',
  });
  return PageBlock.styled(
    layout: TextLayoutEngine.layout(
      text: List.filled(lines, 'aa').join('\n'),
      style: style,
      maxWidth: 100,
    ),
    style: style,
    containingWidth: 100,
    groupId: group,
  );
}

List<PageBlock> _wrap(
  List<PageBlock> children, {
  double padding = 4,
  double before = 0,
  double after = 0,
}) {
  final box = PageContainer(
    style: ComputedStyle({
      'padding': '${padding}px',
      'border': '2px solid red',
    }),
    left: 0,
    width: 100,
    cloneDecoration: true,
  );
  return [
    for (var i = 0; i < children.length; i++)
      children[i].withSpacing(
        topInset: children[i].topInset + (i == 0 ? padding + 2 + before : 0),
        bottomInset:
            children[i].bottomInset +
            (i == children.length - 1 ? padding + 2 + after : 0),
        containers: [
          PageContainerFragment(
            container: box,
            startsHere: i == 0,
            endsHere: i == children.length - 1,
          ),
          ...children[i].containers,
        ],
      ),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('默认容差不侵占续框留白，逐行跨页无丢失', () {
    final pages = Paginator(pageHeight: 50)
        .measureChapter(blocks: _wrap([_text(7)]))
        .pages;
    expect(pages, hasLength(3));
    expect(pages.map((p) => p.slices.single.endLine), [3, 6, 7]);
    expect(pages.map((p) => p.slices.single.startLine), [0, 3, 6]);
    for (final page in pages) {
      expect(page.usedHeight, lessThanOrEqualTo(50));
      expect(page.slices.single.leadingExtent, 6);
      expect(page.slices.single.trailingExtent, 6);
    }
  });

  test('嵌套框累计上下装饰，外边距只在真实首尾出现', () {
    final blocks = _wrap(_wrap([_text(13)], padding: 2), before: 3, after: 5);
    final pages = Paginator(pageHeight: 70)
        .measureChapter(blocks: blocks)
        .pages;
    expect(pages, hasLength(3));
    expect(pages.map((p) => p.slices.single.startLine), [0, 4, 9]);
    expect(pages.map((p) => p.slices.single.leadingExtent), [13, 10, 10]);
    expect(pages.map((p) => p.slices.single.trailingExtent), [10, 10, 15]);
    expect(pages.last.slices.single.endLine, 13);
    expect(pages.every((p) => p.usedHeight <= p.pageHeight), isTrue);
  });

  test('同页段间不重复装饰，续页从段内开始仍补齐', () {
    final pages = Paginator(pageHeight: 50)
        .measureChapter(blocks: _wrap([_text(2), _text(3)]))
        .pages;
    expect(pages, hasLength(2));
    expect(pages.first.slices, hasLength(2));
    expect(pages.first.slices.last.leadingExtent, 0);
    expect(pages.first.slices.last.trailingExtent, 6);
    expect(pages.last.slices.single.startLine, 1);
    expect(pages.last.slices.single.leadingExtent, 6);
    expect(pages.last.usedHeight, 32);
  });

  for (final grouped in [false, true]) {
    test('${grouped ? '整组避断' : '标题跟随正文'}包含续框占高', () {
      final blocks = _wrap([
        _text(3),
        _text(1, heading: !grouped, group: grouped ? 1 : 0),
        _text(1, group: grouped ? 1 : 0),
        _text(1),
      ]);
      final pages = Paginator(pageHeight: 60)
          .measureChapter(blocks: blocks)
          .pages;
      expect(pages, hasLength(2));
      expect(pages.first.slices, hasLength(1));
      expect(pages.last.slices, hasLength(3));
      expect(pages.first.usedHeight, 42);
      expect(pages.last.usedHeight, 42);
    });
  }

  test('页索引重放恢复续框几何，并拒绝旧版边界', () {
    final blocks = _wrap(_wrap([_text(13)], padding: 2), before: 3, after: 5);
    final measured = Paginator(pageHeight: 70).measureChapter(blocks: blocks);
    final index = PageIndex.from(measured, blocks);
    final decoded = PageIndex.decode(index.encode())!;
    final replayed = PageIndex.apply(decoded, blocks, spineIndex: 0)!;
    for (var i = 0; i < measured.pages.length; i++) {
      final actual = replayed[i].slices.single;
      final expected = measured.pages[i].slices.single;
      expect(actual.startLine, expected.startLine);
      expect(actual.endLine, expected.endLine);
      expect(actual.leadingExtent, expected.leadingExtent);
      expect(actual.trailingExtent, expected.trailingExtent);
      expect(replayed[i].usedHeight, measured.pages[i].usedHeight);
    }
    final old = PageIndex(schemaVersion: 11, entries: index.entries);
    expect(PageIndex.decode(old.encode()), isNull);
    expect(PageIndex.apply(old, blocks, spineIndex: 0), isNull);
  });

  test('装饰与单行高于整页时仍可前进，不产生空页或死循环', () {
    final pages = Paginator(pageHeight: 30)
        .measureChapter(blocks: _wrap([_text(2)], padding: 40))
        .pages;
    expect(pages, hasLength(2));
    expect(pages.every((page) => page.slices.single.lines.length == 1), isTrue);
    expect(pages.last.slices.single.endLine, 2);
  });
}
