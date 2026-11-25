import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reader_core/editing/epub_editing.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_mobile/editing/book_edit_repository.dart';
import 'package:reader_mobile/editing/book_editor_controller.dart';
import 'package:reader_mobile/editing/book_editor_page.dart';
import 'package:reader_mobile/editing/book_editor_toolkit.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/theme/app_theme.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/paging/page_turn_view.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:spectacular_epub_tools/local_epub_tools.dart';

import '../test/support/local_toolkit_fixture.dart';
import '../test/support/test_epub.dart';

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 45));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) fail('桌面工具验收超时');
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _capture(WidgetTester tester, String fileName) async {
  if (!const bool.fromEnvironment('CAPTURE_EDITOR_PREVIEW')) return;
  await tester.pump(const Duration(milliseconds: 350));
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('local-toolkit-capture')),
  );
  final image = await boundary.toImage(pixelRatio: 2);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory(
      '${Directory.systemTemp.path}/spectacular-editor-evidence',
    );
    await directory.create(recursive: true);
    await File('${directory.path}/$fileName.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('macOS 本地工具：菜单简繁 → 分页 → 字体原生组件 → 保存导出重开', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final directory = await Directory.systemTemp.createTemp(
      'desktop-local-toolkit-',
    );
    final database = AppDatabase(NativeDatabase.memory());
    final library = LibraryStore(
      database: database,
      directoryProvider: () async => directory,
    );
    final book = await library.importBytes(
      buildMultiChapterEpub(
        chapters: ['皇后头发与数据库', '第二章：AB A'],
        title: '本地工具验收',
      ),
    );
    final repository = BookEditRepository(library);
    final session = await EpubEditSession.open(File(book.filePath));
    BookEntry? savedBook;
    final exported = File('${directory.path}/exported.epub');
    final editor = BookEditorController(
      session: session,
      commit: (session) async {
        final output = File('${directory.path}/saved.epub');
        await EpubWriter.write(session, output);
        savedBook = await repository.commitEditedFile(
          book.id,
          book.contentRevision!,
          output,
          session.summary,
        );
      },
      export: (session) => EpubWriter.write(session, exported),
    );
    addTearDown(() async {
      editor.dispose();
      await database.close();
      await directory.delete(recursive: true);
    });
    var returned = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                returned =
                    await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => RepaintBoundary(
                          key: const ValueKey('local-toolkit-capture'),
                          child: BookEditorPage(
                            controller: editor,
                            title: book.title,
                          ),
                        ),
                      ),
                    ) ??
                    false;
              },
              child: const Text('打开编辑器'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开编辑器'));
    await _until(tester, () => find.byType(PageTurnView).evaluate().isNotEmpty);
    await _until(tester, () => !editor.previewLoading);
    await tester.tap(find.byKey(const ValueKey('editor-category-转换')));
    await _until(tester, () => find.text('简体转繁体').evaluate().isNotEmpty);
    expect(find.textContaining('TXT'), findsNothing);
    await _capture(tester, 'EPUB本地工具');
    await tester.tap(find.text('简体转繁体'));
    await _until(
      tester,
      () => find.widgetWithText(FilledButton, '确定').evaluate().isNotEmpty,
    );
    await tester.tap(find.text('确定'));
    await _until(tester, () => find.text('简体转繁体已应用').evaluate().isNotEmpty);
    expect(session.readText(session.spinePaths.first), contains('皇后頭髮與數據庫'));
    await tester.tap(find.text('关闭'));
    await _until(
      tester,
      () =>
          !editor.previewLoading &&
          find.byType(PageTurnView).evaluate().isNotEmpty,
    );
    final preview = tester
        .widget<PageTurnView>(find.byType(PageTurnView))
        .session;
    await _until(tester, () => preview.page != null && !preview.loading);
    expect(
      tester.widget<ReaderPage>(find.byType(ReaderPage)).pageTurnMode,
      PageTurnMode.slideHorizontal,
    );
    expect(tester.getSize(find.byType(ReaderPage)), const Size(360, 800));
    await _capture(tester, '手机左右分页预览');
    await tester.tap(find.byTooltip('下一页'));
    await _until(tester, () => preview.page?.spineIndex == 1);
    await tester.tap(find.byTooltip('上一页'));
    await _until(tester, () => preview.page?.spineIndex == 0);

    final package = PackageEditor(session);
    package.addResource(
      'OEBPS/probe.bmp',
      buildLocalToolkitBitmap(),
      'image/bmp',
    );
    session.transaction(
      '图片引用',
      (tx) => tx.writeText(
        'OEBPS/c1.xhtml',
        tx
            .readText('OEBPS/c1.xhtml')
            .replaceFirst(
              '</body>',
              '<img src="probe.bmp" alt="本地组件测试"/></body>',
            ),
      ),
    );
    final webp = await BookEditorToolkit(editor).run(LocalEpubTool.toWebp);
    expect(webp, isNotNull, reason: editor.error);
    expect(session.readText('OEBPS/c1.xhtml'), contains('probe.webp'));
    expect(session.readBytes('OEBPS/probe.webp'), isNotNull);
    if (const bool.fromEnvironment('REQUIRE_BUNDLED_CWEBP')) {
      final contents = File(Platform.resolvedExecutable).parent.parent.path;
      expect(webp!.result.message, contains('$contents/Resources/bin/cwebp'));
    }
    await webp!.dispose();

    final data = await rootBundle.load('assets/fonts/MoyuSerif-Regular.otf');
    final font = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    package.addResource('OEBPS/probe.otf', font, 'font/otf');
    package.addResource(
      'OEBPS/probe.css',
      utf8.encode(
        '@font-face { font-family: Probe; src: url("probe.otf"); } p { font-family: Probe; }',
      ),
      'text/css',
    );
    session.transaction(
      '字体引用',
      (tx) => tx.writeText(
        'OEBPS/c2.xhtml',
        tx
            .readText('OEBPS/c2.xhtml')
            .replaceFirst(
              '</head>',
              '<link rel="stylesheet" href="probe.css"/></head>',
            ),
      ),
    );
    final subset = await BookEditorToolkit(editor)
        .run(LocalEpubTool.subsetFont);
    expect(subset, isNotNull, reason: editor.error);
    expect(session.readBytes('OEBPS/probe.otf')!.length, lessThan(font.length));
    await subset!.dispose();
    expect(await editor.exportBook(), isTrue);
    final reopened = await openEpubFile(exported, verifyCrc: true);
    expect(reopened.ok, isTrue);
    expect(reopened.document!.chapterXhtml(0), contains('皇后頭髮'));
    reopened.document!.archive.close();
    final saveButton = find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == '保存书籍',
    );
    await _until(
      tester,
      () => tester.widget<IconButton>(saveButton).onPressed != null,
    );
    await tester.tap(saveButton);
    await _until(tester, () => returned || editor.error != null);
    expect(editor.error, isNull);
    expect(returned, isTrue);
    expect(savedBook!.id, book.id);
    expect(savedBook!.contentRevision, isNot(book.contentRevision));
    final saved = await openEpubFile(
      File(savedBook!.filePath),
      verifyCrc: true,
    );
    expect(saved.ok, isTrue);
    expect(saved.document!.chapterXhtml(0), contains('皇后頭髮'));
    saved.document!.archive.close();
  });
}
