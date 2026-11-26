import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:reader_core/editing/epub_editing.dart';
import 'package:reader_mobile/editing/book_editor_controller.dart';
import 'package:reader_mobile/editing/book_editor_page.dart';
import 'package:reader_mobile/editing/epub_file_editor_page.dart';
import 'package:reader_mobile/home/home_shell.dart';
import 'package:reader_mobile/home/desktop_book_interaction.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/theme/app_theme.dart';
import 'package:reader_ui/reader_session.dart';

import '../test/support/test_epub.dart';

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) fail('桌面首页验收等待超时');
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('CAPTURE_DESKTOP_HOME')) return;
  final focus = FocusManager.instance.primaryFocus;
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump(const Duration(milliseconds: 350));
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('desktop-home-capture')),
  );
  final image = await boundary.toImage(pixelRatio: 1);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory(
      '${Directory.systemTemp.path}/desktop-home-evidence',
    );
    await directory.create(recursive: true);
    await File('${directory.path}/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    debugPrint('桌面验收截图：${directory.path}/$name.png');
  } finally {
    image.dispose();
    if (focus?.context != null && focus!.canRequestFocus) {
      focus.requestFocus();
      await tester.pump();
    }
  }
}

Future<void> _seed(AppDatabase database, LibraryStore library) async {
  final today = DateTime.now();
  final titles = ['山川与日常', '漫长的旅途', '阅读的回声', '城市札记'];
  for (var index = 0; index < titles.length; index++) {
    final book = await library.importBytes(buildTestEpub(title: titles[index]));
    final row = await (database.select(
      database.books,
    )..where((row) => row.uuid.equals(book.id))).getSingle();
    await database
        .into(database.readingProgress)
        .insert(
          ReadingProgressCompanion.insert(
            bookId: Value(row.id),
            locatorCfi: 'epubcfi(/6/2!/4/2:0)',
            finished: const Value(true),
            updatedAt: today.millisecondsSinceEpoch,
          ),
        );
    for (var day = 0; day < 7; day++) {
      final started = DateTime(
        today.year,
        today.month,
        today.day - day,
        9 + index,
      );
      await library.readingSessionStore()!.add(
        bookId: book.id,
        startedAt: started,
        endedAt: started.add(Duration(minutes: 10 + index * 8 + day * 2)),
      );
    }
    if (index < 3) {
      await library.reviewStore()!.save(
        book.id,
        rating: 5 - index,
        content: '读完《${book.title}》，记住了那些平常生活里的细节。文字让人放慢脚步，也让再读一次有了新的理由。',
      );
    }
  }
}

Future<void> _select(WidgetTester tester, String label) async {
  await tester.tap(
    find
        .descendant(
          of: find.byType(NavigationRail),
          matching: find.byTooltip(label),
        )
        .hitTestable()
        .first,
  );
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _shortcut(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool shift = false,
}) async {
  final modifier = Platform.isMacOS && key != LogicalKeyboardKey.tab
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(modifier);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(modifier);
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _checkEditorShortcuts(
  WidgetTester tester,
  BookEditorController editor,
  File output,
) async {
  editor.showSource('OEBPS/content.opf');
  editor.showSource('OEBPS/c1.xhtml');
  await tester.pump();
  await tester.tapAt(
    tester.getTopLeft(find.byType(CodeEditor)) + const Offset(100, 30),
  );
  await tester.pump(const Duration(milliseconds: 50));
  await _shortcut(tester, LogicalKeyboardKey.tab);
  expect(editor.activePath, 'OEBPS/content.opf');
  await _shortcut(tester, LogicalKeyboardKey.tab, shift: true);
  expect(editor.activePath, 'OEBPS/c1.xhtml');
  await _shortcut(tester, LogicalKeyboardKey.keyW);
  expect(editor.activePath, 'OEBPS/content.opf');
  editor.showSource('OEBPS/c1.xhtml');
  await tester.pump();
  await tester.tapAt(
    tester.getTopLeft(find.byType(CodeEditor)) + const Offset(100, 30),
  );
  await tester.pump(const Duration(milliseconds: 50));
  await _shortcut(tester, LogicalKeyboardKey.keyS, shift: true);
  await _until(tester, () => output.existsSync() && !editor.busy);
  expect(editor.dirty, isTrue);
  expect(find.byType(BookEditorPage), findsOneWidget);
  await _shortcut(tester, LogicalKeyboardKey.keyS);
  await _until(tester, () => !editor.busy && !editor.dirty);
  expect(find.byType(BookEditorPage), findsOneWidget);
  await tester.tap(find.byTooltip('退出编辑'));
}

Future<void> _checkShelfSelection(WidgetTester tester) async {
  final books = find.byType(DesktopBookInteraction);
  final modifier = Platform.isMacOS
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(modifier);
  await tester.tap(books.first, kind: PointerDeviceKind.mouse);
  await tester.sendKeyUpEvent(modifier);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.tap(books.at(2), kind: PointerDeviceKind.mouse);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pump(const Duration(milliseconds: 100));
  expect(find.text('已选 3 本'), findsOneWidget);
  await _capture(tester, 'bookshelf-range-selection');
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pump(const Duration(milliseconds: 100));
  final focus = tester
      .widget<FocusableActionDetector>(
        find
            .descendant(
              of: books.first,
              matching: find.byType(FocusableActionDetector),
            )
            .first,
      )
      .focusNode!;
  focus.requestFocus();
  await tester.pump();
  await tester.sendKeyEvent(LogicalKeyboardKey.space);
  await tester.pump();
  expect(find.text('已选 1 本'), findsOneWidget);
  expect(focus.hasFocus, isTrue);
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pump();
  await tester.sendKeyEvent(LogicalKeyboardKey.f1);
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.text('桌面快捷键'), findsOneWidget);
  await _capture(tester, 'desktop-shortcuts');
  await tester.tap(find.text('关闭'));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _checkLibrarySave(WidgetTester tester) async {
  final editor = tester
      .widget<BookEditorPage>(find.byType(BookEditorPage))
      .controller;
  await _until(tester, () => !editor.previewLoading);
  final doc = editor.activeDocument!;
  final original = doc.code.text;
  for (final text in ['第一次连续保存', '第二次连续保存']) {
    doc.code.text = original.replaceFirst('</body>', '<p>$text</p></body>');
    await tester.pump();
    await tester.tapAt(
      tester.getTopLeft(find.byType(CodeEditor)) + const Offset(100, 30),
    );
    await _shortcut(tester, LogicalKeyboardKey.keyS);
    await _until(tester, () => !editor.busy && !editor.dirty);
    expect(editor.error, isNull);
    expect(find.byType(BookEditorPage), findsOneWidget);
    expect(editor.activeDocument, same(doc));
  }
  await _capture(tester, 'editor-save-and-continue');
  await tester.tap(find.text('文件'));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.text('保存并退出编辑'));
  await _until(tester, () => find.byType(BookEditorPage).evaluate().isEmpty);
}

Future<void> _checkLocalFile(
  WidgetTester tester,
  Directory root,
  LibraryStore library,
) async {
  final input = await File('${root.path}/外部书.epub')
      .writeAsBytes(buildTestEpub(paragraphs: ['原文件正文']));
  final output = File('${root.path}/修订.epub');
  final before = (await library.list()).map((book) => book.id).toSet();
  await tester.pumpWidget(
    _app(
      EpubFileEditorPage(
        pickFile: () async => input.path,
        saveFile: (source, {required fileName}) async {
          await source.copy(output.path);
          return true;
        },
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('editor-open-file')));
  await _until(tester, () => find.byType(BookEditorPage).evaluate().isNotEmpty);
  final editor = tester
      .widget<BookEditorPage>(find.byType(BookEditorPage))
      .controller;
  await _until(tester, () => !editor.previewLoading);
  final document = editor.openDocument('OEBPS/c1.xhtml');
  document.code.text = document.code.text.replaceFirst('原文件正文', '无需导入的修订正文');
  await _until(tester, () => !editor.hasPendingText && !editor.previewLoading);
  await _capture(tester, 'local-epub-editor');
  await _checkEditorShortcuts(tester, editor, output);
  await _until(
    tester,
    () => find.byKey(const ValueKey('editor-open-file')).evaluate().isNotEmpty,
  );
  final reopened = await EpubEditSession.open(output);
  expect(reopened.readText('OEBPS/c1.xhtml'), contains('无需导入的修订正文'));
  reopened.close();
  final original = await EpubEditSession.open(input);
  expect(original.readText('OEBPS/c1.xhtml'), contains('原文件正文'));
  original.close();
  expect((await library.list()).map((book) => book.id).toSet(), before);
}

Widget _app(Widget home, {bool dark = false}) => MaterialApp(
  theme: buildAppTheme(),
  darkTheme: buildAppTheme(brightness: Brightness.dark),
  themeMode: dark ? ThemeMode.dark : ThemeMode.light,
  builder: (_, child) => RepaintBoundary(
    key: const ValueKey('desktop-home-capture'),
    child: child,
  ),
  home: home,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('桌面首页实窗：右键编辑、键盘切页与文件编辑、统计与书评日夜布局', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1360, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final root = await Directory.systemTemp.createTemp('desktop-home-test-');
    final database = AppDatabase(NativeDatabase.memory());
    final library = LibraryStore(
      database: database,
      directoryProvider: () async => root,
    );
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });
    await _seed(database, library);
    final home = HomeShell(
      library: library,
      progressStore: MemoryReaderProgressStore(),
    );
    await tester.pumpWidget(_app(home));
    final book = (await library.list()).firstWhere(
      (book) => book.title == '山川与日常',
    );
    await _until(
      tester,
      () => find.byKey(ValueKey('book-card-${book.id}')).evaluate().isNotEmpty,
    );
    await _shortcut(tester, LogicalKeyboardKey.digit4);
    expect(find.byKey(const ValueKey('editor-open-file')), findsOneWidget);
    await _shortcut(tester, LogicalKeyboardKey.digit1);
    await _checkShelfSelection(tester);
    await tester.tap(
      find.byKey(ValueKey('book-card-${book.id}')),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await tester.pump(const Duration(milliseconds: 400));
    await _capture(tester, 'bookshelf-edit-menu');
    await tester.tap(find.text('编辑 EPUB'));
    await _until(
      tester,
      () => find.byType(BookEditorPage).evaluate().isNotEmpty,
    );
    await _checkLibrarySave(tester);
    await tester.pump(const Duration(milliseconds: 400));
    await _select(tester, '统计');
    await _until(
      tester,
      () => find
          .byKey(const ValueKey('stats-desktop-sections'))
          .evaluate()
          .isNotEmpty,
    );
    expect(
      find.byKey(const ValueKey('stats-desktop-sections')),
      findsOneWidget,
    );
    await _capture(tester, 'stats-light');
    await _select(tester, '笔记');
    await tester.tap(find.byKey(const ValueKey('reviews-tab')));
    await _until(
      tester,
      () => find
          .byKey(const ValueKey('reviews-desktop-grid'))
          .evaluate()
          .isNotEmpty,
    );
    expect(find.byKey(const ValueKey('reviews-desktop-grid')), findsOneWidget);
    await _capture(tester, 'reviews-light');
    await tester.tap(find.byKey(ValueKey('review-card-${book.id}')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('review-detail')), findsOneWidget);
    await _capture(tester, 'review-detail');
    await tester.tap(find.byTooltip('关闭'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpWidget(_app(home, dark: true));
    await tester.pump(const Duration(milliseconds: 400));
    await _capture(tester, 'reviews-dark');
    await _select(tester, '统计');
    await _capture(tester, 'stats-dark');
    await tester.binding.setSurfaceSize(const Size(720, 760));
    await tester.pump(const Duration(milliseconds: 400));
    await _capture(tester, 'stats-narrow');
    await _select(tester, '编辑');
    await _capture(tester, 'editor-entry');
    await tester.binding.setSurfaceSize(const Size(1360, 900));
    await _checkLocalFile(tester, root, library);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
