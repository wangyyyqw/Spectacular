import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/line_breaker.dart';

/// P7-26：整组不可切——同组连续块是原子单元（图+题注永不分离）；
/// 组放不下当前页时整体下移；组高于整页时按序切。
ComputedStyle _style() => ComputedStyle(const <String, String>{
  'font-size': '16px',
  'line-height': '1.5',
  'font-family': 'Ahem',
});

PageBlock _block(String text, {int groupId = 0}) {
  final layout = TextLayoutEngine.layout(
    text: text,
    style: _style(),
    maxWidth: 128,
  );
  return PageBlock.styled(
    layout: layout,
    style: _style(),
    containingWidth: 128,
    groupId: groupId,
  );
}

String _visibleText(PageContent page) {
  final buffer = StringBuffer();
  for (final slice in page.slices) {
    for (var i = slice.startLine; i < slice.endLine; i++) {
      final line = slice.block.layout.lines[i];
      buffer.write(slice.block.layout.text.substring(line.start, line.end));
    }
  }
  return buffer.toString();
}

void main() {
  test('组放不下当前页：整组下移到新页（图与题注同页）', () {
    final blocks = <PageBlock>[
      _block('前面占位段落甲'),
      _block('前面占位段落乙'),
      _block('图片内容区', groupId: 1),
      _block('图 1：题注', groupId: 1),
      _block('后续段落'),
    ];
    final result = Paginator(pageHeight: 72).measureChapter(blocks: blocks);
    // 每页 3 行（72/24）：前两段占 2 页（各 2 行…实际按容差），分组块
    // 需 2 行。断言核心：图片块与题注块出现在同一页。
    final groupPages = <int, Set<int>>{};
    for (final page in result.pages) {
      for (final slice in page.slices) {
        final gid = slice.block.groupId;
        if (gid != 0) {
          groupPages.putIfAbsent(gid, () => <int>{}).add(page.pageIndex);
        }
      }
    }
    expect(groupPages[1], hasLength(1), reason: '同组块必须落在同一页');
    final groupPageText = _visibleText(
      result.pages[groupPages[1]!.first],
    );
    expect(groupPageText, contains('图片内容区'));
    expect(groupPageText, contains('图 1：题注'));
  });

  test('无组标记的块按原逻辑切分（对照）', () {
    final blocks = <PageBlock>[
      _block('第一段内容第一行', ),
      _block('第二段内容第二行'),
      _block('第三段内容第三行'),
    ];
    final result = Paginator(pageHeight: 48).measureChapter(blocks: blocks);
    expect(result.pages.length, greaterThanOrEqualTo(2));
    expect(result.truncated, isFalse);
  });

  test('组高于整页：按序切不强制（避免空页与死循环）', () {
    final blocks = <PageBlock>[
      _block('组内第一块占两行高吗', groupId: 1),
      _block('组内第二块占两行高吗', groupId: 1),
      _block('组内第三块占两行高吗', groupId: 1),
    ];
    // 组高 72 > 页高 48 → 按序切。
    final result = Paginator(pageHeight: 48).measureChapter(blocks: blocks);
    expect(result.pages, isNotEmpty);
    expect(result.truncated, isFalse);
    // 组内容全部出现（跨页但无丢失）。
    final all = result.pages.map(_visibleText).join();
    expect(all, contains('组内第一块'));
    expect(all, contains('组内第三块'));
  });

  test('组首在页首时不再多余收页（不产生空页）', () {
    final blocks = <PageBlock>[
      _block('图片内容区', groupId: 1),
      _block('图 1：题注', groupId: 1),
    ];
    final result = Paginator(pageHeight: 72).measureChapter(blocks: blocks);
    expect(result.pages, hasLength(1));
    expect(_visibleText(result.pages.first), contains('图片内容区'));
  });
}
