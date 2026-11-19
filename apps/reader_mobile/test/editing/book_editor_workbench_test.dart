import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:reader_core/editing/epub_editing.dart';
import 'package:reader_mobile/editing/book_editor_controller.dart';
import 'package:reader_mobile/editing/book_editor_page.dart';
import 'package:reader_mobile/editing/book_editor_source.dart';
import 'package:reader_mobile/editing/book_editor_tools.dart';
import 'package:reader_mobile/theme/app_theme.dart';
import 'package:reader_ui/paging/page_turn_view.dart';

import '../support/reader_pump.dart';
import '../support/test_epub.dart';

const _chapter = 'OEBPS/c1.xhtml';
final _desktopPlatforms = TargetPlatformVariant({
  TargetPlatform.macOS,
  TargetPlatform.windows,
});

Future<BookEditorController> _open(WidgetTester tester) async {
  late Directory temporary;
  late EpubEditSession session;
  await tester.runAsync(() async {
    temporary = await Directory.systemTemp.createTemp('desktop-workbench-');
    final file = File('${temporary.path}/book.epub');
    await file.writeAsBytes(
      buildMultiChapterEpub(
        chapters: [
          '<p id="paragraph">原始正文与<em>行内强调</em>继续阅读。</p>',
          '<p>第二章节正文。</p>',
        ],
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
  BookEditorController editor,
  Size size,
) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: BookEditorPage(controller: editor, title: '可编辑测试书'),
    ),
  );
  await pumpReaderUntil(tester, find.byType(PageTurnView));
}

void main() {
  testWidgets('桌面缩放和收起浏览器保留源码缓冲、换行状态与手机分页', (tester) async {
    final editor = await _open(tester);
    await _show(tester, editor, const Size(1360, 900));
    final session = tester
        .widget<PageTurnView>(find.byType(PageTurnView))
        .session;
    final document = editor.activeDocument!;
    await tester.tap(find.text('关闭换行'));
    await tester.pump();
    document.code.text = document.code.text.replaceFirst('原始正文', '已修订正文');
    await tester.pump(const Duration(milliseconds: 300));
    await pumpReaderUntilComplete(tester, () => !editor.previewLoading);
    await pumpReaderUntil(tester, find.byType(PageTurnView));
    final current = tester
        .widget<PageTurnView>(find.byType(PageTurnView))
        .session;
    expect(current, isNot(same(session)));
    final before = tester.getSize(find.byType(BookEditorSource)).width;
    await tester.tap(find.byTooltip('收起书籍浏览器'));
    await tester.pump();
    expect(
      tester.getSize(find.byType(BookEditorSource)).width,
      greaterThan(before),
    );
    for (final width in [960.0, 720.0, 640.0, 390.0, 1000.0, 1360.0]) {
      tester.view.physicalSize = Size(width, 760);
      await tester.pump();
      final code = tester.widget<CodeEditor>(
        find.byType(CodeEditor, skipOffstage: false),
      );
      final view = tester.widget<PageTurnView>(
        find.byType(PageTurnView, skipOffstage: false),
      );
      expect(code.wordWrap, isFalse);
      expect(code.controller, same(document.code));
      expect(view.session, same(current));
      expect(document.code.text, contains('已修订正文'));
      expect(tester.takeException(), isNull, reason: '窗宽 $width');
    }
    await tester.pumpWidget(const SizedBox());
  }, variant: _desktopPlatforms);

  testWidgets('书籍浏览器和源码标签切换真实预览章节，CSS 保留对照章节', (tester) async {
    final editor = await _open(tester);
    PackageEditor(editor.session).addResource(
      'OEBPS/book.css',
      utf8.encode('p { text-indent: 2em; }'),
      'text/css',
    );
    await pumpReaderUntilComplete(tester, () => !editor.previewLoading);
    await _show(tester, editor, const Size(1360, 900));
    final session = tester
        .widget<PageTurnView>(find.byType(PageTurnView))
        .session;
    await tester.tap(
      find.descendant(
        of: find.byType(BookEditorFiles),
        matching: find.byKey(const ValueKey('OEBPS/c2.xhtml')),
      ),
    );
    await pumpReaderUntilComplete(tester, () => session.page?.spineIndex == 1);
    expect(editor.activePath, 'OEBPS/c2.xhtml');
    expect(session.currentText, contains('第二章节正文'));
    await tester.tap(find.byKey(const ValueKey('document-OEBPS/c1.xhtml')));
    await pumpReaderUntilComplete(tester, () => session.page?.spineIndex == 0);
    expect(editor.activePath, _chapter);
    final location = session.readingCfi;
    editor.showSource('OEBPS/book.css');
    await tester.pump();
    expect(session.readingCfi, location);
    expect(editor.activePath, 'OEBPS/book.css');
    await tester.pumpWidget(const SizedBox());
  }, variant: _desktopPlatforms);

  testWidgets('桌面工具菜单可访问元数据，文档查找替换保留各自输入', (tester) async {
    final editor = await _open(tester);
    await _show(tester, editor, const Size(960, 760));
    await tester.tap(find.widgetWithText(SubmenuButton, '工具'));
    await pumpReaderUntil(tester, find.text('书籍信息'));
    await tester.tap(find.text('书籍信息'));
    await pumpReaderUntil(tester, find.widgetWithText(TextField, '书名'));
    await tester.tap(find.text('取消'));
    await pumpReaderUntilComplete(
      tester,
      () => find.byType(AlertDialog).evaluate().isEmpty,
    );
    await tester.tap(find.byTooltip('在文档中查找'));
    await tester.pump();
    final document = editor.activeDocument!;
    await tester.enterText(find.widgetWithText(TextField, '文档内查找'), '原始正文');
    await pumpReaderUntilComplete(
      tester,
      () => document.find.allMatchSelections?.length == 1,
    );
    await tester.tap(find.byTooltip('展开替换'));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, '替换为'), '替换后的正文');
    await tester.tap(find.text('全部替换'));
    await tester.pump(const Duration(milliseconds: 300));
    await pumpReaderUntilComplete(tester, () => !editor.previewLoading);
    expect(editor.session.readText(_chapter), contains('替换后的正文'));
    editor.showSource('OEBPS/c2.xhtml');
    await tester.pump();
    expect(editor.activeDocument!.find.findInputController.text, isEmpty);
    editor.showSource(_chapter);
    await tester.pump();
    expect(document.find.findInputController.text, '原始正文');
    expect(document.find.replaceInputController.text, '替换后的正文');
    await tester.tap(find.byTooltip('关闭查找'));
    await tester.pump();
    expect(find.widgetWithText(TextField, '文档内查找'), findsNothing);
    await tester.tap(find.byTooltip('关闭 c1.xhtml'));
    await tester.pump();
    expect(editor.activePath, 'OEBPS/c2.xhtml');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  }, variant: _desktopPlatforms);
}
