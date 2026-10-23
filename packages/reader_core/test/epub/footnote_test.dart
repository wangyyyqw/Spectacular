import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_core/epub/footnote.dart';

import '../support/corpus.dart';

FootnoteDocument _doc(
  String xhtml, {
  int spine = 0,
  String path = 'OEBPS/ch1.xhtml',
}) => FootnoteParser.parse(spineIndex: spine, path: path, xhtml: xhtml);

List<FootnoteAnchor> _resolve(
  FootnoteDocument source,
  List<FootnoteDocument> docs,
) {
  final map = <String, FootnoteDocument>{for (final doc in docs) doc.path: doc};
  return FootnoteParser.resolve(source: source, documents: map);
}

void main() {
  test('EPUB3 noteref + aside：直接命中注释容器', () {
    final source = _doc('''
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<body><p>正文<a id="r1" epub:type="noteref" href="#fn1">[1]</a></p>
<aside id="fn1" epub:type="footnote"><p>第一段注释</p></aside></body></html>
''');
    final anchors = _resolve(source, [source]);
    expect(anchors, hasLength(1));
    final anchor = anchors.single;
    expect(anchor.kind, NoteKind.footnote);
    expect(anchor.targetId, 'fn1');
    expect(anchor.strategy, AnchorStrategy.directId);
    expect(anchor.noteText, contains('第一段注释'));
    expect(anchor.crossDocument, isFalse);
  });

  test('EPUB2 sup 数字链接识别为脚注', () {
    final source = _doc('''
<html><body><p>正文<sup><a href="#n1">[2]</a></sup></p>
<p id="n1">注文二</p></body></html>
''');
    final anchors = _resolve(source, [source]);
    expect(anchors.single.kind, NoteKind.footnote);
    expect(anchors.single.targetId, 'n1');
    expect(anchors.single.noteText, '注文二');
    expect(anchors.single.strategy, AnchorStrategy.directId);
  });

  test('多看脚注 class 与容器识别', () {
    final source = _doc('''
<html><body><p>正文<a class="duokan-footnote" href="#dk1">3</a></p>
<div class="duokan-footnote-item" id="dk1">多看注释</div></body></html>
''');
    final anchor = _resolve(source, [source]).single;
    expect(anchor.kind, NoteKind.footnote);
    expect(anchor.noteText, '多看注释');
  });

  test('目标 id 缺失时按注释序号前缀兜底', () {
    final source = _doc('''
<html><body><p>正文<a href="#missing">[4]</a></p></body></html>
''');
    final target = _doc('''
<html><body><ol><li>4 前缀注释</li><li>5 其他</li></ol></body></html>
''');
    final anchor = _resolve(source, [source, target]).single;
    expect(anchor.strategy, AnchorStrategy.textPrefix);
    expect(anchor.noteText, contains('前缀注释'));
    expect(anchor.targetId, isNull);
  });

  test('目标 id 缺失时按回链锚点兜底', () {
    final source = _doc('''
<html><body><p>正文<a id="r2" href="#gone">[5]</a></p></body></html>
''');
    final target = _doc('''
<html><body><aside id="fn2"><p>回链注释<a href="#r2">↩</a></p></aside></body></html>
''');
    final anchor = _resolve(source, [source, target]).single;
    expect(anchor.strategy, AnchorStrategy.backlink);
    expect(anchor.targetId, 'fn2');
    expect(anchor.noteText, contains('回链注释'));
  });

  test('跨文档锚点解析到目标 spine', () {
    final source = _doc('''
<html><body><p>正文<a epub:type="noteref" href="ch2.xhtml#fn9">[9]</a></p></body></html>
''');
    final target = _doc(
      '<html><body><aside id="fn9">第二章注释</aside></body></html>',
      spine: 1,
      path: 'OEBPS/ch2.xhtml',
    );
    final anchor = _resolve(source, [source, target]).single;
    expect(anchor.targetSpine, 1);
    expect(anchor.crossDocument, isTrue);
    expect(anchor.noteText, contains('第二章注释'));
  });
  test('普通章节链接不误判为注释，缺失目标标记 unresolved', () {
    final source = _doc('''
<html><body><section id="sec1"><a href="#sec1">普通链接</a></section><p><a href="#nope">[8]</a></p></body></html>
''');
    final anchors = _resolve(source, [source]);
    expect(anchors, hasLength(2));
    expect(anchors[0].kind, NoteKind.link);
    expect(anchors[0].targetId, 'sec1');
    expect(anchors[1].strategy, AnchorStrategy.unresolved);
    expect(anchors[1].targetSpine, 0);
    expect(anchors[1].noteText, isNull);
  });

  test('从 EpubDocument 解析并解析跨章注释', _integrationCheck);
}

/// 用内存 EPUB 验证从打开到注释解析的整链。
Future<void> _integrationCheck() async {
  const containerXml = '''
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>
''';
  const opf = '''
<package version="3.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>注释测试</dc:title><dc:language>zh-CN</dc:language>
    <dc:identifier id="uid">urn:uuid:note</dc:identifier>
  </metadata>
  <manifest>
    <item id="c1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
    <item id="c2" href="ch2.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine><itemref idref="c1"/><itemref idref="c2"/></spine>
</package>
''';
  const ch1 = '''
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<body><p>正文<a id="r1" epub:type="noteref" href="ch2.xhtml#fn1">[1]</a></p></body>
</html>
''';
  const ch2 = '''
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<body><aside id="fn1" epub:type="footnote"><p>第二章注释</p></aside></body>
</html>
''';
  final bytes = buildZip(<String, String>{
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml': containerXml,
    'OEBPS/content.opf': opf,
    'OEBPS/ch1.xhtml': ch1,
    'OEBPS/ch2.xhtml': ch2,
  });
  final opened = await openEpub(bytes);
  final document = opened.document!;
  final first = document.parseFootnotes(0);
  final second = document.parseFootnotes(1);
  final anchors = FootnoteParser.resolve(
    source: first,
    documents: {first.path: first, second.path: second},
  );
  expect(anchors, hasLength(1));
  expect(anchors.single.targetSpine, 1);
  expect(anchors.single.crossDocument, isTrue);
  expect(anchors.single.noteText, contains('第二章注释'));
}
