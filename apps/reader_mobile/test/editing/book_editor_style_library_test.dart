import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/editing/epub_editing.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_mobile/editing/book_editor_controller.dart';
import 'package:reader_mobile/editing/book_editor_tools.dart';
import 'package:reader_mobile/editing/book_style_presets.dart';
import 'package:reader_mobile/editing/book_style_preview.dart';
import 'package:reader_mobile/theme/app_theme.dart';

import '../support/reader_pump.dart';
import '../support/test_epub.dart';

const _path = 'OEBPS/c1.xhtml';
const _targetId = 'target';
final _platforms = TargetPlatformVariant({
  TargetPlatform.macOS,
  TargetPlatform.windows,
});

Future<BookEditorController> _open(WidgetTester tester) async {
  late Directory root;
  late EpubEditSession session;
  await tester.runAsync(() async {
    root = await Directory.systemTemp.createTemp('style-library-');
    final file = await File('${root.path}/book.epub').writeAsBytes(
      buildMultiChapterEpub(
        chapters: [
          '<p id="target" class="body" style="color: red; text-align: left !important; --custom: &quot;a;b&quot;">目标正文<strong>保留行内标签</strong></p><p>相邻正文</p>',
          '<p class="body">同名正文</p>',
        ],
        rawBody: true,
      ),
    );
    session = await EpubEditSession.open(file);
  });
  final editor = BookEditorController(session: session);
  addTearDown(() async {
    editor.dispose();
    await root.delete(recursive: true);
  });
  await pumpReaderUntilComplete(tester, () => !editor.previewLoading);
  editor.showSource(_path, offset: session.readText(_path).indexOf('目标正文'));
  return editor;
}

EditableElementRef _target(BookEditorController editor) => editor.session
    .editableDocument(_path)
    .elements
    .singleWhere((node) => node.attributes['id'] == _targetId);

Future<void> _show(
  WidgetTester tester,
  BookEditorController editor, {
  bool classForm = false,
  bool dark = false,
}) async {
  tester.view
    ..physicalSize = const Size(1200, 900)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(
        brightness: dark ? Brightness.dark : Brightness.light,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              final tools = BookEditorTools(context, editor);
              if (classForm) {
                await tools.classStyle('body');
              } else {
                await tools.styleLibrary(target: _target(editor));
              }
            },
            child: const Text('打开样式'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开样式'));
  await pumpReaderUntil(tester, find.text(classForm ? '全书 .body' : '样式库'));
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> _choose(WidgetTester tester, String name, String id) async {
  await tester.enterText(
    find.byKey(const ValueKey('style-library-search')),
    name,
  );
  await tester.pump();
  await tester.tap(find.byKey(ValueKey('style-preset-$id')));
  await tester.pump();
}

Future<void> _cancel(WidgetTester tester) async {
  await tester.tap(find.text('取消').last);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}

void main() {
  testWidgets('内置样式使用正式引擎生效，只改当前元素且导出、撤销保留作者内容', (tester) async {
    final editor = await _open(tester);
    final session = editor.session;
    final original = session.readText(_path);
    final other = session.readText('OEBPS/c2.xhtml');
    for (final preset in bookStylePresets) {
      final history = session.history.length;
      applyBookStyleToElement(
        session,
        _target(editor),
        preset,
        important: true,
      );
      expect(session.history.length, history + 1);
      final target = _target(editor);
      expect(target.classes, {'body'});
      expect(target.innerXml, '目标正文<strong>保留行内标签</strong>');
      expect(target.attributes['style'], contains('--custom: "a;b";'));
      expect(session.readText('OEBPS/c2.xhtml'), other);
      final preview = await pumpReaderTask(
        tester,
        session.createPreviewSource(),
      );
      try {
        final pages = await pumpReaderTask(tester, preview.loadChapter(0));
        final line = pages
            .expand(TextHitTester.lineBoxes)
            .firstWhere((line) => line.text.contains('目标正文'));
        final expected = {
          'left': CssTextAlign.left,
          'right': CssTextAlign.right,
          'center': CssTextAlign.center,
          'justify': CssTextAlign.justify,
        }[preset.declarations['text-align']];
        expect(
          line.slice.block.style!.textAlign,
          expected,
          reason: preset.name,
        );
      } finally {
        preview.close();
      }
      session.validate();
      session.undo();
      expect(session.readText(_path), original);
    }
    final preset = bookStylePresets.firstWhere(
      (preset) => preset.id == 'signature',
    );
    applyBookStyleToElement(session, _target(editor), preset);
    final preview = await pumpReaderTask(tester, session.createPreviewSource());
    final pages = await pumpReaderTask(tester, preview.loadChapter(0));
    final line = pages
        .expand(TextHitTester.lineBoxes)
        .firstWhere((line) => line.text.contains('目标正文'));
    expect(line.slice.block.style!.textAlign, CssTextAlign.left);
    preview.close();
    applyBookStyleToElement(session, _target(editor), preset, important: true);
    final export = File('${session.baseFile.parent.path}/export.epub');
    await pumpReaderTask(tester, EpubWriter.write(session, export));
    final reopened = await tester.runAsync(() => EpubEditSession.open(export));
    expect(reopened!.readText(_path), session.readText(_path));
    reopened.close();
    await pumpReaderUntilComplete(tester, () => !editor.previewLoading);
  });

  testWidgets('搜索、无结果、复制与取消不改变书籍，窄窗深色可浏览样式', (tester) async {
    final editor = await _open(tester);
    final revision = editor.session.revision;
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _show(tester, editor, dark: true);
    tester.view.physicalSize = const Size(640, 760);
    await tester.pump(const Duration(milliseconds: 300));
    await _choose(tester, '图注', 'caption');
    await tester.tap(find.text('复制 CSS'));
    await tester.pump();
    expect(copied, contains('text-align: center;'));
    await tester.enterText(
      find.byKey(const ValueKey('style-library-search')),
      '不存在的样式',
    );
    await tester.pump();
    expect(find.text('没有匹配的样式'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('style-library-apply')),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('显示全部样式'));
    await tester.pump();
    expect(find.byType(BookStylePreview), findsOneWidget);
    await _cancel(tester);
    expect(editor.session.revision, revision);
    expect(tester.takeException(), isNull);
  }, variant: _platforms);

  testWidgets('当前元素应用、重复应用不增加历史，撤销与重做保持正文', (tester) async {
    final editor = await _open(tester);
    final original = editor.session.readText(_path);
    await _show(tester, editor);
    await _choose(tester, '落款', 'signature');
    final important = find.byKey(const ValueKey('style-library-important'));
    await tester.ensureVisible(important);
    await tester.pump();
    await tester.tap(important);
    await tester.pump();
    expect(tester.widget<CheckboxListTile>(important).value, isTrue);
    await tester.tap(find.byKey(const ValueKey('style-library-apply')));
    await pumpReaderUntilComplete(
      tester,
      () => find.text('样式库').evaluate().isEmpty && !editor.previewLoading,
    );
    expect(
      _target(editor).attributes['style'],
      contains('text-align: right !important;'),
    );
    final applied = editor.session.readText(_path);
    final history = editor.session.history.length;
    applyBookStyleToElement(
      editor.session,
      _target(editor),
      bookStylePresets.last,
      important: true,
    );
    expect(editor.session.history.length, history);
    editor.undo();
    expect(editor.session.readText(_path), original);
    editor.redo();
    expect(editor.session.readText(_path), applied);
    await pumpReaderUntilComplete(tester, () => !editor.previewLoading);
  }, variant: _platforms);

  testWidgets('同名class先检查影响与作者优先级，统一后跨章生效且可一步撤销', (tester) async {
    final editor = await _open(tester);
    final first = editor.session.readText(_path);
    final second = editor.session.readText('OEBPS/c2.xhtml');
    await _show(tester, editor);
    await _choose(tester, '图注', 'caption');
    await tester.ensureVisible(find.text('全书 .body'));
    await tester.pump();
    await tester.tap(find.text('全书 .body'));
    await tester.pump();
    await tester.tap(find.text('检查全书影响'));
    await pumpReaderUntil(tester, find.text('应用全书样式'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('2 个章节 · 2 个元素'), findsOneWidget);
    expect(editor.session.readText(_path), first);
    await tester.tap(find.text('应用全书样式'));
    await pumpReaderUntil(tester, find.text('存在样式优先级冲突'));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('统一同名样式'));
    await pumpReaderUntilComplete(
      tester,
      () => !editor.busy && editor.session.readText(_path) != first,
    );
    expect(
      editor.session.readText(_path),
      contains('text-align: center !important;'),
    );
    expect(
      editor.session.readText('OEBPS/c2.xhtml'),
      contains('spectacular-edit.css'),
    );
    editor.undo();
    expect(editor.session.readText(_path), first);
    expect(editor.session.readText('OEBPS/c2.xhtml'), second);
    await tester.pump(const Duration(milliseconds: 300));
    await pumpReaderUntilComplete(tester, () => !editor.previewLoading);
  });

  testWidgets('全书表单可从样式库填入，取消表单不写入，非法目标拒绝应用', (tester) async {
    final editor = await _open(tester);
    final revision = editor.session.revision;
    await _show(tester, editor, classForm: true);
    await tester.tap(find.text('从样式库填入'));
    await pumpReaderUntil(tester, find.text('样式库'));
    await tester.pump(const Duration(milliseconds: 250));
    await _choose(tester, '无缩进正文', 'body-flat');
    await tester.tap(find.text('填入样式'));
    await pumpReaderUntilComplete(
      tester,
      () => find.text('样式库').evaluate().isEmpty,
    );
    final indent = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == 'text-indent',
    );
    expect(tester.widget<TextField>(indent).controller!.text, '0');
    await _cancel(tester);
    expect(editor.session.revision, revision);
    final head = editor.session
        .editableDocument(_path)
        .elements
        .firstWhere((node) => node.tag == 'head');
    expect(
      () =>
          applyBookStyleToElement(editor.session, head, bookStylePresets.first),
      throwsA(isA<EpubEditException>()),
    );
    expect(editor.session.revision, revision);
  });
}
