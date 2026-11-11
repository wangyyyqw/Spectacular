import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/api.dart' show EpubNode;
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/layout/float_occupancy.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/text_layout_cache.dart';
import 'package:reader_core/paint/image_size.dart';
import 'package:reader_core/parser/block_builder.dart';
import 'package:reader_core/parser/document_parser.dart';
import 'package:reader_core/parser/text_aggregator.dart';
import 'package:reader_core/text/reader_text_overlay.dart';
import 'package:reader_core/util/bounded_cache.dart';
import 'package:reader_core/epub/chapter/book_fonts.dart';
import 'package:reader_core/epub/chapter/book_resources.dart';
import 'package:reader_core/epub/chapter/chapter_flow.dart';
import 'package:reader_core/epub/chapter/chapter_layout_job.dart';
import 'package:reader_core/epub/chapter/chapter_selectors.dart';
import 'package:reader_core/epub/chapter/chapter_style_resolver.dart';
import 'package:reader_core/epub/chapter/chapter_styles.dart';
import 'package:reader_core/epub/chapter/chapter_text_measurer.dart';
import 'package:reader_core/epub/chapter/flex_blocks.dart';
import 'package:reader_core/epub/chapter/generated_chapter_content.dart';
import 'package:reader_core/epub/chapter/image_block_builder.dart';
import 'package:reader_core/epub/chapter/image_blocks.dart';
import 'package:reader_core/epub/chapter/inline_content_builder.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/source/chapter_source.dart';

const _containerXml = '''
<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">
<rootfiles><rootfile full-path="content.opf"
media-type="application/oebps-package+xml"/></rootfiles></container>''';
const _opf = '''
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:identifier id="id">image-flex</dc:identifier><dc:title>图片布局</dc:title>
<dc:language>zh</dc:language></metadata><manifest>
<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>
<item id="i" href="Images/i.png" media-type="image/png"/>
</manifest><spine><itemref idref="c"/></spine></package>''';

Uint8List _book(String body, String css) {
  final archive = Archive();
  final files = {
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml': _containerXml,
    'content.opf': _opf,
    'c.xhtml':
        '<html xmlns="http://www.w3.org/1999/xhtml"><head>'
        '<style>$css</style></head><body>$body</body></html>',
  };
  for (final entry in files.entries) {
    final bytes = utf8.encode(entry.value);
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  final image = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a1ioAAAAASUVORK5CYII=',
  );
  archive.addFile(ArchiveFile('Images/i.png', image.length, image));
  return ZipEncoder().encodeBytes(archive);
}

LayoutSnapshot _snapshot(BookFontView fonts) => LayoutSnapshot(
  spineIndex: 0,
  key: '图片与 Flex 测试',
  contentVersion: '1',
  generation: 1,
  width: 240,
  height: 400,
  pageHeight: 400,
  topInset: 0,
  baseStyle: ComputedStyle({'font-size': '16px', 'font-family': 'serif'}),
  overrides: const ReaderOverrides(),
  textOverlays: ReaderTextOverlayResolver(const []),
  fontDependency: fonts.dependency(const {}),
  fonts: fonts,
  fontFamilies: const {},
  trimTextEdges: true,
);

Future<_ImageFixture> _images(
  String body,
  String css, {
  LayoutBudget? budget,
}) async {
  final document = (await openEpub(
    _book(body, css),
    verifyCrc: false,
  )).document!;
  final resources = BookResources(document);
  final fonts = BookFonts(resources, onFontsChanged: (_) {});
  final sheets = ChapterStyles(resources, fonts);
  await resources.prepareFootnotes(0);
  final preparedSheets = await sheets.prepareStylesheets(0, width: 240);
  final parsed = resources.parsedChapter(0);
  final styles = ChapterStyleResolver(
    _snapshot(fonts.freeze()),
    ChapterSelectors(parsed.root),
    sheets.prepare(preparedSheets),
  );
  final inline = _inline(styles, resources, budget);
  final fixture = _ImageFixture(parsed, styles, inline);
  addTearDown(() {
    sheets.close();
    fonts.close();
    resources.close();
  });
  return fixture;
}

InlineContentBuilder _inline(
  ChapterStyleResolver styles,
  BookResources resources,
  LayoutBudget? budget,
) => InlineContentBuilder(
  styles,
  GeneratedChapterContent(styles, (src) => resources.imageUrl(0, src)),
  ChapterTextMeasurer(
    styles.snapshot,
    budget ??
        LayoutBudget(
          priority: ChapterLayoutPriority.reading,
          isCurrent: () => true,
        ),
    TextLayoutCache(),
    BoundedCache<String, double>(2048),
  ),
  resources,
  resources.footnotes(0),
);

class _ImageFixture {
  _ImageFixture(this.parsed, this.styles, this.inline);

  final ParsedDocument parsed;
  final ChapterStyleResolver styles;
  final InlineContentBuilder inline;
  late final builder = ImageBlockBuilder(styles, inline, inline.content);

  String cfi(String id) => parsed.elementById(id)!.cfi.serialize();

  BlockNode leaf(String id, {bool pseudoParent = false}) {
    final element = parsed.elementById(id)!;
    return BlockNode(
      tag: element.tag,
      display: DisplayMode.block,
      children: const [],
      cfi: pseudoParent ? parsed.root.cfi : element.cfi,
      attributes: element.attributes,
      start: element.start,
      end: element.end,
    );
  }

  BlockPosition position(BlockNode node) {
    final chain = styles.selectorIndex.chainOf(node)!;
    return BlockPosition(ancestors: chain.sublist(0, chain.length - 1));
  }

  List<BlockNode> folded() {
    final tree = TextAggregator.aggregate(
      BlockBuilder.build(parsed),
      inlineDisplay: styles.inlineDisplay,
    );
    return _folded(tree.root).toList();
  }

  Iterable<BlockNode> _folded(EpubNode node) sync* {
    if (node is! BlockNode) return;
    if (node.tag == 'img' && node.children.isEmpty) {
      yield node;
    } else {
      for (final child in node.children) {
        yield* _folded(child);
      }
    }
  }
}

Iterable<ParsedElement> _elements(ParsedElement root) sync* {
  yield root;
  for (final child in root.children.whereType<ParsedElement>()) {
    yield* _elements(child);
  }
}

ComputedStyle _flexStyle(Map<String, String> declarations) => ComputedStyle({
  'display': 'flex',
  'margin': '0',
  'font-size': '16px',
  ...declarations,
});

PageBlock _member(
  String text,
  double width, {
  Map<String, String> declarations = const {},
  double height = 20,
}) => PageBlock.styled(
  style: ComputedStyle({'margin': '0', 'font-size': '16px', ...declarations}),
  containingWidth: 320,
  startCfi: 'epubcfi(/6/2!/4/2[${text.codeUnitAt(0)}])',
  endCfi: 'epubcfi(/6/2!/4/2[${text.codeUnitAt(0)}]:1)',
  layout: TextLayoutResult(
    text: text,
    lines: [
      LineBox(
        start: 0,
        end: text.length,
        top: 0,
        height: height,
        baseline: height,
        width: width,
      ),
    ],
    width: width,
    height: height,
    maxWidth: 320,
  ),
);

class _StopBudget extends LayoutBudget {
  _StopBudget(this.after)
    : super(priority: ChapterLayoutPriority.reading, isCurrent: () => true);

  final int after;
  int checkpoints = 0;

  @override
  Future<void> checkpoint({bool force = false}) async {
    checkpoints += 1;
    if (checkpoints == after) cancel();
    await super.checkpoint(force: true);
  }
}

Future<PageBlock?> _layoutFlex(
  ComputedStyle style,
  List<List<PageBlock>> items, {
  LayoutBudget? budget,
  double width = 320,
}) => buildFlexRowBlock(
  containerStyle: style,
  containerWidth: width,
  items: items,
  containingWidth: 320,
  pageContentHeight: 400,
  groupId: 7,
  checkpoint: budget?.checkpoint,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => LineBreaker.preserveFractionalLineHeight = true);

  test('图片尺寸保留 CSS 优先、百分比基准、缺边补齐和页高限制', () {
    const intrinsic = ImageIntrinsicSize(width: 400, height: 200);
    expect(resolveImageDisplaySize({'width': '70%'}, intrinsic, 200, 300), (
      140.0,
      70.0,
    ));
    expect(
      resolveImageDisplaySize(
        {'width': '200', 'height': '80'},
        intrinsic,
        240,
        400,
        cssWidth: 60,
      ),
      (60.0, 80.0),
    );
    expect(resolveImageDisplaySize({}, null, 240, 400), (240.0, 240.0));
    expect(resolveImageDisplaySize({}, intrinsic, 240, 400, aspectRatio: 3), (
      240.0,
      80.0,
    ));
    expect(resolveImageDisplaySize({'width': '50px'}, intrinsic, 240, 20), (
      50.0,
      20.0,
    ));
  });

  test('折叠父图片使用原始 img CFI，容器宽与图片尺寸保持', () async {
    final fixture = await _images(
      '<div class="gallery"><p><img id="i" src="Images/i.png" '
          'width="80" height="40"/></p></div>',
      'body,p { margin:0; } .gallery { width:50%; text-align:center; }',
    );
    final node = fixture.folded().single;
    expect(node.cfi.serialize(), isNot(fixture.cfi('i')));
    final block = (await fixture.builder.build(
      node,
      fixture.position(node),
    )).single;
    expect(block.startCfi, fixture.cfi('i'));
    expect(block.layout.height, 40);
    expect(block.style!.width!.value, 80);
    expect(block.style!.margin.left, 20);
  });

  test('重复 src 的两个折叠图片按各自元素身份绑定 CFI', () async {
    final fixture = await _images(
      '<p>前</p><div><img id="a" src="Images/i.png" width="80" height="40"/></div>'
          '<section><img id="b" src="Images/i.png" width="60" height="30"/></section>',
      'body,p { margin:0; }',
    );
    final cfis = <String?>[];
    for (final node in fixture.folded()) {
      cfis.add(
        (await fixture.builder.build(
          node,
          fixture.position(node),
        )).single.startCfi,
      );
    }
    expect(cfis, [fixture.cfi('a'), fixture.cfi('b')]);
    expect(cfis.toSet(), hasLength(2));
    expect(
      fixture.styles.selectorIndex.imageCfiForSource('Images/i.png'),
      isNull,
    );
  });

  test('SVG 图片绑定内层 image，不使用 SVG 或外层 div CFI', () async {
    final fixture = await _images(
      '<div id="outer"><svg id="svg" xmlns="http://www.w3.org/2000/svg" '
          'xmlns:xlink="http://www.w3.org/1999/xlink">'
          '<image id="leaf" xlink:href="Images/i.png" width="90" height="30"/>'
          '</svg></div>',
      'body { margin:0; }',
    );
    final node = fixture.folded().single;
    final block = (await fixture.builder.build(
      node,
      fixture.position(node),
    )).single;
    expect(block.startCfi, fixture.cfi('leaf'));
    expect(block.startCfi, isNot(fixture.cfi('svg')));
    expect(block.startCfi, isNot(fixture.cfi('outer')));
  });

  test('同一 SVG 内重复引用的 image 仍按各自元素身份绑定 CFI', () async {
    final fixture = await _images(
      '<svg id="svg" xmlns="http://www.w3.org/2000/svg" '
          'xmlns:xlink="http://www.w3.org/1999/xlink">'
          '<image id="a" xlink:href="Images/i.png" width="80" height="40"/>'
          '<image id="b" xlink:href="Images/i.png" width="60" height="30"/>'
          '</svg>',
      'body { margin:0; }',
    );
    final cfis = <String?>[];
    for (final id in ['a', 'b']) {
      final node = fixture.leaf(id, pseudoParent: true);
      cfis.add(
        (await fixture.builder.build(
          node,
          fixture.position(node),
        )).single.startCfi,
      );
    }
    expect(cfis, [fixture.cfi('a'), fixture.cfi('b')]);
    expect(cfis, isNot(contains(fixture.cfi('svg'))));
    expect(
      fixture.styles.selectorIndex.imageCfiForSource('Images/i.png'),
      isNull,
    );
  });

  test('同一 data 的多个 object 使用各自真实元素 CFI', () async {
    final fixture = await _images(
      '<object id="a" data="Images/i.png" width="80" height="40"></object>'
          '<object id="b" data="Images/i.png" width="60" height="30"></object>',
      'body { margin:0; }',
    );
    final blocks = <PageBlock>[];
    for (final id in ['a', 'b']) {
      final node = fixture.leaf(id, pseudoParent: true);
      blocks.add(
        (await fixture.builder.build(node, fixture.position(node))).single,
      );
    }
    expect(blocks.map((block) => block.startCfi), [
      fixture.cfi('a'),
      fixture.cfi('b'),
    ]);
    expect(blocks.map((block) => block.layout.height), [40.0, 30.0]);
  });

  test('容器浮动图片保留比例、分组和真实 img CFI', () async {
    final fixture = await _images(
      '<div><img id="i" src="Images/i.png" width="200" height="100"/></div>',
      'body { margin:0; }',
    );
    final node = fixture.folded().single;
    final block = (await fixture.builder.build(
      node,
      BlockPosition(
        ancestors: fixture.position(node).ancestors,
        containerFloat: FloatSide.left,
        containerFloatWidth: 60,
        containerFloatGroup: 8,
      ),
    )).single;
    expect(block.startCfi, fixture.cfi('i'));
    expect(block.floatSide, FloatSide.left);
    expect(block.groupId, 8);
    expect(block.layout.width, 60);
    expect(block.layout.height, 30);
  });

  test('实际章节的容器内浮动图片 CFI 等于原始 img 位置', () async {
    final source = await EpubChapterSource.open(
      _book(
        '<p>前</p><div><p><img src="Images/i.png" '
            'width="60" height="30"/>图片后的正文文字。</p></div>',
        'body,p { margin:0; } img { float:left; }',
      ),
      contentWidth: 240,
      contentHeight: 400,
      verifyCrc: false,
    );
    addTearDown(source.close);
    final imageNode = _elements(source.document.parseDocument(0).root)
        .singleWhere((element) => element.tag == 'img');
    final expected = imageNode.cfi.serialize();
    expect(expected, 'epubcfi(/6/2!/4/4/2/2)');
    final pages = await source.loadChapter(0);
    final image = pages
        .expand((page) => page.slices)
        .map((slice) => slice.block)
        .firstWhere(
          (block) =>
              block.floatSide != null && block.style?.backgroundImage != null,
        );
    expect(image.startCfi, expected);
  });

  test('图片容器遍历中取消不会返回可提交的图片块', () async {
    final budget = _StopBudget(3);
    final fixture = await _images(
      '<div><section><p><img id="i" src="Images/i.png"/></p></section></div>',
      'body { margin:0; }',
      budget: budget,
    );
    final node = fixture.folded().single;
    await expectLater(
      fixture.builder.build(node, fixture.position(node)),
      throwsA(isA<ChapterLoadCancelled>()),
    );
    expect(budget.checkpoints, 3);
  });

  test('Flex 增长与收缩保留加权分配、子块 CFI 和分组', () async {
    final style = _flexStyle({'column-gap': '10px'});
    final grown = await _layoutFlex(style, [
      [
        _member('甲', 80, declarations: {'flex-grow': '1'}),
      ],
      [
        _member('乙', 80, declarations: {'flex-grow': '3'}),
      ],
    ]);
    expect(grown!.table!.cells.map((cell) => cell.rect.width), [117.5, 192.5]);
    expect(grown.groupId, 7);
    expect(grown.startCfi, grown.table!.cells.first.startCfi);
    final shrunk = await _layoutFlex(style, [
      [
        _member('甲', 100, declarations: {'flex-shrink': '1'}),
      ],
      [
        _member('乙', 100, declarations: {'flex-shrink': '0'}),
      ],
    ], width: 150);
    expect(shrunk!.table!.cells.map((cell) => cell.rect.width), [40.0, 100.0]);
    expect(shrunk.table!.cells.last.rect.left, 50);
  });

  test('Flex wrap-reverse 和跨轴分布保持行顺序与精确坐标', () async {
    final block = await _layoutFlex(
      _flexStyle({
        'flex-wrap': 'wrap-reverse',
        'row-gap': '10px',
        'height': '120px',
        'align-content': 'space-between',
      }),
      [
        [_member('甲', 100)],
        [_member('乙', 100)],
      ],
      width: 150,
    );
    expect(block!.table!.cells.map((cell) => cell.layout.text), ['乙', '甲']);
    expect(block.table!.rowYs, [0.0, 100.0, 120.0]);
    expect(block.height, 120);
  });

  test('空 Flex 子项不生成页面块', () async {
    expect(await _layoutFlex(_flexStyle({}), const []), isNull);
  });

  test('页面根 Flex 居中忽略脱流块并保留原块身份', () async {
    final first = _member('甲', 80);
    final last = _member('乙', 80);
    final blocks = [
      first,
      PageBlock(layout: first.layout, absolute: true),
      last,
      PageBlock(layout: first.layout, floatSide: FloatSide.left),
    ];
    final async = List<PageBlock>.of(blocks);
    final style = _flexStyle({
      'height': '240px',
      'padding': '10px',
      'border': '1px solid #000',
      'justify-content': 'center',
    });
    await alignPageRootFlexColumn(
      blocks: async,
      start: 0,
      containerStyle: style,
      pageWidth: 240,
      pageHeight: 400,
    );
    expect(async.first.layout.height, 111);
    expect(async.skip(1), blocks);
  });

  test('Flex 逐项布局和居中提交前取消，输入块流均无部分修改', () async {
    final items = [
      [_member('甲', 80)],
      [_member('乙', 80)],
    ];
    final original = [for (final item in items) item.single];
    await expectLater(
      _layoutFlex(
        _flexStyle({'flex-wrap': 'wrap'}),
        items,
        budget: _StopBudget(4),
      ),
      throwsA(isA<ChapterLoadCancelled>()),
    );
    expect([for (final item in items) item.single], original);
    await expectLater(
      _layoutFlex(
        _flexStyle({}),
        List.generate(16, (_) => <PageBlock>[]),
        budget: _StopBudget(3),
      ),
      throwsA(isA<ChapterLoadCancelled>()),
    );
    final budget = _StopBudget(3);
    final blocks = List<PageBlock>.of(original);
    await expectLater(
      alignPageRootFlexColumn(
        blocks: blocks,
        start: 0,
        containerStyle: _flexStyle({
          'height': '240px',
          'justify-content': 'center',
        }),
        pageWidth: 240,
        pageHeight: 400,
        checkpoint: budget.checkpoint,
      ),
      throwsA(isA<ChapterLoadCancelled>()),
    );
    expect(blocks, original);
  });
}
