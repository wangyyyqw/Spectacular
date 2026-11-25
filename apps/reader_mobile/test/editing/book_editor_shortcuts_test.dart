import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:reader_core/editing/epub_editing.dart';
import 'package:reader_mobile/editing/book_editor_controller.dart';
import 'package:reader_mobile/editing/book_editor_page.dart';
import 'package:reader_mobile/theme/app_theme.dart';
import 'package:reader_ui/paging/page_turn_view.dart';
import 'package:reader_ui/theme/reader_sheet_form.dart';

import '../support/reader_pump.dart';
import '../support/test_epub.dart';

const _chapter = 'OEBPS/c1.xhtml';
const _platforms = TargetPlatformVariant({
  TargetPlatform.macOS,
  TargetPlatform.windows,
});

Future<BookEditorController> _open(
  WidgetTester tester,
  CommitEditor commit, {
  CommitEditor? export,
}) async {
  late Directory root;
  late EpubEditSession session;
  await tester.runAsync(() async {
    root = await Directory.systemTemp.createTemp('editor-shortcuts-');
    final input = await File('${root.path}/book.epub')
        .writeAsBytes(buildMultiChapterEpub(chapters: ['原始正文', '第二章正文']));
    session = await EpubEditSession.open(input);
  });
  final editor = BookEditorController(
    session: session,
    commit: commit,
    export: export,
  );
  addTearDown(() async {
    editor.dispose();
    await root.delete(recursive: true);
  });
  return editor;
}

Future<void> _show(
  WidgetTester tester,
  BookEditorController editor, {
  ValueChanged<bool?>? onClosed,
}) async {
  tester.view
    ..physicalSize = const Size(1360, 900)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              final saved = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) =>
                      BookEditorPage(controller: editor, title: '快捷键测试书'),
                ),
              );
              onClosed?.call(saved);
            },
            child: const Text('打开编辑器'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开编辑器'));
  await pumpReaderUntil(tester, find.byType(PageTurnView));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _focusSource(WidgetTester tester) async {
  await tester.tapAt(
    tester.getTopLeft(find.byType(CodeEditor)) + const Offset(100, 30),
  );
  await tester.pump(const Duration(milliseconds: 1));
  expect(
    FocusManager.instance.primaryFocus!.context!
        .findAncestorWidgetOfExactType<CodeEditor>(),
    isNotNull,
  );
}

Future<void> _shortcut(
  WidgetTester tester, {
  LogicalKeyboardKey key = LogicalKeyboardKey.keyS,
  bool shift = false,
  bool control = false,
}) async {
  final platform = Theme.of(tester.element(find.byType(BookEditorPage)))
      .platform;
  final modifier = !control && platform == TargetPlatform.macOS
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(modifier);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(modifier);
  await tester.pump();
}

Future<void> _advanceDialog(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pump();
}

void main() {
  testWidgets('系统退出先确认未保存修改，取消保存与处理期间均阻止退出', (tester) async {
    var cancelSave = true;
    var saves = 0;
    final exporting = Completer<void>();
    final editor = await _open(tester, (_) async {
      saves++;
      if (cancelSave) throw const EditorExportCancelled();
    }, export: (_) => exporting.future);
    await _show(tester, editor);
    final doc = editor.activeDocument!;
    doc.code.text = doc.code.text.replaceFirst('原始正文', '退出前未保存');
    editor.flush();
    await pumpReaderUntilComplete(tester, () => !editor.previewLoading);
    var exit = tester.binding.handleRequestAppExit();
    await _advanceDialog(tester);
    expect(find.text('如何处理未保存的修改？'), findsOneWidget);
    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.cancel);
    await tester.tap(find.text('继续编辑'));
    await _advanceDialog(tester);
    expect(await exit, AppExitResponse.cancel);
    expect(doc.code.text, contains('退出前未保存'));

    exit = tester.binding.handleRequestAppExit();
    await _advanceDialog(tester);
    await tester.tap(find.widgetWithText(FilledButton, '保存书籍'));
    await _advanceDialog(tester);
    expect(await exit, AppExitResponse.cancel);
    expect(saves, 1);
    expect(editor.dirty, isTrue);

    final output = editor.exportBook();
    await tester.pump();
    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.cancel);
    exporting.complete();
    await output;
    cancelSave = false;
    exit = tester.binding.handleRequestAppExit();
    await _advanceDialog(tester);
    await tester.tap(find.widgetWithText(FilledButton, '保存书籍'));
    await _advanceDialog(tester);
    expect(await exit, AppExitResponse.exit);
    expect(saves, 2);
    expect(editor.dirty, isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 400));
  }, variant: _platforms);

  testWidgets('焦点位于资源筛选框时快捷键仍打开当前文档查找', (tester) async {
    final editor = await _open(tester, (_) async {});
    await _show(tester, editor);
    await tester.tap(find.widgetWithText(TextField, '文件名或路径'));
    await _shortcut(tester, key: LogicalKeyboardKey.keyF);
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('editor-search-query')))
          .focusNode!
          .hasFocus,
      isTrue,
    );
    await tester.pumpWidget(const SizedBox());
  }, variant: _platforms);

  testWidgets('跳转行支持行列输入与错误提示，快捷键切换自动换行', (tester) async {
    final editor = await _open(tester, (_) async {});
    await _show(tester, editor);
    final document = editor.activeDocument!;
    document.code.text = document.code.text.replaceFirst(
      '</body>',
      '\n<p>第二行正文</p>\n<p>第三行正文</p></body>',
    );
    editor.flush();
    await pumpReaderUntilComplete(tester, () => !editor.previewLoading);
    await _focusSource(tester);
    await _shortcut(tester, key: LogicalKeyboardKey.keyG);
    await _advanceDialog(tester);
    final field = find.descendant(
      of: find.byType(ReaderSheetForm),
      matching: find.byType(TextField),
    );
    await tester.enterText(field, '2:4');
    await tester.tap(find.widgetWithText(FilledButton, '确定'));
    await _advanceDialog(tester);
    expect(document.code.unfoldLineSelection.extentIndex, 1);
    expect(document.code.unfoldLineSelection.extentOffset, 3);
    expect(
      FocusManager.instance.primaryFocus!.context!
          .findAncestorWidgetOfExactType<CodeEditor>(),
      isNotNull,
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    expect(
      tester.widget<CodeEditor>(find.byType(CodeEditor)).wordWrap,
      isFalse,
    );
    await tester.tap(find.byTooltip('跳转到行'));
    await _advanceDialog(tester);
    await tester.enterText(field, '0');
    await tester.tap(find.widgetWithText(FilledButton, '确定'));
    await _advanceDialog(tester);
    await pumpReaderUntil(tester, find.text('请输入有效的行号，或“行号:列号”。'));
    expect(find.text('请输入有效的行号，或“行号:列号”。'), findsOneWidget);
    expect(document.code.unfoldLineSelection.extentIndex, 1);
    await tester.pumpWidget(const SizedBox());
  }, variant: _platforms);

  testWidgets('脏源码移动光标不重复发送内容通知，恢复原文会清除未保存状态', (tester) async {
    final editor = await _open(tester, (_) async {});
    final document = editor.openDocument(_chapter);
    final original = document.code.text;
    document.code.text = original.replaceFirst('原始正文', '临时输入');
    var notifications = 0;
    editor.addListener(() => notifications++);
    document.code.selection = const CodeLineSelection.collapsed(
      index: 0,
      offset: 4,
    );
    expect(notifications, 0);
    expect(editor.dirty, isTrue);
    document.code.text = original;
    expect(notifications, 1);
    expect(editor.dirty, isFalse);
    await tester.pump(const Duration(milliseconds: 350));
  });

  for (final (name, failure) in [
    ('成功', null),
    ('取消后重试', const EditorExportCancelled()),
    ('失败后重试', const FileSystemException('输出目录不可写')),
  ]) {
    testWidgets('源码区聚焦时保存快捷键$name', (tester) async {
      var attempts = 0;
      String? savedText;
      bool? result;
      final editor = await _open(tester, (session) async {
        attempts++;
        if (attempts == 1 && failure != null) throw failure;
        savedText = session.readText(_chapter);
      });
      await _show(tester, editor, onClosed: (value) => result = value);
      final document = editor.activeDocument!;
      document.code.text = document.code.text.replaceFirst('原始正文', '快捷键修订正文');
      await tester.pump();
      await _focusSource(tester);
      await _shortcut(tester);
      expect(attempts, 1);
      if (failure != null) {
        expect(editor.dirty, isTrue);
        expect(find.byType(BookEditorPage), findsOneWidget);
        expect(document.code.text, contains('快捷键修订正文'));
        if (failure is EditorExportCancelled) {
          expect(editor.error, isNull);
        } else {
          expect(editor.error, contains('输出目录不可写'));
        }
        await _focusSource(tester);
        await _shortcut(tester);
        expect(attempts, 2);
      }
      await pumpReaderUntilComplete(tester, () => !editor.busy);
      expect(savedText, contains('快捷键修订正文'));
      expect(editor.dirty, isFalse);
      expect(find.byType(BookEditorPage), findsOneWidget);
      expect(find.text('书籍已保存'), findsOneWidget);
      expect(
        tester.widget<CodeEditor>(find.byType(CodeEditor)).focusNode!.hasFocus,
        isTrue,
      );
      document.code.text = document.code.text.replaceFirst('快捷键修订正文', '连续保存正文');
      await _shortcut(tester);
      await pumpReaderUntilComplete(tester, () => !editor.busy);
      expect(savedText, contains('连续保存正文'));
      expect(editor.dirty, isFalse);
      await tester.tap(find.byTooltip('退出编辑'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    }, variant: _platforms);
  }

  testWidgets('源码区快捷键保存拒绝非法 XHTML 并保留输入和原文', (tester) async {
    var saves = 0;
    final editor = await _open(tester, (_) async => saves++);
    await _show(tester, editor);
    final document = editor.activeDocument!;
    final original = editor.session.readText(_chapter);
    document.code.text = '<html><body><p>没有闭合';
    await tester.pump();
    await _focusSource(tester);
    await _shortcut(tester);
    expect(saves, 0);
    expect(document.error, isNotNull);
    expect(document.code.text, '<html><body><p>没有闭合');
    expect(editor.session.readText(_chapter), original);
    expect(editor.dirty, isTrue);
    expect(find.byType(BookEditorPage), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  }, variant: _platforms);

  testWidgets('源码区快捷键导出可取消重试且不会提交书籍或退出', (tester) async {
    var saves = 0;
    var exports = 0;
    String? exported;
    final editor = await _open(
      tester,
      (_) async => saves++,
      export: (session) async {
        if (++exports == 1) throw const EditorExportCancelled();
        exported = session.readText(_chapter);
      },
    );
    await _show(tester, editor);
    final document = editor.activeDocument!;
    document.code.text = document.code.text.replaceFirst('原始正文', '另存的正文');
    await tester.pump();
    await _focusSource(tester);
    await _shortcut(tester, shift: true);
    expect(exports, 1);
    expect(editor.error, isNull);
    expect(editor.dirty, isTrue);
    await _shortcut(tester, shift: true);
    expect(exports, 2);
    expect(saves, 0);
    expect(exported, contains('另存的正文'));
    expect(editor.dirty, isTrue);
    expect(find.byType(BookEditorPage), findsOneWidget);
    expect(find.text('导出完成'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  }, variant: _platforms);

  testWidgets('全书查找快捷键聚焦源码底栏，关闭后继续输入', (tester) async {
    final editor = await _open(tester, (_) async {});
    await _show(tester, editor);
    await _focusSource(tester);
    await _shortcut(tester, key: LogicalKeyboardKey.keyF, shift: true);
    await tester.pump();
    expect(find.text('所有文本文件'), findsOneWidget);
    expect(find.byType(ReaderSheetForm), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    final query = find.byKey(const ValueKey('editor-search-query'));
    expect(tester.widget<TextField>(query).focusNode!.hasFocus, isTrue);
    await tester.enterText(query, '正文');
    await pumpReaderUntil(
      tester,
      find.byKey(const ValueKey('search-result-0')),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(query, findsNothing);
    expect(
      tester.widget<CodeEditor>(find.byType(CodeEditor)).focusNode!.hasFocus,
      isTrue,
    );
    await tester.pumpWidget(const SizedBox());
  }, variant: _platforms);

  testWidgets('源码标签快捷键双向循环并保留焦点、源码和查找输入', (tester) async {
    final editor = await _open(tester, (_) async {});
    await _show(tester, editor);
    final document = editor.activeDocument!;
    document.code.text = document.code.text.replaceFirst('原始正文', '未提交的正文');
    await tester.enterText(
      find.byKey(const ValueKey('editor-search-query')),
      '未提交',
    );
    editor.showSource('OEBPS/c2.xhtml');
    editor.showSource('OEBPS/content.opf');
    editor.showSource(_chapter);
    await tester.pump();
    await _focusSource(tester);
    for (final path in ['OEBPS/c2.xhtml', 'OEBPS/content.opf', _chapter]) {
      await _shortcut(tester, key: LogicalKeyboardKey.tab, control: true);
      expect(editor.activePath, path);
      expect(
        tester.widget<CodeEditor>(find.byType(CodeEditor)).focusNode!.hasFocus,
        isTrue,
      );
    }
    await _shortcut(
      tester,
      key: LogicalKeyboardKey.tab,
      control: true,
      shift: true,
    );
    expect(editor.activePath, 'OEBPS/content.opf');
    await tester.tap(find.byKey(const ValueKey('document-OEBPS/c1.xhtml')));
    await tester.pump();
    expect(
      tester.widget<CodeEditor>(find.byType(CodeEditor)).focusNode!.hasFocus,
      isTrue,
    );
    expect(editor.activeDocument, same(document));
    expect(document.code.text, contains('未提交的正文'));
    expect(document.find.findInputController.text, '未提交');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
  }, variant: _platforms);

  testWidgets('关闭源码标签保留有效修改，非法源码拒绝关闭，最后一页可重开', (tester) async {
    final editor = await _open(tester, (_) async {});
    await _show(tester, editor);
    final original = editor.activeDocument!.code.text;
    editor.activeDocument!.code.text = '<html><body><p>未闭合';
    await tester.pump();
    await _focusSource(tester);
    await _shortcut(tester, key: LogicalKeyboardKey.keyW);
    expect(editor.activePath, _chapter);
    expect(editor.activeDocument!.error, isNotNull);
    editor.activeDocument!.code.text = original.replaceFirst('原始正文', '关闭前的修改');
    await tester.pump();
    await _shortcut(tester, key: LogicalKeyboardKey.keyW);
    expect(editor.documents, isEmpty);
    expect(editor.activePath, isNull);
    expect(editor.session.readText(_chapter), contains('关闭前的修改'));
    expect(editor.dirty, isTrue);
    expect(find.byType(CodeEditor), findsNothing);
    editor.showSource(_chapter);
    await tester.pump();
    await _focusSource(tester);
    expect(editor.activeDocument!.code.text, contains('关闭前的修改'));
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  }, variant: _platforms);

  testWidgets('导出期间源码只读且不能切换、关闭标签或重复导出', (tester) async {
    final pending = Completer<void>();
    var exports = 0;
    final editor = await _open(
      tester,
      (_) async {},
      export: (_) {
        exports++;
        return pending.future;
      },
    );
    await _show(tester, editor);
    editor.showSource('OEBPS/c2.xhtml');
    editor.showSource(_chapter);
    await tester.pump();
    await _focusSource(tester);
    final document = editor.activeDocument!;
    document.code.selection = const CodeLineSelection.collapsed(
      index: 0,
      offset: 8,
    );
    final original = document.code.text;
    await _shortcut(tester, shift: true);
    expect(editor.busy, isTrue);
    expect(tester.widget<CodeEditor>(find.byType(CodeEditor)).readOnly, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await _shortcut(tester, key: LogicalKeyboardKey.tab, control: true);
    await _shortcut(tester, key: LogicalKeyboardKey.keyW);
    await _shortcut(tester, shift: true);
    expect(document.code.text, original);
    expect(editor.activePath, _chapter);
    expect(editor.documents, hasLength(2));
    expect(exports, 1);
    pending.complete();
    await tester.pump();
    expect(editor.busy, isFalse);
    expect(
      tester.widget<CodeEditor>(find.byType(CodeEditor)).readOnly,
      isFalse,
    );
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  }, variant: _platforms);
}
