import 'dart:convert';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/cascade.dart';
import 'package:reader_core/css/parser.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/css/selector.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_mobile/reader/epub/book_fonts.dart';
import 'package:reader_mobile/reader/epub/book_resources.dart';
import 'package:reader_mobile/reader/epub/chapter_selectors.dart';
import 'package:reader_mobile/reader/epub/chapter_styles.dart';
import 'package:reader_ui/reader_session.dart';

const _container = '''
<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">
<rootfiles><rootfile full-path="OEBPS/content.opf"
media-type="application/oebps-package+xml"/></rootfiles></container>''';
const _package = '''
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:identifier id="id">chapter-styles</dc:identifier><dc:title>章节样式</dc:title>
<dc:language>zh</dc:language></metadata><manifest>
<item id="c" href="Text/c.xhtml" media-type="application/xhtml+xml"/>
</manifest><spine><itemref idref="c"/></spine></package>''';

Future<BookResources> _resources({
  String head = '',
  String body = '<p class="target">正文</p>',
  Map<String, String> files = const {},
  Map<String, List<int>> binaryFiles = const {},
  int chapters = 1,
}) async {
  final archive = Archive();
  for (final entry in <String, String>{
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml': _container,
    'OEBPS/content.opf': _package.replaceFirst(
      '<itemref idref="c"/>',
      List.filled(chapters, '<itemref idref="c"/>').join(),
    ),
    'OEBPS/Text/c.xhtml':
        '<html xmlns="http://www.w3.org/1999/xhtml"><head>$head</head><body>$body</body></html>',
    ...files,
  }.entries) {
    final bytes = utf8.encode(entry.value);
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  for (final entry in binaryFiles.entries) {
    archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
  }
  final opened = await openEpub(
    ZipEncoder().encodeBytes(archive),
    verifyCrc: false,
  );
  return BookResources(opened.document!);
}

List<SelectorElement> _paragraph(ChapterSelectors selectors) =>
    selectors.chains.firstWhere((chain) => chain.last.tag == 'p');

int _holdWorker(SendPort ready) {
  ready.send(true);
  while (true) {}
}

List<int> _utf16(String text) => [
  0xff,
  0xfe,
  for (final unit in text.codeUnits) ...[unit & 0xff, unit >> 8],
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('异步样式保留 UTF16、重复导入与媒体顺序，跨章复用作者表身份', () async {
    final resources = await _resources(
      chapters: 2,
      head:
          '<style>p{color:red}</style>'
          '<link rel="stylesheet" href="../Styles/a.css"/>'
          '<link rel="stylesheet" media="(min-width:500px)" href="../Styles/a.css"/>',
      files: {'OEBPS/Images/p.png': '图片', 'OEBPS/Fonts/book.otf': '字体'},
      binaryFiles: {
        'OEBPS/Styles/a.css': _utf16(
          '@import "b.css" screen;'
          'p{color:blue;background:url("../Images/p.png")}',
        ),
        'OEBPS/Styles/b.css': _utf16(
          '@import "a.css";p{font-family:"正文"}'
          '@font-face{font-family:"正文";src:url("../Fonts/book.otf")}',
        ),
      },
    );
    final fonts = BookFonts(resources, onFontsChanged: (_) {});
    final styles = ChapterStyles(resources, fonts);
    addTearDown(() async {
      styles.close();
      fonts.close();
      resources.close();
      await styles.preparationsStopped;
      await resources.preparationsStopped;
    });
    final narrow = await styles.prepareStylesheets(0, width: 320);
    final wide = await styles.prepareStylesheets(0, width: 640);
    final other = await styles.prepareStylesheets(1, width: 640);
    expect(narrow, hasLength(3));
    expect(wide, hasLength(5));
    expect(wide[1].mediaConditions, ['screen']);
    expect(wide[3].mediaConditions, ['(min-width:500px)', 'screen']);
    expect(wide[1].fontFaces.single.family, '正文');
    expect(wide[1].fontFaces.single.sources.single.ref, 'OEBPS/Fonts/book.otf');
    expect(
      wide[2].rules.single.declarations.last.value,
      'url("OEBPS/Images/p.png")',
    );
    expect(wide[1].rules, same(wide[3].rules));
    expect(wide[1].rules, same(other[1].rules));
    expect(wide[1].fontFaces, same(other[1].fontFaces));
    expect(styles.stylesheets(1, width: 640)[1].rules, same(wide[1].rules));
  });

  test('样式等待者取消互不干扰，阅读升级抢占 worker 后台工作', () async {
    final resources = await _resources(head: '<style>p{color:red}</style>');
    final fonts = BookFonts(resources, onFontsChanged: (_) {});
    final styles = ChapterStyles(resources, fonts);
    final ready = ReceivePort();
    addTearDown(() async {
      styles.close();
      fonts.close();
      resources.close();
      ready.close();
      await styles.preparationsStopped;
      await resources.preparationsStopped;
    });
    await resources.prepareStyleSources(0);
    final background = resources.preparationWorker.schedule(
      '占用后台槽',
      () => ready.sendPort,
      _holdWorker,
      priority: ChapterLayoutPriority.pageCount,
    );
    await ready.first;
    final preempted = expectLater(
      background.result,
      throwsA(isA<ChapterLoadCancelled>()),
    );
    final first = styles.scheduleStylesheets(
      0,
      width: 320,
      priority: ChapterLayoutPriority.pageCount,
    );
    final second = styles.scheduleStylesheets(
      0,
      width: 640,
      priority: ChapterLayoutPriority.pageCount,
    );
    // 让章节准备持有正在等待的 CSS worker 子任务，再验证优先级沿链传播。
    await Future<void>.delayed(Duration.zero);
    final cancelled = expectLater(
      first.result,
      throwsA(isA<ChapterLoadCancelled>()),
    );
    first.cancel();
    second.promote(ChapterLayoutPriority.reading);
    await cancelled;
    final sheets = await second.result;
    await preempted;
    expect(sheets.single.rules.single.declarations.single.value, 'red');
    await resources.preparationWorker.idle;
    expect(resources.preparationWorker.activeIsolates, 0);
    expect(resources.preparationWorker.openPortCount, 0);
  });

  test('关闭样式准备取消排队解析并阻止晚到结果回填', () async {
    final resources = await _resources(head: '<style>p{color:red}</style>');
    final fonts = BookFonts(resources, onFontsChanged: (_) {});
    final styles = ChapterStyles(resources, fonts);
    final ready = ReceivePort();
    addTearDown(() async {
      styles.close();
      fonts.close();
      resources.close();
      ready.close();
      await styles.preparationsStopped;
      await resources.preparationsStopped;
    });
    await resources.prepareStyleSources(0);
    final blocker = resources.preparationWorker.schedule(
      '占用阅读槽',
      () => ready.sendPort,
      _holdWorker,
    );
    await ready.first;
    final handle = styles.scheduleStylesheets(0, width: 320);
    final cancelled = expectLater(
      handle.result,
      throwsA(isA<ChapterLoadCancelled>()),
    );
    await Future<void>.delayed(Duration.zero);
    styles.close();
    await cancelled;
    await styles.preparationsStopped;
    expect(styles.cacheReport, contains('样式章索引 0/'));
    final released = expectLater(
      blocker.result,
      throwsA(isA<ChapterLoadCancelled>()),
    );
    blocker.cancel();
    await released;
    await resources.preparationWorker.idle;
    expect(resources.preparationWorker.activeIsolates, 0);
    expect(resources.preparationWorker.openPortCount, 0);
  });

  test('CSS 导入与内外链顺序决定作者覆盖，资源 URL 按各来源目录解析', () async {
    final resources = await _resources(
      head:
          '<style>.target {color:#111111}</style>'
          '<link rel="stylesheet" href="../Styles/order.css"/>'
          '<style>.target {color:#444444}</style>',
      files: {
        'OEBPS/Styles/shared.css': '.target {color:#222222}',
        'OEBPS/Styles/order.css':
            '@import "shared.css"; '
            '.target {color:#333333;background-image:url("../Images/p.png")}'
            '@font-face {font-family: Book;src:local("宋体"),url("../Fonts/book.otf")}',
        'OEBPS/Images/p.png': '图像资源占位字节',
        'OEBPS/Fonts/book.otf': '字体资源占位字节',
      },
    );
    addTearDown(resources.close);
    final fonts = BookFonts(resources, onFontsChanged: (_) {});
    addTearDown(fonts.close);
    final styles = ChapterStyles(resources, fonts);
    addTearDown(styles.close);
    final sheets = styles.stylesheets(0, width: 320);
    expect(
      sheets
          .expand((sheet) => sheet.rules)
          .expand((rule) => rule.declarations)
          .where((item) => item.property == 'color')
          .map((item) => item.value),
      ['#111111', '#222222', '#333333', '#444444'],
    );
    final background = sheets
        .expand((sheet) => sheet.rules)
        .expand((rule) => rule.declarations)
        .firstWhere((item) => item.property == 'background-image');
    expect(background.value, 'url("OEBPS/Images/p.png")');
    final face = sheets.expand((sheet) => sheet.fontFaces).single;
    expect(face.sources.first.isLocal, isTrue);
    expect(face.sources.last.ref, 'OEBPS/Fonts/book.otf');
    final chain = _paragraph(ChapterSelectors(resources.parsedChapter(0).root));
    final prepared = styles.prepareBase(sheets);
    final computed = Cascade.compute(
      element: chain.last,
      ancestors: chain.sublist(0, chain.length - 1),
      rules: prepared.cascadeRules.candidatesFor(chain.last),
      viewportWidth: 320,
    );
    expect(computed.values['color'], '#444444');
  });

  test('章节来源缓存每次按快照宽度筛选，媒体条件保留逐层合取', () async {
    final resources = await _resources(
      head:
          '<style>.target {font-size:16px}</style>'
          '<link rel="stylesheet" media="(min-width:500px)" href="../Styles/wide.css"/>',
      files: {'OEBPS/Styles/wide.css': '.target {font-size:24px}'},
    );
    addTearDown(resources.close);
    final fonts = BookFonts(resources, onFontsChanged: (_) {});
    addTearDown(fonts.close);
    final styles = ChapterStyles(resources, fonts);
    addTearDown(styles.close);
    expect(styles.stylesheets(0, width: 320), hasLength(1));
    expect(styles.stylesheets(0, width: 640), hasLength(2));
    expect(styles.stylesheets(0, width: 320), hasLength(1));
    expect(
      ruleMediaMatches(null, ['screen, print', '(min-width:500px)'], 320),
      isFalse,
    );
    expect(
      ruleMediaMatches(null, ['screen, print', '(min-width:500px)'], 640),
      isTrue,
    );
    expect(ruleMediaMatches('print', [], 640), isFalse);
    expect(
      inlineDeclarationsOf('color:red;-reader-title-page:true;--token:Blue')
          .map((item) => item.property),
      ['color', '--token'],
    );
  });

  test('只选命中元素的书内字族，准备缓存共享选择器且保留原作者声明', () async {
    final resources = await _resources(
      body: '<p class="visible" style="font-family:inline_font">正文</p>',
    );
    addTearDown(resources.close);
    final fonts = BookFonts(resources, onFontsChanged: (_) {});
    addTearDown(fonts.close);
    final styles = ChapterStyles(resources, fonts);
    addTearDown(styles.close);
    final sheets = [
      CssParser.parse('''
@font-face {font-family:inline_font;src:local("宋体")}
@font-face {font-family:rule_font;src:local("宋体")}
@font-face {font-family:variable_font;src:local("宋体")}
@font-face {font-family:pseudo_font;src:local("宋体")}
@font-face {font-family:first_font;src:local("宋体")}
@font-face {font-family:wide_font;src:local("宋体")}
@font-face {font-family:unused_font;src:local("宋体")}
.visible {font-family:rule_font;--choice:variable_font;counter-reset:count}
.visible::before {content:'前缀';font-family:pseudo_font}
.visible::first-letter {font-family:first_font;font-size:24px}
@media (min-width:500px) {.visible {font-family:wide_font}}
.absent {font-family:unused_font}
'''),
    ];
    final selectors = ChapterSelectors(resources.parsedChapter(0).root);
    const normal = ReaderOverrides();
    final used = styles.usedBookFonts(sheets, selectors, normal, 320);
    expect(used.map((face) => face.family), [
      'inline_font',
      'rule_font',
      'variable_font',
      'pseudo_font',
      'first_font',
    ]);
    expect(
      styles
          .usedBookFonts(sheets, selectors, normal, 640)
          .map((face) => face.family),
      contains('wide_font'),
    );
    expect(
      styles.usedBookFonts(
        sheets,
        selectors,
        const ReaderOverrides(
          fontFamily: 'user_test',
          overrideEmbeddedFonts: true,
        ),
        640,
      ),
      isEmpty,
    );
    final base = styles.prepareBase(sheets);
    expect(styles.prepare(sheets), same(base));
    await fonts.ensure(used);
    final rewritten = styles.prepare(sheets);
    expect(styles.prepareBase(sheets), same(base));
    expect(styles.prepare(sheets), same(rewritten));
    expect(
      rewritten.firstLetterRules.single.selectors,
      same(base.firstLetterRules.single.selectors),
    );
    expect(
      rewritten.pseudoRules['::before']!.single.declarations.last.value,
      '"builtin_song"',
    );
    expect(
      base.pseudoRules['::before']!.single.declarations.last.value,
      'pseudo_font',
    );
    expect(
      rewritten.auxiliaryRules.single.declarations.first.value,
      '"builtin_song"',
    );
  });
}
