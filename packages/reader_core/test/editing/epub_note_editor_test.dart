import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/editing/epub_editing.dart';
import 'package:reader_core/epub/footnote.dart';

import 'edit_fixture.dart';

const _path = 'OPS/chapter.xhtml';

EditableElementRef _element(EpubEditSession session, String id) => session
    .editableDocument(_path)
    .elements
    .singleWhere((element) => element.attributes['id'] == id);

List<FootnoteAnchor> _parsedNotes(EpubEditSession session) {
  final documents = {
    for (final (index, path) in session.previewPaths.indexed)
      path: FootnoteParser.parse(
        spineIndex: index,
        path: path,
        xhtml: session.readText(path),
      ),
  };
  return FootnoteParser.resolve(
    source: documents[_path]!,
    documents: documents,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late EpubEditSession session;
  late EpubNoteEditor notes;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('epub-note-test-');
    session = await EpubEditSession.open(await createEditingFixture(temporary));
    notes = EpubNoteEditor(session);
  });
  tearDown(() async {
    session.close();
    await temporary.delete(recursive: true);
  });

  test('文字光标添加标准脚注，保留行内结构并由正式解析器识别', () {
    final before = session.readText(_path);
    notes.create(
      _element(session, 'e'),
      label: '[1]',
      text: '甲 & <乙>\n第二行',
      sourceOffset: before.indexOf('乙😀') + 1,
    );
    final source = session.readText(_path);
    expect(source, contains('<em id="e">乙<a '));
    expect(source, contains('</a>😀</em>丙</p>'));
    expect(source, contains('甲 &amp; &lt;乙&gt;<br/>第二行'));
    expect(source, contains('epub:type="noteref" role="doc-noteref"'));
    expect(source, contains('epub:type="footnote" role="doc-footnote"'));
    expect(source, contains('epub:type="backlink" role="doc-backlink"'));
    final note = _parsedNotes(session).single;
    expect(note.kind, NoteKind.footnote);
    expect(note.targetId, 'note-1');
    expect(note.noteText, '甲 & <乙>\n第二行');
    expect(note.noteText, isNot(contains('返回正文')));
    expect(session.history, hasLength(1));
    session.undo();
    expect(session.readText(_path), before);
    session.redo();
    expect(session.readText(_path), source);
  });

  test('标记与正文转义，ID 冲突顺延且原段落结构保持', () {
    session.transaction(
      '准备 ID 冲突',
      (tx) => tx.writeText(
        _path,
        session
            .readText(_path)
            .replaceFirst('id="second"', 'id="second" xml:id="note-1"'),
      ),
    );
    notes.create(_element(session, 'p'), label: '<注&1>', text: '第一条');
    notes.create(_element(session, 'second'), label: '②', text: '第二条');
    final source = session.readText(_path);
    expect(source, contains('<em id="e">乙😀</em>丙<a '));
    expect(source, contains('&lt;注&amp;1&gt;</a>'));
    expect(_parsedNotes(session).map((note) => note.targetId), [
      'note-2',
      'note-3',
    ]);
    expect(_parsedNotes(session).map((note) => note.noteText), ['第一条', '第二条']);
  });

  test('标签、实体和代理对内部光标安全回退元素末尾', () {
    final before = session.readText(_path);
    for (final offset in [
      before.indexOf('class="note"') + 2,
      before.indexOf('&amp;') + 2,
      before.indexOf('😀') + 1,
    ]) {
      final target = _element(session, 'p');
      expect(notes.insertion(target, sourceOffset: offset).atCursor, isFalse);
      notes.create(target, label: '注', text: '安全插入', sourceOffset: offset);
      expect(session.readText(_path), contains('<em id="e">乙😀</em>丙<a '));
      expect(_parsedNotes(session).single.noteText, '安全插入');
      session.undo();
      expect(session.readText(_path), before);
    }
  });

  test('空 body 可创建标记段落与注释，普通链接不产生嵌套 a', () {
    session.transaction(
      '准备空白章',
      (tx) => tx.writeText(
        _path,
        '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>空白</title></head><body/></html>',
      ),
    );
    final body = session.editableDocument(_path).elements.last;
    notes.create(body, label: '[1]', text: '空白章的注释');
    expect(_parsedNotes(session).single.noteText, '空白章的注释');
    expect(session.readText(_path), contains('<body><p><a '));
    session.undo();
    session.undo();
    session.insertAfter(
      _element(session, 'p'),
      '<p><a id="link" href="https://example.com">外链</a></p>',
    );
    notes.create(_element(session, 'link'), label: '[1]', text: '链接说明');
    expect(session.readText(_path), contains('外链</a><a '));
    expect(_parsedNotes(session).single.noteText, '链接说明');
  });

  test('body 中的空白光标插入标记段落，CDATA 内光标不拆开原文', () {
    final body = session
        .editableDocument(_path)
        .elements
        .singleWhere((node) => node.tag == 'body');
    notes.create(body, label: '[1]', text: '段前注', sourceOffset: body.openEnd);
    expect(session.readText(_path), contains('<body><p><a '));
    expect(_parsedNotes(session).single.noteText, '段前注');
    session.undo();
    session.replaceInnerHtml(_element(session, 'p'), '<![CDATA[原文 < & 文本]]>');
    final target = _element(session, 'p');
    final offset = target.document.source.indexOf('原文 <') + 2;
    expect(notes.insertion(target, sourceOffset: offset).atCursor, isFalse);
    notes.create(target, label: '[2]', text: 'CDATA说明', sourceOffset: offset);
    expect(session.readText(_path), contains('<![CDATA[原文 < & 文本]]><a '));
    expect(_parsedNotes(session).single.noteText, 'CDATA说明');
  });

  test('编辑已有标准注释保留作者容器、HTML 与回链，一次撤销恢复', () {
    notes.create(_element(session, 'p'), label: '[1]', text: '原始注释');
    final before = session.readText(_path);
    final note = notes.read(_element(session, 'noteref-1'))!;
    expect(notes.read(_element(session, 'note-1'))!.label, '[1]');
    notes.update(
      note,
      bodyHtml: note.bodyHtml.replaceFirst('原始注释', '<em>修订</em>注释'),
    );
    expect(session.readText(_path), contains('<p><em>修订</em>注释</p>'));
    expect(_parsedNotes(session).single.noteText, '修订注释');
    expect(session.history, hasLength(2));
    session.undo();
    expect(session.readText(_path), before);
    for (final html in ['<p>不闭合', '<p>删除回链</p>', '']) {
      final current = notes.read(_element(session, 'note-1'))!;
      expect(
        () => notes.update(current, bodyHtml: html),
        throwsA(isA<EpubEditException>()),
      );
      expect(session.readText(_path), before);
    }
  });

  test('跨文档标准 noteref 可编辑目标注释，正文引用不变', () {
    const definition =
        '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>注释</title></head><body>'
        '<aside id="remote" role="doc-footnote" class="author"><p><em>原注</em>文本</p>'
        '<a role="doc-backlink" href="chapter.xhtml#remote-ref">回去</a></aside></body></html>';
    PackageEditor(session).addResource(
      'OPS/notes.xhtml',
      Uint8List.fromList(utf8.encode(definition)),
      'application/xhtml+xml',
    );
    session.insertAfter(
      _element(session, 'p'),
      '<p><a id="remote-ref" role="doc-noteref" href="notes.xhtml#remote">①</a></p>',
    );
    final original = session.readText(_path);
    final note = notes.read(_element(session, 'remote-ref'))!;
    expect(note.definition.path, 'OPS/notes.xhtml');
    notes.update(note, bodyHtml: note.bodyHtml.replaceFirst('原注', '新注'));
    expect(session.readText(_path), original);
    expect(
      session.readText('OPS/notes.xhtml'),
      contains('class="author"><p><em>新注</em>文本'),
    );
    expect(_parsedNotes(session).single.noteText, '新注文本');
    expect(_parsedNotes(session).single.crossDocument, isTrue);
    session.undo();
    expect(session.readText('OPS/notes.xhtml'), definition);
  });
}
