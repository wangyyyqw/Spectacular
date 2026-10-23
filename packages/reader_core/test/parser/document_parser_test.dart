import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/parser/cfi_binder.dart';
import 'package:reader_core/parser/document_parser.dart';
import 'package:reader_core/position/cfi.dart';

import '../support/corpus.dart';

const _xhtml = '''
<html><head><title>测试</title></head><body>
<div id="wrap" class="box"><p id="p1">A &amp; B &lt; C &#20013;</p><ul><li>one</li><li>two</li></ul></div>
</body></html>
''';

void main() {
  final corpus = findCorpusRoot();
  final skip = corpus == null ? '本地样本库缺失（test_corpus/ 不入库）' : null;

  test('解析节点树：结构、属性、实体与源码位置', () {
    final doc = DocumentParser.parse(xhtml: _xhtml, spineIndex: 0);
    expect(doc.root.tag, 'body');
    final wrap = doc.elementById('wrap');
    expect(wrap, isNotNull);
    expect(wrap!.tag, 'div');
    expect(wrap.attributes['class'], 'box');
    expect(wrap.children.whereType<ParsedElement>().map((e) => e.tag), <String>[
      'p',
      'ul',
    ]);
    final p1 = doc.elementById('p1')!;
    expect(
      p1.children.whereType<ParsedText>().map((t) => t.text).join(),
      'A & B < C 中',
    );
    expect(p1.start, lessThan(p1.end));
    expect(wrap.start, lessThan(p1.start));
    expect(doc.plainText, contains('A & B < C 中'));
    expect(doc.charCount, doc.plainText.length);
  });

  test('每个元素/文本节点都绑定合法 CFI，且与 CfiBinder 一致', () {
    final doc = DocumentParser.parse(xhtml: _xhtml, spineIndex: 0);
    final bound = CfiBinder.bind(xhtml: _xhtml, spineIndex: 0);
    final docTexts = doc.textNodes.map((node) => node.cfi.serialize()).toList();
    final bindTexts = bound.textNodes
        .map((node) => node.baseCfi.serialize())
        .toList();
    expect(docTexts, bindTexts);
    for (final node in doc.textNodes) {
      expect(EpubCfi.parse(node.cfi.serialize()), isNotNull);
      expect(node.cfi.itemref, 2);
    }
    expect(
      doc.elementById('wrap')!.cfi.serialize(),
      'epubcfi(/6/2!/4/2[wrap])',
    );
  });

  test('nodeAtCfi 命中元素与文本，resolve 容错', () {
    final doc = DocumentParser.parse(xhtml: _xhtml, spineIndex: 0);
    final p1 = doc.elementById('p1')!;
    final text = p1.children.whereType<ParsedText>().first;
    expect(doc.nodeAtCfi(p1.cfi), same(p1));
    expect(doc.nodeAtCfi(text.cfi), same(text));

    final stale = text.cfi;
    final changed = _xhtml.replaceFirst(
      '<p id="p1">A &amp; B &lt; C &#20013;</p>',
      '',
    );
    final changedDoc = DocumentParser.parse(xhtml: changed, spineIndex: 0);
    final result = changedDoc.resolve(stale);
    expect(result.ok, isTrue);
    expect(result.adjusted, isTrue);
    expect(result.warnings, isNotEmpty);
  });

  test('CDATA 与命名实体处理', () {
    const value = '''
<html><body><p id="p">before <![CDATA[a < b & c]]> after</p>
<script><![CDATA[if (a < b) { x = "&"; }]]></script></body></html>
''';
    final doc = DocumentParser.parse(xhtml: value, spineIndex: 0);
    expect(doc.plainText, contains('before'));
    expect(doc.plainText, contains('after'));
    expect(doc.plainText, contains('if (a < b)'));
    for (final text in doc.textNodes) {
      expect(EpubCfi.parse(text.cfi.serialize()), isNotNull);
    }
  });

  test('真实章节解析节点树', () async {
    final opened = await openEpub(
      readSampleBytes(corpus, 'real/zhushen-yuxi.epub')!,
    );
    final document = opened.document!;
    final index = document.spine.length > 50 ? 50 : 0;
    final parsed = document.parseDocument(index);
    expect(parsed.textNodes.length, greaterThan(10));
    expect(parsed.plainText, isNotEmpty);
    for (final node in parsed.textNodes.take(200)) {
      expect(EpubCfi.parse(node.cfi.serialize()), isNotNull);
    }
  }, skip: skip);
}
