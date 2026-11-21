import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/editing/epub_file_editor_page.dart';
import 'package:reader_mobile/home/bookshelf_page.dart';
import 'package:reader_mobile/home/home_shell.dart';
import 'package:reader_mobile/home/profile_page.dart';
import 'package:reader_mobile/home/reviews_page.dart';
import 'package:reader_mobile/home/stats_page.dart';
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

Future<void> _shortcut(WidgetTester tester, LogicalKeyboardKey key) async {
  final platform = Theme.of(
    tester.element(find.byType(HomeShell, skipOffstage: false)),
  ).platform;
  final modifier = platform == TargetPlatform.macOS
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(modifier);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('退出全屏阅读首帧保留书架搜索框和底栏位置，系统栏恢复时不弹动', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    const systemPadding = FakeViewPadding(top: 32, bottom: 24);
    tester.view.viewPadding = systemPadding;
    tester.view.padding = systemPadding;
    addTearDown(tester.view.reset);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: buildAppTheme(),
        home: HomeShell(
          library: LibraryStore.memory(),
          progressStore: MemoryReaderProgressStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('bookshelf-search-field'));
    final bottom = find.byType(BottomNavigationBar);
    final searchRect = tester.getRect(search);
    final bottomRect = tester.getRect(bottom);
    navigator.currentState!.push(
      PageRouteBuilder<void>(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, _, _) => const Scaffold(body: Text('全屏阅读')),
      ),
    );
    await tester.pumpAndSettle();
    tester.view.viewPadding = FakeViewPadding.zero;
    tester.view.padding = FakeViewPadding.zero;
    await tester.pump();
    navigator.currentState!.pop();
    await tester.pump();
    expect(tester.getRect(search), searchRect, reason: '返回首帧搜索框直接位于最终位置');
    expect(tester.getRect(bottom), bottomRect, reason: '返回首帧底栏直接位于最终位置');
    tester.view.viewPadding = const FakeViewPadding(top: 32, bottom: 12);
    tester.view.padding = const FakeViewPadding(top: 32, bottom: 12);
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.getRect(search), searchRect);
    expect(tester.getRect(bottom), bottomRect, reason: '系统栏恢复途中底栏不跟随上移');
    tester.view.viewPadding = systemPadding;
    tester.view.padding = systemPadding;
    await tester.pumpAndSettle();
    expect(tester.getRect(search), searchRect);
    expect(tester.getRect(bottom), bottomRect);
    expect(tester.takeException(), isNull);
  });

  testWidgets('切换书评和我的不重建无关的隐藏书架与统计页', (tester) async {
    await _showHome(tester, LibraryStore.memory());
    await tester.pumpAndSettle();
    final navigation = find.byType(NavigationRail).evaluate().isNotEmpty
        ? find.byType(NavigationRail)
        : find.byType(BottomNavigationBar);
    await _select(tester, navigation, '统计');
    await _select(tester, navigation, '书评');
    await tester.pumpAndSettle();

    final rebuilt = <Type>[];
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtBefore) {
      previous?.call(element, builtBefore);
      if (element.widget is BookshelfPage || element.widget is StatsPage) {
        rebuilt.add(element.widget.runtimeType);
      }
    };
    addTearDown(() => debugOnRebuildDirtyWidget = previous);
    await _select(tester, navigation, '我的');
    await _select(tester, navigation, '书评');
    await tester.pumpAndSettle();
    expect(rebuilt, isEmpty);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant(TargetPlatform.values.toSet()));

  testWidgets('宿主更新主题与回调后保留当前页并使用最新配置', (tester) async {
    final library = LibraryStore.memory();
    final progress = MemoryReaderProgressStore();
    final saved = <String>[];
    Widget app(ThemeMode mode, String callback) => MaterialApp(
      home: HomeShell(
        library: library,
        progressStore: progress,
        themeMode: mode,
        onThemeModeChanged: (selected) async {
          saved.add('$callback:${selected.name}');
        },
      ),
    );
    await tester.pumpWidget(app(ThemeMode.light, '旧'));
    await tester.pumpAndSettle();
    await _select(tester, find.byType(BottomNavigationBar), '我的');
    expect(find.text('日间模式'), findsOneWidget);
    final profile = tester.state(find.byType(ProfilePage));

    await tester.pumpWidget(app(ThemeMode.dark, '新'));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(ProfilePage)), same(profile));
    expect(find.text('夜间模式'), findsOneWidget);
    await tester.tap(find.text('界面主题'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('跟随系统'));
    await tester.pumpAndSettle();
    expect(saved, ['新:system']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('桌面数字快捷键切换五个页面并保留书架搜索', (tester) async {
    await _showHome(tester, LibraryStore.memory());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('搜索书架'));
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('bookshelf-search-field'));
    await tester.enterText(search, '保留搜索');
    for (final (key, index) in [
      (LogicalKeyboardKey.digit2, 1),
      (LogicalKeyboardKey.digit3, 2),
      (LogicalKeyboardKey.digit4, 3),
      (LogicalKeyboardKey.digit5, 4),
      (LogicalKeyboardKey.digit1, 0),
    ]) {
      await _shortcut(tester, key);
      expect(
        tester
            .widget<NavigationRail>(find.byType(NavigationRail))
            .selectedIndex,
        index,
      );
    }
    expect(tester.widget<TextField>(search).controller!.text, '保留搜索');
    expect(tester.takeException(), isNull);
  }, variant: _desktopPlatforms);

  testWidgets('弹窗和上层路由不透传首页切页快捷键', (tester) async {
    await _showHome(tester, LibraryStore.memory());
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(HomeShell));
    final navigator = Navigator.of(context);
    final dialog = showDialog<void>(
      context: context,
      builder: (_) => const AlertDialog(content: TextField(autofocus: true)),
    );
    await tester.pumpAndSettle();
    await _shortcut(tester, LogicalKeyboardKey.digit4);
    expect(
      tester
          .widget<NavigationRail>(
            find.byType(NavigationRail, skipOffstage: false),
          )
          .selectedIndex,
      0,
    );
    expect(
      find.byWidgetPredicate((widget) => widget is AlertDialog),
      findsOneWidget,
    );
    navigator.pop();
    await dialog;
    await tester.pumpAndSettle();
    final route = navigator.push<void>(
      MaterialPageRoute(
        builder: (_) => const Scaffold(body: TextField(autofocus: true)),
      ),
    );
    await tester.pumpAndSettle();
    await _shortcut(tester, LogicalKeyboardKey.digit5);
    expect(
      tester
          .widget<NavigationRail>(
            find.byType(NavigationRail, skipOffstage: false),
          )
          .selectedIndex,
      0,
    );
    navigator.pop();
    await route;
    await tester.pumpAndSettle();
    await _shortcut(tester, LogicalKeyboardKey.digit5);
    expect(
      tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex,
      4,
    );
    expect(tester.takeException(), isNull);
  }, variant: _desktopPlatforms);

  testWidgets(
    '移动端不响应桌面切页快捷键',
    (tester) async {
      await _showHome(tester, LibraryStore.memory());
      await tester.pumpAndSettle();
      await _shortcut(tester, LogicalKeyboardKey.digit5);
      expect(
        tester
            .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
            .currentIndex,
        0,
      );
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets('首页隐藏页暂停动画且不能接收焦点，切页保持页面状态', (tester) async {
    await _showHome(tester, LibraryStore.memory());
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 2),
    );
    final desktop = find.byType(NavigationRail).evaluate().isNotEmpty;
    final navigation = desktop
        ? find.byType(NavigationRail)
        : find.byType(BottomNavigationBar);
    final pages = <(String, Type)>[
      ('书架', BookshelfPage),
      ('统计', StatsPage),
      ('书评', ReviewsPage),
      if (desktop) ('编辑器', EpubFileEditorPage),
      ('我的', ProfilePage),
    ];
    final initialState = tester.state(find.byType(HomeShell));
    for (final (label, _) in pages) {
      await _select(tester, navigation, label);
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 2),
      );
      for (final (pageLabel, type) in pages) {
        final page = tester.element(find.byType(type, skipOffstage: false));
        expect(
          TickerMode.valuesOf(page).enabled,
          pageLabel == label,
          reason: pageLabel,
        );
        expect(
          Focus.of(page, scopeOk: true).descendantsAreFocusable,
          pageLabel == label,
          reason: pageLabel,
        );
      }
      expect(tester.state(find.byType(HomeShell)), same(initialState));
      expect(tester.binding.hasScheduledFrame, isFalse);
    }
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant(TargetPlatform.values.toSet()));

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
    await tester.tap(find.byKey(const ValueKey<String>('reviews-tab')));
    await tester.pump();
    expect(find.byTooltip('刷新书评'), findsOneWidget);
    await _select(tester, rail, '我的');
    expect(find.text('书架排序'), findsOneWidget);

    tester.view.physicalSize = const Size(390, 844);
    await tester.pump();
    expect(rail, findsOneWidget);
    expect(bottom, findsNothing);
    expect(tester.widget<NavigationRail>(rail).selectedIndex, 5);
    await _select(tester, rail, '书评');
    tester.view.physicalSize = _desktop;
    await tester.pump();
    expect(tester.widget<NavigationRail>(rail).selectedIndex, 3);
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
      expect(tester.widget<BottomNavigationBar>(bottom).currentIndex, 4);
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
