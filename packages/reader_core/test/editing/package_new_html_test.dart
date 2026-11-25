import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/editing/epub_edit_session.dart';
import 'package:reader_core/editing/package_editor.dart';
import 'package:xml/xml.dart';

import 'edit_fixture.dart';

void main() {
  late Directory directory;
  late EpubEditSession session;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('new-html-');
    final source = editingXhtml.replaceFirst(
      '</head>',
      '<style media="screen">p { background-image: url("image.png"); }</style></head>',
    );
    session = await EpubEditSession.open(
      await createEditingFixture(directory, chapterBytes: utf8.encode(source)),
    );
  });
  tearDown(() async {
    session.close();
    await directory.delete(recursive: true);
  });

  test('空白 HTML 保留合法命名空间与空正文，跨目录沿用样式并一步撤销', () async {
    final original = session.readText('OPS/chapter.xhtml');
    final before = session.history.length;
    PackageEditor(session).addXhtml(
      'OPS/Text/空白.xhtml',
      '',
      index: 0,
      blank: true,
      stylesFrom: 'OPS/chapter.xhtml',
    );
    final document = XmlDocument.parse(session.readText('OPS/Text/空白.xhtml'));
    final body = document.descendants.whereType<XmlElement>().singleWhere(
      (node) => node.name.local == 'body',
    );
    expect(document.rootElement.namespaceUri, 'http://www.w3.org/1999/xhtml');
    expect(body.childElements, isEmpty);
    expect(body.innerText.trim(), isEmpty);
    expect(
      document.descendants
          .whereType<XmlElement>()
          .singleWhere((node) => node.name.local == 'title')
          .innerText,
      '空白',
    );
    final link = document.descendants.whereType<XmlElement>().singleWhere(
      (node) => node.name.local == 'link',
    );
    expect(link.namespaceUri, 'http://www.w3.org/1999/xhtml');
    expect(link.getAttribute('href'), '../style.css');
    final style = document.descendants.whereType<XmlElement>().singleWhere(
      (node) => node.name.local == 'style',
    );
    expect(style.getAttribute('media'), 'screen');
    expect(style.innerText, contains('url("../image.png")'));
    expect(session.spinePaths, ['OPS/Text/空白.xhtml', 'OPS/chapter.xhtml']);
    expect(session.history.length, before + 1);
    session.validate();
    final preview = await session.createPreviewSource();
    try {
      expect((await preview.loadAnchorChapter(0)).text.trim(), isEmpty);
      expect((await preview.loadAnchorChapter(1)).text, contains('另一段'));
    } finally {
      preview.close();
      await preview.preparationsStopped;
    }
    session.undo();
    expect(session.readBytes('OPS/Text/空白.xhtml'), isNull);
    expect(session.spinePaths, ['OPS/chapter.xhtml']);
    expect(session.readText('OPS/chapter.xhtml'), original);
  });

  test('空白 HTML 可以不继承样式，旧新章节调用继续生成标题正文', () {
    final package = PackageEditor(session);
    package.addXhtml('OPS/plain.html', ' 标题 & 符号 ', blank: true);
    final plain = XmlDocument.parse(session.readText('OPS/plain.html'));
    final body = plain.descendants.whereType<XmlElement>().singleWhere(
      (node) => node.name.local == 'body',
    );
    expect(body.childElements, isEmpty);
    expect(
      plain.descendants.whereType<XmlElement>().where(
        (node) => const {'style', 'link'}.contains(node.name.local),
      ),
      isEmpty,
    );
    expect(
      plain.descendants
          .whereType<XmlElement>()
          .singleWhere((node) => node.name.local == 'title')
          .innerText,
      ' 标题 & 符号 ',
    );
    package.addXhtml('OPS/legacy.xhtml', '旧入口标题');
    expect(
      XmlDocument.parse(session.readText('OPS/legacy.xhtml')).descendants
          .whereType<XmlElement>()
          .singleWhere((node) => node.name.local == 'h1')
          .innerText,
      '旧入口标题',
    );
  });

  test('无效或重复路径不创建资源，不改变阅读顺序与撤销历史', () {
    final package = PackageEditor(session);
    for (final path in ['../outside.xhtml', 'OPS/chapter.xhtml']) {
      expect(() => package.addXhtml(path, '', blank: true), throwsA(anything));
    }
    expect(session.revision, 0);
    expect(session.spinePaths, ['OPS/chapter.xhtml']);
    expect(session.history, isEmpty);
  });
}
