import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/layout/float_occupancy.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/page_background.dart';
import 'package:reader_core/layout/page_index.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/table_layout.dart';
import 'package:reader_core/layout/text_layout_cache.dart';
import 'package:reader_core/text/reader_text_overlay.dart';
import 'package:reader_core/epub/chapter/book_fonts.dart';
import 'package:reader_core/epub/chapter/book_resources.dart';
import 'package:reader_core/epub/chapter/chapter_layout_job.dart';
import 'package:reader_core/epub/chapter/chapter_pagination.dart';
import 'package:reader_core/source/chapter_source.dart';

final _base = ComputedStyle({
  'font-size': '16px',
  'line-height': '1.25',
  'margin': '0',
});
const _sentence = '逐行绕排保持原文坐标，浮动结束后恢复整行宽度。';
late BookFontView _fonts;

Future<BookFontView> _fontView() async {
  final archive = Archive();
  const files = {
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml': '''
<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">
<rootfiles><rootfile full-path="content.opf"
media-type="application/oebps-package+xml"/></rootfiles></container>''',
    'content.opf': '''
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:identifier id="id">page-layout</dc:identifier><dc:title>分页</dc:title>
<dc:language>zh</dc:language></metadata><manifest>
<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>
</manifest><spine><itemref idref="c"/></spine></package>''',
    'c.xhtml': '<html xmlns="http://www.w3.org/1999/xhtml"><body/></html>',
  };
  for (final entry in files.entries) {
    final bytes = utf8.encode(entry.value);
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  final document = (await openEpub(
    ZipEncoder().encodeBytes(archive),
    verifyCrc: false,
  )).document!;
  final resources = BookResources(document);
  final fonts = BookFonts(resources, onFontsChanged: (_) {});
  final view = fonts.freeze();
  fonts.close();
  resources.close();
  return view;
}

LayoutSnapshot _snapshot({bool trim = false, double topInset = 24}) =>
    LayoutSnapshot(
      spineIndex: 2,
      key: '分页测试',
      contentVersion: '1',
      generation: 1,
      width: 220,
      height: 100,
      pageHeight: 160,
      topInset: topInset,
      baseStyle: _base,
      overrides: const ReaderOverrides(),
      textOverlays: ReaderTextOverlayResolver(const []),
      fontDependency: _fonts.dependency(const {}),
      fonts: _fonts,
      fontFamilies: const {},
      trimTextEdges: trim,
    );

LayoutBudget _budget() => LayoutBudget(
  priority: ChapterLayoutPriority.reading,
  isCurrent: () => true,
);

ChapterPageLayout _layout({bool trim = false}) =>
    ChapterPageLayout(_snapshot(trim: trim), _budget(), TextLayoutCache());

PageBlock _paragraph(String text, {ComputedStyle? style, double width = 220}) =>
    PageBlock.styled(
      layout: TextLayoutEngine.layout(
        text: text,
        style: style ?? _base,
        maxWidth: width,
        hasGlyph: _fonts.hasGlyph,
      ),
      style: style ?? _base,
      containingWidth: width,
    );

TextLayoutResult _boxLayout(double width, double height) => TextLayoutResult(
  text: '',
  lines: const [],
  width: width,
  height: height,
  maxWidth: width,
  runs: const [],
);

PageBlock _float({FloatSide side = FloatSide.left, double height = 40}) =>
    PageBlock(layout: _boxLayout(70, height), floatSide: side);

List<Object?> _geometry(List<PageContent> pages) => [
  for (final page in pages)
    [
      page.spineIndex,
      page.pageIndex,
      page.usedHeight,
      page.pageHeight,
      page.topPadding,
      page.background,
      [for (final slice in page.slices) _sliceGeometry(slice)],
    ],
];

List<Object?> _sliceGeometry(PageBlockSlice slice) => [
  slice.startLine,
  slice.endLine,
  slice.height,
  slice.leadingExtent,
  slice.trailingExtent,
  slice.textTopTrim,
  slice.textBottomTrim,
  slice.leftInset,
  slice.overlay,
  slice.absoluteTop,
  slice.block.height,
  slice.block.layout.text,
  slice.block.layout.width,
  slice.block.layout.maxWidth,
  slice.block.effectiveOpacity,
  [for (final line in slice.lines) _lineGeometry(line)],
];

List<Object?> _lineGeometry(LineBox line) => [
  line.start,
  line.end,
  line.top,
  line.height,
  line.baseline,
  line.width,
  line.indent,
  line.offsetX,
  line.justifyExtra,
  line.justifyMode,
  line.isLastLine,
  line.isHardBreak,
  line.ellipsized,
  line.ellipsisWidth,
  line.hyphenated,
  line.hyphenWidth,
  [
    for (final box in line.inlineBoxes)
      [box.offset, box.left, box.width, box.height, box.ascent, box.descent],
  ],
];

class _CancellingBudget extends LayoutBudget {
  _CancellingBudget(this.shouldCancel)
    : super(priority: ChapterLayoutPriority.reading, isCurrent: () => true);

  final bool Function(int) shouldCancel;
  int checkpoints = 0;

  @override
  Future<void> checkpoint({bool force = false}) async {
    checkpoints += 1;
    if (shouldCancel(checkpoints)) cancel();
    await super.checkpoint(force: true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => _fonts = await _fontView());

  for (final trim in [false, true]) {
    test('普通异步分页与同步分页、索引回放几何完全一致：trim=$trim', () async {
      final blocks = [
        _paragraph('短标题', style: _base.withTypography(fontSize: 20)),
        _paragraph(_sentence * 12),
        _paragraph(_sentence * 4),
      ];
      final synchronous = Paginator(
        pageWidth: 220,
        pageHeight: 100,
        trimTextEdges: trim,
      ).measureChapter(blocks: blocks, spineIndex: 2).pages;
      final first = await _layout(trim: trim).paginate(blocks, const [], null);
      expect(first.pages.length, greaterThan(1));
      expect(_geometry(first.pages), _geometry(synchronous));
      expect(first.pageIndex, isNotNull);
      expect(first.indexDiagnostic, isNull);
      final replay = await _layout(trim: trim)
          .paginate(blocks, const [], null, pageIndex: first.pageIndex);
      expect(_geometry(replay.pages), _geometry(first.pages));
      expect(replay.pageIndex, same(first.pageIndex));
      expect(() => first.pages.clear(), throwsUnsupportedError);
    });
  }

  test('损坏和越界页索引回退到同一分页结果并返回诊断', () async {
    final blocks = [_paragraph(_sentence * 8)];
    final expected = await _layout().paginate(blocks, const [], null);
    final badBoundary = PageIndex(
      schemaVersion: PageIndex.currentSchemaVersion,
      entries: const [
        PageIndexEntry(
          blockIndex: 99,
          startLine: 0,
          usedHeight: 20,
          pageHeight: 100,
          topPadding: 0,
        ),
      ],
    ).encode();
    final cases = {
      'indexCorrupted': Uint8List.fromList([1, 2, 3]),
      'indexSchemaMismatch': badBoundary,
    };
    for (final entry in cases.entries) {
      final result = await _layout().paginate(
        blocks,
        const [],
        null,
        pageIndex: entry.value,
      );
      expect(_geometry(result.pages), _geometry(expected.pages));
      expect(result.indexDiagnostic, entry.key);
      expect(PageIndex.decode(result.pageIndex!), isNotNull);
    }
  });

  test('声明盒高、裁剪和绝对定位章节不回放或生成索引', () async {
    final text = _paragraph(_sentence * 4);
    final cases = [
      PageBlock(layout: text.layout, declaredContentHeight: 40),
      PageBlock(
        layout: text.layout,
        style: ComputedStyle({'height': '40px', 'overflow': 'hidden'}),
        declaredContentHeight: 40,
      ),
      PageBlock(layout: _boxLayout(20, 20), absolute: true, absoluteTop: 5),
    ];
    for (final block in cases) {
      final result = await _layout().paginate(
        [block],
        const [],
        null,
        pageIndex: Uint8List.fromList([1, 2, 3]),
      );
      expect(result.pageIndex, isNull);
      expect(result.indexDiagnostic, isNull);
      expect(result.pages, isNotEmpty);
    }
  });

  test('固定覆盖使用页面基准高度，背景不改变正文分页', () async {
    final blocks = [_paragraph(_sentence * 8)];
    final fixed = PageBlock(
      layout: _boxLayout(40, 20),
      style: ComputedStyle({
        'position': 'fixed',
        'width': '40px',
        'height': '20px',
        'bottom': '10%',
        'right': '5px',
      }),
    );
    const background = PageBackground(imageUrl: 'background.png');
    final plain = await _layout().paginate(blocks, const [], null);
    final result = await _layout().paginate(blocks, [fixed], background);
    expect(result.pages.length, plain.pages.length);
    for (var i = 0; i < result.pages.length; i++) {
      final page = result.pages[i];
      expect(page.usedHeight, plain.pages[i].usedHeight);
      expect(page.background, same(background));
      final overlay = page.slices.where((slice) => slice.overlay).single;
      expect(overlay.absoluteTop, 124);
      expect(overlay.leftInset, 175);
      expect(overlay.height, 20);
    }
    final replay = await _layout().paginate(
      blocks,
      [fixed],
      background,
      pageIndex: result.pageIndex,
    );
    expect(_geometry(replay.pages), _geometry(result.pages));
    for (final page in replay.pages) {
      expect(page.slices.where((slice) => slice.overlay), hasLength(1));
    }
  });

  test('纯装饰章节补空页，章首出血图回收冻结的顶部内缩', () async {
    const background = PageBackground(imageUrl: 'decoration.png');
    final empty = await _layout().paginate(const [], const [], background);
    expect(empty.pages, hasLength(1));
    expect(empty.pages.single.slices, isEmpty);
    expect(empty.pages.single.background, same(background));
    final blocks = [
      PageBlock(
        layout: _boxLayout(220, 120),
        style: ComputedStyle({'background-image': 'url(cover.png)'}),
        bleedTop: true,
      ),
      _paragraph(_sentence),
    ];
    final result = await _layout().paginate(blocks, const [], null);
    final synchronous = Paginator(
      pageWidth: 220,
      pageHeight: 100,
      topPadding: -24,
    ).measureChapter(blocks: blocks, spineIndex: 2).pages;
    expect(_geometry(result.pages), _geometry(synchronous));
    expect(result.pages.first.topPadding, -24);
    expect(result.pages.skip(1).every((page) => page.topPadding == 0), isTrue);
  });

  test('浮动章首出血图回收顶部内缩，图片绕排位置随正文同步上移', () async {
    final blocks = [
      PageBlock(
        layout: _boxLayout(220, 60),
        style: ComputedStyle({'background-image': 'url(header.png)'}),
        bleedTop: true,
      ),
      _paragraph('标题'),
      _float(height: 10),
      _paragraph(_sentence * 14),
    ];
    final result = await _layout().paginate(blocks, const [], null);
    final first = result.pages.first;
    expect(first.topPadding, -24);
    expect(first.pageHeight, 100);
    final image = first.slices.singleWhere((slice) => slice.overlay);
    expect(image.absoluteTop, 60 + blocks[1].height - 24);
    expect(first.usedHeight + first.topPadding, lessThanOrEqualTo(100));
    expect(result.pages.length, greaterThan(1));
    expect(result.pages.skip(1).every((page) => page.topPadding == 0), isTrue);
  });

  test('出血图后的同组浮动图片和图注同步上移，不减少首屏可用高度', () async {
    final result = await _layout().paginate([
      PageBlock(
        layout: _boxLayout(220, 40),
        style: ComputedStyle({'background-image': 'url(header.png)'}),
        bleedTop: true,
      ),
      ..._groupedFloats(),
    ], const [], null);
    expect(result.pages, hasLength(1));
    final page = result.pages.single;
    final floats = page.slices.where((slice) => slice.overlay).toList();
    expect(floats.map((slice) => slice.absoluteTop), [16, 36, 16, 36]);
    expect(page.usedHeight, 100);
    expect(page.topPadding, -24);
    expect(page.pageHeight, 100);
  });

  test('绕排跨页恢复全宽，续行不重复缩进且原文坐标连续', () async {
    final text = _sentence * 14;
    final style = _base.withTypography(textIndent: 32);
    final result = await _layout().paginate(
      [_float(), _paragraph(text, style: style)],
      const [],
      null,
    );
    expect(result.pageIndex, isNull);
    final slices = result.pages.expand((page) => page.slices).toList();
    expect(slices.where((slice) => slice.overlay), hasLength(1));
    final lines = slices
        .where((slice) => !slice.overlay)
        .expand((s) => s.lines)
        .toList();
    expect(lines.first.indent, 32);
    expect(lines.skip(1).every((line) => line.indent == 0), isTrue);
    expect(lines.any((line) => line.offsetX > 0), isTrue);
    expect(lines.any((line) => line.offsetX == 0), isTrue);
    expect(lines.first.start, 0);
    expect(lines.last.end, text.length);
    for (var i = 1; i < lines.length; i++) {
      expect(lines[i].start, lines[i - 1].end);
    }
  });

  test('绕排重测保留行内盒和注音的原文偏移', () async {
    final text = '甲乙\uFFFC丙丁${_sentence * 4}';
    const boxes = [
      InlineBoxSpec(
        offset: 2,
        width: 12,
        height: 16,
        replacesPlaceholder: true,
      ),
    ];
    const rubies = [RubyAnnotation(start: 0, end: 2, text: 'jiayi')];
    final block = PageBlock(
      layout: TextLayoutEngine.layout(
        text: text,
        style: _base,
        maxWidth: 220,
        inlineBoxes: boxes,
        rubies: rubies,
        hasGlyph: _fonts.hasGlyph,
      ),
      style: _base,
      inlineImages: const [InlineImageSpec(offset: 2, url: 'inline.png')],
      rubies: rubies,
    );
    final result = await _layout().paginate([_float(), block], const [], null);
    final flow = result.pages
        .expand((page) => page.slices)
        .where((s) => !s.overlay);
    final placements = flow
        .expand((s) => s.lines)
        .expand((line) => line.inlineBoxes);
    expect(placements.map((box) => box.offset), [2]);
    expect(placements.single.spec.offset, 2);
    expect(flow.first.block.inlineImages.single.offset, 2);
    expect(flow.first.block.rubies!.single.start, 0);
    expect(flow.first.block.rubies!.single.end, 2);
  });

  test('同组浮动竖向堆叠、下一组并排，clear 推到整组底边', () async {
    final blocks = _groupedFloats();
    final result = await _layout().paginate(blocks, const [], null);
    final slices = result.pages.first.slices;
    final floats = slices.where((slice) => slice.overlay).toList();
    expect(floats, hasLength(4));
    expect(floats[1].absoluteTop, floats[0].absoluteTop! + 20);
    expect(floats[2].absoluteTop, floats[0].absoluteTop);
    expect(floats[2].leftInset - floats[0].leftInset, 110);
    final spacer = slices.firstWhere(
      (s) => !s.overlay && s.block.layout.text.isEmpty,
    );
    expect(spacer.height, 40);
    expect(result.pages.first.usedHeight, 60);
  });

  test('浮动流声明盒高保留裁剪高度，表格按余高拆行并重复表头', () async {
    final style = ComputedStyle({
      ..._base.values,
      'height': '30px',
      'overflow': 'hidden',
    });
    final clipped = _paragraph(_sentence * 4, style: style);
    final result = await _layout().paginate(
      [_float(), clipped],
      const [],
      null,
    );
    final slice = result.pages.first.slices.firstWhere((s) => !s.overlay);
    expect(slice.height, 30);
    expect(slice.block.height, 30);
    expect(slice.block.clipsContent, isTrue);
    final tableResult = await _layout().paginate(
      [_float(height: 5), PageBlock(layout: _boxLayout(20, 40)), _table()],
      const [],
      null,
    );
    final tables = tableResult.pages
        .expand((p) => p.slices)
        .where((s) => s.block.table != null)
        .toList();
    expect(tables.length, greaterThan(1));
    expect(tables.first.height, 60);
    for (final table in tables) {
      expect(table.block.table!.headerRowCount, 1);
      expect(
        table.block.table!.cells.any(
          (cell) => cell.row == 0 && cell.rect.top == 0,
        ),
        isTrue,
      );
    }
  });

  test('普通分页已推进后取消，调用者不能收到已生成的部分页', () async {
    final blocks = List.generate(20, (_) => _paragraph(_sentence * 2));
    final budget = _CancellingBudget((count) => count == blocks.length + 4);
    final layout = ChapterPageLayout(_snapshot(), budget, TextLayoutCache());
    await expectLater(
      layout.paginate(blocks, const [], null),
      throwsA(isA<ChapterLoadCancelled>()),
    );
    expect(budget.checkpoints, blocks.length + 4);
    expect(budget.yieldCount, greaterThan(0));
  });

  test('生产索引回放在单片长行循环中取消，不返回页面或索引', () async {
    final blocks = [_indexedLongBlock()];
    final synchronous = Paginator(
      pageWidth: 220,
      pageHeight: 100,
    ).measureChapter(blocks: blocks, spineIndex: 2);
    final bytes = PageIndex.from(synchronous, blocks).encode();
    final originalBytes = Uint8List.fromList(bytes);
    final budget = _CancellingBudget((count) => count == 30);
    final cache = TextLayoutCache();
    final layout = ChapterPageLayout(_snapshot(), budget, cache);
    var committed = false;
    final result = layout
        .paginate(blocks, const [], null, pageIndex: bytes)
        .then((value) {
          committed = true;
          return value;
        });
    await expectLater(result, throwsA(isA<ChapterLoadCancelled>()));
    expect(committed, isFalse);
    expect(budget.checkpoints, 30);
    expect(cache.misses, 0);
    expect(bytes, originalBytes);
  });

  test('浮动文字异步测量中取消，不发布页面或缓存半成品', () async {
    final cache = TextLayoutCache();
    final budget = _CancellingBudget((_) => cache.misses > 0);
    final layout = ChapterPageLayout(_snapshot(), budget, cache);
    await expectLater(
      layout.paginate([_float(), _paragraph(_sentence * 8)], const [], null),
      throwsA(isA<ChapterLoadCancelled>()),
    );
    expect(cache.misses, 1);
    expect(cache.length, 0);
    expect(budget.yieldCount, greaterThan(0));
  });
}

PageBlock _indexedLongBlock() => PageBlock(
  layout: TextLayoutResult(
    text: '甲' * 256,
    width: 220,
    height: 256,
    maxWidth: 220,
    lines: [
      for (var i = 0; i < 256; i++)
        LineBox(
          start: i,
          end: i + 1,
          top: i.toDouble(),
          height: 1,
          baseline: i + 0.75,
          width: 220,
        ),
    ],
  ),
  style: _base,
);

List<PageBlock> _groupedFloats() => [
  for (final group in [500001, 500002])
    for (var member = 0; member < 2; member++)
      PageBlock(
        layout: _boxLayout(100, 20),
        style: ComputedStyle({'margin-right': '10px'}),
        floatSide: FloatSide.left,
        groupId: group,
      ),
  _paragraph('清除后正文', style: ComputedStyle({..._base.values, 'clear': 'both'})),
];

PageBlock _table() {
  final cells = [
    for (var row = 0; row < 9; row++)
      TableCellRender(
        row: row,
        rect: Rect.fromLTWH(0, row * 20, 220, 20),
        layout: _paragraph(row == 0 ? '表头' : '第 $row 行').layout,
        style: _base,
      ),
  ];
  return PageBlock(
    layout: _boxLayout(220, 180),
    table: TableRenderSpec(
      cells: cells,
      columnXs: const [0, 220],
      rowYs: [for (var row = 0; row <= 9; row++) row * 20.0],
      tableWidth: 220,
      headerRowCount: 1,
      headerHeight: 20,
    ),
  );
}
