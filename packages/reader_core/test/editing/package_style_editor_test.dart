import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/editing/class_style_editor.dart';
import 'package:reader_core/editing/epub_edit_session.dart';
import 'package:reader_core/editing/package_editor.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:xml/xml.dart';

void main() {
  late Directory directory;
  late EpubEditSession session;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('epub-编辑测试-');
    final file = File('${directory.path}/book.epub');
    await file.writeAsBytes(_epub());
    session = await EpubEditSession.open(file);
  });
  tearDown(() async {
    session.close();
    await directory.delete(recursive: true);
  });

  test('选中元素读取原始 CSS 规则，修改写回原样式表且支持撤销', () async {
    final editor = ClassStyleEditor(session);
    final paragraph = session
        .editableDocument('OPS/a.xhtml')
        .elements
        .firstWhere((node) => node.tag == 'p');
    final original = session.readText('OPS/style.css');
    final rule = editor
        .rulesForElement(paragraph)
        .singleWhere((rule) => rule.selector == 'p.note');
    expect(rule.text, 'p.note { margin-top: 3px; }');
    const replacement =
        'p.note { font-family: "kh"; font-size: 0.6em; text-indent: 0px; text-align: center; line-height: 1.25em; margin: 1em auto; }';
    editor.replaceStyleRule(rule, replacement);
    expect(
      session.readText('OPS/style.css'),
      original.replaceFirst(rule.text, replacement),
    );
    expect(session.metadata['classStylesheet'], isNull);
    final preview = await session.createPreviewSource();
    expect(preview.chapterCount, 2);
    preview.close();
    session.undo();
    expect(session.readText('OPS/style.css'), original);
  });

  test('内嵌媒体规则精确修改，不覆盖外链同名规则与媒体条件', () {
    final editor = ClassStyleEditor(session);
    final paragraph = session
        .editableDocument('OPS/b.xhtml')
        .elements
        .firstWhere((node) => node.tag == 'p');
    final original = session.readText('OPS/b.xhtml');
    final external = session.readText('OPS/style.css');
    final rule = editor
        .rulesForElement(paragraph)
        .singleWhere((rule) => rule.path == 'OPS/b.xhtml');
    expect(rule.media, contains('900px'));
    editor.replaceStyleRule(rule, 'p.note { margin-top: 42px !important; }');
    expect(
      session.readText('OPS/b.xhtml'),
      original.replaceFirst(
        rule.text,
        'p.note { margin-top: 42px !important; }',
      ),
    );
    expect(session.readText('OPS/style.css'), external);
  });

  test('CSS 语法错误和过期来源拒绝覆盖样式表', () {
    final editor = ClassStyleEditor(session);
    final paragraph = session
        .editableDocument('OPS/a.xhtml')
        .elements
        .firstWhere((node) => node.tag == 'p');
    final rule = editor.rulesForElement(paragraph).first;
    final original = session.readText(rule.path);
    expect(
      () => editor.replaceStyleRule(rule, '.note { color: red;'),
      throwsFormatException,
    );
    expect(session.readText(rule.path), original);
    editor.writeSource(rule.path, '$original\n.note { color: green; }');
    expect(
      () => editor.replaceStyleRule(rule, '.note { color: blue; }'),
      throwsA(isA<Exception>()),
    );
    expect(session.readText(rule.path), contains('color: green'));
  });

  test('在指定 HTML 前后插入章节是单步事务，顺序可撤销', () {
    final editor = PackageEditor(session);
    final original = session.spinePaths;
    editor.addXhtml('OPS/new.xhtml', '新章节', index: 1);
    expect(session.spinePaths, ['OPS/a.xhtml', 'OPS/new.xhtml', 'OPS/b.xhtml']);
    session.undo();
    expect(session.spinePaths, original);
    expect(session.readBytes('OPS/new.xhtml'), isNull);
    expect(
      () => editor.addXhtml('OPS/invalid.xhtml', '无效位置', index: 99),
      throwsRangeError,
    );
    expect(session.readBytes('OPS/invalid.xhtml'), isNull);
  });

  test('完整 class token 跨章应用，强规则提示并按确认覆盖', () async {
    final editor = ClassStyleEditor(session);
    final report = editor.inspect('note', proposed: {'margin-top': '12px'});
    expect(report.elementCount, 3);
    expect(report.chapterCount, 2);
    expect(report.conflicts, isNotEmpty);
    editor.apply('note', {'margin-top': '12px'}, unifyConflicts: true);
    final first = XmlDocument.parse(session.readText('OPS/a.xhtml'));
    final notes = first.descendants.whereType<XmlElement>().where(
      (e) => e.getAttribute('class') == 'note',
    );
    expect(notes.first.getAttribute('style'), contains('12px !important'));
    final other = first.descendants.whereType<XmlElement>().firstWhere(
      (e) => e.getAttribute('class') == 'notebook',
    );
    expect(other.getAttribute('style'), isNull);
    expect(
      session.readText('OPS/b.xhtml'),
      contains(editor.stylesheetPath.split('/').last),
    );
    final preview = await session.createPreviewSource();
    expect(preview.chapterCount, 2);
    preview.close();
    editor.apply('note', {'margin-top': '24px'});
    expect(session.readText('OPS/a.xhtml'), contains('24px !important'));
    session.undo();
    expect(session.readText('OPS/a.xhtml'), contains('12px !important'));
  });

  test('手工源码修改同步类覆盖，局部人工例外不会被覆盖', () {
    final editor = ClassStyleEditor(session);
    editor.apply('note', {'color': 'red'}, unifyConflicts: true);
    final css = session.readText(editor.stylesheetPath);
    editor.writeSource(editor.stylesheetPath, css.replaceAll('red', 'green'));
    expect(session.readText('OPS/a.xhtml'), contains('green !important'));
    final source = session.readText('OPS/a.xhtml');
    editor.writeSource(
      'OPS/a.xhtml',
      source.replaceAll('green !important', 'purple !important'),
    );
    editor.apply('note', {'color': 'blue'});
    expect(session.readText('OPS/a.xhtml'), contains('purple !important'));
  });

  test('删除共享属性恢复原始内联声明，多类交集提示冲突', () {
    final editor = ClassStyleEditor(session);
    editor.apply('note', {'color': 'red'}, unifyConflicts: true);
    editor.apply('note', {'color': ''});
    expect(
      session.readText('OPS/a.xhtml'),
      contains('style="color: black !important"'),
    );
    expect(session.readText(editor.stylesheetPath).trim(), isEmpty);
    editor.apply('caption', {'color': 'green'});
    expect(
      editor
          .inspect('note', proposed: {'color': 'blue'})
          .conflicts
          .any((c) => c.reason.contains('多个 class')),
      isTrue,
    );
  });

  test('依赖父元素的高优先级 inherit 与 var 声明仍提示冲突', () {
    session.transaction(
      '准备继承与变量声明',
      (tx) => tx.writeText(
        'OPS/style.css',
        'body { --ink: red; color: blue; } p.note { color: inherit; margin-top: var(--gap); }',
      ),
    );
    final report = ClassStyleEditor(session)
        .inspect('note', proposed: {'color': 'green', 'margin-top': '12px'});
    expect(report.conflicts.any((c) => c.property == 'color'), isTrue);
    expect(report.conflicts.any((c) => c.property == 'margin-top'), isTrue);
  });

  test('重命名跨目录 CSS 与图片同步标准引用，撤销恢复资源', () {
    final editor = PackageEditor(session);
    editor.renameResource('OPS/style.css', 'OPS/styles/main.css');
    expect(session.readText('OPS/a.xhtml'), contains('styles/main.css'));
    expect(session.readText('OPS/styles/main.css'), contains('../image.png'));
    editor.renameResource('OPS/image.png', 'OPS/images/图.png');
    expect(session.readText('OPS/styles/main.css'), contains('../images/'));
    expect(session.readText('OPS/a.xhtml'), contains('images/'));
    session.undo();
    expect(session.readBytes('OPS/image.png'), isNotNull);
  });

  test('查找可限定文件范围，替换只修改范围内匹配', () {
    final editor = PackageEditor(session);
    final all = editor.find('段落');
    final scoped = editor.find('段落', paths: {'OPS/a.xhtml'});
    expect(scoped, isNotEmpty);
    expect(scoped.length, lessThan(all.length));
    expect(scoped.every((match) => match.path == 'OPS/a.xhtml'), isTrue);
    expect(editor.find('段落', paths: <String>{}), isEmpty);

    editor.replaceAll(scoped, '正文');
    expect(editor.find('段落', paths: {'OPS/a.xhtml'}), isEmpty);
    expect(editor.find('段落', paths: {'OPS/b.xhtml'}), isNotEmpty);
  });

  test('元数据保留唯一标识；目录、分合章、替换为可撤销事务', () {
    final editor = PackageEditor(session);
    editor.setMetadata({'title': '新书名', 'creator': '新作者'});
    expect(session.readText('OPS/book.opf'), contains('urn:test:editor'));
    expect(editor.metadata['title'], '新书名');
    editor.generateToc();
    expect(editor.toc.length, 2);
    expect(editor.toc.first.label, '一章');
    final matches = editor.find('段落');
    editor.replaceAll(matches, '正文');
    expect(editor.find('段落'), isEmpty);
    session.undo();
    expect(editor.find('段落').length, matches.length);
    final text = session.readText('OPS/a.xhtml');
    final offset = text.indexOf('<p class="notebook"');
    editor.splitChapter('OPS/a.xhtml', offset, 'OPS/parts/new.xhtml');
    expect(editor.chapters.length, 3);
    expect(session.readText('OPS/parts/new.xhtml'), contains('../style.css'));
    editor.mergeChapters('OPS/a.xhtml', 'OPS/parts/new.xhtml');
    expect(editor.chapters.length, 2);
    expect(session.readText('OPS/a.xhtml'), contains('class="notebook"'));
  });

  test('非法草稿可保留，严格预览阻止错误源码发布', () async {
    ClassStyleEditor(session).writeSources({'OPS/a.xhtml': '<html><body>'});
    expect(session.toDraft()['entries'], isNotEmpty);
    expect(() => session.validate(), throwsA(anything));
    session.undo();
    final opened = await openEpubFile(session.baseFile);
    expect(opened.ok, isTrue);
    opened.document!.archive.close();
  });
}

List<int> _epub() {
  final sources = <String, String>{
    'mimetype': 'application/epub+zip',
    'META-INF/container.xml': '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0"><rootfiles><rootfile full-path="OPS/book.opf" media-type="application/oebps-package+xml"/></rootfiles></container>',
    'OPS/book.opf': '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="uid">urn:test:editor</dc:identifier><dc:title>测试</dc:title><dc:language>zh</dc:language></metadata><manifest><item id="a" href="a.xhtml" media-type="application/xhtml+xml"/><item id="b" href="b.xhtml" media-type="application/xhtml+xml"/><item id="css" href="style.css" media-type="text/css"/><item id="image" href="image.png" media-type="image/png"/></manifest><spine><itemref idref="a"/><itemref idref="b"/></spine></package>',
    'OPS/a.xhtml': '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>一</title><link rel="stylesheet" href="style.css"/></head><body><h1 id="one">一章</h1><p class="note" style="color: black !important">中文<strong>段落</strong></p><p class="notebook">不应改变</p><p class="note caption">交集</p><img src="image.png" alt="图"/></body></html>',
    'OPS/b.xhtml': '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>二</title><style>@import "style.css"; @media (min-width: 900px) { p.note { margin-top: 99px !important; } }</style></head><body><h1 id="two">二章</h1><p class="note">第二段落</p></body></html>',
    'OPS/style.css': 'p.note { margin-top: 3px; } .caption { color: navy; } body { background-image: url("image.png"); }',
    'OPS/image.png': 'image',
  };
  final archive = Archive();
  for (final entry in sources.entries) {
    final bytes = utf8.encode(entry.value);
    archive.addFile(
      ArchiveFile(entry.key, bytes.length, bytes)
        ..compression = entry.key == 'mimetype'
            ? CompressionType.none
            : CompressionType.deflate,
    );
  }
  return ZipEncoder().encode(archive);
}
