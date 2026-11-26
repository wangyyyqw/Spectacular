import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reader_ui/theme/reader_switch.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/bookshelf_page.dart';
import 'package:reader_mobile/home/bookshelf_sort.dart';
import 'package:reader_mobile/home/home_shell.dart';
import 'package:reader_mobile/library/library_store.dart';

import '../support/test_epub.dart';

import 'package:reader_ui/reader_session.dart';

Future<void> _settle(WidgetTester tester, {int frames = 12}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

class _PreferencesLibrary extends LibraryStore {
  _PreferencesLibrary() : super.memory();

  Completer<void>? pending;

  @override
  Future<String?> getSetting(String key) async {
    await pending?.future;
    return super.getSetting(key);
  }
}

void main() {
  testWidgets('返回书架读取相同偏好时不再次重建，偏好变化仍立即生效', (tester) async {
    final library = _PreferencesLibrary();
    final progress = MemoryReaderProgressStore();
    Widget app(int refresh) => MaterialApp(
      home: BookshelfPage(
        library: library,
        progressStore: progress,
        refreshToken: refresh,
      ),
    );
    await tester.pumpWidget(app(0));
    await tester.pumpAndSettle();
    library.pending = Completer<void>();
    await tester.pumpWidget(app(1));
    var rebuilds = 0;
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtBefore) {
      previous?.call(element, builtBefore);
      if (element.widget is BookshelfPage) rebuilds++;
    };
    try {
      library.pending!.complete();
      await tester.pumpAndSettle();
      expect(rebuilds, 0);
      await library.setSetting('bookshelf.grid', 'false');
      await tester.pumpWidget(app(2));
      await tester.pumpAndSettle();
      expect(find.byTooltip('网格视图'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      debugOnRebuildDirtyWidget = previous;
    }
  });

  testWidgets('书架管理关闭宫格书名后仅宫格隐藏书名，列表书名保留', (tester) async {
    final library = LibraryStore.memory();
    final ids = <String>[];
    await tester.runAsync(() async {
      for (final title in <String>['A书', 'B书']) {
        ids.add((await library.importBytes(buildTestEpub(title: title))).id);
      }
    });

    await tester.pumpWidget(
      MaterialApp(
        home: HomeShell(
          library: library,
          progressStore: MemoryReaderProgressStore(),
        ),
      ),
    );
    await _settle(tester);

    Finder cardTitle(String id) =>
        find.byKey(ValueKey<String>('book-card-title-$id'));
    for (final id in ids) {
      expect(cardTitle(id), findsOneWidget);
    }

    await tester.tap(find.text('我的'));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('profile-settings-entry')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('bookshelf-management-entry')));
    await _settle(tester);
    final switchTile = find.byKey(
      const ValueKey<String>('bookshelf-grid-title-setting'),
    );
    expect(tester.widget<ReaderSwitchListTile>(switchTile).value, isTrue);
    await tester.tap(switchTile);
    await _settle(tester);
    expect(tester.widget<ReaderSwitchListTile>(switchTile).value, isFalse);
    expect(await library.getSetting(bookshelfGridShowTitlesKey), 'false');

    await tester.binding.handlePopRoute();
    await _settle(tester);
    await tester.binding.handlePopRoute();
    await _settle(tester);
    await tester.tap(find.text('书架'));
    await _settle(tester);
    for (final id in ids) {
      expect(cardTitle(id), findsNothing);
    }

    await tester.tap(find.byTooltip('列表视图'));
    await _settle(tester);
    for (final id in ids) {
      expect(
        find.byKey(ValueKey<String>('book-row-title-$id')),
        findsOneWidget,
      );
    }

    // 重新构建页面（≈ 重启）仍保持隐藏。
    await tester.pumpWidget(
      MaterialApp(
        home: BookshelfPage(
          library: library,
          progressStore: MemoryReaderProgressStore(),
        ),
      ),
    );
    await _settle(tester);
    for (final id in ids) {
      expect(
        find.byKey(ValueKey<String>('book-row-title-$id')),
        findsOneWidget,
      );
    }
  });
}
