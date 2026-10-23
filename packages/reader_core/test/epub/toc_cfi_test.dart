import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/epub/toc_cfi.dart';
import 'package:reader_core/position/cfi.dart';

import '../support/corpus.dart';

const _container = '''
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>
''';

String _opf(int chapters) =>
    '''
<package version="3.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>CFI 绑定测试</dc:title><dc:language>zh-CN</dc:language>
    <dc:identifier id="uid">urn:uuid:toc-cfi</dc:identifier>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    ${List.generate(chapters, (i) => '<item id="c$i" href="ch${i + 1}.xhtml" media-type="application/xhtml+xml"/>').join()}
  </manifest>
  <spine>${List.generate(chapters, (i) => '<itemref idref="c$i"/>').join()}</spine>
</package>
''';

Map<String, String> _files(int chapters, String navBody) => <String, String>{
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml': _container,
  'OEBPS/content.opf': _opf(chapters),
  'OEBPS/nav.xhtml':
      '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">'
      '<body><nav epub:type="toc">$navBody</nav></body></html>',
  for (var i = 1; i <= chapters; i++)
    'OEBPS/ch$i.xhtml': '<html><body><p id="p$i">第 $i 章</p></body></html>',
};

void main() {
  final corpus = findCorpusRoot();
  final skip = corpus == null ? '本地样本库缺失（test_corpus/ 不入库）' : null;

  test('100 章目录全部绑定为 CFI，itemref 与顺序正确', () async {
    final items = List.generate(
      100,
      (i) => '<li><a href="ch${i + 1}.xhtml#p${i + 1}">第 ${i + 1} 章</a></li>',
    ).join();
    final opened = await openEpub(buildZip(_files(100, '<ol>$items</ol>')));
    final document = opened.document!;
    final result = TocCfiBinder.bind(
      archive: document.archive,
      spine: document.spine,
      opfPath: document.opfPath,
      toc: document.toc,
    );
    expect(result.bound, 100);
    expect(result.missing, 0);
    for (var i = 0; i < 100; i++) {
      final cfi = result.toc[i].cfi;
      expect(cfi, isNotNull, reason: '第 ${i + 1} 章');
      expect(cfi!.itemref, (i + 1) * 2);
      expect(cfi.body, 4);
      expect(cfi.steps.last.index, 2);
      expect(cfi.steps.last.assertion, 'p${i + 1}');
      expect(EpubCfi.parse(cfi.serialize())!.serialize(), cfi.serialize());
    }
    for (var i = 0; i + 1 < 100; i++) {
      expect(result.toc[i].cfi!.compareTo(result.toc[i + 1].cfi!), lessThan(0));
    }
  });

  test('fragment 缺失时不绑定并记录 warning', () async {
    const nav = '<ol><li><a href="ch1.xhtml#missing">缺失</a></li></ol>';
    final opened = await openEpub(buildZip(_files(1, nav)));
    final result = TocCfiBinder.bind(
      archive: opened.document!.archive,
      spine: opened.document!.spine,
      opfPath: opened.document!.opfPath,
      toc: opened.document!.toc,
    );
    expect(result.bound, 0);
    expect(result.missing, 1);
    expect(result.toc.single.cfi, isNull);
    expect(result.warnings, isNotEmpty);
  });

  test('无 fragment 时绑定到 body 起始 CFI', () async {
    const nav = '<ol><li><a href="ch1.xhtml">第一章</a></li></ol>';
    final opened = await openEpub(buildZip(_files(1, nav)));
    final result = TocCfiBinder.bind(
      archive: opened.document!.archive,
      spine: opened.document!.spine,
      opfPath: opened.document!.opfPath,
      toc: opened.document!.toc,
    );
    final cfi = result.toc.single.cfi!;
    expect(cfi.serialize(), 'epubcfi(/6/2!/4)');
    expect(cfi.itemref, 2);
    expect(cfi.body, 4);
  });

  test('真实书前 20 项目录绑定成功', () async {
    final bytes = readSampleBytes(corpus, 'real/zhushen-yuxi.epub')!;
    final opened = await openEpub(bytes);
    final document = opened.document!;
    final result = TocCfiBinder.bind(
      archive: document.archive,
      spine: document.spine,
      opfPath: document.opfPath,
      toc: document.toc,
      maxEntries: 20,
    );
    expect(result.bound, greaterThan(0));
    expect(result.missing, 0);
    // ignore: avoid_print
    print('P1-10 zhushen bound=${result.bound} missing=${result.missing}');
  }, skip: skip);
}
