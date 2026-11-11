import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/epub/footnote.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/table_layout.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_ui/selection/selection.dart';
import 'package:reader_ui/selection/selection_support.dart';

const _cfi = 'epubcfi(/6/2!/4/2/1:0)';
final _style = ComputedStyle(const {
  'font-size': '16px',
  'line-height': '1.5',
  'font-family': 'Ahem',
});

PageBlock _block(
  String text, {
  String? cfi = _cfi,
  bool eligible = true,
  List<PageFootnote> footnotes = const [],
  List<InlineImageSpec> images = const [],
  TableRenderSpec? table,
}) => PageBlock(
  startCfi: cfi,
  style: _style,
  textRuleEligible: eligible,
  footnotes: footnotes,
  inlineImages: images,
  table: table,
  layout: TextLayoutEngine.layout(text: text, style: _style, maxWidth: 160),
);

PageContent _page(List<PageBlock> blocks, {int index = 0}) => PageContent(
  spineIndex: 0,
  pageIndex: index,
  pageHeight: 600,
  topPadding: 0,
  usedHeight: blocks.fold(0, (sum, block) => sum + block.layout.height),
  slices: [
    for (final block in blocks)
      PageBlockSlice(
        block: block,
        startLine: 0,
        endLine: block.layout.lineCount,
        height: block.layout.height,
      ),
  ],
);

TextHit _hit(PageLineBox line, int offset) => TextHit(
  lineBox: line,
  charOffset: offset,
  textOffset: line.textOffset + offset,
  atLineStart: offset == 0,
  atLineEnd: offset == line.text.length,
);

ReaderSelection _select(PageContent page, {int start = 0, int? end}) {
  final lines = TextHitTester.lineBoxes(page);
  return ReaderSelection.normalized(
    _hit(lines.first, start),
    _hit(lines.last, end ?? lines.last.text.length),
    pageIndex: page.pageIndex,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('软换行按原文拼接，不向摘录插入空格', () {
    final page = _page([_block('abcdefghijklmnopqrst')]);
    expect(TextHitTester.lineBoxes(page), hasLength(2));
    final result = ReaderSelectionSupport.capture([page], _select(page));
    expect(result?.quote, 'abcdefghijklmnopqrst');
    expect(result?.startCfi, _cfi);
    expect(result?.endCfi, 'epubcfi(/6/2!/4/2/1:20)');
  });

  test('摘录与前后文使用原文偏移', () {
    final page = _page([_block('abcdefghij')]);
    final result = ReaderSelectionSupport.capture([
      page,
    ], _select(page, start: 2, end: 6));
    expect(result?.quote, 'cdef');
    expect(result?.contextBefore, 'ab');
    expect(result?.contextAfter, 'ghij');
  });

  test('包含行内图片或脚注引用的选区被完整拒绝', () {
    final image = _page([_block('abc\uFFFCdef')]);
    final note = _page([
      _block(
        'abc1def',
        footnotes: const [
          PageFootnote(start: 3, end: 4, label: '1', kind: NoteKind.footnote),
        ],
      ),
    ]);
    expect(ReaderSelectionSupport.capture([image], _select(image)), isNull);
    expect(ReaderSelectionSupport.capture([note], _select(note)), isNull);
    expect(
      ReaderSelectionSupport.capture([note], _select(note, end: 3))?.quote,
      'abc',
    );
  });

  test('非法 CFI、空选区和越界端点不生成记录', () {
    final page = _page([_block('abcdef')]);
    final invalid = _page([_block('abcdef', cfi: 'invalid')]);
    expect(ReaderSelectionSupport.capture([invalid], _select(invalid)), isNull);
    expect(
      ReaderSelectionSupport.capture([page], _select(page, start: 3, end: 3)),
      isNull,
    );
    expect(
      ReaderSelectionSupport.capture([page], _select(page, end: 9)),
      isNull,
    );
  });

  test('仅包含空白的选区不生成记录', () {
    final page = _page([_block('abc def')]);
    expect(
      ReaderSelectionSupport.capture([page], _select(page, start: 3, end: 4)),
      isNull,
    );
  });

  test('跨块选区中间存在无法映射的文字时不创建半成品', () {
    final page = _page([
      _block('abc'),
      _block('中间文字', cfi: null),
      _block('def', cfi: 'epubcfi(/6/2!/4/2/5:0)'),
    ]);
    expect(ReaderSelectionSupport.capture([page], _select(page)), isNull);
  });

  test('跨块选区跳过独立图片、表格或页眉时统一拒绝', () {
    final forbidden = [
      _block('', images: const [InlineImageSpec(offset: 0, url: 'image.png')]),
      _block('页眉', eligible: false),
      _block(
        '',
        table: const TableRenderSpec(
          cells: [],
          columnXs: [0, 100],
          rowYs: [0, 30],
          tableWidth: 100,
        ),
      ),
    ];
    for (final block in forbidden) {
      final page = _page([
        _block('abc'),
        block,
        _block('def', cfi: 'epubcfi(/6/2!/4/2/5:0)'),
      ]);
      expect(ReaderSelectionSupport.capture([page], _select(page)), isNull);
    }
  });

  test('多列块保留原偏移，重叠部分只拼接一次', () {
    final page = _page([
      _block('abcdefghij'),
      _block('fghijklmno', cfi: 'epubcfi(/6/2!/4/2/1:5)'),
    ]);
    expect(
      ReaderSelectionSupport.capture([page], _select(page))?.quote,
      'abcdefghijklmno',
    );
  });

  test('多列原文缺口或重叠文字不一致时拒绝错误区间', () {
    for (final second in [
      _block('klmno', cfi: 'epubcfi(/6/2!/4/2/1:11)'),
      _block('XXXXXX', cfi: 'epubcfi(/6/2!/4/2/1:5)'),
    ]) {
      final page = _page([_block('abcdefghij'), second]);
      expect(ReaderSelectionSupport.capture([page], _select(page)), isNull);
    }
  });

  test('跨页同块去重，起止页之间保留完整原文', () {
    final block = _block('abcdefghijklmnopqrst');
    final pages = Paginator(pageHeight: 24)
        .measureChapter(blocks: [block])
        .pages;
    expect(pages, hasLength(2));
    final first = TextHitTester.lineBoxes(pages.first).first;
    final last = TextHitTester.lineBoxes(pages.last).last;
    final selection = ReaderSelection.spanning(
      start: _hit(first, 2),
      startPageIndex: 0,
      end: _hit(last, last.text.length - 2),
      endPageIndex: 1,
    );
    expect(
      ReaderSelectionSupport.capture(pages, selection)?.quote,
      'cdefghijklmnopqr',
    );
  });

  test('UTF-16 代理对不可从中间截断', () {
    final page = _page([_block('a😀b')]);
    expect(
      ReaderSelectionSupport.capture([
        page,
      ], _select(page, start: 1, end: 3))?.quote,
      '😀',
    );
    expect(
      ReaderSelectionSupport.capture([page], _select(page, start: 1, end: 2)),
      isNull,
    );
  });
}
