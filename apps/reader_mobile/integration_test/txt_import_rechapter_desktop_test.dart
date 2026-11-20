import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reader_core/editing.dart';
import 'package:reader_core/epub/epub_document.dart';
import 'package:reader_mobile/editing/book_edit_repository.dart';
import 'package:reader_mobile/home/book_detail_sheet.dart';
import 'package:reader_mobile/home/bookshelf_page.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/reader/epub_reader_page.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/storage/drift_progress_store.dart';
import 'package:reader_mobile/theme/app_theme.dart';
import 'package:reader_mobile/txt/txt_chapter_rule_page.dart';
import 'package:reader_ui/paging/page_turn_view.dart';

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 45));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      final visibleText = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data ?? text.textSpan?.toPlainText())
          .join('\n');
      fail('TXT 桌面验收等待超时，当前页面：\n$visibleText');
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('CAPTURE_TXT_RECHAPTER')) return;
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump(const Duration(milliseconds: 350));
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('txt-desktop-capture')),
  );
  final image = await boundary.toImage(pixelRatio: 1);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = await Directory(
      '${Directory.systemTemp.path}/txt-rechapter-evidence',
    ).create(recursive: true);
    final path = '${directory.path}/$name.png';
    await File(path).writeAsBytes(bytes!.buffer.asUint8List());
    debugPrint('TXT 验收截图：$path');
  } finally {
    image.dispose();
  }
}

Future<BookEntry> _editCurrentBook(LibraryStore library, BookEntry book) async {
  final session = await EpubEditSession.open(File(book.filePath));
  final output = File('${session.baseFile.parent.path}/edited-for-test.epub');
  try {
    final path = session.spinePaths.first;
    session.transaction(
      '修改验收正文',
      (tx) => tx.writeText(
        path,
        tx.readText(path).replaceFirst('原始记述', '<strong>编辑后记述</strong>'),
      ),
    );
    await EpubWriter.write(session, output);
    return await library.commitEditedFile(
      book.id,
      book.contentRevision!,
      output,
      session.summary,
    );
  } finally {
    session.close();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('桌面 TXT：书架导入、编辑当前正文、正则重分章与正式阅读', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final directory = await Directory.systemTemp.createTemp('desktop-txt-');
    final database = AppDatabase(NativeDatabase.memory());
    final library = LibraryStore(
      database: database,
      directoryProvider: () async => directory,
    );
    final input = File('${directory.path}/雨后航记.txt');
    await input.writeAsString(
      [
        '第一章 雨后',
        '',
        '   \t　',
        '原始记述：雨停以后，我们沿着河岸慢慢前行。',
        for (var index = 0; index < 18; index++)
          '沿岸第${index + 1}处灯光映在水上，远处船只驶向桥边。',
        '第二章 夜航',
        '夜色渐深，河面仍然明亮。',
        for (var index = 0; index < 18; index++)
          '夜航第${index + 1}段记录，风从窗外吹进来，远处传来轻轻的汽笛声。',
      ].join('\n'),
    );
    addTearDown(() async {
      await database.close();
      await directory.delete(recursive: true);
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        builder: (_, child) => RepaintBoundary(
          key: const ValueKey('txt-desktop-capture'),
          child: child,
        ),
        home: BookshelfPage(
          library: library,
          progressStore: DriftProgressStore(database),
          pickEpubFiles: () async => [input.path],
        ),
      ),
    );
    await _until(
      tester,
      () => find.byTooltip('导入 EPUB / TXT').evaluate().isNotEmpty,
    );
    await tester.tap(find.byTooltip('导入 EPUB / TXT'));
    await _until(tester, () => find.text('雨后航记').evaluate().isNotEmpty);
    final imported = (await library.list()).single;
    expect(imported.spineCount, 2);
    final edited = await _editCurrentBook(library, imported);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.longPress(find.byKey(ValueKey('book-card-${edited.id}')));
    await _until(
      tester,
      () => find
          .byKey(const ValueKey('book-detail-chapters'))
          .evaluate()
          .isNotEmpty,
    );
    await tester.tap(find.byKey(const ValueKey('book-detail-chapters')));
    await _until(
      tester,
      () => find.byType(DropdownButtonFormField<String>).evaluate().isNotEmpty,
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.text('自定义正则').last);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.enterText(
      find.byKey(const ValueKey('txt-chapter-pattern')),
      r'^第一章.*$',
    );
    await tester.tap(find.byKey(const ValueKey('txt-preview')));
    await _until(
      tester,
      () => find.textContaining('目录预览 · 1 项').evaluate().isNotEmpty,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('txt-apply')))
          .onPressed,
      isNotNull,
    );
    await _capture(tester, '章节正则预览');
    await tester.tap(find.byKey(const ValueKey('txt-apply')));
    await _until(
      tester,
      () => find.byType(TxtChapterRulePage).evaluate().isEmpty,
    );
    final updated = (await library.list()).single;
    expect(updated.id, imported.id);
    expect(updated.spineCount, 1);
    final opened = await openEpubFile(File(updated.filePath));
    try {
      expect(
        opened.document!.chapterXhtml(0),
        contains('<strong>编辑后记述</strong>'),
      );
      expect(opened.document!.chapterXhtml(0), contains('第二章 夜航'));
    } finally {
      opened.document?.archive.close();
    }
    expect(find.byType(BookDetailSheet), findsNothing);
    // 正式阅读页直接读取已提交版本；封面路由动画不属于本项转换验收。
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        builder: (_, child) => RepaintBoundary(
          key: const ValueKey('txt-desktop-capture'),
          child: child,
        ),
        home: EpubReaderPage(
          sourcePath: updated.filePath,
          bookId: updated.id,
          book: updated,
          bookTitle: updated.title,
          contentRevision: updated.contentRevision,
          bookEditorRepository: BookEditRepository(library),
          store: DriftProgressStore(database),
        ),
      ),
    );
    await _until(tester, () => find.byType(PageTurnView).evaluate().isNotEmpty);
    final session = tester
        .widget<PageTurnView>(find.byType(PageTurnView))
        .session;
    await _until(tester, () => session.hasContent && !session.loading);
    expect(session.toc, hasLength(1));
    await _capture(tester, '重分章后正式阅读');
    await session.flushProgress();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
  });
}
