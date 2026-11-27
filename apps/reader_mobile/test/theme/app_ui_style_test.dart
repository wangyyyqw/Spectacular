import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/app_settings_page.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/main.dart';
import 'package:reader_mobile/storage/db.dart';
import 'package:reader_mobile/theme/app_theme.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/reader_pump.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.spectacular.reader_mobile/theme_color');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'getStartupTheme':
            case 'getWallpaperSeed':
              return null;
            case 'cacheStartupTheme':
              return null;
            default:
              fail('未预期的取色调用：${call.method}');
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('界面样式默认 classic，未知偏好回退 classic', () {
    expect(AppUiStyle.fromSetting(null), AppUiStyle.classic);
    expect(AppUiStyle.fromSetting('legacy'), AppUiStyle.classic);
    expect(AppUiStyle.fromSetting('material3'), AppUiStyle.material3);
    expect(buildAppTheme().useMaterial3, isFalse);
    expect(buildAppTheme(uiStyle: AppUiStyle.material3).useMaterial3, isTrue);
  });

  testWidgets('设置页切换并持久化 Material 3，重启后恢复且可切回 classic', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1400);
    addTearDown(tester.view.reset);
    final directory = Directory.systemTemp.createTempSync('app-ui-style');
    final file = File('${directory.path}/reader.sqlite');
    var database = AppDatabase(NativeDatabase(file));
    var library = LibraryStore(database: database);
    addTearDown(() async {
      await database.close();
      await directory.delete(recursive: true);
    });

    Future<void> openApp() async {
      await tester.pumpWidget(
        ReaderApp(library: library, progressStore: MemoryReaderProgressStore()),
      );
      await pumpReaderUntil(tester, find.text('书架还是空的'));
    }

    Future<void> openSettings() async {
      final nav = find.byWidgetPredicate(
        (widget) => widget is NavigationBar || widget is BottomNavigationBar,
      );
      await tester.tap(find.descendant(of: nav, matching: find.text('我的')));
      await pumpReaderUntil(
        tester,
        find.byKey(const ValueKey('profile-settings-entry')),
      );
      await tester.tap(find.byKey(const ValueKey('profile-settings-entry')));
      await pumpReaderUntil(tester, find.text('主题外观'));
      await tester.tap(find.text('主题外观'));
      await pumpReaderUntil(
        tester,
        find.byKey(const ValueKey('app-ui-style-setting')),
      );
    }

    Future<void> selectStyle(String label) async {
      final entry = find.byKey(const ValueKey('app-ui-style-setting'));
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(PopupMenuItem<AppUiStyle>, label));
      await tester.pumpAndSettle();
      await pumpReaderUntil(
        tester,
        find.byKey(const ValueKey('app-ui-style-setting')),
      );
    }

    await openApp();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!.useMaterial3,
      isFalse,
    );
    await openSettings();
    expect(
      find.descendant(of: find.byKey(const ValueKey('app-ui-style-setting')), matching: find.text('经典')),
      findsOneWidget,
    );
    await selectStyle('Material 3');
    expect(await library.getSetting(AppUiStyle.settingKey), 'material3');
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!.useMaterial3,
      isTrue,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await database.close();
    database = AppDatabase(NativeDatabase(file));
    library = LibraryStore(database: database);
    await openApp();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!.useMaterial3,
      isTrue,
    );
    await openSettings();
    expect(
      find.descendant(of: find.byKey(const ValueKey('app-ui-style-setting')), matching: find.text('Material 3')),
      findsOneWidget,
    );
    await selectStyle('经典');
    expect(await library.getSetting(AppUiStyle.settingKey), 'classic');
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!.useMaterial3,
      isFalse,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('无应用级主题作用域时设置页仍可通过传入回调选择样式', (tester) async {
    final library = LibraryStore.memory();
    AppUiStyle? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: AppSettingsPage(
          library: library,
          onUiStyleChanged: (style) async => selected = style,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('界面样式'), findsNothing);
    await tester.tap(find.text('主题外观'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('app-ui-style-setting')));
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuItem<AppUiStyle>), findsNWidgets(2));
    await tester.tap(find.text('Material 3'));
    await tester.pumpAndSettle();
    expect(selected, AppUiStyle.material3);
    expect(tester.takeException(), isNull);
  });
}
