import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reader_core/epub/epub_chapter_source.dart';
import 'package:reader_mobile/home/bookshelf_page.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/search/scan_search_service.dart';
import 'package:reader_mobile/theme/app_theme.dart';
import 'package:reader_ui/menu/reader_menu_overlay.dart';
import 'package:reader_ui/panels/search_panel.dart';
import 'package:reader_ui/reader_page.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/reader_view.dart';

import '../test/support/test_epub.dart';

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) fail('桌面阅读验收等待超时');
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump();
}

Future<ReaderSession> _openReader(
  WidgetTester tester,
  EpubChapterSource source,
  String contentRevision,
) async {
  ReaderSession? session;
  final search = ScanSearchService(source: source);
  addTearDown(search.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      builder: (_, child) => RepaintBoundary(
        key: const ValueKey('desktop-reader-capture'),
        child: child!,
      ),
      home: Scaffold(
        body: ReaderPage(
          source: source,
          store: MemoryReaderProgressStore(),
          bookId: 'desktop-wheel-acceptance',
          contentRevision: contentRevision,
          bookTitle: '桌面滚轮验收',
          onSearch: (query) async => [
            for (final result in await search.search(query))
              SearchPanelResult(
                spineIndex: result.spineIndex,
                charOffset: result.charOffset,
                chapterTitle: result.chapterTitle,
                context: result.context,
                matchLength: result.matchLength,
              ),
          ],
          onSessionReady: (value) => session = value,
        ),
      ),
    ),
  );
  await _until(tester, () => session?.page != null && !session!.loading);
  return session!;
}

Future<void> _wheel(WidgetTester tester, double delta) async {
  await tester.sendEventToBinding(
    PointerScrollEvent(
      kind: PointerDeviceKind.mouse,
      position: tester.getCenter(find.byType(ReaderView)),
      scrollDelta: Offset(0, delta),
    ),
  );
}

Future<void> _capture(WidgetTester tester, String name) async {
  const capture = bool.fromEnvironment('CAPTURE_DESKTOP_INPUT');
  if (!capture) return;
  final output = '${Directory.systemTemp.path}/spectacular-desktop-input';
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('desktop-reader-capture')),
  );
  await tester.pump(const Duration(milliseconds: 350));
  final image = await boundary.toImage(pixelRatio: 1);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(output).create(recursive: true);
    await File('$output/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    debugPrint('桌面验收截图：$output/$name.png');
  } finally {
    image.dispose();
  }
}

Future<void> _checkMenu(WidgetTester tester, ReaderSession session) async {
  final page = session.page;
  await tester.tapAt(tester.getCenter(find.byType(ReaderView)));
  await tester.pumpAndSettle();
  expect(
    tester.widget<ReaderMenuOverlay>(find.byType(ReaderMenuOverlay)).open,
    isTrue,
  );
  await _wheel(tester, 120);
  await tester.pump(const Duration(milliseconds: 500));
  expect(session.page, same(page));
}

Future<void> _shortcut(WidgetTester tester, LogicalKeyboardKey key) async {
  final modifier = Platform.isMacOS
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(modifier);
  await tester.pumpAndSettle();
}

Future<void> _checkKeyboard(WidgetTester tester, ReaderSession session) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
  await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
  await _until(tester, () => session.page?.pageIndex == 1);
  await tester.pumpAndSettle();
  await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
  await _until(tester, () => session.page?.pageIndex == 0);
  await tester.pumpAndSettle();
  await _shortcut(tester, LogicalKeyboardKey.keyF);
  final search = find.byKey(const ValueKey('search-input'));
  final editable = tester.widget<EditableText>(
    find.descendant(of: search, matching: find.byType(EditableText)),
  );
  expect(editable.focusNode.hasFocus, isTrue);
  await tester.enterText(search, '桌面');
  await _until(tester, () => find.byType(ListTile).evaluate().isNotEmpty);
  final page = session.page;
  await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
  await tester.pumpAndSettle();
  expect(session.page, same(page));
  await _capture(tester, 'reader-search');
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
  await tester.tapAt(
    tester.getRect(find.byType(ReaderView)).centerRight - const Offset(20, 0),
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryButton,
  );
  await tester.pumpAndSettle();
  expect(
    tester.widget<ReaderMenuOverlay>(find.byType(ReaderMenuOverlay)).open,
    isTrue,
  );
  expect(session.page, same(page));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('桌面正式 EPUB 引擎：滚轮与键盘翻页、搜索焦点、右键与位置保存', (tester) async {
    final bytes = buildTestEpub(
      title: '桌面滚轮验收',
      paragraphs: List.generate(
        100,
        (index) => '第 $index 段。${'这是正式 EPUB 引擎的桌面滚轮翻页验收正文。' * 12}',
      ),
    );
    final revision = sha256.convert(bytes).toString();
    final source = await EpubChapterSource.open(
      bytes,
      contentVersion: revision,
    );
    addTearDown(source.close);
    final session = await _openReader(tester, source, revision);
    final firstCfi = session.readingCfi;
    expect(firstCfi, isNotNull);
    await _capture(tester, 'reader-first');
    await _wheel(tester, 120);
    await _until(tester, () => session.page?.pageIndex == 1);
    expect(session.readingCfi, isNot(firstCfi));
    await _capture(tester, 'reader-next');
    await tester.pump(const Duration(milliseconds: 300));
    await _wheel(tester, -120);
    await _until(tester, () => session.page?.pageIndex == 0);
    expect(session.readingCfi, firstCfi);
    await session.flushProgress();
    expect((await session.store.load(session.bookId))?.cfi, firstCfi);
    await _capture(tester, 'reader-returned');
    await _checkMenu(tester, session);
    await _checkKeyboard(tester, session);
    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await tester.pumpAndSettle();
    await _capture(tester, 'reader-shortcuts');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await session.flushProgress();
    expect((await session.store.load(session.bookId))?.cfi, firstCfi);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('桌面书架实窗：右键菜单、搜索和导入快捷键', (tester) async {
    final library = LibraryStore.memory();
    final book = await library.importBytes(buildTestEpub(title: '桌面书架验收'));
    var imports = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        builder: (_, child) => RepaintBoundary(
          key: const ValueKey('desktop-reader-capture'),
          child: child!,
        ),
        home: BookshelfPage(
          library: library,
          progressStore: MemoryReaderProgressStore(),
          pickEpubFiles: () async {
            imports++;
            return [];
          },
        ),
      ),
    );
    await _until(tester, () => find.text(book.title).evaluate().isNotEmpty);
    await tester.tap(
      find.byKey(ValueKey('book-card-${book.id}')),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    expect(find.text('书籍详情'), findsOneWidget);
    await _capture(tester, 'bookshelf-context-menu');
    await tester.tap(find.text('选择多本书'));
    await tester.pumpAndSettle();
    expect(find.text('已选 1 本'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await _shortcut(tester, LogicalKeyboardKey.keyF);
    await tester.enterText(
      find.byKey(const ValueKey('bookshelf-search-field')),
      '桌面',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('book-card-title-${book.id}')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await _shortcut(tester, LogicalKeyboardKey.keyO);
    expect(imports, 1);
    expect((await library.list()).single.id, book.id);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
