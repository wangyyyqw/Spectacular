import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/home_shell.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/theme/app_theme.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/test_epub.dart';

const _desktop = Size(1280, 720);
const _desktopPlatforms = TargetPlatformVariant({
  TargetPlatform.macOS,
  TargetPlatform.windows,
  TargetPlatform.linux,
});

Future<void> _showHome(WidgetTester tester, LibraryStore library) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = _desktop;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: HomeShell(
        library: library,
        progressStore: MemoryReaderProgressStore(),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _select(
  WidgetTester tester,
  Finder navigation,
  String label,
) async {
  await tester.tap(find.descendant(of: navigation, matching: find.text(label)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

void main() {
  testWidgets('桌面往返书评页后搜索快捷键仍可聚焦', (tester) async {
    await _showHome(tester, LibraryStore.memory());
    final rail = find.byType(NavigationRail);
    await _select(tester, rail, '书评');
    await tester.tap(find.byKey(const ValueKey('reviews-tab')));
    await tester.pump();
    final search = find.byKey(const ValueKey('reviews-search-field'));
    final modifier =
        Theme.of(tester.element(search)).platform == TargetPlatform.macOS
        ? LogicalKeyboardKey.metaLeft
        : LogicalKeyboardKey.controlLeft;
    for (var visit = 0; visit < 2; visit++) {
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(modifier);
      await tester.pump();
      expect(tester.widget<TextField>(search).focusNode!.hasFocus, isTrue);
      await _select(tester, rail, '统计');
      await _select(tester, rail, '书评');
    }
    expect(tester.takeException(), isNull);
  }, variant: _desktopPlatforms);

  testWidgets('桌面平台缩放窗口始终使用侧栏并保留当前页和书架搜索', (tester) async {
    await _showHome(tester, LibraryStore.memory());
    final rail = find.byType(NavigationRail);
    final bottom = find.byType(BottomNavigationBar);
    final search = find.byKey(const ValueKey('bookshelf-search-field'));
    expect(rail, findsOneWidget);
    expect(bottom, findsNothing);
    expect(
      find.descendant(of: rail, matching: find.text('编辑器')),
      findsOneWidget,
    );
    expect(find.text('书架还是空的'), findsOneWidget);
    await tester.tap(find.byTooltip('搜索书架'));
    await tester.pump();
    await tester.enterText(search, '山海');

    await _select(tester, rail, '统计');
    expect(find.text('图书时长'), findsOneWidget);
    await _select(tester, rail, '书评');
    expect(find.byKey(const ValueKey('notes-tab')), findsOneWidget);
    await _select(tester, rail, '我的');
    expect(find.text('书架排序'), findsOneWidget);

    tester.view.physicalSize = const Size(390, 844);
    await tester.pump();
    expect(rail, findsOneWidget);
    expect(bottom, findsNothing);
    expect(tester.widget<NavigationRail>(rail).selectedIndex, 4);
    await _select(tester, rail, '书评');
    tester.view.physicalSize = _desktop;
    await tester.pump();
    expect(tester.widget<NavigationRail>(rail).selectedIndex, 2);
    expect(find.byKey(const ValueKey('notes-tab')), findsOneWidget);
    await _select(tester, rail, '书架');
    expect(tester.widget<TextField>(search).controller!.text, '山海');
    await _select(tester, rail, '编辑器');
    expect(find.byKey(const ValueKey('editor-open-file')), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: _desktopPlatforms);

  testWidgets(
    '移动平台宽屏和窄屏始终使用底栏并保留当前页',
    (tester) async {
      await _showHome(tester, LibraryStore.memory());
      final bottom = find.byType(BottomNavigationBar);
      expect(find.byType(NavigationRail), findsNothing);
      expect(bottom, findsOneWidget);
      expect(find.text('编辑器'), findsNothing);
      await _select(tester, bottom, '我的');

      tester.view.physicalSize = const Size(390, 844);
      await tester.pump();
      expect(find.byType(NavigationRail), findsNothing);
      expect(tester.widget<BottomNavigationBar>(bottom).currentIndex, 3);
      await _select(tester, bottom, '书架');

      tester.view.physicalSize = _desktop;
      await tester.pump();
      expect(find.byType(NavigationRail), findsNothing);
      expect(tester.widget<BottomNavigationBar>(bottom).currentIndex, 0);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets('书架按侧栏外的可用宽度增列，窄窗仍为三列', (tester) async {
    final library = LibraryStore.memory();
    for (var index = 1; index <= 4; index++) {
      await library.importBytes(buildTestEpub(title: '书目$index'));
    }
    await _showHome(tester, library);
    final covers = find.byKey(const ValueKey('book-card-cover'));
    double rowTop(int index) => tester.getTopLeft(covers.at(index)).dy;
    expect(rowTop(3), rowTop(0));
    expect(tester.getSize(covers.first).aspectRatio, closeTo(3 / 4, 0.001));

    for (final width in [960.0, 390.0]) {
      tester.view.physicalSize = Size(width, 800);
      await tester.pump();
      expect(rowTop(2), rowTop(0));
      expect(rowTop(3), greaterThan(rowTop(0)));
    }
  }, variant: _desktopPlatforms);
}
