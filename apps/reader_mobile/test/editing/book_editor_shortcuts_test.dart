import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:reader_core/editing/epub_editing.dart';
import 'package:reader_mobile/editing/book_editor_controller.dart';
import 'package:reader_mobile/editing/book_editor_page.dart';
import 'package:reader_mobile/theme/app_theme.dart';
import 'package:reader_ui/paging/page_turn_view.dart';

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

void main() {
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
      await pumpReaderUntilComplete(
        tester,
        () => find.byType(BookEditorPage).evaluate().isEmpty,
      );
      expect(savedText, contains('快捷键修订正文'));
      expect(editor.dirty, isFalse);
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

  testWidgets('源码快捷键打开全书查找，弹窗内不误保存或关闭文档', (tester) async {
    var saves = 0;
    final editor = await _open(tester, (_) async => saves++);
    await _show(tester, editor);
    await _focusSource(tester);
    await _shortcut(tester, key: LogicalKeyboardKey.keyF, shift: true);
    await pumpReaderUntil(tester, find.text('全书源码查找替换'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(TextField, '查找内容'));
    await _shortcut(tester);
    await _shortcut(tester, key: LogicalKeyboardKey.keyW);
    expect(saves, 0);
    expect(editor.documents, hasLength(1));
    expect(find.text('全书源码查找替换'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await pumpReaderUntilComplete(
      tester,
      () => find.byType(AlertDialog).evaluate().isEmpty,
    );
    await _focusSource(tester);
    await _shortcut(tester);
    await pumpReaderUntilComplete(
      tester,
      () => find.byType(BookEditorPage).evaluate().isEmpty,
    );
    expect(saves, 1);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  }, variant: _platforms);

  testWidgets('源码标签快捷键双向循环并保留焦点、源码和查找输入', (tester) async {
    final editor = await _open(tester, (_) async {});
    await _show(tester, editor);
    final document = editor.activeDocument!;
    document.code.text = document.code.text.replaceFirst('原始正文', '未提交的正文');
    document.find.findInputController.text = '未提交';
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
