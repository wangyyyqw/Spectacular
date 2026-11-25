import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/editing/epub_editing.dart';
import 'package:reader_core/epub/footnote.dart';
import 'package:reader_mobile/editing/book_editor_controller.dart';
import 'package:reader_mobile/editing/book_editor_note_dialog.dart';
import 'package:reader_mobile/theme/app_theme.dart';

import '../support/reader_pump.dart';
import '../support/test_epub.dart';

const _path = 'OEBPS/c1.xhtml';

EditableElementRef _element(BookEditorController editor, String id) => editor
    .session
    .editableDocument(_path)
    .elements
    .singleWhere((element) => element.attributes['id'] == id);

Future<BookEditorController> _open(WidgetTester tester) async {
  late Directory temporary;
  late EpubEditSession session;
  await tester.runAsync(() async {
    temporary = await Directory.systemTemp.createTemp('editor-note-widget-');
    final file = File('${temporary.path}/book.epub');
    await file.writeAsBytes(
      buildMultiChapterEpub(
        chapters: ['<p id="p">第一段<em>行内内容</em>结束。</p>'],
        rawBody: true,
      ),
    );
    session = await EpubEditSession.open(file);
  });
  final editor = BookEditorController(session: session);
  addTearDown(() async {
    editor.dispose();
    await temporary.delete(recursive: true);
  });
  await pumpReaderUntilComplete(tester, () => !editor.previewLoading);
  return editor;
}

Future<void> _show(
  WidgetTester tester,
  BookEditorController editor, {
  String id = 'p',
  int? sourceOffset,
  ValueChanged<bool>? onResult,
}) async {
  tester.view
    ..physicalSize = const Size(1100, 900)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme().copyWith(platform: TargetPlatform.macOS),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              final result = await editBookNote(
                context,
                editor,
                _element(editor, id),
                sourceOffset: sourceOffset,
              );
              onResult?.call(result);
            },
            child: const Text('打开注释设置'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开注释设置'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('取消无写入，创建校验留在表单，成功写入可解析的标准注释', (tester) async {
    final editor = await _open(tester);
    final before = editor.session.readText(_path);
    bool? result;
    await _show(tester, editor, onResult: (value) => result = value);
    await tester.enterText(find.byKey(const ValueKey('note-text')), '取消的内容');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    expect(editor.session.readText(_path), before);
    expect(editor.session.history, isEmpty);

    await tester.tap(find.text('打开注释设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('note-apply')));
    await tester.pumpAndSettle();
    expect(find.text('请填写注释标记和注释内容'), findsOneWidget);
    expect(editor.session.history, isEmpty);
    await tester.enterText(find.byKey(const ValueKey('note-label')), '①');
    await tester.enterText(find.byKey(const ValueKey('note-text')), '说明 & 原文');
    await tester.tap(find.byKey(const ValueKey('note-apply')));
    await tester.pumpAndSettle();
    expect(result, isTrue);
    final document = FootnoteParser.parse(
      spineIndex: 0,
      path: _path,
      xhtml: editor.session.readText(_path),
    );
    final note = FootnoteParser.resolve(
      source: document,
      documents: {_path: document},
    ).single;
    expect(note.noteText, '说明 & 原文');
    expect(note.label, '①');
    expect(editor.session.history, hasLength(1));
    editor.undo();
    expect(editor.session.readText(_path), before);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('标签内光标提示回退，已有注释的格式与返回链接保留', (tester) async {
    final editor = await _open(tester);
    final source = editor.session.readText(_path);
    await _show(tester, editor, sourceOffset: source.indexOf('id="p"') + 2);
    expect(find.textContaining('光标不在可插入的文字边界'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('note-text')), '原始说明');
    await tester.tap(find.byKey(const ValueKey('note-apply')));
    await tester.pumpAndSettle();
    final beforeEdit = editor.session.readText(_path);
    await _show(tester, editor, id: 'noteref-1');
    expect(find.text('编辑 EPUB 注释'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('note-label')))
          .readOnly,
      isTrue,
    );
    final htmlField = find.byKey(const ValueKey('note-html'));
    final html = tester.widget<TextField>(htmlField).controller!.text;
    await tester.enterText(htmlField, '<p>丢失回链</p>');
    await tester.tap(find.byKey(const ValueKey('note-apply')));
    await tester.pumpAndSettle();
    expect(find.text('请保留原有返回正文的链接及其属性'), findsOneWidget);
    expect(editor.session.readText(_path), beforeEdit);
    await tester.enterText(
      htmlField,
      html.replaceFirst('原始说明', '<em>新的说明</em>'),
    );
    await tester.tap(find.byKey(const ValueKey('note-apply')));
    await tester.pumpAndSettle();
    expect(editor.session.readText(_path), contains('<p><em>新的说明</em></p>'));
    expect(editor.session.history, hasLength(2));
    editor.undo();
    expect(editor.session.readText(_path), beforeEdit);
    await tester.pumpWidget(const SizedBox());
  });
}
