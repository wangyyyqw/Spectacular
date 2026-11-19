import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reader_core/editing/epub_editing.dart';
import 'package:reader_mobile/editing/book_editor_page.dart';
import 'package:reader_mobile/editing/epub_file_editor_page.dart';
import 'package:reader_mobile/home/home_shell.dart';
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
    find.descendant(
      of: find.byType(NavigationRail),
      matching: find.text(label),
    ),
  );
  await tester.pump(const Duration(milliseconds: 400));
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
  await tester.tap(find.byTooltip('保存书籍'));
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
  testWidgets('桌面首页实窗：右键编辑、本地文件保存、统计与书评日夜布局', (tester) async {
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
    await tester.tap(find.byTooltip('退出编辑'));
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
    await _select(tester, '书评');
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
    expect(find.byType(Dialog), findsOneWidget);
    await _capture(tester, 'review-detail');
    await tester.tap(find.byTooltip('关闭书评详情'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpWidget(_app(home, dark: true));
    await tester.pump(const Duration(milliseconds: 400));
    await _capture(tester, 'reviews-dark');
    await _select(tester, '统计');
    await _capture(tester, 'stats-dark');
    await tester.binding.setSurfaceSize(const Size(720, 760));
    await tester.pump(const Duration(milliseconds: 400));
    await _capture(tester, 'stats-narrow');
    await _select(tester, '编辑器');
    await _capture(tester, 'editor-entry');
    await tester.binding.setSurfaceSize(const Size(1360, 900));
    await _checkLocalFile(tester, root, library);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
