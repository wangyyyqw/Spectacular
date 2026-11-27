import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/editing/book_editor_page.dart';
import 'package:reader_mobile/editing/book_editor_route.dart';
import 'package:reader_mobile/home/bookshelf_page.dart';
import 'package:reader_mobile/home/home_shell.dart';
import 'package:reader_mobile/home/desktop_book_interaction.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/theme/app_theme.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/test_epub.dart';
import '../support/reader_pump.dart';

final _platforms = TargetPlatformVariant({
  TargetPlatform.macOS,
  TargetPlatform.windows,
});

Future<void> _show(WidgetTester tester, Widget child) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 760);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: child));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _shortcut(WidgetTester tester, LogicalKeyboardKey key) async {
  final modifier = defaultTargetPlatform == TargetPlatform.macOS
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(modifier);
  await tester.pump();
}

void main() {
  testWidgets('桌面书架支持修饰键多选、范围选择、可见全选及键盘菜单', (tester) async {
    final library = LibraryStore.memory();
    await library.setSetting('bookshelf.sort', 'title');
    for (final title in ['范围甲', '范围乙', '其他丙', '其他丁']) {
      await library.importBytes(buildTestEpub(title: title));
    }
    await _show(
      tester,
      BookshelfPage(
        library: library,
        progressStore: MemoryReaderProgressStore(),
      ),
    );
    await tester.pumpAndSettle();
    final cards = find.byType(DesktopBookInteraction);
    final modifier = defaultTargetPlatform == TargetPlatform.macOS
        ? LogicalKeyboardKey.metaLeft
        : LogicalKeyboardKey.controlLeft;
    for (final kind in ['网格', '列表']) {
      if (kind == '列表') {
        await tester.tap(find.byTooltip('列表视图'));
        await tester.pumpAndSettle();
      }
      await tester.sendKeyDownEvent(modifier);
      await tester.tap(cards.at(0), kind: PointerDeviceKind.mouse);
      await tester.sendKeyUpEvent(modifier);
      await tester.pumpAndSettle();
      expect(find.text('已选 1 本'), findsOneWidget);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tap(cards.at(2), kind: PointerDeviceKind.mouse);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(find.text('已选 3 本'), findsOneWidget);
      await _shortcut(tester, LogicalKeyboardKey.keyA);
      expect(find.text('已选 4 本'), findsOneWidget);
      if (defaultTargetPlatform == TargetPlatform.macOS) {
        await _shortcut(tester, LogicalKeyboardKey.backspace);
      } else {
        await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      }
      await tester.pumpAndSettle();
      expect(find.text('删除选中的 4 本书？'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(await library.list(), hasLength(4));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      final target = find
          .descendant(
            of: cards.first,
            matching: find.byType(FocusableActionDetector),
          )
          .first;
      tester.widget<FocusableActionDetector>(target).focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.text('已选 1 本'), findsOneWidget);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.f10);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(find.text('书籍详情'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        tester.widget<FocusableActionDetector>(target).focusNode!.hasFocus,
        isTrue,
      );
      await tester.sendKeyEvent(
        kind == '列表'
            ? LogicalKeyboardKey.arrowDown
            : LogicalKeyboardKey.arrowRight,
      );
      await tester.pumpAndSettle();
      final nextTarget = find
          .descendant(
            of: cards.at(1),
            matching: find.byType(FocusableActionDetector),
          )
          .first;
      expect(
        tester.widget<FocusableActionDetector>(nextTarget).focusNode!.hasFocus,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
    }
    await _shortcut(tester, LogicalKeyboardKey.keyF);
    final search = find.byKey(const ValueKey('bookshelf-search-field'));
    await tester.enterText(search, '范围');
    await _shortcut(tester, LogicalKeyboardKey.keyA);
    await tester.pumpAndSettle();
    expect(find.byTooltip('退出多选'), findsNothing);
    expect(
      tester.widget<TextField>(search).controller!.selection,
      const TextSelection(baseOffset: 0, extentOffset: 2),
    );
    await tester.tap(find.byTooltip('多选'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bookshelf-select-all')));
    await tester.pumpAndSettle();
    expect(find.text('已选 2 本'), findsOneWidget);
    expect(cards, findsNWidgets(2));
    expect(tester.takeException(), isNull);
  }, variant: _platforms);

  testWidgets('F1 打开平台快捷键，弹窗不透传切页，窄窗说明可滚动', (tester) async {
    await _show(
      tester,
      HomeShell(
        library: LibraryStore.memory(),
        progressStore: MemoryReaderProgressStore(),
      ),
    );
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(390, 760);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await tester.pumpAndSettle();
    expect(find.text('桌面快捷键'), findsOneWidget);
    await _shortcut(tester, LogicalKeyboardKey.digit4);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('bookshelf-search-field')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('editor-open-file')), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: _platforms);

  testWidgets('书架搜索快捷键可重复聚焦，输入框全选与 Esc 关闭正常', (tester) async {
    await _show(
      tester,
      BookshelfPage(
        library: LibraryStore.memory(),
        progressStore: MemoryReaderProgressStore(),
      ),
    );
    await _shortcut(tester, LogicalKeyboardKey.keyF);
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('bookshelf-search-field'));
    expect(search, findsOneWidget);
    await tester.enterText(search, '山川');
    await _shortcut(tester, LogicalKeyboardKey.keyA);
    final field = tester.widget<TextField>(search);
    expect(
      field.controller!.selection,
      const TextSelection(baseOffset: 0, extentOffset: 2),
    );
    await _shortcut(tester, LogicalKeyboardKey.keyF);
    await tester.pumpAndSettle();
    expect(field.focusNode!.hasFocus, isTrue);
    expect(field.controller!.text, '山川');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(search, findsOneWidget);
    expect(tester.widget<TextField>(search).focusNode!.hasFocus, isFalse);
    expect(tester.widget<TextField>(search).controller!.text, isEmpty);
    await _shortcut(tester, LogicalKeyboardKey.keyF);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(search).controller!.text, isEmpty);
  }, variant: _platforms);

  testWidgets('导入快捷键在文件选择期间不重复打开，临时模式禁用导入', (tester) async {
    final picked = Completer<List<String>>();
    var count = 0;
    Future<List<String>> pick() {
      count++;
      return picked.future;
    }

    final library = LibraryStore.memory();
    final progress = MemoryReaderProgressStore();
    await _show(
      tester,
      BookshelfPage(
        library: library,
        progressStore: progress,
        pickEpubFiles: pick,
      ),
    );
    await _shortcut(tester, LogicalKeyboardKey.keyO);
    await _shortcut(tester, LogicalKeyboardKey.keyO);
    expect(count, 1);
    picked.complete([]);
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: BookshelfPage(
          library: library,
          progressStore: progress,
          pickEpubFiles: pick,
          allowImport: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _shortcut(tester, LogicalKeyboardKey.keyO);
    expect(count, 1);
  }, variant: _platforms);

  testWidgets('网格和列表右键显示书籍菜单，取消删除不改数据', (tester) async {
    final library = LibraryStore.memory();
    final book = await library.importBytes(buildTestEpub(title: '桌面操作验收'));
    await _show(
      tester,
      BookshelfPage(
        library: library,
        progressStore: MemoryReaderProgressStore(),
      ),
    );
    for (final kind in ['card', 'row']) {
      if (kind == 'row') {
        await tester.tap(find.byTooltip('列表视图'));
        await tester.pumpAndSettle();
      }
      final item = find.byKey(ValueKey('book-$kind-${book.id}'));
      await tester.tap(
        item,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('开始阅读'), findsOneWidget);
      expect(
        tester
            .widget<PopupMenuItem<String>>(
              find.widgetWithText(PopupMenuItem<String>, '编辑 EPUB'),
            )
            .enabled,
        isFalse,
      );
      expect(find.text('书籍详情'), findsOneWidget);
      await tester.tap(find.text('选择多本书'));
      await tester.pumpAndSettle();
      expect(find.text('已选 1 本'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('已选 1 本'), findsNothing);
      await tester.tap(
        item,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除本书'));
      await tester.pumpAndSettle();
      expect(find.text('删除《桌面操作验收》'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect((await library.list()).single.id, book.id);
    }
  }, variant: _platforms);

  testWidgets('书架网格与列表右键可直接打开对应 EPUB 编辑器', (tester) async {
    late Directory root;
    late AppDatabase database;
    late LibraryStore library;
    late BookEntry book;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('shelf-editor-test-');
      database = AppDatabase(NativeDatabase.memory());
      library = LibraryStore(
        database: database,
        directoryProvider: () async => root,
      );
      book = await library.importBytes(buildTestEpub(title: '右键编辑样本'));
    });
    addTearDown(() async {
      await database.close();
      await root.delete(recursive: true);
    });
    await _show(
      tester,
      BookshelfPage(
        library: library,
        progressStore: MemoryReaderProgressStore(),
      ),
    );
    await pumpReaderUntil(tester, find.text(book.title));
    for (final kind in ['card', 'row']) {
      if (kind == 'row') {
        await tester.tap(find.byTooltip('列表视图'));
        await tester.pumpAndSettle();
      }
      await tester.tap(
        find.byKey(ValueKey('book-$kind-${book.id}')),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryButton,
      );
      await pumpReaderUntil(tester, find.text('编辑 EPUB'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑 EPUB'));
      await pumpReaderUntil(tester, find.byType(BookEditorPage));
      final editor = tester
          .widget<BookEditorPage>(find.byType(BookEditorPage))
          .controller;
      await pumpReaderUntilComplete(tester, () => !editor.previewLoading);
      await tester.pump(const Duration(milliseconds: 400));
      final route = tester.widget<BookEditorRoute>(
        find.byType(BookEditorRoute),
      );
      expect(route.bookId, book.id);
      expect(route.sourcePath, book.filePath);
      expect(route.contentRevision, book.contentRevision);
      expect(library.syncRepository().busy, isTrue);
      await tester.tap(find.byTooltip('退出编辑'));
      await tester.pumpAndSettle();
      expect(library.syncRepository().busy, isFalse);
    }
    expect((await pumpReaderTask(tester, library.list())).single.id, book.id);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  }, variant: _platforms);

  testWidgets('切换侧栏后隐藏书架不响应快捷键，返回后恢复', (tester) async {
    await _show(
      tester,
      HomeShell(
        library: LibraryStore.memory(),
        progressStore: MemoryReaderProgressStore(),
      ),
    );
    final rail = find.byType(NavigationRail);
    await tester.tap(find.descendant(of: rail, matching: find.text('统计')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await _shortcut(tester, LogicalKeyboardKey.keyF);
    final hiddenSearch = tester.widget<TextField>(
      find.byKey(const ValueKey('bookshelf-search-field'), skipOffstage: false),
    );
    expect(hiddenSearch.focusNode!.hasFocus, isFalse);
    expect(hiddenSearch.controller!.text, isEmpty);
    await tester.tap(find.descendant(of: rail, matching: find.text('书架')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await _shortcut(tester, LogicalKeyboardKey.keyF);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('bookshelf-search-field')),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.tap(find.descendant(of: rail, matching: find.text('书架')));
    await tester.pump();
    await tester.pump();
    await _shortcut(tester, LogicalKeyboardKey.keyF);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('bookshelf-search-field')),
      findsOneWidget,
    );
  }, variant: _platforms);
}
