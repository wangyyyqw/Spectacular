import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_core/source/format_opener.dart';

import '../audit/audit_epub_fixture.dart';

const _titleCss = '''
h2 { font-family: Ahem; font-size: .95em; line-height: 150%;
  margin: -1em 0 2em .35em; border-width: 15px;
  border-style: dashed dashed dashed solid;
  border-color: transparent transparent transparent #ab2524; }
h2 b { font-size: 1.25em; padding: .1em .2em .1em .15em;
  border-style: none none solid none; border-width: 0 0 1px 0;
  border-color: #7a4c99; }
''';

Future<PageContent> _titlePage({bool padding = true}) async {
  final bytes = auditZip({
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml':
        '<container><rootfiles><rootfile '
        'full-path="book.opf"/></rootfiles></container>',
    'book.opf':
        '<package version="3.0" unique-identifier="id" '
        'xmlns="http://www.idpf.org/2007/opf"><metadata '
        'xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '<dc:identifier id="id">inline-padding</dc:identifier>'
        '<dc:title>行内标题回归</dc:title><dc:language>zh</dc:language>'
        '</metadata><manifest><item id="c" href="c.xhtml" '
        'media-type="application/xhtml+xml"/></manifest>'
        '<spine><itemref idref="c"/></spine></package>',
    'c.xhtml':
        '<html xmlns="http://www.w3.org/1999/xhtml"><head>'
        '<style>$_titleCss ${padding ? '' : 'h2 b { padding: 0; }'}</style>'
        '</head><body><h2>第一章<br/><b>标题样式</b></h2>'
        '<p>相邻正文内容。</p></body></html>',
  });
  // 真机 384×853⅓ dp，扣除现有左右边距与上下各 20 dp 的页眉页脚。
  final source = await const EpubFormatOpener().openBytes(
    bytes,
    options: const ReaderOpenOptions(
      contentWidth: 366.6666666666667,
      contentHeight: 806.9333333333333,
    ),
  );
  addTearDown(source.close);
  await source.applyOverrides(
    const ReaderOverrides(fontSize: 17, lineHeight: 1.6, paragraphSpacing: 10),
  );
  return (await source.loadChapter(0)).first;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('章节标题行内内边距同时参与排版和文字位置', () async {
    final plain = await _titlePage(padding: false);
    final padded = await _titlePage();
    final plainLine = TextHitTester.lineBoxes(plain)
        .firstWhere((line) => line.text.contains('标题样式'));
    final paddedLine = TextHitTester.lineBoxes(padded)
        .firstWhere((line) => line.text.contains('标题样式'));
    final plainRect = TextHitTester.selectionRects(plainLine, 0, 4).first;
    final paddedRect = TextHitTester.selectionRects(paddedLine, 0, 4).first;
    // 行内元素基于标题的最终字号 17×.95×1.25 解析相对内边距。
    expect(paddedRect.left - plainRect.left, closeTo(20.1875 * .15, .01));
    final plainLayout = plainLine.slice.block.layout.lines[plainLine.lineIndex];
    final paddedLayout =
        paddedLine.slice.block.layout.lines[paddedLine.lineIndex];
    expect(paddedLayout.width - plainLayout.width, closeTo(20.1875 * .35, .01));
    expect(paddedLine.slice.block.style!.fontSize, closeTo(16.15, .01));
  });
}
