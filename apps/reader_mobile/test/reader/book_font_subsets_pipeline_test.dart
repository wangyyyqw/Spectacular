import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_core/layout/paginator.dart';

import 'support/css_chapter_book.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Uint8List regular;
  late Uint8List bold;
  setUpAll(() async {
    regular = await File('../../test_fonts/SourceHanSerifSC-Regular.otf')
        .readAsBytes();
    bold = await File('../../test_fonts/SourceHanSerifSC-Bold.otf')
        .readAsBytes();
  });

  test('章节正式入口按字符分片生成 runs，重复加载保留真实字体依赖', () async {
    final source = await openCssChapter(
      body: '<p>AB中文</p><p><b>AB中文</b></p>',
      css: '''
@font-face {font-family: Composite; src: url("../Fonts/latin.otf"); unicode-range: U+0-FF;}
@font-face {font-family: Composite; src: url("../Fonts/cjk.otf"); unicode-range: U+4E00-9FFF;}
p {font-family: Composite; margin: 0;}
''',
      binaryFiles: {
        'OEBPS/Fonts/latin.otf': regular,
        'OEBPS/Fonts/cjk.otf': bold,
      },
    );
    addTearDown(source.close);
    final pages = await source.loadChapter(0);
    final blocks = _paragraphs(pages).toList();
    expect(blocks, hasLength(2));
    for (final block in blocks) {
      expect(block.layout.runs.map((run) => (run.start, run.end)), [
        (0, 2),
        (2, 4),
      ]);
      expect(
        block.layout.runs.first.style.fontFamily,
        isNot(block.layout.runs.last.style.fontFamily),
      );
    }
    final dependency = source.layoutDependencyForSpine(0);
    expect(dependency, contains('composite=bi_'));
    final again = _paragraphs(await source.loadChapter(0)).toList();
    expect(source.layoutDependencyForSpine(0), dependency);
    expect(
      again.first.layout.runs.map((run) => run.style.fontFamily),
      blocks.first.layout.runs.map((run) => run.style.fontFamily),
    );
  });

  test('后章同族同字重不同来源不改前章字体与缓存，加载顺序不改变结果', () async {
    final bytes = _twoChapterBook(regular, bold);
    final source = await EpubChapterSource.open(
      bytes,
      contentWidth: 300,
      contentHeight: 500,
      verifyCrc: false,
    );
    addTearDown(source.close);
    final first = _paragraphs(await source.loadChapter(0)).single;
    final firstDependency = source.layoutDependencyForSpine(0);
    final second = _paragraphs(await source.loadChapter(1)).single;
    expect(
      first.layout.runs.single.style.fontFamily,
      isNot(second.layout.runs.single.style.fontFamily),
    );
    final again = _paragraphs(await source.loadChapter(0)).single;
    expect(source.layoutDependencyForSpine(0), firstDependency);
    expect(again.layout, same(first.layout), reason: '后章登记不能使前章已缓存几何失效');
    expect(
      again.layout.runs.single.style.fontFamily,
      first.layout.runs.single.style.fontFamily,
    );

    final reversed = await EpubChapterSource.open(
      bytes,
      contentWidth: 300,
      contentHeight: 500,
      verifyCrc: false,
    );
    addTearDown(reversed.close);
    final reverseSecond = _paragraphs(await reversed.loadChapter(1)).single;
    final reverseFirst = _paragraphs(await reversed.loadChapter(0)).single;
    expect(
      reverseFirst.layout.runs.single.style.fontFamily,
      first.layout.runs.single.style.fontFamily,
    );
    expect(
      reverseSecond.layout.runs.single.style.fontFamily,
      second.layout.runs.single.style.fontFamily,
    );
    expect(reversed.layoutDependencyForSpine(0), firstDependency);
  });
}

Iterable<PageBlock> _paragraphs(List<PageContent> pages) => pages
    .expand((page) => page.slices)
    .map((slice) => slice.block)
    .where((block) => block.layout.text == 'AB中文');

Uint8List _twoChapterBook(Uint8List regular, Uint8List bold) {
  final archive = Archive();
  final files = {
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml': '''
<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">
<rootfiles><rootfile full-path="content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>''',
    'content.opf': '''
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">font-scope</dc:identifier>
<dc:title>章节字体范围</dc:title><dc:language>zh</dc:language></metadata><manifest>
<item id="a" href="a.xhtml" media-type="application/xhtml+xml"/>
<item id="b" href="b.xhtml" media-type="application/xhtml+xml"/>
</manifest><spine><itemref idref="a"/><itemref idref="b"/></spine></package>''',
    for (final name in ['a', 'b'])
      '$name.xhtml':
          '''
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>正文</title><style>
@font-face {font-family: Shared; src: url("${name == 'a' ? 'regular' : 'bold'}.otf");}
p {font-family: Shared; margin: 0;}
</style></head><body><p>AB中文</p></body></html>''',
  };
  for (final entry in files.entries) {
    final bytes = utf8.encode(entry.value);
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  for (final entry in {'regular.otf': regular, 'bold.otf': bold}.entries) {
    archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
  }
  return ZipEncoder().encodeBytes(archive);
}
