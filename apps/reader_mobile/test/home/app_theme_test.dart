import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/main.dart';
import 'package:reader_mobile/theme/app_theme.dart';
import 'package:reader_ui/menu/reader_menu_overlay.dart';
import 'package:reader_ui/panels/settings_panel.dart';
import 'package:reader_ui/reader_session.dart';
import 'package:reader_ui/selection/selection_menu.dart';
import 'package:reader_ui/theme/reader_panel_theme.dart';
import 'package:reader_ui/theme/reader_theme.dart';

import '../support/reader_pump.dart';

double _contrast(Color foreground, Color background) {
  final first = foreground.computeLuminance();
  final second = background.computeLuminance();
  return first > second
      ? (first + .05) / (second + .05)
      : (second + .05) / (first + .05);
}

void main() {
  for (final preset in AppThemePreset.presets) {
    for (final brightness in Brightness.values) {
      final theme = buildAppTheme(brightness: brightness, preset: preset);
      final colors = theme.colorScheme;
      final semantics = theme.extension<AppSemanticColors>()!;

      test('${preset.name} $brightness 的正文、操作、选中与语义色满足对比度', () {
        for (final background in [
          colors.surface,
          theme.scaffoldBackgroundColor,
          colors.surfaceContainerLow,
        ]) {
          for (final foreground in [
            colors.onSurface,
            colors.onSurfaceVariant,
            colors.primary,
          ]) {
            expect(
              _contrast(foreground, background),
              greaterThanOrEqualTo(4.5),
            );
          }
          expect(
            _contrast(colors.outline, background),
            greaterThanOrEqualTo(3),
          );
        }
        for (final (foreground, background) in [
          (colors.onPrimary, colors.primary),
          (colors.onPrimaryContainer, colors.primaryContainer),
          (colors.onSecondaryContainer, colors.secondaryContainer),
          (colors.onError, colors.error),
          (colors.onErrorContainer, colors.errorContainer),
          (colors.onInverseSurface, colors.inverseSurface),
          (semantics.onSuccess, semantics.success),
          (semantics.onSuccessContainer, semantics.successContainer),
          (semantics.onWarning, semantics.warning),
          (semantics.onWarningContainer, semantics.warningContainer),
        ]) {
          expect(_contrast(foreground, background), greaterThanOrEqualTo(4.5));
        }
        expect(colors.primary, isNot(colors.onSurface));
        expect(colors.surface, isNot(theme.scaffoldBackgroundColor));
        expect(
          colors.surfaceContainerLow,
          isNot(theme.scaffoldBackgroundColor),
        );
      });
    }
  }

  test('配色预设注册表按标识查找，未知标识安全回退至清蓝', () {
    expect(AppThemePreset.presets.map((p) => p.id), [
      'clear_blue',
      'ink_paper',
      'bamboo_green',
      'warm_amber',
    ]);
    for (final preset in AppThemePreset.presets) {
      expect(AppThemePreset.byId(preset.id), same(preset));
    }
    expect(AppThemePreset.byId(null), same(AppThemePreset.clearBlue));
    expect(AppThemePreset.byId(''), same(AppThemePreset.clearBlue));
    expect(
      AppThemePreset.byId('unknown_future_id'),
      same(AppThemePreset.clearBlue),
    );
  });

  for (final brightness in Brightness.values) {
    final theme = buildAppTheme(brightness: brightness);
    final colors = theme.colorScheme;

    testWidgets('阅读菜单与选区在 $brightness 下使用软件颜色', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Stack(
              children: [
                ReaderMenuOverlay(
                  open: true,
                  theme: ReaderTheme.moss,
                  bookTitle: '颜色回归',
                  progress: .2,
                  chapterLabel: '第一章',
                  onBack: () {},
                  onToggleDayNight: () {},
                  nightMode: brightness == Brightness.dark,
                  onPreviousChapter: null,
                  onNextChapter: () {},
                  onSeek: (_) {},
                  onEntry: (_) {},
                  drawerTitle: '',
                  drawerChild: null,
                  onCloseDrawer: () {},
                ),
                SelectionMenu(
                  actions: [
                    SelectionAction(id: 'copy', label: '复制', onTap: () {}),
                  ],
                  anchor: const Rect.fromLTWH(100, 200, 120, 30),
                  bounds: const Size(800, 600),
                  readerTheme: ReaderTheme.sepia,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final label in ['颜色回归', '复制']) {
        final text = tester.widget<Text>(find.text(label));
        expect(text.style!.color, colors.onSurface);
        expect(Theme.of(tester.element(find.text(label))).colorScheme, colors);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('正文换色后 $brightness 阅读控件保持软件主题并可切换', (tester) async {
      bool? toggled;
      for (final reading in [ReaderTheme.sepia, ReaderTheme.moss]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: ReaderPanelTheme(
              theme: reading,
              child: Scaffold(
                body: SettingsPanel(
                  section: SettingsSection.settings,
                  overrides: ReaderSettingsDefaults.overrides,
                  themeId: reading.id,
                  onOverridesChanged: (_) {},
                  onThemeChanged: (_) {},
                  keepScreenOn: true,
                  onKeepScreenOnChanged: (value) => toggled = value,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          Theme.of(tester.element(find.byType(SettingsPanel))).colorScheme,
          colors,
        );
        final toggle = find.byKey(const ValueKey('settings-keep-screen-on'));
        await tester.ensureVisible(toggle);
        await tester.tap(toggle);
        expect(toggled, isFalse);
        expect(tester.takeException(), isNull);
      }
    });
  }

  test('新增预设可经统一入口控制明暗主题并保留应用字体', () {
    final original = AppThemePreset.clearBlue;
    final preset = AppThemePreset(
      id: '测试预设',
      name: '测试预设',
      light: original.light.copyWith(primary: const Color(0xFF14694E)),
      dark: original.dark.copyWith(primary: const Color(0xFF82CDB3)),
    );
    for (final brightness in Brightness.values) {
      final theme = buildAppTheme(
        brightness: brightness,
        preset: preset,
        fontFamily: '测试应用字体',
      );
      expect(theme.colorScheme, preset.colorsFor(brightness));
      expect(theme.textTheme.bodyMedium!.fontFamily, '测试应用字体');
      expect(
        theme.bottomNavigationBarTheme.selectedItemColor,
        theme.colorScheme.primary,
      );
    }
  });

  testWidgets('ReaderApp 持久化并恢复已选配色方案，切换后立即刷新全局主题', (tester) async {
    final library = LibraryStore.memory();
    await library.setSetting(
      AppThemePreset.settingKey,
      AppThemePreset.warmAmber.id,
    );
    await tester.pumpWidget(
      ReaderApp(library: library, progressStore: MemoryReaderProgressStore()),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await pumpStartupFinished(tester);
    final initialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(initialApp.theme!.colorScheme, AppThemePreset.warmAmber.light);
    expect(initialApp.darkTheme!.colorScheme, AppThemePreset.warmAmber.dark);

    await tester.tap(
      find.descendant(
        of: find.byType(BottomNavigationBar),
        matching: find.text('我的'),
      ),
    );
    await tester.pumpAndSettle();
    final settings = find.byKey(const ValueKey('profile-settings-entry'));
    await tester.ensureVisible(settings);
    await tester.tap(settings);
    await tester.pumpAndSettle();
    final colors = find.byKey(const ValueKey('theme-color-settings-entry'));
    await tester.ensureVisible(colors);
    await tester.tap(colors);
    await tester.pumpAndSettle();
    final presetRow = find.widgetWithText(ListTile, '配色方案');
    Finder presetValue(String label) => find.descendant(
      of: find.byWidget(tester.widget<ListTile>(presetRow).trailing!),
      matching: find.text(label),
    );
    expect(tester.widget<ListTile>(presetRow).subtitle, isNull);
    expect(presetValue(AppThemePreset.warmAmber.name), findsOneWidget);
    await tester.tap(presetRow);
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuItem<AppThemePreset>), findsNWidgets(AppThemePreset.presets.length));
    await tester.tap(find.byKey(const ValueKey('theme-preset-ink_paper')));
    await tester.pumpAndSettle();

    expect(presetValue(AppThemePreset.inkPaper.name), findsOneWidget);
    expect(
      await library.getSetting(AppThemePreset.settingKey),
      AppThemePreset.inkPaper.id,
    );
    final updatedApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(updatedApp.theme!.colorScheme, AppThemePreset.inkPaper.light);
    expect(updatedApp.darkTheme!.colorScheme, AppThemePreset.inkPaper.dark);
    expect(tester.takeException(), isNull);
  });
}
