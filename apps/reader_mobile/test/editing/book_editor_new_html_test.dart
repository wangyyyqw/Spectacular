import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/editing/epub_editing.dart';
import 'package:reader_mobile/editing/book_editor_controller.dart';
import 'package:reader_mobile/editing/book_editor_new_html.dart';
import 'package:reader_mobile/theme/app_theme.dart';
import 'package:xml/xml.dart';

import '../support/reader_pump.dart';
import '../support/test_epub.dart';

const _first = 'OEBPS/Text/c1.xhtml';
const _second = 'OEBPS/Text/c2.xhtml';

Future<BookEditorController> _open(WidgetTester tester) async {
  late Directory directory;
  late EpubEditSession session;
  await tester.runAsync(() async {
    directory = await Directory.systemTemp.createTemp('new-html-widget-');
    final file = File('${directory.path}/book.epub');
    await file.writeAsBytes(buildMultiChapterEpub(chapters: ['原始正文', '末章正文']));
    session = await EpubEditSession.open(file);
    final package = PackageEditor(session);
    package.renameResource('OEBPS/c1.xhtml', _first);
    package.renameResource('OEBPS/c2.xhtml', _second);
    package.addResource(
      'OEBPS/Text/Section0001.xhtml',
      session.readBytes(_first)!,
      'application/xhtml+xml',
    );
    package.addResource(
      'OEBPS/style.css',
      utf8.encode('p { color: red; }'),
      'text/css',
    );
    session.transaction(
      '准备样式',
      (tx) => tx.writeText(
        _first,
        tx
            .readText(_first)
            .replaceFirst(
              '</head>',
              '<link rel="stylesheet" href="../style.css"/></head>',
            ),
      ),
    );
  });
  final editor = BookEditorController(session: session);
  addTearDown(() async {
    editor.dispose();
    await directory.delete(recursive: true);
  });
  await pumpReaderUntilComplete(tester, () => !editor.previewLoading);
  return editor;
}

Future<void> _show(
  WidgetTester tester,
  BookEditorController editor, {
  bool after = true,
  ValueChanged<String?>? onCreated,
}) async {
  tester.view.physicalSize = const Size(1000, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme().copyWith(platform: TargetPlatform.macOS),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => onCreated?.call(
              await createBookHtml(
                context,
                editor,
                anchor: _first,
                after: after,
              ),
            ),
            child: const Text('新建'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('新建'));
  await pumpReaderUntil(tester, find.text('新建空白 HTML'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('单表单沿用目录并避开文件重名，空正文可编辑且创建一步撤销', (tester) async {
    final editor = await _open(tester);
    String? created;
    await _show(tester, editor, onCreated: (path) => created = path);
    final pathField = find.byKey(const ValueKey('new-html-path'));
    expect(
      tester.widget<TextField>(pathField).controller!.text,
      'OEBPS/Text/Section0002.xhtml',
    );
    final history = editor.session.history.length;
    await tester.tap(find.text('创建 HTML'));
    await pumpReaderUntilComplete(tester, () => created != null);
    expect(created, 'OEBPS/Text/Section0002.xhtml');
    expect(editor.session.spinePaths, [_first, created, _second]);
    expect(editor.activePath, created);
    final source = editor.activeDocument!.code.text;
    final doc = XmlDocument.parse(source);
    final body = doc.descendants.whereType<XmlElement>().singleWhere(
      (node) => node.name.local == 'body',
    );
    expect(body.childElements, isEmpty);
    expect(body.innerText.trim(), isEmpty);
    expect(source, contains('href="../style.css"'));
    expect(editor.activeDocument!.code.selection.extentOffset, 4);
    expect(editor.session.history.length, history + 1);
    editor.activeDocument!.code.replaceSelection('<p>新建正文可继续编辑</p>');
    expect(editor.flush(), isTrue);
    await pumpReaderUntilComplete(tester, () => !editor.previewLoading);
    final chapter = await pumpReaderTask(
      tester,
      editor.previewSource!.loadAnchorChapter(1),
    );
    expect(chapter.text, contains('新建正文可继续编辑'));
    editor.undo();
    expect(editor.session.readText(created!), isNot(contains('新建正文可继续编辑')));
    editor.undo();
    expect(editor.session.spinePaths, [_first, _second]);
    expect(editor.session.readBytes(created!), isNull);
    await pumpReaderUntilComplete(tester, () => !editor.previewLoading);
  });

  testWidgets('错误路径保留表单与标题，修正后在章节之前创建并可关闭样式继承', (tester) async {
    final editor = await _open(tester);
    String? created;
    await _show(
      tester,
      editor,
      after: false,
      onCreated: (path) => created = path,
    );
    await tester.enterText(
      find.byKey(const ValueKey('new-html-title')),
      '我的空白页',
    );
    final path = find.byKey(const ValueKey('new-html-path'));
    for (final invalid in ['../outside.xhtml', _first]) {
      await tester.enterText(path, invalid);
      await tester.tap(find.text('创建 HTML'));
      await tester.pump();
      expect(find.byKey(const ValueKey('new-html-error')), findsOneWidget);
      expect(find.text('新建空白 HTML'), findsOneWidget);
      expect(tester.widget<TextField>(path).controller!.text, invalid);
      expect(created, isNull);
    }
    await tester.enterText(path, 'OEBPS/Text/新页.html');
    await tester.tap(find.text('沿用参考章节样式'));
    await tester.tap(find.text('创建 HTML'));
    await pumpReaderUntilComplete(tester, () => created != null);
    expect(editor.session.spinePaths, [created, _first, _second]);
    expect(editor.session.readText(created!), contains('<title>我的空白页</title>'));
    expect(editor.session.readText(created!), isNot(contains('<link')));
  });

  testWidgets('插入位置可改为书籍末尾，取消不创建任何资源', (tester) async {
    final editor = await _open(tester);
    String? created;
    await _show(tester, editor, onCreated: (path) => created = path);
    await tester.tap(find.byKey(const ValueKey('new-html-position')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('书籍末尾').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('创建 HTML'));
    await pumpReaderUntilComplete(tester, () => created != null);
    expect(editor.session.spinePaths, [_first, _second, created]);
    final revision = editor.session.revision;
    await tester.tap(find.text('新建'));
    await pumpReaderUntil(tester, find.text('新建空白 HTML'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await pumpReaderUntilComplete(
      tester,
      () => find.text('新建空白 HTML').evaluate().isEmpty,
    );
    expect(editor.session.revision, revision);
    expect(created, isNull);
  });
}
