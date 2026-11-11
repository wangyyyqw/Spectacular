import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/api.dart' show EpubNode;
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/css/selector.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout_cache.dart';
import 'package:reader_core/parser/block_builder.dart';
import 'package:reader_core/parser/text_aggregator.dart';
import 'package:reader_core/text/reader_text_overlay.dart';
import 'package:reader_mobile/reader/bounded_cache.dart';
import 'package:reader_mobile/reader/epub/book_fonts.dart';
import 'package:reader_mobile/reader/epub/book_resources.dart';
import 'package:reader_mobile/reader/epub/chapter_flow.dart';
import 'package:reader_mobile/reader/epub/chapter_layout_job.dart';
import 'package:reader_mobile/reader/epub/chapter_pagination.dart';
import 'package:reader_mobile/reader/epub/chapter_selectors.dart';
import 'package:reader_mobile/reader/epub/chapter_style_resolver.dart';
import 'package:reader_mobile/reader/epub/chapter_styles.dart';
import 'package:reader_mobile/reader/epub/chapter_text_measurer.dart';
import 'package:reader_mobile/reader/epub/container_blocks.dart';
import 'package:reader_mobile/reader/epub/generated_chapter_content.dart';
import 'package:reader_mobile/reader/epub/inline_content_builder.dart';
import 'package:reader_mobile/reader/epub/table_block_builder.dart';
import 'package:reader_ui/reader_session.dart';

const _plainCss =
    'body, table { margin: 0; } '
    'table { width: 100%; border-collapse: collapse; } '
    'td, th { padding: 2px; border: 1px solid #000; font-size: 13px; }';
typedef _TableEntry = ({BlockNode node, List<SelectorElement> ancestors});
typedef _PageSize = ({double content, double page});

Uint8List _bookBytes(String body, String css) {
  final archive = Archive();
  final files = {
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml': '''
<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">
<rootfiles><rootfile full-path="OEBPS/content.opf"
media-type="application/oebps-package+xml"/></rootfiles></container>''',
    'OEBPS/content.opf': '''
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:identifier id="id">table-builder</dc:identifier><dc:title>表格</dc:title>
<dc:language>zh</dc:language></metadata><manifest>
<item id="c" href="Text/c.xhtml" media-type="application/xhtml+xml"/>
<item id="s" href="Styles/s.css" media-type="text/css"/>
</manifest><spine><itemref idref="c"/></spine></package>''',
    'OEBPS/Text/c.xhtml': '''
<html xmlns="http://www.w3.org/1999/xhtml"><head>
<link rel="stylesheet" href="../Styles/s.css"/></head><body>$body</body></html>''',
    'OEBPS/Styles/s.css': css,
  };
  for (final entry in files.entries) {
    final bytes = utf8.encode(entry.value);
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  final image = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a1ioAAAAASUVORK5CYII=',
  );
  archive.addFile(ArchiveFile('OEBPS/Images/i.png', image.length, image));
  return ZipEncoder().encodeBytes(archive);
}

LayoutSnapshot _snapshot(
  BookFontView fonts,
  ReaderOverrides overrides,
  _PageSize size,
) => LayoutSnapshot(
  spineIndex: 0,
  key: '表格构块测试',
  contentVersion: '1',
  generation: 1,
  width: 320,
  height: size.content,
  pageHeight: size.page,
  topInset: 0,
  baseStyle: ComputedStyle({'font-size': '16px', 'font-family': 'serif'}),
  overrides: overrides,
  textOverlays: ReaderTextOverlayResolver(const []),
  fontDependency: fonts.dependency(const {}),
  fonts: fonts,
  fontFamilies: const {},
  trimTextEdges: true,
);

Future<_Fixture> _fixture(
  String body,
  String css, {
  LayoutBudget? budget,
  ReaderOverrides overrides = const ReaderOverrides(),
  _PageSize size = (content: 600, page: 600),
}) async {
  final document = (await openEpub(
    _bookBytes(body, css),
    verifyCrc: false,
  )).document!;
  final resources = BookResources(document);
  final fonts = BookFonts(resources, onFontsChanged: (_) {});
  final sheets = ChapterStyles(resources, fonts);
  final activeBudget =
      budget ??
      LayoutBudget(
        priority: ChapterLayoutPriority.reading,
        isCurrent: () => true,
      );
  final fixture = _prepareFixture(
    resources,
    sheets,
    _snapshot(fonts.freeze(), overrides, size),
    activeBudget,
  );
  addTearDown(() {
    sheets.close();
    fonts.close();
    resources.close();
  });
  return fixture;
}

_Fixture _prepareFixture(
  BookResources resources,
  ChapterStyles sheets,
  LayoutSnapshot snapshot,
  LayoutBudget budget,
) {
  final parsed = resources.document.parseDocument(0);
  final styles = ChapterStyleResolver(
    snapshot,
    ChapterSelectors(parsed.root),
    sheets.prepare(sheets.stylesheets(0, width: snapshot.width)),
  );
  final raw = BlockBuilder.build(parsed);
  final fixture = _Fixture(
    styles,
    _inlineBuilder(styles, resources, budget),
    _aggregate(raw, styles).root,
  );
  styles.chainStyleCache.clear();
  return fixture;
}

InlineContentBuilder _inlineBuilder(
  ChapterStyleResolver styles,
  BookResources resources,
  LayoutBudget budget,
) {
  final measure = budget is _MeasurementCancellationBudget
      ? _CancellingMeasurer(styles.snapshot, budget)
      : ChapterTextMeasurer(
          styles.snapshot,
          budget,
          TextLayoutCache(),
          BoundedCache<String, double>(2048),
        );
  return InlineContentBuilder(
    styles,
    GeneratedChapterContent(styles, (src) => resources.imageUrl(0, src)),
    measure,
    resources,
  );
}

BlockDocument _aggregate(BlockDocument raw, ChapterStyleResolver styles) =>
    TextAggregator.aggregate(
      raw,
      whiteSpace: styles.style.whiteSpace,
      inlineDisplay: styles.inlineDisplay,
      whiteSpaceFor: (node, ancestors) => styles
          .chainStyle(
            styles.selectorIndex.chainOf(node) ??
                [
                  for (final ancestor in ancestors)
                    ChapterNodeView(
                      ancestor.tag,
                      ancestor.attributes,
                      const [],
                    ),
                  styles.selectorViewOf(node),
                ],
          )
          .whiteSpace,
    );

class _Fixture {
  _Fixture(this.styles, this.inline, this.root);

  final ChapterStyleResolver styles;
  final InlineContentBuilder inline;
  final BlockNode root;
  final flow = ChapterFlow();
  late final builder = TableBlockBuilder(styles, inline, flow);
  LayoutSnapshot get snapshot => styles.snapshot;

  Iterable<_TableEntry> entries() {
    // 镜像章节流的初始 body 上下文及根节点视图，保留祖先级联口径。
    return _entries(root, [ChapterNodeView('body', root.attributes, const [])]);
  }

  Iterable<_TableEntry> _entries(
    EpubNode node,
    List<SelectorElement> ancestors,
  ) sync* {
    if (node is! BlockNode) return;
    if (node.tag == 'table') {
      yield (node: node, ancestors: ancestors);
      return;
    }
    final chain = [...ancestors, styles.selectorViewOf(node)];
    for (final child in node.children) {
      yield* _entries(child, chain);
    }
  }

  Future<void> build() async {
    for (final entry in entries()) {
      await builder.build(entry.node, entry.ancestors);
    }
  }

  Future<List<PageContent>> pages() async {
    final blocks = collapseMarginsIgnoringFloats(
      configureContainerDecoration(flow.blocks),
    );
    return (await ChapterPageLayout(
      snapshot,
      inline.measure.budget,
      TextLayoutCache(),
    ).paginate(blocks, flow.fixedBlocks, null)).pages;
  }

  List<PageBlock> get tableBlocks => [
    for (final block in flow.blocks)
      if (block.table != null) block,
  ];
}

/// 在真实异步文字测量的 checkpoint 取消，避免依赖遍历次数或计时。
class _MeasurementCancellationBudget extends LayoutBudget {
  _MeasurementCancellationBudget()
    : super(priority: ChapterLayoutPriority.reading, isCurrent: () => true);

  bool _measuring = false;
  int measurementCheckpoints = 0;

  Future<T> duringMeasurement<T>(Future<T> Function() work) async {
    _measuring = true;
    try {
      return await work();
    } finally {
      _measuring = false;
    }
  }

  @override
  Future<void> checkpoint({bool force = false}) async {
    if (_measuring) {
      measurementCheckpoints += 1;
      cancel();
    }
    await super.checkpoint(force: force);
  }
}

class _CancellingMeasurer extends ChapterTextMeasurer {
  _CancellingMeasurer(
    LayoutSnapshot snapshot,
    _MeasurementCancellationBudget budget,
  ) : super(snapshot, budget, TextLayoutCache(), BoundedCache(2048));

  // 覆写既有度量签名以验证公共取消行为，混排参数需与原入口一致。
  @override
  Future<TextLayoutResult> layout({
    required String text,
    required ComputedStyle style,
    required double maxWidth,
    List<StyledRun> runs = const [],
    List<RubyAnnotation> rubies = const [],
    List<InlineBoxSpec> inlineBoxes = const [],
    bool preserveContentWidth = false,
  }) => (budget as _MeasurementCancellationBudget).duringMeasurement(
    () => super.layout(
      text: text,
      style: style,
      maxWidth: maxWidth,
      runs: runs,
      rubies: rubies,
      inlineBoxes: inlineBoxes,
      preserveContentWidth: preserveContentWidth,
    ),
  );
}

PageBlock _heightBlock(double height) => PageBlock(
  layout: TextLayoutResult(
    text: '',
    lines: [
      LineBox(
        start: 0,
        end: 0,
        top: 0,
        height: height,
        baseline: height,
        width: 320,
      ),
    ],
    width: 320,
    height: height,
    maxWidth: 320,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => LineBreaker.preserveFractionalLineHeight = true);

  test('自动网格保留跨行跨列、来源 CFI 和单元格作者字号', () async {
    final fixture = await _fixture(
      '<table><tr><td rowspan="2" colspan="2">分组</td><td>甲</td></tr>'
      '<tr><td>乙</td></tr><tr><td>丙</td><td>丁</td><td>戊</td></tr></table>',
      _plainCss,
      overrides: const ReaderOverrides(fontSize: 30),
    );
    await fixture.build();
    final block = fixture.tableBlocks.single;
    final table = block.table!;
    final group = table.cells.first;
    expect(table.cells, hasLength(6));
    expect(table.columnXs, hasLength(4));
    expect(group.rect.width, table.columnXs[2]);
    expect(group.rect.height, table.rowYs[2]);
    expect(table.cells[2].rect.left, group.rect.right);
    expect(block.startCfi, isNull);
    for (final cell in table.cells) {
      expect(cell.startCfi, startsWith('epubcfi('));
      expect(cell.style.fontSize, 13);
    }
  });

  test('fixed 百分比列保留 col 声明优先级与 HTML 表宽口径', () async {
    final fixture = await _fixture(
      '<table width="200"><colgroup><col width="40%"/><col/></colgroup>'
          '<tr><td style="width: 60%">甲</td><td>乙</td></tr></table>',
      'body, table { margin: 0; } '
          'table { width: 280px; table-layout: fixed; border-spacing: 6px; } '
          'col { width: 25%; } td { padding: 2px 4px; border: 1px solid #000; }',
    );
    await fixture.build();
    final table = fixture.tableBlocks.single.table!;
    final first = table.cells.first;
    final columnSpace = 200.0 - 6 * 3;
    // 第二列同样命中 col，未铺满的声明列仍按原 fixed 算法保留。
    expect(first.rect.width, 0.25 * columnSpace + 10);
    expect(table.cells[1].rect.width, first.rect.width);
    expect(table.tableWidth, first.rect.width * 2 + 6 * 3);
    expect(first.rect.left, 6);
  });

  test('separate 间距进入网格坐标，collapse 分摊单元格边框', () async {
    Future<_Fixture> build(String model) async {
      final fixture = await _fixture(
        '<table><tr><td>甲</td><td>乙</td></tr></table>',
        'body, table { margin: 0; } table { width: 100%; '
            'border-collapse: $model; border-spacing: 6px 8px; } '
            'td { border: 2px solid #000; padding: 4px; font-size: 13px; }',
      );
      await fixture.build();
      return fixture;
    }

    final separate = (await build('separate')).tableBlocks.single;
    final collapse = (await build('collapse')).tableBlocks.single;
    final first = separate.table!.cells.first;
    final second = separate.table!.cells[1];
    expect(first.rect.left, 6);
    expect(first.rect.top, 8);
    expect(second.rect.left - first.rect.right, 6);
    expect(separate.layout.height, separate.table!.rowYs.last);
    expect(first.rect.height - collapse.table!.cells.first.rect.height, 2);
    expect(collapse.table!.cells.first.rect.left, 0);
  });

  for (final side in ['top', 'bottom']) {
    test('caption 的 $side 顺序、外边距与表格冻结样式保持一致', () async {
      final fixture = await _fixture(
        '<div><table><caption>表题</caption><tr><td>格</td></tr></table></div>',
        'body { margin: 0; } div { border: 1px solid #000; } '
            'table { margin: 11px 0 13px; caption-side: $side; opacity: .5; } '
            'caption { margin: 3px 0 5px; opacity: .4; } td { opacity: .2; }',
      );
      await fixture.build();
      final table = fixture.tableBlocks.single;
      final caption = fixture.flow.blocks.firstWhere(
        (block) => block.table == null,
      );
      expect(fixture.flow.blocks.first, side == 'top' ? caption : table);
      expect(caption.startCfi, startsWith('epubcfi('));
      expect(caption.spaceBefore, side == 'top' ? 14 : 3);
      expect(caption.spaceAfter, side == 'bottom' ? 18 : 5);
      expect(table.spaceBefore, side == 'top' ? 0 : 11);
      expect(table.spaceAfter, side == 'bottom' ? 0 : 13);
      expect(table.containerSides, isTrue);
      expect(table.effectiveOpacity, 0.5);
      expect(table.table!.cells.single.style.effectiveOpacity, 0.1);
    });
  }

  test('百分比格高使用冻结的页面基准高度，空格保留自然占位', () async {
    final fixture = await _fixture(
      '<table><tr><td class="declared"></td></tr><tr><td></td></tr></table>',
      'body, table { margin: 0; } table { width: 100%; border-spacing: 0; } '
          'td { padding: 3px; border: 2px solid #000; font-size: 20px; '
          'line-height: 1; } .declared { height: 50%; box-sizing: content-box; }',
      size: (content: 180, page: 240),
    );
    await fixture.build();
    final cells = fixture.tableBlocks.single.table!.cells;
    expect(cells.first.rect.height, 130);
    expect(cells.last.rect.height, 22);
    expect(cells.every((cell) => cell.layout.lines.isEmpty), isTrue);
  });

  test('格内作者行内字号、空原子盒和图片占位保留原文坐标', () async {
    final fixture = await _fixture(
      '<table><tr><td> 首 <span class="label">字号</span>'
          '<img src="../Images/i.png" width="24" height="18"/> 尾 </td>'
          '<td> 前 <span class="empty"></span> 后 </td></tr></table>',
      '$_plainCss .label { font-size: 19px; color: #f00; } '
          '.empty { display: inline-block; width: 18px; height: 12px; }',
    );
    await fixture.build();
    final cells = fixture.tableBlocks.single.table!.cells;
    final first = cells.first.layout;
    expect(first.text, contains('\uFFFC'));
    expect(first.runs.any((run) => run.style.fontSize == 19), isTrue);
    final empty = cells.last.layout;
    expect(empty.lines.expand((line) => line.inlineBoxes).single.width, 18);
    expect(empty.text, '前  后');
    for (final layout in [first, empty]) {
      for (final line in layout.lines) {
        expect(line.start, greaterThanOrEqualTo(0));
        expect(line.end, lessThanOrEqualTo(layout.text.length));
      }
    }
  });

  test('整表按页面余高切片，每页一次表头且跨页 rowspan 不丢失', () async {
    final fixture = await _fixture(
      '<table><thead><tr><th>组</th><th>值</th></tr></thead><tbody>'
          '<tr><td rowspan="8">分组</td><td>值0</td></tr>'
          '${List.generate(7, (i) => '<tr><td>值${i + 1}</td></tr>').join()}'
          '</tbody></table>',
      '$_plainCss td { height: 44px; box-sizing: border-box; } '
          'th { height: 30px; box-sizing: border-box; }',
      size: (content: 150, page: 180),
    );
    fixture.flow.blocks.add(_heightBlock(40));
    await fixture.build();
    expect(fixture.tableBlocks, hasLength(1));
    final pages = await fixture.pages();
    expect(pages.length, greaterThan(2));
    final values = <String>[];
    for (final page in pages) {
      final table = page.slices
          .where((slice) => slice.block.table != null)
          .single;
      final spec = table.block.table!;
      expect(
        spec.cells
            .where((cell) => cell.row == 0)
            .map((cell) => cell.layout.text),
        ['组', '值'],
      );
      final group = spec.cells.where((cell) => cell.layout.text == '分组').single;
      expect(group.rect.bottom, lessThanOrEqualTo(table.block.layout.height));
      values.addAll(
        spec.cells
            .map((cell) => cell.layout.text)
            .where((text) => text.startsWith('值') && text != '值'),
      );
    }
    expect(values, [for (var i = 0; i < 8; i++) '值$i']);
  });

  test('无行表格保留原文字流回退，同一入口的两个表格状态不串用', () async {
    final fallback = await _fixture(
      '<table><caption>原文</caption></table>',
      _plainCss,
    );
    await fallback.build();
    expect(fallback.flow.blocks.single.layout.text, '原文');
    expect(fallback.tableBlocks, isEmpty);
    final fixture = await _fixture(
      '<table class="first"><caption>题</caption><thead><tr><th>首格</th></tr>'
          '</thead></table><table class="second"><tr><td>次格</td></tr></table>',
      '$_plainCss .first { width: 120px; table-layout: fixed; } '
          '.second { width: 100%; table-layout: auto; }',
    );
    await fixture.build();
    final tables = fixture.tableBlocks.map((block) => block.table!).toList();
    expect(tables[0].tableWidth, 120);
    expect(tables[0].headerRowCount, 1);
    expect(tables[1].tableWidth, 320);
    expect(tables[1].headerRowCount, 0);
    expect(tables[1].cells.single.layout.text, '次格');
  });

  test('逐格真实异步测量中取消，不向章节流追加半成品', () async {
    final budget = _MeasurementCancellationBudget();
    final fixture = await _fixture(
      '<table><caption>标题</caption><tr><td>逐格测量${'文字' * 80}</td>'
      '<td>后格</td></tr></table>',
      _plainCss,
      budget: budget,
    );
    final sentinel = _heightBlock(10);
    fixture.flow.blocks.add(sentinel);
    await expectLater(fixture.build(), throwsA(isA<ChapterLoadCancelled>()));
    expect(budget.measurementCheckpoints, greaterThan(0));
    expect(fixture.flow.blocks, [sentinel]);
  });
}
