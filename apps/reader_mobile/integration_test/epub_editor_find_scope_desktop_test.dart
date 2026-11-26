import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reader_core/editing/epub_editing.dart';
import 'package:reader_mobile/editing/book_editor_controller.dart';
import 'package:reader_mobile/editing/book_editor_page.dart';
import 'package:reader_mobile/editing/book_editor_source.dart';
import 'package:reader_mobile/theme/app_theme.dart';
import 'package:reader_ui/paging/page_turn_view.dart';

import '../test/support/test_epub.dart';

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) fail('查找范围验收等待超时');
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _capture(WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 300));
  expect(tester.takeException(), isNull);
  if (!const bool.fromEnvironment('CAPTURE_FIND_SCOPE')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('find-scope-capture')),
  );
  final image = await boundary.toImage(pixelRatio: 1);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = await Directory(
      '${Directory.systemTemp.path}/find-scope-evidence',
    ).create(recursive: true);
    final file = File('${directory.path}/$name.png');
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    debugPrint('查找范围截图：${file.path}');
  } finally {
    image.dispose();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('源码查找范围菜单、结果片段和编辑器高亮', (tester) async {
    final temporary = await Directory.systemTemp.createTemp('find-scope-');
    final file = File('${temporary.path}/book.epub');
    await file.writeAsBytes(
      buildMultiChapterEpub(
        chapters: [
          '<p>目标词一，目标词二。</p>',
          '${List.generate(45, (index) => '<p>第$index段正文，用于验收搜索跳转后的预览位置。</p>').join()}<p>第二章目标词。</p>',
          '<p>第三章目标词。</p>',
        ],
        rawBody: true,
      ),
    );
    final session = await EpubEditSession.open(file);
    final editor = BookEditorController(session: session);
    addTearDown(() async {
      editor.dispose();
      await temporary.delete(recursive: true);
    });
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1360, 900));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        darkTheme: buildAppTheme(brightness: Brightness.dark),
        themeMode: ThemeMode.dark,
        builder: (_, child) => RepaintBoundary(
          key: const ValueKey('find-scope-capture'),
          child: child,
        ),
        home: BookEditorPage(controller: editor, title: '查找范围验收'),
      ),
    );
    await _until(
      tester,
      () =>
          find.byType(PageTurnView).evaluate().isNotEmpty &&
          !editor.previewLoading,
    );
    await tester.tap(find.byTooltip('全书查找替换'));
    await _until(
      tester,
      () => find
          .byKey(const ValueKey('editor-search-query'))
          .evaluate()
          .isNotEmpty,
    );
    await tester.pump(const Duration(milliseconds: 400));
    final query = find.byKey(const ValueKey('editor-search-query'));
    await tester.enterText(query, '目标词');
    await _until(
      tester,
      () => find.text('4 处匹配 · 3 个文档').evaluate().isNotEmpty,
    );
    expect(find.byType(Dialog), findsNothing);
    await _capture(tester, '所有文本-结果高亮');

    await tester.tap(find.byKey(const ValueKey('search-result-2')));
    await _until(tester, () {
      final preview = tester
          .widget<PageTurnView>(find.byType(PageTurnView))
          .session;
      return preview.currentText.contains('第二章目标词');
    });
    expect(editor.activeDocument!.code.selectedText, '目标词');
    expect(
      tester
          .widget<PageTurnView>(find.byType(PageTurnView))
          .session
          .page!
          .pageIndex,
      greaterThan(0),
    );
    await _capture(tester, '跨章结果-源码预览对照');

    await tester.tap(find.text('所有文本文件'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('当前文件').hitTestable(), findsOneWidget);
    await _capture(tester, '范围菜单');
    await tester.tap(find.text('当前文件').hitTestable());
    await tester.pump(const Duration(milliseconds: 400));
    editor.showSource(session.spinePaths.first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(query);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.enterText(query, '目标词');
    await _until(
      tester,
      () => find.text('2 处匹配 · 1 个文档').evaluate().isNotEmpty,
    );
    await _capture(tester, '当前文件-结果高亮');

    await tester.tap(find.byKey(const ValueKey('search-result-0')));
    await tester.pump(const Duration(milliseconds: 600));
    await _capture(tester, '编辑器命中高亮');
    expect(editor.activePath, session.spinePaths.first);

    await tester.tap(find.byTooltip('查找范围'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('指定文档').last);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const ValueKey('search-file-OEBPS/c2.xhtml')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.ensureVisible(
      find.byKey(const ValueKey('search-file-OEBPS/c3.xhtml')),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byKey(const ValueKey('search-file-OEBPS/c3.xhtml')));
    await _until(
      tester,
      () => find.text('2 处匹配 · 2 个文档').evaluate().isNotEmpty,
    );
    expect(find.byType(Dialog), findsNothing);
    await tester.ensureVisible(query);
    await tester.pump(const Duration(milliseconds: 200));
    await _capture(tester, '指定文档-内联勾选');
    for (final size in [const Size(720, 600), const Size(390, 640)]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(BookEditorSource), findsOneWidget);
      expect(
        find.byKey(const ValueKey('editor-search-query')).hitTestable(),
        findsOneWidget,
      );
      await _capture(tester, '内联搜索-${size.width.toInt()}');
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
