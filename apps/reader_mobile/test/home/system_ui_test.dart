import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/main.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_ui/reader_session.dart';

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
  await _pumpApp(tester);
}

Iterable<AnnotatedRegion<SystemUiOverlayStyle>> _regions(WidgetTester tester) =>
    tester.widgetList<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
    );

Future<void> _openProfile(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byWidgetPredicate(
        (widget) => widget is BottomNavigationBar || widget is NavigationRail,
      ),
      matching: find.text('我的'),
    ),
  );
  await _pumpApp(tester);
}

Future<void> _selectMode(
  WidgetTester tester,
  String label,
  ThemeMode mode,
) async {
  await tester.tap(find.text('界面主题'));
  await _pumpApp(tester);
  await tester.tap(find.widgetWithText(RadioListTile<ThemeMode>, label));
  await pumpReaderUntilComplete(
    tester,
    () =>
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode == mode,
  );
  await _pumpApp(tester);
}

void main() {
  testWidgets('应用四页保留可见的状态栏和导航栏图标样式', (tester) async {
    await _showApp(tester);
    for (final label in ['书架', '统计', '书评', '我的']) {
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
        expect(call.method, 'setDarkMode');
        windowModes.add(call.arguments as bool);
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
      expect(windowModes, [false]);
      await _openProfile(tester);
      expect(find.text('日间模式'), findsOneWidget);
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
}
