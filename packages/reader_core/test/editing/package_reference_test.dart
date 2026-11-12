import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/editing.dart';
import 'package:xml/xml.dart';

const _opfNamespace = 'http://www.idpf.org/2007/opf';
const _xhtmlNamespace = 'http://www.w3.org/1999/xhtml';

Future<EpubEditSession> _fixture({String? first, String? second}) async {
  final directory = await Directory.systemTemp.createTemp(
    'package-references-',
  );
  addTearDown(() => directory.delete(recursive: true));
  final files = {
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml': '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OPS/book.opf"/></rootfiles></container>',
    'OPS/book.opf':
        '<opf:package xmlns:opf="$_opfNamespace" version="3.0" unique-identifier="uid">'
        '<opf:metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="uid">package-test</dc:identifier><dc:title>包引用测试</dc:title></opf:metadata>'
        '<opf:manifest><opf:item id="a" href="a.xhtml" media-type="application/xhtml+xml"/><opf:item id="b" href="parts/b.xhtml" media-type="application/xhtml+xml"/>'
        '<opf:item id="image" href="image.png" media-type="image/png"/><opf:item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/></opf:manifest>'
        '<opf:spine><opf:itemref idref="a"/><opf:itemref idref="b"/></opf:spine>'
        '<opf:guide><opf:reference type="text" title="第二章" href="parts/b.xhtml#body-b"/></opf:guide></opf:package>',
    'OPS/a.xhtml':
        first ??
        '<html xmlns="$_xhtmlNamespace"><head><title>第一章</title></head><body><p id="a">第一段</p><a href="parts/b.xhtml#body-b">继续</a></body></html>',
    'OPS/parts/b.xhtml':
        second ??
        '<h:html xmlns:h="$_xhtmlNamespace"><h:head><h:title>第二章</h:title></h:head><h:body id="body-b" class="chapter" xml:lang="fr" lang="fr"><h:p xml:id="next">第二段</h:p><h:img src="../image.png"/></h:body></h:html>',
    'OPS/image.png': 'image',
    'OPS/toc.ncx': '<n:ncx xmlns:n="http://www.daisy.org/z3986/2005/ncx/" version="2005-1"><n:head/><n:docTitle><n:text>目录</n:text></n:docTitle><n:navMap/></n:ncx>',
  };
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile.bytes(entry.key, utf8.encode(entry.value)));
  }
  final file = File('${directory.path}/book.epub');
  await file.writeAsBytes(ZipEncoder().encodeBytes(archive));
  final session = await EpubEditSession.open(file);
  addTearDown(session.close);
  return session;
}

XmlElement _element(XmlDocument doc, String name) => doc.descendants
    .whereType<XmlElement>()
    .firstWhere((node) => node.name.local == name);

void main() {
  test('合章保留 guide 重写和第二个 body 的属性、命名空间与片段目标', () async {
    final session = await _fixture();
    PackageEditor(session).mergeChapters('OPS/a.xhtml', 'OPS/parts/b.xhtml');
    final opf = XmlDocument.parse(session.readText('OPS/book.opf'));
    expect(_element(opf, 'reference').getAttribute('href'), 'a.xhtml#body-b');
    final document = XmlDocument.parse(session.readText('OPS/a.xhtml'));
    final wrapper = document.descendants.whereType<XmlElement>().firstWhere(
      (node) => node.getAttribute('id') == 'body-b',
    );
    expect(wrapper.name.local, 'div');
    expect(wrapper.namespaceUri, _xhtmlNamespace);
    expect(wrapper.getAttribute('class'), 'chapter');
    expect(wrapper.getAttribute('lang'), 'fr');
    expect(
      wrapper.getAttribute(
        'lang',
        namespaceUri: 'http://www.w3.org/XML/1998/namespace',
      ),
      'fr',
    );
    expect(_element(document, 'img').getAttribute('src'), 'image.png');
    expect(_element(document, 'img').namespaceUri, _xhtmlNamespace);
    expect(session.readBytes('OPS/parts/b.xhtml'), isNull);
    final output = File('${session.baseFile.parent.path}/merged.epub');
    await EpubWriter.write(session, output);
    final reopened = await EpubEditSession.open(output);
    addTearDown(reopened.close);
    expect(PackageEditor(reopened).chapters, hasLength(1));
    expect(reopened.readText('OPS/book.opf'), contains('a.xhtml#body-b'));
    session.undo();
    expect(session.readBytes('OPS/parts/b.xhtml'), isNotNull);
    expect(session.readText('OPS/book.opf'), contains('parts/b.xhtml#body-b'));
  });

  test('合章拒绝 id 与 xml:id 的跨章重复且不改写工作副本', () async {
    final session = await _fixture(
      first:
          '<html xmlns="$_xhtmlNamespace"><head><title>第一章</title></head><body><p id="next">正文</p></body></html>',
    );
    final before = session.readText('OPS/a.xhtml');
    expect(
      () =>
          PackageEditor(session)
              .mergeChapters('OPS/a.xhtml', 'OPS/parts/b.xhtml'),
      throwsStateError,
    );
    expect(session.readText('OPS/a.xhtml'), before);
    expect(session.changedPaths, isEmpty);
  });

  test('拆章移动 xml:id 的片段引用并保留 OPF 前缀', () async {
    final session = await _fixture(
      first:
          '<html xmlns="$_xhtmlNamespace"><head><title>第一章</title></head><body><p id="keep">保留</p><p xml:id="move">移动</p><a href="#move">跳转</a></body></html>',
    );
    final editor = PackageEditor(session);
    final source = session.readText('OPS/a.xhtml');
    editor.splitChapter(
      'OPS/a.xhtml',
      source.indexOf('<p xml:id'),
      'OPS/split.xhtml',
    );
    final moved = XmlDocument.parse(session.readText('OPS/split.xhtml'));
    expect(_element(moved, 'a').getAttribute('href'), 'split.xhtml#move');
    final opf = XmlDocument.parse(session.readText('OPS/book.opf'));
    for (final node in opf.descendants.whereType<XmlElement>().where(
      (node) => node.name.local == 'item' || node.name.local == 'itemref',
    )) {
      expect(node.namespaceUri, _opfNamespace);
    }
    editor.setToc([
      const EditTocEntry('移动', 'OPS/split.xhtml', fragment: 'move'),
    ]);
    expect(editor.toc.single.fragment, 'move');
    final ncx = XmlDocument.parse(session.readText('OPS/toc.ncx'));
    for (final node in ncx.descendants.whereType<XmlElement>()) {
      expect(node.namespaceUri, 'http://www.daisy.org/z3986/2005/ncx/');
    }
  });

  for (final dependency in ['cover', 'toc', 'fallback', 'guide']) {
    test('删除资源拒绝仍有效的 $dependency 包内引用', () async {
      final session = await _fixture(
        first:
            '<html xmlns="$_xhtmlNamespace"><head><title>一</title></head><body><p>正文一</p></body></html>',
        second:
            '<html xmlns="$_xhtmlNamespace"><head><title>二</title></head><body id="body-b"><p>正文二</p></body></html>',
      );
      final opf = XmlDocument.parse(session.readText('OPS/book.opf'));
      final target = switch (dependency) {
        'guide' => 'OPS/parts/b.xhtml',
        'toc' => 'OPS/toc.ncx',
        _ => 'OPS/image.png',
      };
      _addDependency(opf, dependency);
      session.transaction(
        '准备包引用',
        (tx) => tx.writeText('OPS/book.opf', opf.toXmlString()),
      );
      final before = session.readText('OPS/book.opf');
      expect(
        () => PackageEditor(session).removeResource(target),
        throwsStateError,
      );
      expect(session.readText('OPS/book.opf'), before);
      expect(session.readBytes(target), isNotNull);
    });
  }

  test('无包内依赖的资源仍可删除，清单保持正确命名空间', () async {
    final session = await _fixture(
      second:
          '<html xmlns="$_xhtmlNamespace"><head><title>二</title></head><body id="body-b"><p>正文</p></body></html>',
    );
    final editor = PackageEditor(session);
    editor.addXhtml('OPS/third.xhtml', '第三章');
    editor.removeResource('OPS/image.png');
    expect(session.readBytes('OPS/image.png'), isNull);
    final opf = XmlDocument.parse(session.readText('OPS/book.opf'));
    for (final node in opf.descendants.whereType<XmlElement>().where(
      (node) => node.name.local == 'item' || node.name.local == 'itemref',
    )) {
      expect(node.namespaceUri, _opfNamespace);
      expect(node.getAttribute('id'), isNot('image'));
    }
  });
}

void _addDependency(XmlDocument opf, String dependency) {
  if (dependency == 'cover') {
    _element(opf, 'metadata').children.add(
      XmlElement(XmlName.parts('meta', prefix: 'opf'), [
        XmlAttribute(XmlName.parts('name'), 'cover'),
        XmlAttribute(XmlName.parts('content'), 'image'),
      ]),
    );
  } else if (dependency == 'toc') {
    _element(opf, 'spine').setAttribute('toc', 'ncx');
  } else if (dependency == 'fallback') {
    _element(opf, 'item').setAttribute('fallback', 'image');
  }
}
