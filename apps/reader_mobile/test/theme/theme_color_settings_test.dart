import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reader_ui/theme/reader_switch.dart';
import 'package:reader_ui/theme/reader_ui_components.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/home/theme_color_settings_page.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/main.dart';
import 'package:reader_mobile/theme/app_theme.dart';
import 'package:reader_mobile/theme/theme_color_settings.dart';
import 'package:reader_mobile/theme/startup_theme_cache.dart';
import 'package:reader_ui/reader_session.dart';

import '../support/reader_pump.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.spectacular.reader_mobile/theme_color');
  Color? seed;
  Map<String, Object?>? nativeCache;
  setUp(() {
    seed = const Color(0xFF26796B);
    nativeCache = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'getWallpaperSeed':
              return seed?.toARGB32();
            case 'getStartupTheme':
              return nativeCache;
            case 'cacheStartupTheme':
              nativeCache = Map<String, Object?>.from(call.arguments as Map);
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
    await restored.refreshWallpaper();
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

  test('原生缓存保存日夜背景，关闭取色后保留种子但使用默认背景', () async {
    final cached = StartupThemeCache(
      wallpaperEnabled: true,
      mode: ThemeMode.dark,
      seed: seed,
    );
    await cached.save();
    final restored = (await StartupThemeCache.read())!;
    expect(restored.mode, ThemeMode.dark);
    expect(restored.seed, seed);
    expect(restored.wallpaperEnabled, isTrue);
    expect(
      nativeCache!['darkBackground'],
      buildAppTheme(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed!,
          brightness: Brightness.dark,
        ),
      ).scaffoldBackgroundColor.toARGB32(),
    );
    await StartupThemeCache(
      wallpaperEnabled: false,
      mode: ThemeMode.system,
      seed: seed,
    ).save();
    expect((await StartupThemeCache.read())!.wallpaperEnabled, isFalse);
    expect(
      nativeCache!['lightBackground'],
      buildAppTheme().scaffoldBackgroundColor.toARGB32(),
    );
  });

  test('缓存先恢复，系统取色延迟时不阻塞，刷新后更新缓存', () async {
    final library = LibraryStore.memory();
    await library.setSetting(ThemeColorSettings.wallpaperKey, 'true');
    await library.setSetting(
      ThemeColorSettings.wallpaperSeedKey,
      '${seed!.toARGB32()}',
    );
    final response = Completer<int?>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) => response.future);
    final settings = ThemeColorSettings(library);
    addTearDown(settings.dispose);
    await settings.initialize();
    expect(settings.initialized, isTrue);
    expect(settings.wallpaperSeed, seed);
    expect(settings.wallpaperScheme(Brightness.light), isNotNull);
    final changed = const Color(0xFFAB5036);
    response.complete(changed.toARGB32());
    await settings.refreshWallpaper();
    expect(settings.wallpaperSeed, changed);
    expect(
      await library.getSetting(ThemeColorSettings.wallpaperSeedKey),
      '${changed.toARGB32()}',
    );
    await settings.setWallpaperEnabled(false);
    expect(settings.wallpaperScheme(Brightness.light), isNull);
  });

  test('取色临时失败保留缓存，系统明确不支持时清除过期缓存', () async {
    final library = LibraryStore.memory();
    await library.setSetting(ThemeColorSettings.wallpaperKey, 'true');
    await library.setSetting(
      ThemeColorSettings.wallpaperSeedKey,
      '${seed!.toARGB32()}',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          throw PlatformException(code: 'temporary_failure');
        });
    final settings = ThemeColorSettings(library);
    addTearDown(settings.dispose);
    await settings.initialize();
    await settings.refreshWallpaper();
    expect(settings.wallpaperSeed, seed);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
    await settings.refreshWallpaper();
    expect(settings.wallpaperSupported, isFalse);
    expect(settings.wallpaperScheme(Brightness.dark), isNull);
    expect(
      await library.getSetting(ThemeColorSettings.wallpaperSeedKey),
      isEmpty,
    );
  });

  testWidgets('系统取色挂起时缓存恢复深色首屏，仍可进入书架', (tester) async {
    final library = LibraryStore.memory();
    await library.setSetting(ThemeColorSettings.wallpaperKey, 'true');
    await library.setSetting('app.themeMode', ThemeMode.dark.name);
    await library.setSetting(
      AppThemePreset.settingKey,
      AppThemePreset.bambooGreen.id,
    );
    final response = Completer<int?>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getWallpaperSeed') return response.future;
          if (call.method == 'getStartupTheme') return nativeCache;
          if (call.method == 'cacheStartupTheme') {
            nativeCache = Map<String, Object?>.from(call.arguments as Map);
            return null;
          }
          return null;
        });
    await tester.pumpWidget(
      ReaderApp(
        library: library,
        progressStore: MemoryReaderProgressStore(),
        startupTheme: StartupThemeCache(
          wallpaperEnabled: true,
          mode: ThemeMode.dark,
          seed: seed,
        ),
      ),
    );
    await pumpReaderUntil(tester, find.text('书架还是空的'));
    final theme = Theme.of(tester.element(find.text('书架还是空的')));
    final expected = ColorScheme.fromSeed(
      seedColor: seed!,
      brightness: Brightness.dark,
    );
    expect(theme.colorScheme, expected);
    expect(theme.scaffoldBackgroundColor, expected.surfaceContainerLow);
    expect(nativeCache!['mode'], 'dark');
    final settings = ThemeColorScope.maybeOf(
      tester.element(find.text('书架还是空的')),
    )!;
    await settings.setWallpaperEnabled(false);
    await tester.pumpAndSettle();
    expect(nativeCache!['wallpaperEnabled'], isFalse);
    expect(
      Theme.of(tester.element(find.text('书架还是空的'))).colorScheme,
      AppThemePreset.bambooGreen.dark,
    );
    expect(
      nativeCache!['darkBackground'],
      AppThemePreset.bambooGreen.dark.surfaceContainerLowest.toARGB32(),
    );
    expect(
      (await StartupThemeCache.read())!.preset,
      AppThemePreset.bambooGreen,
    );
    response.complete(seed!.toARGB32());
    await settings.refreshWallpaper();
    await tester.pumpWidget(const SizedBox());
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
    expect(tester.widget<ReaderSwitchListTile>(wallpaper).subtitle, isNull);
    expect(tester.widget<ReaderSwitchListTile>(reader).subtitle, isNull);
    expect(tester.widget<ReaderSectionGroup>(find.byType(ReaderSectionGroup)).footer, isNull);
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
    testWidgets('首屏使用壁纸背景和已保存的${mode.name}主题', (tester) async {
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
      final theme = Theme.of(tester.element(find.text('书架还是空的')));
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      final expected = mode == ThemeMode.dark ? app.darkTheme! : app.theme!;
      expect(theme.brightness, expected.brightness);
      expect(theme.colorScheme, expected.colorScheme);
      expect(theme.scaffoldBackgroundColor, expected.scaffoldBackgroundColor);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
