import 'package:flutter/material.dart';
import 'package:reader_ui/theme/reader_switch.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/theme_color_settings_page.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/main.dart';
import 'package:reader_mobile/home/startup_splash.dart';
import 'package:reader_mobile/theme/app_theme.dart';
import 'package:reader_mobile/theme/theme_color_settings.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/reader_pump.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.spectacular.reader_mobile/theme_color');
  Color? seed;
  setUp(() {
    seed = const Color(0xFF26796B);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'getWallpaperSeed');
          return seed?.toARGB32();
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('取色独立持久化，重启恢复，重新获取壁纸后更新日夜主题', () async {
    final library = LibraryStore.memory();
    final settings = ThemeColorSettings(library);
    addTearDown(settings.dispose);
    await settings.initialize();
    expect(settings.wallpaperEnabled, isFalse);
    expect(settings.readerBackgroundEnabled, isFalse);
    expect(settings.wallpaperScheme(Brightness.light), isNull);
    await settings.setWallpaperEnabled(true);
    await settings.setReaderBackgroundEnabled(true);
    final light = settings.wallpaperScheme(Brightness.light)!;
    final dark = settings.wallpaperScheme(Brightness.dark)!;
    expect(light.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark);
    expect(light.surface.computeLuminance(), greaterThan(0.8));
    expect(dark.surface.computeLuminance(), lessThan(0.1));
    expect(
      buildAppTheme(colorScheme: light)
          .filledButtonTheme
          .style!
          .backgroundColor!
          .resolve({}),
      light.primary,
    );
    await settings.setWallpaperEnabled(false);
    expect(settings.readerBackgroundEnabled, isTrue);
    final restored = ThemeColorSettings(library);
    addTearDown(restored.dispose);
    await restored.initialize();
    expect(restored.wallpaperEnabled, isFalse);
    expect(restored.readerBackgroundEnabled, isTrue);
    await restored.setWallpaperEnabled(true);
    seed = const Color(0xFFAB5036);
    await restored.refreshWallpaper();
    expect(
      restored.wallpaperScheme(Brightness.light)!.primary,
      isNot(light.primary),
    );
  });

  testWidgets('不支持系统取色的设备置灰壁纸选项，阅读取色仍可启用', (tester) async {
    seed = null;
    final library = LibraryStore.memory();
    final settings = ThemeColorSettings(library);
    addTearDown(settings.dispose);
    await settings.initialize();
    await tester.pumpWidget(
      MaterialApp(home: ThemeColorSettingsPage(settings: settings)),
    );
    final wallpaper = find.byKey(const ValueKey('wallpaper-color-switch'));
    final reader = find.byKey(const ValueKey('reader-background-color-switch'));
    expect(tester.widget<ReaderSwitchListTile>(wallpaper).onChanged, isNull);
    expect(tester.widget<ReaderSwitchListTile>(reader).onChanged, isNotNull);
    await tester.tap(reader);
    await tester.pumpAndSettle();
    expect(settings.readerBackgroundEnabled, isTrue);
    expect(
      await library.getSetting(ThemeColorSettings.readerBackgroundKey),
      'true',
    );
    await settings.setWallpaperEnabled(true);
    expect(settings.wallpaperEnabled, isFalse);
  });

  testWidgets('宿主启动恢复壁纸取色，开关立即更新全局主题，回到前台更新系统色', (tester) async {
    final library = LibraryStore.memory();
    await library.setSetting(ThemeColorSettings.wallpaperKey, 'true');
    await tester.pumpWidget(
      ReaderApp(library: library, progressStore: MemoryReaderProgressStore()),
    );
    await pumpReaderUntil(tester, find.text('书架还是空的'));
    Color primary() => tester
        .widget<MaterialApp>(find.byType(MaterialApp))
        .theme!
        .colorScheme
        .primary;
    final expected = ColorScheme.fromSeed(seedColor: seed!).primary;
    expect(primary(), expected);
    final settings = ThemeColorScope.maybeOf(
      tester.element(find.text('书架还是空的')),
    )!;
    await settings.setWallpaperEnabled(false);
    await tester.pumpAndSettle();
    expect(primary(), buildAppTheme().colorScheme.primary);
    await settings.setReaderBackgroundEnabled(true);
    await tester.pumpAndSettle();
    expect(primary(), buildAppTheme().colorScheme.primary);
    await settings.setWallpaperEnabled(true);
    await tester.pumpAndSettle();
    expect(primary(), expected);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    seed = const Color(0xFFAA5030);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(primary(), ColorScheme.fromSeed(seedColor: seed!).primary);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('开屏与应用共用壁纸背景和已保存的${mode.name}主题', (tester) async {
      final library = LibraryStore.memory();
      await library.setSetting(ThemeColorSettings.wallpaperKey, 'true');
      await library.setSetting('app.themeMode', mode.name);
      await tester.pumpWidget(
        ReaderApp(library: library, progressStore: MemoryReaderProgressStore()),
      );
      await pumpReaderUntilComplete(
        tester,
        () => find.byType(MaterialApp).evaluate().isNotEmpty,
      );
      final splash = find.byType(StartupSplash);
      expect(splash, findsOneWidget);
      expect(tester.widget<StartupSplash>(splash).ready, isTrue);
      final theme = Theme.of(tester.element(splash));
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      final expected = mode == ThemeMode.dark ? app.darkTheme! : app.theme!;
      expect(theme.brightness, expected.brightness);
      expect(theme.colorScheme, expected.colorScheme);
      expect(theme.scaffoldBackgroundColor, expected.scaffoldBackgroundColor);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
