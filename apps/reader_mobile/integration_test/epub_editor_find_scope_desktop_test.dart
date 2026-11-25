import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reader_core/editing/epub_editing.dart';
import 'package:reader_mobile/editing/book_editor_controller.dart';
import 'package:reader_mobile/editing/book_editor_page.dart';
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
        chapters: ['<p>目标词一，目标词二。</p>', '<p>第二章目标词。</p>', '<p>第三章目标词。</p>'],
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
    await _until(tester, () => find.text('全书源码查找替换').evaluate().isNotEmpty);
    await tester.pump(const Duration(milliseconds: 400));
    final query = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == '查找内容',
    );
    await tester.enterText(query, '目标词');
    final findButton = find.widgetWithText(TextButton, '查找');
    await tester.ensureVisible(findButton);
    await tester.tap(findButton);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('4 处匹配'), findsOneWidget);
    await _capture(tester, '所有文本-结果高亮');

    await tester.tap(find.text('所有文本文件'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('当前文件').hitTestable(), findsOneWidget);
    await _capture(tester, '范围菜单');
    await tester.tap(find.text('当前文件').hitTestable());
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('2 处匹配'), findsOneWidget);
    await _capture(tester, '当前文件-结果高亮');

    await tester.tap(find.byKey(const ValueKey('search-result-0')));
    await tester.pump(const Duration(milliseconds: 600));
    await _capture(tester, '编辑器命中高亮');
    expect(editor.activePath, session.spinePaths.first);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
