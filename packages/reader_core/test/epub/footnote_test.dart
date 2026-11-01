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

  test('QQ、掌阅、通用与 Reeden 类名均可识别', () {
    final source = _doc('''
<html><body>
  <p>正文
    <a class="qqreader-footnote" href="#q1">1</a>
    <a class="zhangyue-footnote" href="#z1">2</a>
    <a class="epub-footnote" href="#e1">3</a>
    <a class="reeden-footnote duokan-footnote" href="#r1">4</a>
  </p>
  <div id="q1" class="qqreader-footnote">QQ 注释</div>
  <p id="z1" class="zhangyue-footnote">掌阅注释</p>
  <dd id="e1" class="epub-footnote">通用注释</dd>
  <ol class="reeden-footnote-content duokan-footnote-content">
    <li id="r1" class="reeden-footnote-item duokan-footnote-item">Reeden 注释</li>
  </ol>
</body></html>
''');
    final anchors = _resolve(source, [source]);
    expect(anchors.map((anchor) => anchor.noteText), [
      'QQ 注释',
      '掌阅注释',
      '通用注释',
      'Reeden 注释',
    ]);
    expect(anchors.every((anchor) => anchor.kind == NoteKind.footnote), isTrue);
  });

  test('DPUB 尾注语义与返回链接清洗', () {
    final source = _doc('''
<html><body>
  <p>正文<a id="r1" role="doc-noteref" href="#en1">[1]</a></p>
  <aside id="en1" role="doc-endnote">
    <p>第一段尾注</p><p>第二段尾注</p>
    <a href="#r1" role="doc-backlink">返回</a>
  </aside>
</body></html>
''');
    final anchor = _resolve(source, [source]).single;
    expect(anchor.kind, NoteKind.endnote);
    expect(anchor.noteText, '第一段尾注\n第二段尾注');
    expect(anchor.noteText, isNot(contains('返回')));
  });

  test('WR file 属性与 zy-footnote 图片入口', () {
    final source = _doc('''
<html><body>
  <p>正文
    <a data-wr-footernote="file:Images/wr-note.png">WR</a>
    <a href="#zy1"><span zy-footnote="Images/zy-note.jpg">掌阅图注</span></a>
  </p>
  <aside id="zy1"><p>掌阅图片注释</p></aside>
</body></html>
''');
    final anchors = _resolve(source, [source]);
    expect(anchors[0].kind, NoteKind.footnote);
    expect(anchors[0].noteImages, ['OEBPS/Images/wr-note.png']);
    expect(anchors[1].kind, NoteKind.footnote);
    expect(anchors[1].noteText, '掌阅图片注释');
  });

  test('注释正文内图片转为书内路径', () {
    final source = _doc('''
<html><body>
  <p>正文<a epub:type="noteref" href="#fn1">1</a></p>
  <aside id="fn1" epub:type="footnote">
    <p>图中说明</p><img src="Images/note.png" alt="图示"/>
  </aside>
</body></html>
''');
    final anchor = _resolve(source, [source]).single;
    expect(anchor.noteImages, ['OEBPS/Images/note.png']);
  });

  test('数字普通内链指向正文区块时不误判为脚注', () {
    final source = _doc('''
<html><body>
  <p><a href="#chapter-1">1</a></p>
  <section id="chapter-1"><p>第一章正文</p></section>
</body></html>
''');
    final anchor = _resolve(source, [source]).single;
    expect(anchor.kind, NoteKind.link);
  });

  test('数字注号接受连字符形式的 fn-1 目标 id', () {
    final source = _doc('''
<html><body>
  <p>正文<a href="#fn-1">1</a></p>
  <p id="fn-1">连字符注释</p>
</body></html>
''');
    final anchor = _resolve(source, [source]).single;
    expect(anchor.kind, NoteKind.footnote);
    expect(anchor.noteText, '连字符注释');
  });

  test('目标 id 在定义块内部时记录外层容器 id', () {
    final source = _doc('''
<html><body>
  <p>正文<a epub:type="noteref" href="#fn-anchor">1</a></p>
  <aside id="note-wrap"><p><span id="fn-anchor">外层定义</span></p></aside>
</body></html>
''');
    final anchor = _resolve(source, [source]).single;
    expect(anchor.targetId, 'fn-anchor');
    expect(anchor.definitionId, 'note-wrap');
  });

  test('目标 id 在无 id 列表项内时读取同级注释正文', () {
    final source = _doc('''
<html><body>
  <p>正文<a epub:type="noteref" href="#fn-inner">[1]</a></p>
  <ol><li><a id="fn-inner"></a>无 id 容器注释</li></ol>
</body></html>
''');
    final anchor = _resolve(source, [source]).single;
    expect(anchor.kind, NoteKind.footnote);
    expect(anchor.targetId, 'fn-inner');
    expect(anchor.noteText, '无 id 容器注释');
  });

  test('长注释正文完整保留，不在解析层截断', () {
    final note = List<String>.filled(600, '注').join();
    final source = _doc(
      '<html><body><p>正文<a epub:type="noteref" href="#fn1">1</a></p>'
      '<aside id="fn1" epub:type="footnote">$note</aside></body></html>',
    );
    final anchor = _resolve(source, [source]).single;
    expect(anchor.noteText, note);
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
  final anchors = document.resolveFootnotes(0);
  expect(anchors, hasLength(1));
  expect(anchors.single.targetSpine, 1);
  expect(anchors.single.crossDocument, isTrue);
  expect(anchors.single.noteText, contains('第二章注释'));
}
