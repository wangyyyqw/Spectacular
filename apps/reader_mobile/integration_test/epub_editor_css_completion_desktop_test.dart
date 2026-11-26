import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/editing/epub_editing.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_mobile/editing/book_editor_controller.dart';
import 'package:reader_mobile/editing/book_editor_page.dart';
import 'package:reader_mobile/editing/book_editor_style_rule.dart';
import 'package:reader_mobile/theme/app_theme.dart';
import 'package:reader_ui/paging/page_turn_view.dart';
import 'package:reader_ui/reader_page.dart';

import '../test/support/test_epub.dart';

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 25));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) fail('CSS 补全实窗验收等待超时');
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(milliseconds: 120));
}

Future<void> _manual(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.space);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 120));
}

Future<void> _capture(WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 200));
  expect(tester.takeException(), isNull);
  if (!const bool.fromEnvironment('CAPTURE_CSS_COMPLETION')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('css-completion-capture')),
  );
  final image = await boundary.toImage(pixelRatio: 1);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = await Directory(
      '${Directory.systemTemp.path}/css-completion-evidence',
    ).create(recursive: true);
    final file = File('${directory.path}/$name.png');
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    debugPrint('CSS 补全截图：${file.path}');
  } finally {
    image.dispose();
  }
}

Widget _app(BookEditorController editor, {bool dark = false}) => MaterialApp(
  theme: buildAppTheme(),
  darkTheme: buildAppTheme(brightness: Brightness.dark),
  themeMode: dark ? ThemeMode.dark : ThemeMode.light,
  builder: (_, child) => RepaintBoundary(
    key: const ValueKey('css-completion-capture'),
    child: child,
  ),
  home: BookEditorPage(controller: editor, title: 'CSS 智能补全验收'),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('CSS源码、嵌入样式与检查器在实窗补全后应用到正式预览', (tester) async {
    final root = await Directory.systemTemp.createTemp('css-completion-');
    final file = await File('${root.path}/book.epub').writeAsBytes(
      buildMultiChapterEpub(
        chapters: ['<p class="body" style="color: black;">补全后检查原文与预览。</p>'],
        rawBody: true,
      ),
    );
    final session = await EpubEditSession.open(file);
    const chapter = 'OEBPS/c1.xhtml';
    const path = 'OEBPS/book.css';
    PackageEditor(session).addResource(
      path,
      utf8.encode('.body {\n  font-size: 1em;\n  text-align: left;\n}'),
      'text/css',
    );
    session.transaction(
      '加载样式',
      (tx) => tx.writeText(
        chapter,
        tx
            .readText(chapter)
            .replaceFirst(
              '</head>',
              '<link rel="stylesheet" href="book.css"/></head>',
            ),
      ),
    );
    final editor = BookEditorController(session: session);
    addTearDown(() async {
      editor.dispose();
      await root.delete(recursive: true);
    });
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1360, 900));
    await tester.pumpWidget(_app(editor));
    await _until(
      tester,
      () =>
          !editor.previewLoading &&
          find.byType(PageTurnView).evaluate().isNotEmpty,
    );
    editor.showSource(path);
    await tester.pump(const Duration(milliseconds: 150));
    final code = editor.activeDocument!.code;
    final focus = tester.widget<CodeEditor>(find.byType(CodeEditor)).focusNode!;
    focus.requestFocus();
    await tester.pump();
    editor.openDocument(path, offset: code.text.indexOf('font-size') + 6);
    await tester.pump();
    await _manual(tester);
    expect(
      find.byKey(const ValueKey('css-completion-font-size')),
      findsOneWidget,
    );
    await _capture(tester, '源码-属性补全');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(code.text, contains('font-size: 1em;'));
    expect(find.byKey(const ValueKey('css-completion-menu')), findsOneWidget);
    await _capture(tester, '源码-属性值补全');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);

    editor.openDocument(path, offset: code.text.indexOf('left') + 2);
    await tester.pump();
    await _manual(tester);
    await tester.tap(find.byKey(const ValueKey('css-completion-left')));
    await tester.pump();
    expect(code.text, contains('text-align: left;'));
    expect(editor.flush(), isTrue);
    await _until(tester, () => !editor.previewLoading);

    editor.showSource(chapter);
    await tester.pump();
    tester
        .widget<CodeEditor>(find.byType(CodeEditor))
        .focusNode!
        .requestFocus();
    final html = editor.activeDocument!.code;
    editor.openDocument(chapter, offset: html.text.indexOf('color') + 3);
    await tester.pump();
    await _manual(tester);
    expect(find.byKey(const ValueKey('css-completion-color')), findsOneWidget);
    await _capture(tester, 'XHTML-行内样式补全');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    final target = session.cfiForSourceOffset(
      chapter,
      html.text.indexOf('补全后'),
    );
    tester.widget<ReaderPage>(find.byType(ReaderPage)).onEditTarget!(
      ReaderEditTarget(spineIndex: 0, cfi: target),
    );
    await tester.pump();
    await tester.tap(find.text('样式检查器'));
    await _until(
      tester,
      () => find.byType(BookEditorStyleRule).evaluate().isNotEmpty,
    );
    final ruleField = find.descendant(
      of: find.byType(BookEditorStyleRule).first,
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(ruleField);
    await tester.tap(ruleField);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.enterText(
      ruleField,
      '.body {\n  font-size: 1em;\n  text-align: ce;\n}',
    );
    final input = tester.widget<TextField>(ruleField).controller!;
    input.selection = TextSelection.collapsed(
      offset: input.text.indexOf('ce;') + 2,
    );
    await tester.pump();
    await _manual(tester);
    expect(find.byKey(const ValueKey('css-completion-center')), findsOneWidget);
    await _capture(tester, '样式检查器-属性值补全');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(input.text, contains('text-align: center;'));
    final apply = find.text('应用到样式表').first;
    await tester.ensureVisible(apply);
    await tester.tap(apply);
    await _until(
      tester,
      () =>
          session.readText(path).contains('text-align: center') &&
          !editor.previewLoading,
    );
    expect(find.byKey(const ValueKey('css-completion-menu')), findsNothing);
    final preview = tester
        .widget<PageTurnView>(find.byType(PageTurnView))
        .session;
    await _until(tester, () => preview.page != null && !preview.loading);
    final line = TextHitTester.lineBoxes(preview.page!)
        .firstWhere((line) => line.text.contains('补全后'));
    expect(line.slice.block.style!.textAlign, CssTextAlign.center);
    await _capture(tester, '补全后-正式预览');
    for (final (size, dark) in [
      (const Size(960, 760), false),
      (const Size(640, 760), true),
    ]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(_app(editor, dark: dark));
      editor.showSource(path);
      await tester.pump(const Duration(milliseconds: 250));
      if (size.width < 720) await tester.tap(find.text('源码'));
      await tester.pump();
      tester
          .widget<CodeEditor>(find.byType(CodeEditor))
          .focusNode!
          .requestFocus();
      editor.openDocument(path, offset: code.text.indexOf('font-size') + 6);
      await tester.pump();
      await _manual(tester);
      final menu = find.byKey(const ValueKey('css-completion-menu'));
      expect(menu, findsOneWidget);
      final bounds = tester.getRect(menu);
      expect(bounds.left, greaterThanOrEqualTo(0));
      expect(bounds.top, greaterThanOrEqualTo(0));
      expect(bounds.right, lessThanOrEqualTo(size.width));
      expect(bounds.bottom, lessThanOrEqualTo(size.height));
      await _capture(tester, '${size.width.toInt()}-补全-${dark ? '夜间' : '日间'}');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    }
    session.validate();
    await tester.pumpWidget(const SizedBox());
  });
}
