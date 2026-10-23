import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/archive_reader.dart';
import 'package:reader_core/epub/container.dart';
import 'package:reader_core/epub/epub_exception.dart';
import 'package:reader_core/epub/opf.dart';
import 'package:reader_core/api.dart';
import 'package:reader_core/epub/toc.dart';

import '../support/corpus.dart';

const _ncxHeader = '''
<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <head><meta name="dtb:uid" content="urn:uuid:test"/></head>
  <docTitle><text>测试</text></docTitle>
  <navMap>
''';

const _ncxFooter = '''
  </navMap>
</ncx>
''';

const _opf = '''
<package version="3.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>测试</dc:title><dc:language>zh</dc:language>
    <dc:identifier id="uid">urn:uuid:test</dc:identifier>
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="c1" href="text/c1.xhtml" media-type="application/xhtml+xml"/>
    <item id="c2" href="text/c2.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine toc="ncx">
    <itemref idref="c1"/><itemref idref="c2"/>
  </spine>
</package>
''';

TocResult _parse(String body) {
  final package = OpfParser.parse(_opf);
  return TocParser.parseNcxText(
    '$_ncxHeader$body$_ncxFooter',
    ncxPath: 'OEBPS/toc.ncx',
    package: package,
    opfPath: 'OEBPS/content.opf',
  );
}

void main() {
  final corpus = findCorpusRoot();
  final skip = corpus == null ? '本地样本库缺失（test_corpus/ 不入库）' : null;

  test('NAV 缺失的 EPUB2 样本 NCX 层级与 playOrder 正确', () {
    final archive = EpubArchive.fromBytes(
      readSampleBytes(corpus, 'toc-ncx.epub')!,
    );
    final container = EpubContainer.parse(archive);
    final opf = OpfParser.parse(
      utf8.decode(archive.readBytes(container.rootfilePath)!),
    );
    final result = TocParser.parseNcx(
      archive: archive,
      package: opf,
      opfPath: container.rootfilePath,
    );
    expect(result.source, 'ncx');
    expect(result.entries, hasLength(3));
    expect(result.entries.map((e) => e.title), contains('第一章 旧纸'));
    expect(result.entries.map((e) => e.spineIndex), <int>[0, 1, 2]);
    expect(result.entries.map((e) => e.playOrder), <int>[1, 2, 3]);
  }, skip: skip);

  test('真实书 NCX：诸神愚戏 1541 项并可定位 spine', () {
    final archive = EpubArchive.fromBytes(
      readSampleBytes(corpus, 'real/zhushen-yuxi.epub')!,
    );
    final container = EpubContainer.parse(archive);
    final opf = OpfParser.parse(
      utf8.decode(archive.readBytes(container.rootfilePath)!),
    );
    final result = TocParser.parseNcx(
      archive: archive,
      package: opf,
      opfPath: container.rootfilePath,
    );
    expect(result.entries, isNotEmpty);
    expect(result.entries.first.spineIndex, greaterThanOrEqualTo(0));
    var count = 0;
    void walk(List<TocEntry> entries) {
      for (final entry in entries) {
        count++;
        walk(entry.children);
      }
    }

    walk(result.entries);
    expect(count, 1541);
  }, skip: skip);

  test('两级目录保留嵌套结构', () {
    const body = '''
    <navPoint id="p1" playOrder="1">
      <navLabel><text>第一卷</text></navLabel>
      <content src="text/c1.xhtml#part1"/>
      <navPoint id="p1c1" playOrder="2">
        <navLabel><text>第一章</text></navLabel>
        <content src="text/c1.xhtml"/>
      </navPoint>
      <navPoint id="p1c2" playOrder="3">
        <navLabel><text>第二章</text></navLabel>
        <content src="text/c2.xhtml"/>
      </navPoint>
    </navPoint>
''';
    final result = _parse(body);
    expect(result.entries, hasLength(1));
    final root = result.entries.single;
    expect(root.title, '第一卷');
    expect(root.fragment, 'part1');
    expect(root.children.map((e) => e.title), <String>['第一章', '第二章']);
    expect(root.children.map((e) => e.spineIndex), <int>[0, 1]);
    expect(root.children.map((e) => e.playOrder), <int>[2, 3]);
  });

  test('缺失 playOrder 时按文档顺序编号', () {
    const body = '''
    <navPoint id="a"><navLabel><text>A</text></navLabel><content src="text/c1.xhtml"/></navPoint>
    <navPoint id="b"><navLabel><text>B</text></navLabel><content src="text/c2.xhtml"/></navPoint>
''';
    final result = _parse(body);
    expect(result.entries.map((e) => e.playOrder), <int>[1, 2]);
  });

  test('缺失 navMap 与非法 XML 分别报错', () {
    final package = OpfParser.parse(_opf);
    expect(
      () => TocParser.parseNcxText(
        '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/"><head/></ncx>',
        ncxPath: 'OEBPS/toc.ncx',
        package: package,
        opfPath: 'OEBPS/content.opf',
      ),
      throwsA(
        isA<EpubException>().having((e) => e.code, 'code', 'E_TOC_NCX_EMPTY'),
      ),
    );
    expect(
      () => TocParser.parseNcxText(
        '<ncx><navMap></ncx>',
        ncxPath: 'OEBPS/toc.ncx',
        package: package,
        opfPath: 'OEBPS/content.opf',
      ),
      throwsA(
        isA<EpubException>().having((e) => e.code, 'code', 'E_TOC_NCX_XML'),
      ),
    );
  });
}
