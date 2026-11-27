import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/main.dart';
import 'package:reader_mobile/reader/reader_route.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/theme/reader_sheet_form.dart';

import '../support/reader_pump.dart';

Future<void> _pumpApp(WidgetTester tester) async {
  for (var frame = 0; frame < 4; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _showApp(WidgetTester tester) async {
  await tester.pumpWidget(
    ReaderApp(
      library: LibraryStore.memory(),
      progressStore: MemoryReaderProgressStore(),
    ),
  );
  await pumpStartupFinished(tester);
  await _pumpApp(tester);
}

Iterable<AnnotatedRegion<SystemUiOverlayStyle>> _regions(WidgetTester tester) =>
    tester.widgetList<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
    );

Future<void> _openProfile(WidgetTester tester) async {
  final rail = find.byType(NavigationRail);
  final compact = rail.evaluate().isNotEmpty &&
      !tester.widget<NavigationRail>(rail).extended;
  await tester.tap(
    find.descendant(
      of: find.byWidgetPredicate(
        (widget) => widget is BottomNavigationBar || widget is NavigationRail,
      ),
      matching: compact ? find.byTooltip('我的') : find.text('我的'),
    ).hitTestable().first,
  );
  await _pumpApp(tester);
  await tester.tap(find.byKey(const ValueKey('profile-settings-entry')));
  await _pumpApp(tester);
  await tester.ensureVisible(find.text('界面主题'));
  await _pumpApp(tester);
}

Future<void> _selectMode(
  WidgetTester tester,
  String label,
  ThemeMode mode,
) async {
  await tester.tap(find.text('界面主题'));
  await _pumpApp(tester);
  final drawer = find.byType(ReaderSheetForm);
  expect(drawer, findsOneWidget);
  expect(
    find.byWidgetPredicate((widget) => widget is AlertDialog),
    findsNothing,
  );
  await tester.tap(
    find.descendant(
      of: drawer,
      matching: find.widgetWithText(RadioListTile<ThemeMode>, label),
    ),
  );
  await pumpReaderUntilComplete(
    tester,
    () => drawer.evaluate().isEmpty,
    description: '界面主题抽屉退场',
  );
  await pumpReaderUntilComplete(
    tester,
    () =>
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode == mode,
  );
  await _pumpApp(tester);
}

void main() {
  testWidgets(
    '仅阅读路由隐藏系统标题栏，其他路由及离开阅读后恢复',
    (tester) async {
      final modes = <bool>[];
      const window = MethodChannel('com.spectacular.reader_mobile/window');
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(window, (call) async {
        if (call.method == 'getWindowInsets') return {'top': 28.0};
        if (call.method == 'setReaderWindowMode') {
          modes.add(call.arguments as bool);
          return null;
        }
        if (call.method == 'setDarkMode') return null;
        fail('未知桌面窗口方法：${call.method}');
      });
      addTearDown(() => messenger.setMockMethodCallHandler(window, null));

      await _showApp(tester);
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push<void>(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: readerWindowRouteName),
          builder: (_) => const Scaffold(body: Text('阅读页')),
        ),
      );
      await _pumpApp(tester);
      expect(modes, [true]);

      navigator.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('阅读设置')),
        ),
      );
      await _pumpApp(tester);
      expect(modes, [true, false]);

      navigator.pop();
      await _pumpApp(tester);
      expect(modes, [true, false, true]);
      navigator.pop();
      await _pumpApp(tester);
      expect(modes, [true, false, true, false]);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
    }),
  );

  testWidgets('应用四页保留可见的状态栏和导航栏图标样式', (tester) async {
    await _showApp(tester);
    for (final label in ['书架', '统计', '笔记', '我的']) {
      await tester.tap(
        find.descendant(
          of: find.byType(BottomNavigationBar),
          matching: find.text(label),
        ),
      );
      await _pumpApp(tester);
      final region = _regions(tester).first;
      expect(region.value.statusBarIconBrightness, Brightness.dark);
      expect(region.value.systemNavigationBarIconBrightness, Brightness.dark);
      expect(region.value.systemStatusBarContrastEnforced, false);
      expect(region.value.systemNavigationBarContrastEnforced, false);
      expect(region.value.statusBarColor, Colors.transparent);
      expect(region.value.systemNavigationBarColor, Colors.transparent);
      expect(
        _regions(tester).last.value.systemStatusBarContrastEnforced,
        false,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('独立页面继承应用导航栏图标样式，状态栏图标与页面背景形成对比', (tester) async {
    await _showApp(tester);
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(appBar: AppBar(title: const Text('独立页面'))),
          ),
        );
    await _pumpApp(tester);
    final regions = _regions(tester);
    expect(
      regions.first.value.systemNavigationBarIconBrightness,
      Brightness.dark,
    );
    expect(regions.last.value.statusBarIconBrightness, Brightness.dark);
    expect(regions.last.value.systemStatusBarContrastEnforced, false);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    '界面主题切换更新系统栏和桌面标题栏，重新打开数据库后恢复',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync('app-theme');
      final file = File('${directory.path}/reader.sqlite');
      var database = AppDatabase(NativeDatabase(file));
      addTearDown(() async {
        await database.close();
        await directory.delete(recursive: true);
      });
      final windowModes = <bool>[];
      const window = MethodChannel('com.spectacular.reader_mobile/window');
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(window, (call) async {
        if (call.method == 'getWindowInsets') return {'top': 28.0};
        expect(call.method, 'setDarkMode');
        windowModes.add(
          call.arguments as bool? ??
              (tester.binding.platformDispatcher.platformBrightness ==
                  Brightness.dark),
        );
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(window, null));

      Future<void> openApp() async {
        await tester.pumpWidget(
          ReaderApp(
            library: LibraryStore(database: database),
            progressStore: MemoryReaderProgressStore(),
          ),
        );
        await pumpReaderUntil(tester, find.text('书架还是空的'));
      }

      await openApp();
      expect(windowModes, [
        tester.binding.platformDispatcher.platformBrightness == Brightness.dark,
      ]);
      await _openProfile(tester);
      expect(find.text('跟随系统'), findsOneWidget);
      await _selectMode(tester, '夜间模式', ThemeMode.dark);
      expect(windowModes, [false, true]);
      expect(
        _regions(tester).first.value.systemNavigationBarIconBrightness,
        Brightness.light,
      );
      expect(
        _regions(tester).last.value.statusBarIconBrightness,
        Brightness.light,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await pumpReaderTask(tester, database.close());
      database = AppDatabase(NativeDatabase(file));
      await openApp();
      expect(windowModes, [false, true, true]);
      expect(
        _regions(tester).last.value.statusBarIconBrightness,
        Brightness.light,
      );
      await _openProfile(tester);
      expect(find.text('夜间模式'), findsOneWidget);
      await _selectMode(tester, '日间模式', ThemeMode.light);
      expect(windowModes, [false, true, true, false]);
      expect(
        _regions(tester).last.value.statusBarIconBrightness,
        Brightness.dark,
      );
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
    }),
  );

  testWidgets(
    '跟随系统实时更新亮度并持久化选择，固定主题不受系统变化影响',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync('system-theme');
      final file = File('${directory.path}/reader.sqlite');
      var database = AppDatabase(NativeDatabase(file));
      final dispatcher = tester.binding.platformDispatcher;
      dispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(dispatcher.clearPlatformBrightnessTestValue);
      addTearDown(() async {
        await database.close();
        await directory.delete(recursive: true);
      });
      final windowModes = <bool>[];
      final windowArguments = <Object?>[];
      const window = MethodChannel('com.spectacular.reader_mobile/window');
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(window, (call) async {
        if (call.method == 'getWindowInsets') return {'top': 28.0};
        if (call.method == 'setReaderWindowMode') return null;
        windowArguments.add(call.arguments);
        windowModes.add(
          call.arguments as bool? ??
              (tester.binding.platformDispatcher.platformBrightness ==
                  Brightness.dark),
        );
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(window, null));

      Future<void> openApp() async {
        await tester.pumpWidget(
          ReaderApp(
            library: LibraryStore(database: database),
            progressStore: MemoryReaderProgressStore(),
          ),
        );
        await pumpReaderUntil(tester, find.text('书架还是空的'));
        await _openProfile(tester);
      }

      Brightness brightness() =>
          Theme.of(tester.element(find.text('界面主题'))).brightness;

      await openApp();
      if (defaultTargetPlatform == TargetPlatform.macOS) {
        expect(windowArguments.last, isNull);
      } else if (defaultTargetPlatform == TargetPlatform.windows) {
        expect(windowArguments.last, false);
      }
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.system,
      );
      expect(find.text('跟随系统'), findsOneWidget);
      await _selectMode(tester, '日间模式', ThemeMode.light);
      await _selectMode(tester, '跟随系统', ThemeMode.system);
      expect(find.text('跟随系统'), findsOneWidget);
      expect(brightness(), Brightness.light);
      dispatcher.platformBrightnessTestValue = Brightness.dark;
      await _pumpApp(tester);
      expect(brightness(), Brightness.dark);
      expect(find.text('跟随系统'), findsOneWidget);
      expect(
        _regions(tester).last.value.statusBarIconBrightness,
        Brightness.light,
      );
      expect(
        _regions(tester).first.value.systemNavigationBarIconBrightness,
        Brightness.light,
      );
      if (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS) {
        expect(windowModes.last, true);
        expect(
          windowArguments.last,
          defaultTargetPlatform == TargetPlatform.macOS ? isNull : isTrue,
        );
      }

      await tester.pumpWidget(const SizedBox.shrink());
      await pumpReaderTask(tester, database.close());
      database = AppDatabase(NativeDatabase(file));
      await openApp();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.system,
      );
      expect(find.text('跟随系统'), findsOneWidget);
      expect(brightness(), Brightness.dark);
      await tester.tap(find.text('界面主题'));
      await _pumpApp(tester);
      final drawer = find.byType(ReaderSheetForm);
      expect(drawer, findsOneWidget);
      expect(
        tester
            .widget<RadioGroup<ThemeMode>>(
              find.descendant(
                of: drawer,
                matching: find.byType(RadioGroup<ThemeMode>),
              ),
            )
            .groupValue,
        ThemeMode.system,
      );
      await tester.binding.handlePopRoute();
      await pumpReaderUntilComplete(
        tester,
        () => drawer.evaluate().isEmpty,
        description: '关闭主题抽屉',
      );
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.system,
      );

      dispatcher.platformBrightnessTestValue = Brightness.light;
      await _pumpApp(tester);
      expect(brightness(), Brightness.light);
      await _selectMode(tester, '夜间模式', ThemeMode.dark);
      dispatcher.platformBrightnessTestValue = Brightness.dark;
      await _pumpApp(tester);
      dispatcher.platformBrightnessTestValue = Brightness.light;
      await _pumpApp(tester);
      expect(brightness(), Brightness.dark);
      expect(find.text('夜间模式'), findsOneWidget);
      await _selectMode(tester, '日间模式', ThemeMode.light);
      dispatcher.platformBrightnessTestValue = Brightness.dark;
      await _pumpApp(tester);
      expect(brightness(), Brightness.light);
      expect(find.text('日间模式'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpReaderTask(tester, database.close());
      database = AppDatabase(NativeDatabase(file));
      await openApp();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.light,
      );
      expect(brightness(), Brightness.light);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    }),
  );
}
