import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/editing/epub_editing.dart';
import 'package:reader_core/paint/hit_test.dart';
import 'package:reader_mobile/editing/book_editor_controller.dart';
import 'package:reader_mobile/editing/book_editor_page.dart';
import 'package:reader_mobile/editing/book_style_preview.dart';
import 'package:reader_mobile/theme/app_theme.dart';
import 'package:reader_ui/paging/page_turn_view.dart';
import 'package:reader_ui/reader_page.dart';

import '../test/support/test_epub.dart';

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 25));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) fail('样式库实窗验收等待超时');
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(milliseconds: 250));
}

Widget _app(BookEditorController editor, {bool dark = false}) => MaterialApp(
  theme: buildAppTheme(),
  darkTheme: buildAppTheme(brightness: Brightness.dark),
  themeMode: dark ? ThemeMode.dark : ThemeMode.light,
  builder: (_, child) => RepaintBoundary(
    key: const ValueKey('style-library-capture'),
    child: child,
  ),
  home: BookEditorPage(controller: editor, title: '样式库 · EPUB 排版'),
);

Future<void> _capture(WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 300));
  expect(tester.takeException(), isNull);
  if (!const bool.fromEnvironment('CAPTURE_STYLE_LIBRARY')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('style-library-capture')),
  );
  final image = await boundary.toImage(pixelRatio: 1);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = await Directory(
      '${Directory.systemTemp.path}/style-library-evidence',
    ).create(recursive: true);
    final file = File('${directory.path}/$name.png');
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    debugPrint('样式库截图：${file.path}');
  } finally {
    image.dispose();
  }
}

Future<void> _choose(WidgetTester tester, String name, String id) async {
  await tester.enterText(
    find.byKey(const ValueKey('style-library-search')),
    name,
  );
  await tester.pump();
  await tester.tap(find.byKey(ValueKey('style-preset-$id')));
  await _until(
    tester,
    () => find
        .descendant(
          of: find.byType(BookStylePreview),
          matching: find.byType(CustomPaint),
        )
        .evaluate()
        .isNotEmpty,
  );
  expect(find.text('示例暂不可用，可查看下方 CSS'), findsNothing);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('桌面样式库从工具栏和检查器应用，保留预览与导出，日夜窄窗可操作', (tester) async {
    final root = await Directory.systemTemp.createTemp('style-library-native-');
    final file = await File('${root.path}/book.epub').writeAsBytes(
      buildMultiChapterEpub(
        chapters: [
          '<p id="target" class="body">样式应用后，正文可以快速成为居中的图注。</p><p>相邻正文保留原来的排版方式。</p>',
          '<p class="body">第二章同名正文。</p>',
        ],
        rawBody: true,
      ),
    );
    final session = await EpubEditSession.open(file);
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
    await tester.tap(find.byKey(const ValueKey('editor-style-library')));
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('style-library-apply')),
          )
          .onPressed,
      isNull,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _until(
      tester,
      () =>
          find.byKey(const ValueKey('style-library-search')).evaluate().isEmpty,
    );

    const path = 'OEBPS/c1.xhtml';
    final original = session.readText(path);
    editor.openDocument(path, offset: original.indexOf('样式应用后'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('editor-style-library')));
    await tester.pump(const Duration(milliseconds: 350));
    await _choose(tester, '图注', 'caption');
    await _capture(tester, '1360-样式库-图注');
    await tester.tap(find.byKey(const ValueKey('style-library-apply')));
    await _until(
      tester,
      () =>
          !editor.previewLoading &&
          session.readText(path) != original &&
          find.byKey(const ValueKey('style-library-search')).evaluate().isEmpty,
    );
    final preview = tester
        .widget<PageTurnView>(find.byType(PageTurnView))
        .session;
    await _until(tester, () => preview.page != null && !preview.loading);
    final line = TextHitTester.lineBoxes(preview.page!)
        .firstWhere((line) => line.text.contains('样式应用后'));
    expect(line.slice.block.style!.textAlign, CssTextAlign.center);
    await _capture(tester, '1360-应用图注-正文预览');
    final export = File('${root.path}/styled.epub');
    await EpubWriter.write(session, export);
    final reopened = await EpubEditSession.open(export);
    expect(reopened.readText(path), session.readText(path));
    reopened.close();

    tester.widget<ReaderPage>(find.byType(ReaderPage)).onEditTarget!(
      ReaderEditTarget(
        spineIndex: 0,
        cfi: session.cfiForSourceOffset(
          path,
          session.readText(path).indexOf('样式应用后'),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('样式检查器'));
    await _until(tester, () => find.text('从样式库应用').evaluate().isNotEmpty);
    await tester.tap(find.text('从样式库应用'));
    await tester.pump(const Duration(milliseconds: 350));
    await _choose(tester, '侧线', 'quote-rule');
    await _capture(tester, '1360-样式库-引文');
    await tester.tap(find.text('取消').last);
    await tester.pump(const Duration(milliseconds: 350));
    for (final (width, dark) in [(960.0, false), (640.0, true)]) {
      await tester.binding.setSurfaceSize(Size(width, 760));
      await tester.pumpWidget(_app(editor, dark: dark));
      await tester.pump();
      editor.openDocument(
        path,
        offset: session.readText(path).indexOf('样式应用后'),
      );
      await tester.tap(find.byKey(const ValueKey('editor-style-library')));
      await tester.pump(const Duration(milliseconds: 350));
      await _choose(tester, '边框', 'note-box');
      await _capture(tester, '${width.toInt()}-样式库-${dark ? '夜间' : '日间'}');
      final apply = tester.getRect(
        find.byKey(const ValueKey('style-library-apply')),
      );
      expect(apply.right, lessThanOrEqualTo(width));
      expect(apply.bottom, lessThanOrEqualTo(760));
      await tester.tap(find.text('取消').last);
      await tester.pump(const Duration(milliseconds: 350));
    }
    editor.undo();
    expect(session.readText(path), original);
    session.validate();
    await _until(tester, () => !editor.previewLoading);
    await tester.pumpWidget(const SizedBox());
  });
}
