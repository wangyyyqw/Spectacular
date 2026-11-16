import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/epub/epub_format_opener.dart';
import 'package:reader_core/epub/chapter/chapter_layout_cache.dart';
import 'package:reader_core/layout/paginator.dart';
import 'package:reader_core/layout/table_layout.dart' show TableCellRender;
import 'package:reader_core/parser/document_parser.dart';
import 'package:reader_core/position/cfi.dart';
import 'package:reader_core/position/text_cfi_map.dart';
import 'package:reader_core/source/chapter_source.dart';
import 'package:reader_core/source/format_opener.dart';

import '../audit/audit_epub_fixture.dart';

Uint8List _epub(String body, String css) => auditZip({
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml':
      '<container><rootfiles><rootfile full-path="book.opf"/>'
      '</rootfiles></container>',
  'book.opf':
      '<package version="3.0" unique-identifier="id" '
      'xmlns="http://www.idpf.org/2007/opf"><metadata '
      'xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:identifier id="id">cfi-source-map</dc:identifier>'
      '<dc:title>字符块坐标回归</dc:title></metadata><manifest>'
      '<item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="img" href="image.png" media-type="image/png"/>'
      '</manifest><spine><itemref idref="c"/></spine></package>',
  'c.xhtml':
      '<html xmlns="http://www.w3.org/1999/xhtml"><head><style>'
      'body,p{margin:0;padding:0}p{word-break:break-all}$css'
      '</style></head><body>$body</body></html>',
  'image.png': base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=',
  ),
});

Future<EpubChapterSource> _source(String body, {String css = ''}) async {
  final source = await const EpubFormatOpener().openBytes(
    _epub(body, css),
    options: ReaderOpenOptions(
      contentWidth: 80,
      contentHeight: 120,
      trimTextEdges: false,
      style: ComputedStyle(const {
        'font-family': 'Ahem',
        'font-size': '16px',
        'line-height': '1.5',
      }),
    ),
  );
  addTearDown(source.close);
  return source;
}

String _cfi(String steps, int offset) => 'epubcfi(/6/2!/4$steps:$offset)';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('正式阅读锚点将段内 tail 偏移映射到 /5 并精确回读', () async {
    final source = await _source(
      '<p id="p">lead<b id="b">A</b><i id="i">B</i>tail</p>',
    );
    final chapter = await source.loadAnchorChapter(0);
    final expected = _cfi('/2[p]/5', 2);

    expect(chapter.text, 'leadABtail');
    expect(chapter.cfiAt(8), expected);
    expect(chapter.offsetFor(expected), 8);
    expect(source.cfiForReadingPercent(.8), expected);
    expect(source.readingPercentForCfi(expected), closeTo(.8, .0001));
    final resolved = source.document.resolveCfi(0, EpubCfi.parse(expected)!);
    expect(resolved.exact, isTrue);
    expect(resolved.textOffset, 2);
    final parsed = source.document.parseDocument(0);
    expect(
      (parsed.nodeAtCfi(EpubCfi.parse(expected)!) as ParsedText).text,
      'tail',
    );
  });

  test('段内元素起点与相邻字符块终点保留各自的规范 CFI', () async {
    final source = await _source(
      '<p id="p">lead<b id="b">A</b><i id="i">B</i>tail</p>',
    );
    final chapter = await source.loadAnchorChapter(0);

    expect(chapter.cfiAt(4), _cfi('/2[p]/2[b]/1', 0));
    expect(chapter.cfiAt(4, end: true), _cfi('/2[p]/1', 4));
    expect(chapter.cfiAt(5), _cfi('/2[p]/4[i]/1', 0));
    expect(chapter.cfiAt(6), _cfi('/2[p]/5', 0));
    expect(chapter.cfiAt(10, end: true), _cfi('/2[p]/5', 4));
    for (var offset = 0; offset <= chapter.text.length; offset++) {
      final cfi = chapter.cfiAt(offset, end: offset == chapter.text.length)!;
      expect(chapter.offsetFor(cfi), offset);
      expect(source.document.resolveCfi(0, EpubCfi.parse(cfi)!).exact, isTrue);
    }
  });

  test('实体、CDATA 与折叠空白的显示偏移映射回源字符块', () async {
    final source = await _source(
      '<p id="p">A &amp;<!--忽略--><![CDATA[😀]]>'
      '<b id="b">B</b> \n tail</p>',
    );
    final chapter = await source.loadAnchorChapter(0);

    expect(chapter.text, 'A &😀B tail');
    expect(chapter.cfiAt(5), _cfi('/2[p]/2[b]/1', 0));
    expect(chapter.cfiAt(5, end: true), _cfi('/2[p]/1', 5));
    expect(chapter.cfiAt(6), _cfi('/2[p]/3', 0));
    expect(chapter.cfiAt(7), _cfi('/2[p]/3', 3));
    expect(chapter.cfiAt(8), _cfi('/2[p]/3', 4));
    expect(chapter.offsetFor(_cfi('/2[p]/3', 4)), 8);
    expect(
      source.document.resolveCfi(0, EpubCfi.parse(chapter.cfiAt(8)!)!).exact,
      isTrue,
    );
  });

  test('正式原文锚点的 NBSP、双码元实体与 CDATA 保持解析偏移一致', () async {
    final source = await _source(
      '<p id="p">A&nbsp;&NotEqualTilde;<![CDATA[&copy;]]>'
      '<b id="b">X</b>&copy;&unknown;tail</p>',
    );
    final chapter = await source.loadAnchorChapter(0);
    expect(chapter.text, 'A\u00a0\u2242\u0338&copy;X© tail');
    expect(chapter.cfiAt(4), _cfi('/2[p]/1', 4));
    expect(chapter.cfiAt(10), _cfi('/2[p]/2[b]/1', 0));
    expect(chapter.cfiAt(11), _cfi('/2[p]/3', 0));
    expect(chapter.cfiAt(13), _cfi('/2[p]/3', 2));
    for (var offset = 0; offset <= chapter.text.length; offset++) {
      final cfi = chapter.cfiAt(offset, end: offset == chapter.text.length)!;
      expect(chapter.offsetFor(cfi), offset);
      final resolved = source.document.resolveCfi(0, EpubCfi.parse(cfi)!);
      expect(resolved.exact, isTrue);
      expect(resolved.textOffset, cfiCharOffset(cfi));
    }
  });

  test('被折叠的首尾空白不再生成超出原文本的偏移', () async {
    final source = await _source('<p id="p"> \n  a   b \n </p>');
    final chapter = await source.loadAnchorChapter(0);

    expect(chapter.text, 'a b');
    expect(chapter.cfiAt(0), _cfi('/2[p]/1', 4));
    expect(chapter.cfiAt(1, end: true), _cfi('/2[p]/1', 5));
    expect(chapter.cfiAt(2), _cfi('/2[p]/1', 8));
    expect(chapter.cfiAt(3, end: true), _cfi('/2[p]/1', 9));
    expect(chapter.offsetFor(_cfi('/2[p]/1', 6)), 1);
  });

  test('正式分页的每页首行通过同一来源映射往返到字符块', () async {
    final source = await _source(
      '<p id="p">lead<b id="b">A</b><i id="i">B</i>${'tail' * 11}</p>',
      css: 'p{width:64px}',
    );
    final chapter = await source.loadAnchorChapter(0);
    final pages = await source.loadChapter(0);

    expect(pages.length, 3);
    final starts = <String>[];
    for (final page in pages) {
      final slice = page.slices.single;
      final line = slice.block.layout.lines[slice.startLine];
      final cfi = slice.block.cfiAt(line.start)!;
      starts.add(cfi);
      expect(slice.block.offsetForCfi(cfi), line.start);
      expect(chapter.offsetFor(cfi), line.start);
      expect(source.document.resolveCfi(0, EpubCfi.parse(cfi)!).exact, isTrue);
    }
    expect(starts, [
      _cfi('/2[p]/1', 0),
      _cfi('/2[p]/5', 14),
      _cfi('/2[p]/5', 34),
    ]);
  });

  test('大小写变换保留 CFI 与行内样式的同一显示范围', () async {
    final source = await _source(
      '<p id="p">xa<b id="b">b</b>tail</p>',
      css: 'p{text-transform:uppercase}',
    );
    final chapter = await source.loadAnchorChapter(0);
    final pages = await source.loadChapter(0);
    final block = pages.first.slices.single.block;

    expect(chapter.text, 'xabtail');
    expect(block.layout.text, 'XABTAIL');
    expect(block.cfiAt(1), _cfi('/2[p]/1', 1));
    expect(block.cfiAt(2, end: true), _cfi('/2[p]/1', 2));
    expect(block.cfiAt(2), _cfi('/2[p]/2[b]/1', 0));
    expect(block.cfiAt(5), _cfi('/2[p]/3', 2));
    expect(block.offsetForCfi(_cfi('/2[p]/3', 2)), 5);
    expect(block.rangeForCfis(_cfi('/2[p]/1', 1), _cfi('/2[p]/1', 2)), (1, 2));
    final bold = block.layout.runs.where((run) => run.style.fontWeight >= 700);
    expect(bold.map((run) => (run.start, run.end)), [(2, 3)]);
  });

  test('制表符实测展开后页内偏移仍回到原始 UTF-16 字符', () async {
    final source = await _source(
      '<p id="p">a\tb</p>',
      css: 'p{white-space:pre;tab-size:8}',
    );
    final chapter = await source.loadAnchorChapter(0);
    final pages = await source.loadChapter(0);
    final block = pages.first.slices.single.block;

    expect(chapter.text, 'a\tb');
    expect(block.layout.text, 'a       b');
    expect(block.cfiAt(8), _cfi('/2[p]/1', 2));
    expect(block.offsetForCfi(_cfi('/2[p]/1', 2)), 8);
    expect(block.rangeForCfis(_cfi('/2[p]/1', 1), _cfi('/2[p]/1', 2)), (1, 8));
    expect(chapter.offsetFor(block.cfiAt(8)!), 2);
  });

  test('表格 trim 和拼接保留来源字符块，格载荷与阅读锚点一致', () async {
    final source = await _source(
      '<p>before</p><table><tr><td id="cell"><p id="p">'
      ' lead<b id="b">A</b><i id="i">B</i>tail '
      '</p></td></tr></table><p>after</p>',
    );
    final chapter = await source.loadAnchorChapter(0);
    final pages = await source.loadChapter(0);
    final cell = pages
        .expand((page) => page.slices)
        .expand(
          (slice) => slice.block.table?.cells ?? const <TableCellRender>[],
        )
        .first;
    final expected = _cfi('/4/2/2[cell]/2[p]/5', 2);

    expect(cell.layout.text, 'leadABtail');
    expect(cell.cfiAt(8), expected);
    expect(cell.offsetForCfi(expected), 8);
    expect(chapter.offsetFor(expected), 'before'.length + 8);
    expect(chapter.cfiAt('before'.length + 8), expected);
  });

  test('行内原子盒保留自身来源，摘除后的正文仍定位 tail', () async {
    final source = await _source(
      '<p id="p">lead<span id="s" style="display:inline-block">'
      'inside<b id="b">x</b></span>tail</p>',
    );
    final chapter = await source.loadAnchorChapter(0);
    final pages = await source.loadChapter(0);
    final block = pages.first.slices.first.block;
    final payload = block.layout.lines
        .expand((line) => line.inlineBoxes)
        .map((box) => box.spec.payload)
        .whereType<PageBlock>()
        .first;

    expect(chapter.text, 'leadinsidextail');
    expect(block.layout.text, 'leadtail');
    expect(block.cfiAt(4), _cfi('/2[p]/3', 0));
    expect(payload.layout.text, 'insidex');
    expect(payload.cfiAt(6), _cfi('/2[p]/2[s]/2[b]/1', 0));
    expect(chapter.offsetFor(payload.cfiAt(6)!), 10);
    expect(payload.offsetForCfi(_cfi('/2[p]/2[s]/2[b]/1', 0)), 6);
  });

  test('自动引号不生成 XML 字符偏移，正文和装饰区间避开伪文字', () async {
    final source = await _source('<p id="p">pre<q id="q">x</q>tail</p>');
    final chapter = await source.loadAnchorChapter(0);
    final pages = await source.loadChapter(0);
    final block = pages.first.slices.first.block;

    expect(chapter.text, 'prextail');
    expect(block.layout.text, 'pre“x”tail');
    expect(block.cfiAt(4), _cfi('/2[p]/2[q]/1', 0));
    expect(block.cfiAt(6), _cfi('/2[p]/3', 0));
    expect(block.offsetForCfi(_cfi('/2[p]/3', 2)), 8);
    expect(
      block.rangeForCfis(_cfi('/2[p]/2[q]/1', 0), _cfi('/2[p]/2[q]/1', 1)),
      (4, 5),
    );
    expect(block.rangeForCfis(_cfi('/2[p]/3', 0), _cfi('/2[p]/3', 1)), (6, 7));
  });

  test('相邻引号同边界先关闭后开启，字符区间不包含生成的引号', () async {
    final source = await _source(
      '<p id="p">pre<q id="q">x</q><q id="r">y</q>tail</p>',
    );
    final block = (await source.loadChapter(0)).first.slices.first.block;
    expect(block.layout.text, 'pre“x”“y”tail');
    expect(
      block.rangeForCfis(_cfi('/2[p]/4[r]/1', 0), _cfi('/2[p]/4[r]/1', 1)),
      (7, 8),
    );
    expect(block.rangeForCfis(_cfi('/2[p]/5', 0), _cfi('/2[p]/5', 1)), (9, 10));
  });

  test('首字下沉切片保持原始字符偏移与后续行内来源', () async {
    final source = await _source(
      '<p id="p">ab<b id="b">B</b>tail</p>',
      css: 'p{initial-letter:2}p::first-letter{color:red}',
    );
    final pages = await source.loadChapter(0);
    final blocks = pages
        .expand((page) => page.slices)
        .map((slice) => slice.block);
    final cap = blocks.firstWhere((block) => block.layout.text == 'a');
    final rest = blocks.firstWhere((block) => block.layout.text == 'bBtail');

    expect(cap.cfiAt(0), _cfi('/2[p]/1', 0));
    expect(cap.cfiAt(1, end: true), _cfi('/2[p]/1', 1));
    expect(rest.cfiAt(0), _cfi('/2[p]/1', 1));
    expect(rest.cfiAt(1), _cfi('/2[p]/2[b]/1', 0));
    expect(rest.cfiAt(4), _cfi('/2[p]/3', 2));
  });

  test('图片占位的起止亲和与纯图章节锚点保留元素位置', () async {
    final source = await _source(
      '<p id="p">a<img id="img" src="image.png"/>tail</p>',
    );
    final chapter = await source.loadAnchorChapter(0);
    final pages = await source.loadChapter(0);
    final block = pages.first.slices.first.block;
    const image = 'epubcfi(/6/2!/4/2[p]/2[img])';
    expect(chapter.cfiAt(1), image);
    expect(block.offsetForCfi(image), 1);
    expect(block.offsetForCfi(image, end: true), 2);
    expect(block.rangeForCfis(image, _cfi('/2[p]/3', 1)), (1, 3));

    final imageOnly = await _source('<p><img id="only" src="image.png"/></p>');
    final imageChapter = await imageOnly.loadAnchorChapter(0);
    expect(imageChapter.text, isEmpty);
    const only = 'epubcfi(/6/2!/4/2/2[only])';
    expect(imageOnly.isValidElementCfi(only), isTrue);
    expect(imageOnly.cfiForReadingPercent(.5), only);
    expect(imageOnly.readingPercentForCfi(only), 0);
  });

  test('来源映射按片检查取消，缓存估算计入 CFI 与变换元数据', () async {
    final source = await _source('<p id="p">${'a<span>b</span>' * 40}</p>');
    final pages = await source.loadChapter(0);
    final block = pages.first.slices.first.block;
    final withoutMap = PageBlock(
      layout: block.layout,
      style: block.style,
      startCfi: block.startCfi,
    );
    final withBytes = estimateLayoutBytes(const [], [block], const []);
    final withoutBytes = estimateLayoutBytes(const [], [withoutMap], const []);
    expect(
      withBytes - withoutBytes,
      greaterThan(block.textCfis!.runs.length * 64),
    );

    final mapping = TextCfiMap.linear(EpubCfi.parse(_cfi('/2[p]/1', 0))!, 4096);
    var checkpoints = 0;
    await expectLater(
      mapping.remapAsync(
        length: 8192,
        start: (offset) => offset * 2,
        end: (offset) => offset * 2,
        checkpoint: () async {
          if (++checkpoints == 3) throw const ChapterLoadCancelled();
        },
      ),
      throwsA(isA<ChapterLoadCancelled>()),
    );
    expect(checkpoints, 3);
    expect(mapping.cfiAt(4096, end: true), _cfi('/2[p]/1', 4096));
  });
}
