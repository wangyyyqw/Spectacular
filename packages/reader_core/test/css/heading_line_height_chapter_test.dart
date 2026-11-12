import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/layout/line_breaker.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/source/format_opener.dart';

import '../audit/audit_epub_fixture.dart';

const _title = '（完美世界/遮天/圣墟）三部曲';
const _css = '''
body { margin:0 .5%; line-height:130%; }
h3 { font-family:S1CJK; font-size:xx-large; text-align:center;
  text-indent:0; padding:25% 5px 5px; }
''';

Uint8List _fixture(String css, String body) => auditZip({
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml':
      '<container><rootfiles><rootfile full-path="book.opf"/>'
      '</rootfiles></container>',
  'book.opf':
      '<package version="3.0" unique-identifier="id" '
      'xmlns="http://www.idpf.org/2007/opf"><metadata '
      'xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="id">heading-line-height</dc:identifier>'
      '<dc:title>标题阅读行高回归</dc:title></metadata><manifest>'
      '<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>'
      '</manifest><spine><itemref idref="c"/></spine></package>',
  'c.xhtml':
      '<html xmlns="http://www.w3.org/1999/xhtml"><head>'
      '<style>$_css$css</style></head><body>$body</body></html>',
});

Future<EpubChapterSource> _source({
  String css = '',
  String body = '<h3>$_title</h3>',
  double? lineHeight = 1.6,
}) async {
  final source = await const EpubFormatOpener().openBytes(
    _fixture(css, body),
    options: const ReaderOpenOptions(
      contentWidth: 366.6666666666667,
      contentHeight: 773.1694444444445,
    ),
  );
  addTearDown(source.close);
  await source.applyOverrides(
    ReaderOverrides(fontSize: 21, lineHeight: lineHeight, paragraphSpacing: 10),
  );
  return source;
}

Future<PageContent> _page({
  String css = '',
  String body = '<h3>$_title</h3>',
  double? lineHeight = 1.6,
}) async => (await (await _source(
  css: css,
  body: body,
  lineHeight: lineHeight,
)).loadChapter(0)).single;

void _expectHeadingHeight(PageContent page, double height) {
  final layout = page.slices.single.block.layout;
  expect(layout.lines, hasLength(2));
  expect(page.slices.single.block.style!.fontSize, closeTo(42, .001));
  expect(page.slices.single.block.style!.lineHeight, closeTo(height, .001));
  for (final line in layout.lines) {
    expect(line.height, closeTo(height, .001));
  }
  expect(
    layout.lines[1].baseline - layout.lines[0].baseline,
    closeTo(height, .001),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final bytes = await File('../../test_fonts/SourceHanSerifSC-Regular.otf')
        .readAsBytes();
    await (FontLoader(
      'S1CJK',
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  });
  setUp(() {
    final previous = LineBreaker.preserveFractionalLineHeight;
    LineBreaker.preserveFractionalLineHeight = true;
    addTearDown(() => LineBreaker.preserveFractionalLineHeight = previous);
  });

  test('未单独声明行高的标题使用阅读器倍数并保留字号与原文', () async {
    final page = await _page();
    _expectHeadingHeight(page, 67.2);
    final block = page.slices.single.block;
    expect(block.layout.text, _title);
    expect(block.style!.textAlign.name, 'center');
    expect(block.style!.padding.top, greaterThan(0));
    final boxes = TextHitTester.lineBoxes(page).toList();
    expect(boxes, hasLength(2));
    expect(boxes[1].rect.top, greaterThanOrEqualTo(boxes[0].rect.bottom));
    final target = boxes[1];
    final selection = TextHitTester.selectionRects(target, 0, 1).single;
    final hit = TextHitTester.hitTest(
      page,
      Offset(target.rect.left + selection.left + .05, target.rect.center.dy),
    );
    expect(hit, isNotNull);
    expect(hit!.lineIndex, 1);
    expect(hit.charOffset, 0);
    expect(hit.textOffset, target.blockTextOffset);
  });

  test('更改阅读行高按标题最终字号重算', () async {
    _expectHeadingHeight(await _page(lineHeight: 1.8), 75.6);
  });

  test('标题内普通行内文字继承阅读器行高', () async {
    _expectHeadingHeight(await _page(body: '<h3><b>$_title</b></h3>'), 67.2);
  });

  test('标题重排后原文 CFI 与文本位置保持', () async {
    final source = await _source(lineHeight: null);
    final before = await source.loadAnchorChapter(0);
    final cfi = before.cfiAt(9)!;
    _expectHeadingHeight((await source.loadChapter(0)).single, 27.3);
    await source.applyOverrides(
      const ReaderOverrides(fontSize: 21, lineHeight: 1.6),
    );
    _expectHeadingHeight((await source.loadChapter(0)).single, 67.2);
    final after = await source.loadAnchorChapter(0);
    expect(after.text, before.text);
    expect(after.cfiAt(9), cfi);
    expect(after.offsetFor(cfi), 9);
  });

  test('浮动容器中的标题保留作者布局行高', () async {
    _expectHeadingHeight(
      await _page(
        css: '.panel { float:left; width:100%; }',
        body: '<div class="panel"><h3>$_title</h3></div>',
      ),
      27.3,
    );
  });

  for (final declaration in ['130%', '1.3', '20.8px', 'normal']) {
    test('标题明确声明 $declaration 时保留作者行高', () async {
      final page = await _page(css: 'h3 { line-height:$declaration; }');
      final style = page.slices.single.block.style!;
      if (declaration == 'normal') {
        expect(style.lineHeightFactor, isNull);
      } else {
        _expectHeadingHeight(page, declaration == '20.8px' ? 27.3 : 54.6);
      }
    });
  }

  test('标题字体简写中的行高仍由作者控制', () async {
    _expectHeadingHeight(
      await _page(css: 'h3 { font:bold xx-large/130% S1CJK; }'),
      54.6,
    );
  });

  test('局部容器明确声明的继承行高不被阅读设置覆盖', () async {
    _expectHeadingHeight(
      await _page(
        css: '.panel { line-height:130%; }',
        body: '<div class="panel"><h3>$_title</h3></div>',
      ),
      27.3,
    );
  });

  test('未设置阅读行高时继续保留作者的百分比继承', () async {
    _expectHeadingHeight(await _page(lineHeight: null), 27.3);
  });
}
