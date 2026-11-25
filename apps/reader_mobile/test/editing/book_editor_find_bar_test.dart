import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/editing/epub_editing.dart';
import 'package:reader_mobile/editing/book_editor_controller.dart';
import 'package:reader_mobile/editing/book_editor_find_bar.dart';
import 'package:reader_mobile/editing/book_editor_search.dart';

import '../support/reader_pump.dart';
import '../support/test_epub.dart';

const _first = 'OEBPS/c1.xhtml';
const _second = 'OEBPS/c2.xhtml';

Future<BookEditorSearch> _show(
  WidgetTester tester, {
  String? first,
  CommitEditor? commit,
}) async {
  late Directory root;
  late EpubEditSession session;
  await tester.runAsync(() async {
    root = await Directory.systemTemp.createTemp('inline-editor-search-');
    final file = await File('${root.path}/book.epub').writeAsBytes(
      buildMultiChapterEpub(
        chapters: [first ?? '<p>甲1 甲2 甲3</p>', '<p>甲4 第二章正文</p>'],
        rawBody: true,
      ),
    );
    session = await EpubEditSession.open(file);
  });
  final editor = BookEditorController(session: session, commit: commit)
    ..openDocument(_first);
  final search = BookEditorSearch(editor);
  addTearDown(() async {
    search.dispose();
    editor.dispose();
    await root.delete(recursive: true);
  });
  await pumpReaderUntilComplete(tester, () => !editor.previewLoading);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(width: 500, child: EditorFindBar(search: search)),
        ),
      ),
    ),
  );
  return search;
}

Future<void> _query(
  WidgetTester tester,
  BookEditorSearch search,
  String text,
) async {
  await tester.enterText(
    find.byKey(const ValueKey('editor-search-query')),
    text,
  );
  await pumpReaderTask(tester, search.searchNow());
}

Future<void> _finish(WidgetTester tester, BookEditorSearch search) async {
  await tester.pump(const Duration(milliseconds: 350));
  await pumpReaderUntilComplete(tester, () => !search.editor.previewLoading);
  await pumpReaderTask(tester, search.searchNow());
  await tester.pumpWidget(const SizedBox());
}

void main() {
  testWidgets('底栏查询读取非法未保存缓冲，不提交内容并展示无结果与正则错误', (tester) async {
    final search = await _show(tester);
    final editor = search.editor;
    final original = editor.session.readText(_first);
    editor.activeDocument!.code.text = '<p>未保存的目标词';
    await _query(tester, search, '目标词');
    expect(search.matches, hasLength(1));
    expect(editor.session.readText(_first), original);
    search.openMatch(0);
    expect(editor.activeDocument!.code.selectedText, '目标词');
    expect(editor.session.revision, 0);
    expect(editor.error, isNull);
    await _query(tester, search, '不存在');
    expect(find.text('没有匹配结果'), findsOneWidget);
    search.setRegex(true);
    await _query(tester, search, '[');
    expect(find.text('正则表达式无效，请检查括号和转义。'), findsOneWidget);
    await _finish(tester, search);
  });

  testWidgets('指定文档在底栏勾选，结果范围与替换一致且一次撤销', (tester) async {
    final search = await _show(tester);
    await _query(tester, search, '甲');
    await tester.tap(find.byTooltip('查找范围'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('指定文档').last);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    await tester.tap(find.byKey(const ValueKey('search-file-$_second')));
    await pumpReaderTask(tester, search.searchNow());
    expect(search.matches, hasLength(1));
    expect(search.matches.single.path, _second);
    search.replacement.text = r'$0';
    await pumpReaderTask(tester, search.replaceAll());
    expect(search.editor.session.readText(_first), contains('甲1'));
    expect(search.editor.session.readText(_second), contains(r'$04'));
    search.editor.undo();
    expect(search.editor.session.readText(_second), contains('甲4'));
    await _finish(tester, search);
  });

  testWidgets('CRLF 正则跨行替换保留换行、捕获组和撤销', (tester) async {
    final search = await _show(tester, first: '<p>开头\r\n甲1\r\n乙2\r\n结尾</p>');
    final original = search.editor.session.readText(_first);
    search.setRegex(true);
    await _query(tester, search, r'(甲1)\n(乙2)');
    expect(search.matches, hasLength(1));
    search.replacement.text = r'$2-$1';
    await pumpReaderTask(tester, search.replaceCurrent());
    expect(
      search.editor.activeDocument!.code.text,
      contains('开头\r\n乙2-甲1\r\n结尾'),
    );
    search.editor.undo();
    expect(search.editor.session.readText(_first), original);
    await pumpReaderTask(tester, search.searchNow());
    await pumpReaderTask(tester, search.replaceAll());
    expect(search.editor.session.readText(_first), contains('乙2-甲1'));
    await _finish(tester, search);
  });

  testWidgets('跨文档结果定位选区并保留查询，键盘前后查找与关闭', (tester) async {
    final search = await _show(tester);
    search.setScope(EditorSearchScope.all);
    await _query(tester, search, r'甲');
    expect(search.matches, hasLength(4));
    search.queryFocus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(search.index, 1);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(search.index, 0);
    search.openMatch(3);
    await tester.pump();
    expect(search.editor.activePath, _second);
    expect(search.editor.activeDocument!.code.selectedText, '甲');
    expect(search.query.text, '甲');
    expect(search.matches, hasLength(4));
    search.setWrap(false);
    search.move(false);
    expect(search.index, 3);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(search.opened, isFalse);
    await _finish(tester, search);
  });

  testWidgets('当前文件保留各自查询，跨文档选项不覆盖原查询', (tester) async {
    final search = await _show(tester);
    await _query(tester, search, '甲1');
    search.editor.showSource(_second);
    await tester.pump();
    expect(search.query.text, isEmpty);
    await _query(tester, search, '第二章');
    search.setScope(EditorSearchScope.all);
    await _query(tester, search, '甲');
    search.openMatch(0);
    search.setScope(EditorSearchScope.current);
    await tester.pump();
    expect(search.query.text, '甲1');
    await _finish(tester, search);
  });

  testWidgets('保存期间替换禁用，文本变动立即清除过期结果', (tester) async {
    final completing = Completer<void>();
    final search = await _show(tester, commit: (_) => completing.future);
    await _query(tester, search, '甲');
    final saving = search.editor.save();
    await tester.pump();
    expect(search.editor.busy, isTrue);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '全部替换'))
          .onPressed,
      isNull,
    );
    completing.complete();
    expect(await pumpReaderTask(tester, saving), isTrue);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '全部替换'))
          .onPressed,
      isNotNull,
    );
    search.editor.activeDocument!.code.text = '<p>新的文本</p>';
    expect(search.matches, isEmpty);
    await _finish(tester, search);
  });
}
