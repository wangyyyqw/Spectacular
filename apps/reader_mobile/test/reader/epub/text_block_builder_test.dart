import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/css/selector.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/layout/float_occupancy.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/text_layout_cache.dart';
import 'package:reader_core/parser/block_builder.dart';
import 'package:reader_core/parser/text_aggregator.dart';
import 'package:reader_core/position/cfi.dart';
import 'package:reader_core/text/reader_text_overlay.dart';
import 'package:reader_mobile/reader/bounded_cache.dart';
import 'package:reader_mobile/reader/epub/book_fonts.dart';
import 'package:reader_mobile/reader/epub/book_resources.dart';
import 'package:reader_mobile/reader/epub/chapter_flow.dart';
import 'package:reader_mobile/reader/epub/chapter_layout_job.dart';
import 'package:reader_mobile/reader/epub/chapter_selectors.dart';
import 'package:reader_mobile/reader/epub/chapter_style_resolver.dart';
import 'package:reader_mobile/reader/epub/chapter_styles.dart';
import 'package:reader_mobile/reader/epub/chapter_text_measurer.dart';
import 'package:reader_mobile/reader/epub/generated_chapter_content.dart';
import 'package:reader_mobile/reader/epub/inline_content_builder.dart';
import 'package:reader_mobile/reader/epub/text_block_builder.dart';
import 'package:reader_ui/reader_session.dart';

const _sentence = '长段中文与 Latin words、标点混排，分页和锚点保持连续。';
final _base = ComputedStyle({
  'font-size': '16px',
  'line-height': '1.5',
  'margin': '0',
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => LineBreaker.preserveFractionalLineHeight = true);

  test('嵌套 q 和伪内容扩写后，ruby、图片、脚注仍指向同一文字', () async {
    final chapter = await _TestChapter.open(
      '<p class="target">甲<q>乙<q><ruby>丙<rt>bing</rt></ruby></q>，'
          '<a epub:type="noteref" href="#note">注</a>'
          '<img src="../Images/i.png"/></q>丁</p>'
          '<aside id="note" epub:type="footnote"><p>脚注正文</p></aside>',
      'p {quotes:"《" "》" "「" "」";} img {width:12px;height:18px;}'
          '.target::before {content:"前";color:red;}'
          '.target::after {content:"尾";color:blue;}',
    );
    final job = chapter.job();
    await job.buildClass('target');
    final block = job.flow.blocks.single;
    const text = '前甲《乙「丙」，注\uFFFC》丁尾';
    expect(block.layout.text, text);
    expect(block.rubies!.single.start, text.indexOf('丙'));
    expect(block.rubies!.single.end, text.indexOf('丙') + 1);
    expect(block.inlineImages.single.offset, text.indexOf('\uFFFC'));
    expect(block.inlineImages.single.url, 'OEBPS/Images/i.png');
    expect(
      block.layout.lines.expand((line) => line.inlineBoxes).single.offset,
      text.indexOf('\uFFFC'),
    );
    expect(block.footnotes.single.start, text.indexOf('注'));
    expect(block.footnotes.single.end, text.indexOf('注') + 1);
    expect(block.footnotes.single.text, contains('脚注正文'));
    expect(block.startCfi, job.node('target').cfi.serialize());
  });

  test('空可见盒在计数器之前短路，下一段编号不被空盒消耗', () async {
    final chapter = await _TestChapter.open(
      '<p class="first number">甲</p><div class="empty"></div>'
          '<p class="last number">乙</p>',
      '.number {counter-increment:n;}'
          '.number::before {content:counter(n) ".";}'
          '.empty {counter-increment:n;height:20px;background:red;}',
    );
    final job = chapter.job();
    await job.buildClass('first');
    final empty = TextContentNode(
      text: ' ',
      runs: const [],
      hardBreaks: const [],
      cfi: job.node('first').cfi,
      start: 0,
      end: 0,
    );
    await job.builder.build(
      empty,
      BlockPosition(ancestors: job.ancestors('empty')),
    );
    await job.buildClass('last');
    expect(job.flow.blocks.map((block) => block.layout.text), [
      '1.甲',
      '',
      '2.乙',
    ]);
    expect(job.flow.blocks[1].height, 20);
    expect(job.content.cssCounters['n'], 2);
  });

  test('首字拆出完整 emoji，同步重映射 ruby、图片与正文 CFI', () async {
    final chapter = await _TestChapter.open(
      '<p class="target">😀<ruby>甲<rt>jia</rt></ruby>乙'
          '<img src="../Images/i.png"/>$_sentence</p>',
      '.target {initial-letter:2;} img {width:12px;height:14px;}',
    );
    final job = chapter.job();
    await job.buildClass('target');
    final cap = job.flow.blocks.first;
    final body = job.flow.blocks.last;
    expect(cap.layout.text, '😀');
    expect(cap.floatSide, FloatSide.left);
    expect(cap.startCfi, job.node('target').cfi.serialize());
    expect(body.layout.text, '甲乙\uFFFC$_sentence');
    expect(cfiCharOffset(body.startCfi!), 2);
    expect(body.rubies!.single.start, 0);
    expect(body.rubies!.single.end, 1);
    expect(body.inlineImages.single.offset, 2);
    expect(
      body.layout.lines.expand((line) => line.inlineBoxes).single.offset,
      2,
    );
  });

  test('单个首字或 emoji 摘空正文后仍保留浮动首字和原文 CFI', () async {
    for (final text in ['甲', '😀']) {
      final chapter = await _TestChapter.open(
        '<p class="target">$text</p>',
        '.target {initial-letter:2;}',
      );
      final job = chapter.job();
      await job.buildClass('target');
      final cap = job.flow.blocks.single;
      expect(cap.layout.text, text);
      expect(cap.floatSide, FloatSide.left);
      expect(cap.height, greaterThan(0));
      expect(cap.startCfi, job.node('target').cfi.serialize());
    }
  });

  test('相对位移抵扣只由下一个普通流块消费，固定和浮动块不吞掉抵扣', () async {
    final chapter = await _TestChapter.open(
      '<p class="relative">相对正文</p><p class="fixed">固定文字</p>'
          '<p class="float">浮动文字</p><p class="next">后续正文</p>',
      'p {margin:12px 0 14px;} .relative {position:relative;left:7px;top:5px;}'
          '.fixed {position:fixed;width:120px;top:10px;right:10px;}'
          '.float {float:left;width:90px;}',
    );
    final job = chapter.job();
    await job.buildClass('relative');
    expect(job.flow.pendingRelativeTop, 5);
    expect(job.flow.blocks.single.spaceBefore, 17);
    expect(job.flow.blocks.single.spaceAfter, 9);
    expect(job.flow.blocks.single.leftInset, 7);
    await job.buildClass('fixed');
    await job.buildClass('float');
    expect(job.flow.pendingRelativeTop, 5);
    expect(job.flow.fixedBlocks.single.absolute, isTrue);
    expect(job.flow.fixedBlocks.single.absoluteTop, 10);
    expect(job.flow.blocks.last.floatSide, FloatSide.left);
    await job.buildClass('next');
    expect(job.flow.blocks.last.spaceBefore, 7);
    expect(job.flow.pendingRelativeTop, 0);
  });

  test('列表标记只消费一次，inside 缩进和首末容器段距各自保留', () async {
    final chapter = await _TestChapter.open(
      '<ol><li class="target">列表正文</li></ol>',
      'li {margin:0;text-indent:0;list-style-position:inside;}',
    );
    final job = chapter.job();
    final list = ListContext(
      'ol',
      0,
      inside: true,
      spaceBefore: 8,
      spaceAfter: 9,
    )..markerPending = true;
    final position = BlockPosition(
      ancestors: job.ancestors('target'),
      list: list,
      listFirst: true,
      listLast: true,
    );
    await job.buildClass('target', position: position);
    final first = job.flow.blocks.single;
    expect(first.listMarker, '1.');
    expect(first.style!.textIndent, 0);
    expect(first.layout.lines.first.indent, greaterThan(0));
    expect(first.spaceBefore, 8);
    expect(first.spaceAfter, 9);
    await job.buildClass('target', position: position);
    expect(job.flow.blocks.last.listMarker, isNull);
    expect(job.flow.blocks.last.layout.lines.first.indent, 0);
  });

  test('单图片正文复用块图构建，保留图片脚注和容器浮动组', () async {
    final chapter = await _TestChapter.open(
      '<p class="target"><span class="keep"></span>'
          '<img epub:type="noteref" href="#note" src="../Images/i.png" width="30" height="20"/></p>'
          '<aside id="note" epub:type="footnote"><p>图片脚注</p></aside>',
      '.keep {display:inline-block;}',
    );
    final job = chapter.job();
    await job.buildClass(
      'target',
      position: BlockPosition(
        ancestors: job.ancestors('target'),
        containerFloat: FloatSide.right,
        containerFloatWidth: 100,
        containerFloatGroup: 500001,
      ),
    );
    final block = job.flow.blocks.single;
    expect(block.layout.text, '');
    expect(block.style!.backgroundImage, 'OEBPS/Images/i.png');
    expect(block.floatSide, FloatSide.right);
    expect(block.groupId, 500001);
    expect(block.footnotes.single.text, contains('图片脚注'));
  });

  test('冻结覆盖只作用普通正文，标题与紧凑作者组件保留书籍字号', () async {
    final chapter = await _TestChapter.open(
      '<p class="normal">$_sentence</p><p class="title">视觉标题</p>'
          '<div class="compact"><p class="label">小组件</p></div>',
      '.title {font-size:20px;text-align:center;} '
          '.compact {font-size:20px;line-height:1;} .label {font-size:12px;}',
    );
    final job = chapter.job(
      overrides: const ReaderOverrides(fontSize: 22, paragraphSpacing: 11),
    );
    chapter.fonts.close();
    await job.buildClass('normal');
    await job.buildClass('title');
    await job.buildClass('label');
    expect(job.flow.blocks.map((block) => block.style!.fontSize), [22, 20, 12]);
    expect(job.flow.blocks.first.spaceBefore, 11);
    expect(job.flow.blocks[1].breakAfterAvoid, isTrue);
    expect(job.flow.blocks[1].spaceBefore, isNot(11));
    expect(job.flow.blocks[2].spaceBefore, isNot(11));
  });

  test('冻结文字覆盖参与混排测量，同文不同作者样式保留各自 run', () async {
    final chapter = await _TestChapter.open(
      '<p class="red"><span>同文混排</span>$_sentence</p>'
          '<p class="blue"><span>同文混排</span>$_sentence</p>',
      '.red span {color:red;font-size:12px;} '
          '.blue span {color:blue;font-size:24px;font-family:monospace;}',
    );
    final probe = chapter.job();
    final cfi = probe.node('red').cfi.serialize();
    final job = chapter.job(
      overlays: ReaderTextOverlayResolver([
        ReaderTextOverlay(
          startCfi: cfiWithCharOffset(cfi, 4),
          endCfi: cfiWithCharOffset(cfi, 8),
          fontWeight: 700,
          fontSizeScale: 1.25,
        ),
      ]),
    );
    await job.buildClass('red');
    await job.buildClass('blue');
    final blocks = job.flow.blocks;
    expect(blocks[0].layout.runs.first.style.fontSize, 12);
    expect(blocks[1].layout.runs.first.style.fontSize, 24);
    expect(blocks[0].layout.runs.first.style.color.toARGB32(), 0xffff0000);
    expect(blocks[1].layout.runs.first.style.color.toARGB32(), 0xff0000ff);
    expect(
      blocks[0].layout.runs.any((run) => run.style.fontWeight == 700),
      isTrue,
    );
    expect(identical(blocks[0].layout, blocks[1].layout), isFalse);
  });

  test('异步 run 解析保持最深级联、混合字体与上标位移', () async {
    final chapter = await _TestChapter.open(
      '<p class="target">甲<span class="outer">乙<b>丙</b>丁</span><sup>上</sup>戊</p>',
      '.outer {font-family:monospace;color:red;} b {font-size:24px;color:blue;}',
    );
    final job = chapter.job();
    final resolver = job.builder.styles;
    final context = (
      ancestors: job.ancestors('target'),
      style: _base,
      width: 344.0,
      readerFontFamily: null,
    );
    final marks = job.node('target').inlineMarks;
    final synchronous = resolver.resolveInlineRuns(marks, context);
    var checks = 0;
    final asynchronous = await resolver.resolveInlineRunsAsync(
      marks,
      context,
      checkpoint: () async {
        checks += 1;
      },
    );
    expect(_runStructure(asynchronous), _runStructure(synchronous));
    final nested = asynchronous.firstWhere(
      (run) => run.start == 2 && run.end == 3,
    );
    expect(nested.style.fontSize, 24);
    expect(nested.style.fontFamily, contains('monospace'));
    expect(nested.style.color.toARGB32(), 0xff0000ff);
    expect(asynchronous.any((run) => run.baselineShift < 0), isTrue);
    expect(checks, greaterThan(marks.length));
  });

  test('长行内标记解析支持中途取消，不返回部分 run', () async {
    final chapter = await _TestChapter.open(
      '<p class="target">正文</p>',
      '.piece {color:red;}',
    );
    final job = chapter.job();
    final marks = List.generate(
      120,
      (index) => InlineMark(
        start: index * 2,
        end: index * 2 + 2,
        tag: 'span',
        classes: const ['piece'],
        chain: const [
          MarkSubject(
            tag: 'span',
            classes: {'piece'},
            attributes: {'class': 'piece'},
          ),
        ],
      ),
    );
    final context = (
      ancestors: job.ancestors('target'),
      style: _base,
      width: 344.0,
      readerFontFamily: null,
    );
    var checks = 0;
    final budget = _CancellingBudget(() => ++checks == marks.length + 10);
    await expectLater(
      job.builder.styles.resolveInlineRunsAsync(
        marks,
        context,
        checkpoint: budget.checkpoint,
      ),
      throwsA(isA<ChapterLoadCancelled>()),
    );
    expect(budget.yieldCount, greaterThan(0));
    expect(job.flow.blocks, isEmpty);
    expect(job.cache.misses, 0);
  });

  test('逐行测量中取消，不追加当前段落或缓存半成品', () async {
    final chapter = await _TestChapter.open(
      '<p class="target">${_sentence * 80}</p>',
      '',
    );
    late _TestJob job;
    var measuringChecks = 0;
    final budget = _CancellingBudget(
      () => job.cache.misses > 0 && ++measuringChecks == 3,
    );
    job = chapter.job(budget: budget);
    await expectLater(
      job.buildClass('target'),
      throwsA(isA<ChapterLoadCancelled>()),
    );
    expect(measuringChecks, 3);
    expect(job.flow.blocks, isEmpty);
    expect(job.flow.fixedBlocks, isEmpty);
    expect(job.cache.length, 0);
    expect(budget.yieldCount, greaterThan(0));
  });

  test('行内盒测量中取消，已完成的内盒不能作为正文块追加', () async {
    final chapter = await _TestChapter.open(
      '<p class="target"><span class="box">内盒内容</span>${_sentence * 4}</p>',
      '.box {display:inline-block;padding:2px;border:1px solid red;}',
    );
    late _TestJob job;
    final budget = _CancellingBudget(() => job.cache.length > 0);
    job = chapter.job(budget: budget);
    await expectLater(
      job.buildClass('target'),
      throwsA(isA<ChapterLoadCancelled>()),
    );
    expect(job.flow.blocks, isEmpty);
    expect(job.flow.fixedBlocks, isEmpty);
    expect(job.cache.length, 1, reason: '只允许保留已经完成的内盒测量');
  });

  test('取消作业不进入文字生成或测量', () async {
    final chapter = await _TestChapter.open(
      '<p class="target">正文</p>',
      '.target {counter-increment:n;}',
    );
    final budget = _CancellingBudget(() => false)..cancel();
    final job = chapter.job(budget: budget);
    await expectLater(
      job.buildClass('target'),
      throwsA(isA<ChapterLoadCancelled>()),
    );
    expect(job.flow.blocks, isEmpty);
    expect(job.content.cssCounters, isEmpty);
    expect(job.cache.misses, 0);
  });
}

List<Object?> _runStructure(List<StyledRun> runs) => [
  for (final run in runs)
    [
      run.start,
      run.end,
      run.baselineShift,
      run.style.values,
      run.style.declaredTextProperties,
      run.style.layoutFingerprint,
    ],
];

class _TestChapter {
  _TestChapter(this.resources, this.fonts, this.css, this.selectors);
  final BookResources resources;
  final BookFonts fonts;
  final ChapterStyles css;
  final ChapterSelectors selectors;

  static Future<_TestChapter> open(String body, String css) async {
    final document = (await openEpub(
      _book(body, css),
      verifyCrc: false,
    )).document!;
    final resources = BookResources(document);
    addTearDown(resources.close);
    final fonts = BookFonts(resources, onFontsChanged: (_) {});
    addTearDown(fonts.close);
    final styles = ChapterStyles(resources, fonts);
    addTearDown(styles.close);
    return _TestChapter(
      resources,
      fonts,
      styles,
      ChapterSelectors(resources.parsedChapter(0).root),
    );
  }

  _TestJob job({
    LayoutBudget? budget,
    ReaderOverrides overrides = const ReaderOverrides(),
    ReaderTextOverlayResolver? overlays,
  }) {
    final view = fonts.freeze();
    final snapshot = LayoutSnapshot(
      spineIndex: 0,
      key: '构块测试',
      contentVersion: '1',
      generation: 1,
      width: 344,
      height: 250,
      pageHeight: 350,
      topInset: 24,
      baseStyle: _base,
      overrides: overrides,
      textOverlays: overlays ?? ReaderTextOverlayResolver(const []),
      fontDependency: view.dependency(const {'serif', 'monospace'}),
      fonts: view,
      fontFamilies: const {'serif', 'monospace'},
      trimTextEdges: false,
    );
    final resolver = ChapterStyleResolver(
      snapshot,
      selectors,
      css.prepare(css.stylesheets(0, width: snapshot.width)),
    );
    return _TestJob.create(
      resolver,
      resources,
      budget ??
          LayoutBudget(
            priority: ChapterLayoutPriority.reading,
            isCurrent: () => true,
          ),
    );
  }
}

class _TestJob {
  _TestJob(this.builder, this.content, this.flow, this.cache, this.root);
  final TextBlockBuilder builder;
  final GeneratedChapterContent content;
  final ChapterFlow flow;
  final TextLayoutCache cache;
  final BlockNode root;

  factory _TestJob.create(
    ChapterStyleResolver styles,
    BookResources resources,
    LayoutBudget budget,
  ) {
    final cache = TextLayoutCache();
    final measure = ChapterTextMeasurer(
      styles.snapshot,
      budget,
      cache,
      BoundedCache<String, double>(128),
    );
    final content = GeneratedChapterContent(
      styles,
      (src) => resources.imageUrl(0, src),
    );
    final inline = InlineContentBuilder(styles, content, measure, resources);
    final flow = ChapterFlow();
    final parsed = resources.parsedChapter(0);
    final root = TextAggregator.aggregate(
      BlockBuilder.build(parsed),
      inlineDisplay: styles.inlineDisplay,
      whiteSpaceFor: (node, _) => styles
          .chainStyle(styles.selectorIndex.chainOf(node) ?? const [])
          .whiteSpace,
    ).root;
    return _TestJob(
      TextBlockBuilder(styles, inline, content, flow),
      content,
      flow,
      cache,
      root,
    );
  }

  List<SelectorElement> ancestors(String name) =>
      builder.styles.selectorIndex.chains.firstWhere(
        (chain) =>
            (chain.last.attributes['class'] ?? '').split(' ').contains(name),
      );

  TextContentNode node(String name) {
    final element = _findBlock(root, name)!;
    return element.children.whereType<TextContentNode>().single;
  }

  Future<void> buildClass(String name, {BlockPosition? position}) => builder
      .build(node(name), position ?? BlockPosition(ancestors: ancestors(name)));

  static BlockNode? _findBlock(BlockNode block, String name) {
    if ((block.attributes['class'] ?? '').split(' ').contains(name)) {
      return block;
    }
    for (final child in block.children.whereType<BlockNode>()) {
      final result = _findBlock(child, name);
      if (result != null) return result;
    }
    return null;
  }
}

class _CancellingBudget extends LayoutBudget {
  _CancellingBudget(this.shouldCancel)
    : super(priority: ChapterLayoutPriority.reading, isCurrent: () => true);
  final bool Function() shouldCancel;
  @override
  Future<void> checkpoint({bool force = false}) async {
    if (shouldCancel()) cancel();
    await super.checkpoint(force: true);
  }
}

Uint8List _book(String body, String css) {
  final archive = Archive();
  final files = {
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml':
        '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">'
        '<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>',
    'OEBPS/content.opf':
        '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">'
        '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">text-builder</dc:identifier>'
        '<dc:title>文字构块</dc:title><dc:language>zh</dc:language></metadata><manifest>'
        '<item id="c" href="Text/c.xhtml" media-type="application/xhtml+xml"/></manifest>'
        '<spine><itemref idref="c"/></spine></package>',
    'OEBPS/Text/c.xhtml':
        '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">'
        '<head><style>$css</style></head><body>$body</body></html>',
  };
  for (final entry in files.entries) {
    final bytes = utf8.encode(entry.value);
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  final image = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==',
  );
  archive.addFile(ArchiveFile('OEBPS/Images/i.png', image.length, image));
  return ZipEncoder().encodeBytes(archive);
}
