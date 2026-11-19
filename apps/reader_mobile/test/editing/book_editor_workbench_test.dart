import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:reader_core/editing/epub_editing.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_mobile/editing/book_editor_controller.dart';
import 'package:reader_mobile/editing/book_editor_inspector.dart';
import 'package:reader_mobile/editing/book_editor_page.dart';
import 'package:reader_mobile/editing/book_editor_source.dart';
import 'package:reader_mobile/editing/book_editor_tools.dart';
import 'package:reader_mobile/theme/app_theme.dart';
import 'package:reader_ui/paging/page_turn_view.dart';
import 'package:reader_ui/page_furniture/page_furniture.dart';
import 'package:reader_ui/reader_page.dart';

import '../support/reader_pump.dart';
import '../support/test_epub.dart';

const _chapter = 'OEBPS/c1.xhtml';
final _desktopPlatforms = TargetPlatformVariant({
  TargetPlatform.macOS,
  TargetPlatform.windows,
});

Future<BookEditorController> _open(
  WidgetTester tester, {
  String? firstChapter,
}) async {
  late Directory temporary;
  late EpubEditSession session;
  await tester.runAsync(() async {
    temporary = await Directory.systemTemp.createTemp('desktop-workbench-');
    final file = File('${temporary.path}/book.epub');
    await file.writeAsBytes(
      buildMultiChapterEpub(
        chapters: [
          firstChapter ?? '<p id="paragraph">原始正文与<em>行内强调</em>继续阅读。</p>',
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
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('editor-find-bottom-bar')))
          .dy,
      greaterThan(tester.getTopLeft(find.byType(CodeEditor)).dy),
    );
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

  testWidgets('源码光标跨页跟随到长段落中部，保留焦点且切章后不回跳', (tester) async {
    final body = List.generate(
      240,
      (index) => '第$index句长段落正文，定位应当显示这里。',
    ).join();
    final editor = await _open(tester, firstChapter: '<p>$body</p>');
    await _show(tester, editor, const Size(1360, 900));
    final preview = tester
        .widget<PageTurnView>(find.byType(PageTurnView))
        .session;
    await pumpReaderUntilComplete(tester, () => preview.page != null);
    await tester.tapAt(
      tester.getTopLeft(find.byType(CodeEditor)) + const Offset(90, 24),
    );
    final document = editor.activeDocument!;
    editor.openDocument(_chapter, offset: document.code.text.indexOf('第180句'));
    await tester.pump(const Duration(milliseconds: 200));
    await pumpReaderUntilComplete(
      tester,
      () => preview.currentText.contains('第180句'),
    );
    expect(preview.page!.pageIndex, greaterThan(0));
    expect(
      tester.widget<CodeEditor>(find.byType(CodeEditor)).focusNode!.hasFocus,
      isTrue,
    );
    editor.openDocument(_chapter, offset: document.code.text.indexOf('第210句'));
    editor.showSource('OEBPS/c2.xhtml');
    await tester.pump(const Duration(milliseconds: 250));
    await pumpReaderUntilComplete(tester, () => preview.page?.spineIndex == 1);
    expect(preview.currentText, contains('第二章节正文'));
    expect(editor.activePath, 'OEBPS/c2.xhtml');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  }, variant: _desktopPlatforms);

  testWidgets('未列入阅读顺序的 HTML 可直接预览，文件行只显示文件名', (tester) async {
    final editor = await _open(tester);
    const extra = 'OEBPS/附录.xhtml';
    PackageEditor(editor.session).addResource(
      extra,
      utf8.encode(
        editor.session.readText(_chapter).replaceFirst('原始正文', '附录正文'),
      ),
      'application/xhtml+xml',
    );
    await pumpReaderUntilComplete(tester, () => !editor.previewLoading);
    await _show(tester, editor, const Size(1360, 900));
    final row = find.descendant(
      of: find.byType(BookEditorFiles),
      matching: find.byKey(const ValueKey(extra)),
    );
    expect(tester.widget<ListTile>(row).subtitle, isNull);
    expect(find.byTooltip(extra), findsOneWidget);
    await tester.tap(row);
    final preview = tester
        .widget<PageTurnView>(find.byType(PageTurnView))
        .session;
    await pumpReaderUntilComplete(tester, () => preview.page?.spineIndex == 2);
    expect(preview.currentText, contains('附录正文'));
    expect(editor.session.spinePaths, [_chapter, 'OEBPS/c2.xhtml']);
    await tester.pumpWidget(const SizedBox());
  }, variant: _desktopPlatforms);

  testWidgets('正文文件与源码标签真实右键支持插入、重命名、取消删除和撤销', (tester) async {
    final editor = await _open(tester);
    await _show(tester, editor, const Size(1360, 900));
    final row = find.descendant(
      of: find.byType(BookEditorFiles),
      matching: find.byKey(const ValueKey(_chapter)),
    );
    await tester.tap(row, buttons: kSecondaryMouseButton);
    await pumpReaderUntil(tester, find.text('在此处之前插入 HTML').hitTestable());
    await tester.tap(find.text('在此处之前插入 HTML'));
    await pumpReaderUntil(tester, find.byType(AlertDialog));
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'OEBPS/新章.xhtml',
    );
    await tester.tap(find.text('确定'));
    await pumpReaderUntilComplete(
      tester,
      () => editor.activePath == 'OEBPS/新章.xhtml' && !editor.previewLoading,
    );
    expect(editor.session.spinePaths, [
      'OEBPS/新章.xhtml',
      _chapter,
      'OEBPS/c2.xhtml',
    ]);
    await tester.tap(
      find.byKey(const ValueKey('document-OEBPS/新章.xhtml')),
      buttons: kSecondaryMouseButton,
    );
    await pumpReaderUntil(tester, find.text('重命名').hitTestable());
    await tester.tap(find.text('重命名'));
    await pumpReaderUntil(tester, find.byType(AlertDialog));
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'OEBPS/改名.xhtml',
    );
    await tester.tap(find.text('确定'));
    await pumpReaderUntilComplete(
      tester,
      () => editor.activePath == 'OEBPS/改名.xhtml' && !editor.previewLoading,
    );
    expect(editor.session.spinePaths.first, 'OEBPS/改名.xhtml');
    await tester.tap(
      find.byKey(const ValueKey('document-OEBPS/改名.xhtml')),
      buttons: kSecondaryMouseButton,
    );
    await pumpReaderUntil(tester, find.text('删除').hitTestable());
    await tester.tap(find.text('删除'));
    await pumpReaderUntil(tester, find.byType(AlertDialog));
    await tester.tap(find.text('取消'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(editor.session.readBytes('OEBPS/改名.xhtml'), isNotNull);
    editor.runCommand(editor.session.undo);
    editor.runCommand(editor.session.undo);
    await pumpReaderUntilComplete(tester, () => !editor.previewLoading);
    expect(editor.session.spinePaths, [_chapter, 'OEBPS/c2.xhtml']);
    expect(editor.session.readBytes('OEBPS/改名.xhtml'), isNull);
    await tester.pumpWidget(const SizedBox());
  }, variant: _desktopPlatforms);

  testWidgets('实际点击预览段落后修改原 CSS，正式引擎重排且检查器保留', (tester) async {
    final editor = await _open(
      tester,
      firstChapter: '<p class="nvwz">目标段落样式</p>',
    );
    final package = PackageEditor(editor.session);
    const stylesheet = 'OEBPS/book.css';
    const original = '.nvwz { font-size: 16px; text-align: left; }';
    const replacement =
        '.nvwz { font-family: "kh"; font-size: 0.6em; text-indent: 0px; text-align: center; line-height: 1.25em; margin: 1em auto; }';
    package.addResource(stylesheet, utf8.encode(original), 'text/css');
    editor.session.transaction(
      '引用作者样式',
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
    await pumpReaderUntilComplete(tester, () => !editor.previewLoading);
    await _show(tester, editor, const Size(1360, 900));
    final preview = tester
        .widget<PageTurnView>(find.byType(PageTurnView))
        .session;
    await pumpReaderUntilComplete(tester, () => preview.page != null);
    final line = TextHitTester.lineBoxes(preview.page!)
        .firstWhere((line) => line.text.contains('目标段落'));
    final paper = tester.renderObject<RenderBox>(
      find.byKey(const ValueKey('reader-page-0-0')),
    );
    final reader = tester.widget<ReaderPage>(find.byType(ReaderPage));
    final safe = MediaQuery.of(tester.element(find.byType(ReaderPage))).padding;
    await tester.tapAt(
      paper.localToGlobal(
        line.rect.center +
            Offset(
              reader.padding.left,
              reader.padding.top +
                  safe.top +
                  PageFurniture.headerHeight +
                  PageFurniture.headerGap,
            ),
      ),
    );
    await pumpReaderUntil(tester, find.byType(BookEditorInspector));
    expect(find.widgetWithText(ChoiceChip, '.nvwz'), findsOneWidget);
    final field = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.controller?.text == original,
    );
    await pumpReaderUntil(tester, field);
    await tester.ensureVisible(field);
    await tester.enterText(field, replacement);
    await tester.pump();
    final apply = find.text('应用到样式表');
    await tester.ensureVisible(apply);
    await tester.tap(apply);
    await pumpReaderUntilComplete(tester, () => !editor.previewLoading);
    expect(editor.session.readText(stylesheet), replacement);
    expect(find.byType(BookEditorInspector), findsOneWidget);
    await pumpReaderUntil(tester, find.byType(PageTurnView));
    final updated = tester
        .widget<PageTurnView>(find.byType(PageTurnView))
        .session;
    await pumpReaderUntilComplete(tester, () => updated.page != null);
    final styled = TextHitTester.lineBoxes(updated.page!)
        .firstWhere((line) => line.text.contains('目标段落'));
    expect(
      styled.slice.block.style!.fontSize,
      closeTo(editor.previewSource!.baseStyle.fontSize * .6, .01),
    );
    expect(styled.rect.center.dx, greaterThan(line.rect.center.dx));
    editor.runCommand(editor.session.undo);
    await pumpReaderUntilComplete(tester, () => !editor.previewLoading);
    expect(editor.session.readText(stylesheet), original);
    await tester.pumpWidget(const SizedBox());
  }, variant: _desktopPlatforms);
}
