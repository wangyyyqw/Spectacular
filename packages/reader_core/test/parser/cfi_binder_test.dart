import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/parser/cfi_binder.dart';
import 'package:reader_core/position/cfi.dart';

import '../support/corpus.dart';

void main() {
  const xhtml = '''
<html xmlns="http://www.w3.org/1999/xhtml"><body>
<p id="p1">Hello <b id="b1">world</b> tail</p><p id="p2">第二段</p>
</body></html>
''';

  test('每个文本节点都有合法 base CFI', () {
    final doc = CfiBinder.bind(xhtml: xhtml, spineIndex: 0);
    expect(doc.textNodes, hasLength(6));
    expect(doc.warnings, isEmpty);

    final serialized = doc.textNodes
        .map((node) => node.baseCfi.serialize())
        .toList();
    expect(serialized, <String>[
      'epubcfi(/6/2!/4/1)',
      'epubcfi(/6/2!/4/2[p1]/1)',
      'epubcfi(/6/2!/4/2[p1]/2[b1]/1)',
      'epubcfi(/6/2!/4/2[p1]/3)',
      'epubcfi(/6/2!/4/4[p2]/1)',
      'epubcfi(/6/2!/4/3)',
    ]);
    for (final node in doc.textNodes) {
      final parsed = EpubCfi.parse(node.baseCfi.serialize());
      expect(parsed, isNotNull);
      expect(parsed!.itemref, 2);
      expect(parsed.body, 4);
    }
  });

  test('元素 id 绑定与 refine 偏移不越界', () {
    final doc = CfiBinder.bind(xhtml: xhtml, spineIndex: 0);
    expect(doc.cfiForId('p1')!.serialize(), 'epubcfi(/6/2!/4/2[p1])');
    expect(doc.cfiForId('p2')!.serialize(), 'epubcfi(/6/2!/4/4[p2])');
    expect(doc.cfiForId('b1')!.serialize(), 'epubcfi(/6/2!/4/2[p1]/2[b1])');

    final first = doc.textNodes[1];
    expect(doc.refine(first, 0)!.serialize(), 'epubcfi(/6/2!/4/2[p1]/1:0)');
    expect(doc.refine(first, 3)!.serialize(), 'epubcfi(/6/2!/4/2[p1]/1:3)');
    expect(
      doc.refine(first, first.text.length)!.serialize(),
      'epubcfi(/6/2!/4/2[p1]/1:${first.text.length})',
    );
    expect(doc.refine(first, -1), isNull);
    expect(doc.refine(first, first.text.length + 1), isNull);
  });

  test('100 个段落的文本节点全部绑定', () {
    final html = StringBuffer('<html><body>');
    for (var i = 1; i <= 100; i++) {
      html.write('<p id="p$i">第 $i 段</p>');
    }
    html.write('</body></html>');
    final doc = CfiBinder.bind(xhtml: html.toString(), spineIndex: 3);
    expect(doc.textNodes, hasLength(100));
    for (var i = 0; i < 100; i++) {
      final cfi = doc.textNodes[i].baseCfi;
      expect(cfi.itemref, 8);
      expect(EpubCfi.parse(cfi.serialize()), isNotNull);
      expect(doc.refine(doc.textNodes[i], 1), isNotNull);
    }
  });

  test('真实章节的文本节点全部可解析', () async {
    final corpus = findCorpusRoot();
    if (corpus == null) {
      return;
    }
    final opened = await openEpub(
      readSampleBytes(corpus, 'real/zhushen-yuxi.epub')!,
    );
    final document = opened.document!;
    final bound = document.bindCfi(0);
    expect(bound.textNodes, isNotEmpty);
    for (final node in bound.textNodes.take(500)) {
      expect(EpubCfi.parse(node.baseCfi.serialize()), isNotNull);
    }
  });
}
