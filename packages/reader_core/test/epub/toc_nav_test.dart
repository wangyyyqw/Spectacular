import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/epub_document.dart';

import '../support/corpus.dart';

const _container = '''
<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>
''';

String _opf({required bool nav, required bool ncx, required bool brokenNav}) {
  final navItem = nav
      ? '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>'
      : '';
  final ncxItem = ncx
      ? '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>'
      : '';
  final spineToc = ncx ? ' toc="ncx"' : '';
  return '''
<package version="3.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>目录测试</dc:title><dc:language>zh-CN</dc:language>
    <dc:identifier id="uid">urn:uuid:toc</dc:identifier>
  </metadata>
  <manifest>
    $navItem$ncxItem
    <item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>
    <item id="c2" href="c2.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine$spineToc><itemref idref="c1"/><itemref idref="c2"/></spine>
</package>
''';
}

const _navOk = '''
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<body><nav epub:type="toc"><ol>
<li><a href="c1.xhtml">第一章</a></li>
<li><a href="c2.xhtml#s2">第二章</a></li>
</ol></nav></body></html>
''';

const _navBroken = '''
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<body><nav epub:type="toc"><ol><li><a href="c1.xhtml">坏
''';

const _ncxOk = '''
<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <navMap>
    <navPoint id="n1" playOrder="1"><navLabel><text>NCX 一章</text></navLabel><content src="c1.xhtml"/></navPoint>
    <navPoint id="n2" playOrder="2"><navLabel><text>NCX 二章</text></navLabel><content src="c2.xhtml"/></navPoint>
  </navMap>
</ncx>
''';

Map<String, String> _files({
  required bool nav,
  required bool ncx,
  required bool brokenNav,
  String? navText,
}) => <String, String>{
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml': _container,
  'content.opf': _opf(nav: nav, ncx: ncx, brokenNav: brokenNav),
  'c1.xhtml': '<html><body>一章</body></html>',
  'c2.xhtml': '<html><body>二章</body></html>',
  if (nav) 'nav.xhtml': navText ?? (brokenNav ? _navBroken : _navOk),
  if (ncx) 'toc.ncx': _ncxOk,
};

void main() {
  final corpus = findCorpusRoot();
  final skip = corpus == null ? '本地样本库缺失（test_corpus/ 不入库）' : null;

  test('NAV 正常：优先使用 NAV，层级与锚点正确', () async {
    final result = await openEpub(
      buildZip(_files(nav: true, ncx: true, brokenNav: false)),
    );
    expect(result.ok, isTrue);
    final document = result.document!;
    expect(document.tocSource, 'nav');
    expect(document.toc, hasLength(2));
    expect(document.toc.first.title, '第一章');
    expect(document.toc.first.spineIndex, 0);
    expect(document.toc[1].fragment, 's2');
    expect(document.toc[1].spineIndex, 1);
  });

  test('NAV 中的转义文本只解码一次，不会被当成标签或丢失目录层级', () async {
    final nav = _navOk.replaceFirst(
      '<li><a href="c1.xhtml">第一章</a></li>',
      '<li><a href="c1.xhtml">List&lt;T&gt;&nbsp;&amp; Map</a>'
      '<ol><li><a href="c2.xhtml#s2">&amp;lt;</a></li></ol></li>',
    );
    final result = await openEpub(
      buildZip(_files(nav: true, ncx: false, brokenNav: false, navText: nav)),
    );
    final document = result.document!;
    addTearDown(document.archive.close);
    expect(document.tocSource, 'nav');
    final entry = document.toc.first;
    expect(entry.title, 'List<T>\u00a0& Map');
    expect(entry.children.single.title, '&lt;');
    expect(entry.children.single.fragment, 's2');
    expect(entry.children.single.spineIndex, 1);
  });

  test('NAV 损坏时回退 NCX', () async {
    final result = await openEpub(
      buildZip(_files(nav: true, ncx: true, brokenNav: true)),
    );
    expect(result.ok, isTrue);
    final document = result.document!;
    expect(document.tocSource, 'ncx');
    expect(document.toc.first.title, 'NCX 一章');
    expect(document.report.warnings.any((w) => w.contains('NAV 解析失败')), isTrue);
  });

  test('NAV 与 NCX 都没有时回退 spine 平坦目录', () async {
    final result = await openEpub(
      buildZip(_files(nav: false, ncx: false, brokenNav: false)),
    );
    expect(result.ok, isTrue);
    final document = result.document!;
    expect(document.tocSource, 'spine');
    expect(document.toc, hasLength(2));
    expect(document.toc.map((e) => e.spineIndex), <int>[0, 1]);
    expect(document.report.warnings.any((w) => w.contains('spine 兜底')), isTrue);
  });

  test('真实样本 basic 使用 NAV，toc-ncx 使用 NCX', () async {
    final basic = await openEpub(readSampleBytes(corpus, 'basic.epub')!);
    expect(basic.document!.tocSource, 'nav');
    expect(basic.document!.toc.first.title, contains('第一章'));

    final ncx = await openEpub(readSampleBytes(corpus, 'toc-ncx.epub')!);
    expect(ncx.document!.tocSource, 'ncx');
    expect(ncx.document!.toc, hasLength(3));
  }, skip: skip);

  test('真实大书目录非空', () async {
    for (final file in <String>[
      'real/zhushen-yuxi.epub',
      'real/shiji-yuewei.epub',
      'real/ludingji-1.epub',
    ]) {
      final result = await openEpub(readSampleBytes(corpus, file)!);
      expect(result.ok, isTrue, reason: file);
      expect(result.document!.toc, isNotEmpty, reason: file);
      // ignore: avoid_print
      print(
        'P1-07 $file source=${result.document!.tocSource} '
        'toc=${result.document!.toc.length}',
      );
    }
  }, skip: skip);
}
