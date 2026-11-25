import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reader_core/editing/epub_editing.dart';
import 'package:reader_core/epub/footnote.dart';
import 'package:reader_mobile/editing/book_editor_controller.dart';
import 'package:reader_mobile/editing/book_editor_inspector.dart';
import 'package:reader_mobile/editing/book_editor_page.dart';
import 'package:reader_mobile/theme/app_theme.dart';
import 'package:reader_ui/paging/page_turn_view.dart';
import 'package:reader_ui/page_furniture/page_furniture.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/theme/reader_sheet_form.dart';

import '../test/support/test_epub.dart';

const _chapter = 'OEBPS/c1.xhtml';

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) fail('桌面工作台验收等待超时');
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(milliseconds: 200));
}

Widget _app(BookEditorController editor, {bool dark = false}) => MaterialApp(
  theme: buildAppTheme(),
  darkTheme: buildAppTheme(brightness: Brightness.dark),
  themeMode: dark ? ThemeMode.dark : ThemeMode.light,
  builder: (_, child) => RepaintBoundary(
    key: const ValueKey('editor-workbench-capture'),
    child: child,
  ),
  home: BookEditorPage(controller: editor, title: '桌面编辑器验收'),
);

Future<void> _capture(WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
  expect(tester.takeException(), isNull);
  if (!const bool.fromEnvironment('CAPTURE_EDITOR_WORKBENCH')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('editor-workbench-capture')),
  );
  final image = await boundary.toImage(pixelRatio: 1);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = await Directory(
      '${Directory.systemTemp.path}/editor-workbench-evidence',
    ).create(recursive: true);
    final file = File('${directory.path}/$name.png');
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    debugPrint('工作台截图：${file.path}');
  } finally {
    image.dispose();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('桌面实窗工作台：源码底栏、作者 CSS 写回和日夜缩窗', (tester) async {
    final temporary = await Directory.systemTemp.createTemp(
      'workbench-native-',
    );
    final file = await File('${temporary.path}/book.epub').writeAsBytes(
      buildMultiChapterEpub(
        chapters: [
          '<p class="nvwz">目标段落与作者样式。</p>${List.generate(40, (index) => '<p>后续第$index段正文，用于验收分页四角信息。</p>').join()}',
          '<p>第二章正文。</p>',
        ],
        rawBody: true,
      ),
    );
    final session = await EpubEditSession.open(file);
    const css =
        '.nvwz { font-family: "kh"; font-size: 0.6em; text-indent: 0px; text-align: center; line-height: 1.25em; margin: 1em auto; }';
    PackageEditor(session)
        .addResource('OEBPS/book.css', utf8.encode(css), 'text/css');
    session.transaction(
      '加载作者样式',
      (tx) => tx.writeText(
        _chapter,
        tx
            .readText(_chapter)
            .replaceFirst(
              '</head>',
              '<link rel="stylesheet" href="book.css"/></head>',
            ),
      ),
    );
    final editor = BookEditorController(session: session);
    addTearDown(() async {
      editor.dispose();
      await temporary.delete(recursive: true);
    });
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1360, 900));
    await tester.pumpWidget(_app(editor));
    await _until(
      tester,
      () =>
          find.byType(PageTurnView).evaluate().isNotEmpty &&
          !editor.previewLoading,
    );
    expect(find.text('查找替换'), findsOneWidget);
    expect(find.text('样式检查器'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('editor-find-bottom-bar')),
      findsOneWidget,
    );
    final target = session.cfiForSourceOffset(
      _chapter,
      session.readText(_chapter).indexOf('目标段落'),
    );
    tester.widget<ReaderPage>(find.byType(ReaderPage)).onEditTarget!(
      ReaderEditTarget(
        spineIndex: 0,
        cfi: target,
        contentRevision: 'editor-${session.revision}',
      ),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('editor-find-bottom-bar')),
      findsOneWidget,
    );
    await tester.tap(find.text('样式检查器'));
    await _until(
      tester,
      () =>
          find.byType(BookEditorInspector).evaluate().isNotEmpty &&
          find.text('.nvwz').evaluate().isNotEmpty,
    );
    expect(find.byKey(const ValueKey('editor-find-bottom-bar')), findsNothing);
    final field = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.controller?.text == css,
    );
    await _until(tester, () => field.evaluate().isNotEmpty);
    await tester.ensureVisible(field);
    final replacement = css.replaceFirst('0.6em', '0.8em');
    await tester.enterText(field, replacement);
    await tester.pump();
    await tester.ensureVisible(find.text('应用到样式表'));
    await tester.tap(find.text('应用到样式表'));
    await _until(tester, () => !editor.previewLoading);
    expect(session.readText('OEBPS/book.css'), replacement);
    expect(find.byType(BookEditorInspector), findsOneWidget);
    await _until(tester, () => find.byType(PageTurnView).evaluate().isNotEmpty);
    final preview = tester
        .widget<PageTurnView>(find.byType(PageTurnView))
        .session;
    await _until(tester, () => preview.page != null && !preview.loading);
    await _capture(tester, '1360-900-作者样式');
    await tester.tap(find.byTooltip('下一页'));
    await _until(tester, () => preview.page!.pageIndex > 0 && !preview.loading);
    expect(find.byType(ReaderPageHeader), findsOneWidget);
    expect(find.byType(ReaderPageFooter), findsOneWidget);
    await _capture(tester, '1360-900-四角信息');
    for (final size in [const Size(960, 760), const Size(640, 760)]) {
      await tester.binding.setSurfaceSize(size);
      await _capture(tester, '${size.width.toInt()}-${size.height.toInt()}-日间');
      if (size.width < 720) {
        await tester.tap(find.text('源码'));
        await _capture(tester, '640-760-源码底栏');
      }
    }
    await tester.binding.setSurfaceSize(const Size(1360, 900));
    await tester.pumpWidget(_app(editor, dark: true));
    await _capture(tester, '1360-900-夜间');
    final previewLabel = tester.element(find.text('手机预览'));
    expect(
      DefaultTextStyle.of(previewLabel).style.color,
      Theme.of(previewLabel).colorScheme.onSurface,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('五类工具栏完成空白 HTML、图片、注释并导出重新打开', (tester) async {
    final temporary = await Directory.systemTemp.createTemp(
      'editor-authoring-',
    );
    final file = await File('${temporary.path}/book.epub')
        .writeAsBytes(buildMultiChapterEpub(chapters: ['原书正文', '下一章正文']));
    final session = await EpubEditSession.open(file);
    final picture = await rootBundle.load('assets/branding/app_icon.png');
    PackageEditor(session).addResource(
      'OEBPS/Images/示例.png',
      picture.buffer.asUint8List(),
      'image/png',
    );
    final editor = BookEditorController(session: session);
    addTearDown(() async {
      editor.dispose();
      await temporary.delete(recursive: true);
    });
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1360, 900));
    await tester.pumpWidget(_app(editor));
    await _until(tester, () => !editor.previewLoading);

    await tester.tap(find.byKey(const ValueKey('editor-category-结构')));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('新建空白 HTML').hitTestable());
    await _until(
      tester,
      () => find.byKey(const ValueKey('new-html-path')).evaluate().isNotEmpty,
    );
    await tester.tap(find.byKey(const ValueKey('new-html-path')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(
      find.byKey(const ValueKey('new-html-path')),
      'OEBPS/新建正文.xhtml',
    );
    await tester.enterText(
      find.byKey(const ValueKey('new-html-title')),
      '插图与注释',
    );
    await _capture(tester, '新建空白HTML-表单');
    await tester.tap(find.text('创建 HTML'));
    await _until(
      tester,
      () =>
          editor.activePath == 'OEBPS/新建正文.xhtml' &&
          !editor.previewLoading &&
          find.byType(ReaderSheetForm).evaluate().isEmpty,
    );
    expect(editor.session.spinePaths[1], 'OEBPS/新建正文.xhtml');
    expect(editor.activeDocument!.code.text, isNot(contains('<h1>')));
    editor.activeDocument!.code.replaceSelection(
      '<p id="new-text">这是新建章节的正文。</p>',
    );
    expect(editor.flush(), isTrue);
    await _until(tester, () => !editor.previewLoading);
    final created = editor.activePath!;
    editor.openDocument(
      created,
      offset: editor.activeDocument!.code.text.indexOf('新建章节'),
    );
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(find.byKey(const ValueKey('editor-category-图片')));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('插入图片').hitTestable());
    await _until(
      tester,
      () => find.byKey(const ValueKey('image-alt')).evaluate().isNotEmpty,
    );
    await tester.tap(find.byKey(const ValueKey('image-alt')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(find.byKey(const ValueKey('image-alt')), '示例插图');
    await _capture(tester, '插入图片-预览与位置');
    await tester.tap(find.widgetWithText(FilledButton, '插入图片'));
    await _until(
      tester,
      () =>
          session.readText(created).contains('alt="示例插图"') &&
          !editor.previewLoading &&
          find.byType(ReaderSheetForm).evaluate().isEmpty,
    );
    final beforeNote = session.readText(created);
    editor.openDocument(created, offset: beforeNote.indexOf('正文。') + 2);
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(find.byKey(const ValueKey('editor-category-注释与正文')));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('设置 EPUB 注释').hitTestable());
    await _until(
      tester,
      () => find.byKey(const ValueKey('note-text')).evaluate().isNotEmpty,
    );
    await tester.tap(find.byKey(const ValueKey('note-text')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(
      find.byKey(const ValueKey('note-text')),
      '这是一条直接写入 EPUB 的注释。',
    );
    await _capture(tester, '设置EPUB注释-表单');
    await tester.tap(find.byKey(const ValueKey('note-apply')));
    await _until(
      tester,
      () =>
          session.readText(created).contains('epub:type="noteref"') &&
          !editor.previewLoading &&
          find.byType(ReaderSheetForm).evaluate().isEmpty,
    );
    final document = FootnoteParser.parse(
      spineIndex: 1,
      path: created,
      xhtml: session.readText(created),
    );
    expect(
      FootnoteParser.resolve(
        source: document,
        documents: {created: document},
      ).single.noteText,
      '这是一条直接写入 EPUB 的注释。',
    );
    final preview = tester
        .widget<PageTurnView>(find.byType(PageTurnView))
        .session;
    await _until(
      tester,
      () =>
          preview.page?.spineIndex == 1 && preview.currentText.contains('新建章节'),
    );
    await _capture(tester, '新建正文-图片注释预览');
    editor.undo();
    expect(session.readText(created), beforeNote);
    editor.redo();
    final output = File('${temporary.path}/edited.epub');
    await EpubWriter.write(session, output);
    final reopened = await EpubEditSession.open(output);
    try {
      reopened.validate();
      expect(reopened.spinePaths, session.spinePaths);
      expect(reopened.readText(created), session.readText(created));
      expect(reopened.readBytes('OEBPS/Images/示例.png'), isNotNull);
    } finally {
      reopened.close();
    }
    await tester.pumpWidget(const SizedBox());
  });
}
