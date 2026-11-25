import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/panels/settings_panel.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/theme/reader_panel_theme.dart';
import 'package:reader_ui/theme/reader_frosted_surface.dart';
import 'package:reader_ui/theme/reader_theme.dart';
import 'package:reader_ui/theme/reader_drawer_style.dart';

void main() {
  testWidgets('阅读面板主题跟随深色阅读主题', (tester) async {
    late ThemeData captured;
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderPanelTheme(
          theme: ReaderTheme.black,
          child: Builder(
            builder: (context) {
              captured = Theme.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(captured.brightness, Brightness.dark);
    expect(captured.colorScheme.surface, ReaderTheme.black.background);
    expect(captured.colorScheme.onSurface, ReaderTheme.black.text);
    expect(captured.iconTheme.color, ReaderTheme.black.text);
  });

  testWidgets('设置面板在深色主题下使用深色背景', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderPanelTheme(
          theme: ReaderTheme.black,
          child: SettingsPanel(
            section: SettingsSection.theme,
            overrides: ReaderSettingsDefaults.overrides,
            themeId: ReaderTheme.black.id,
            onOverridesChanged: (_) {},
            onThemeChanged: (_) {},
          ),
        ),
      ),
    );

    final surface = tester.widget<Material>(
      find.byKey(const ValueKey<String>('settings-panel-surface')),
    );
    expect(surface.color, ReaderTheme.black.background);
    expect(find.text('排版'), findsNothing);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey<String>('settings-title')))
          .data,
      '主题',
    );
  });

  testWidgets('设置段不再重复绘制面板标题', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPanel(
          section: SettingsSection.settings,
          overrides: ReaderSettingsDefaults.overrides,
          themeId: ReaderTheme.white.id,
          pageTurnMode: PageTurnMode.cover,
          onPageTurnModeChanged: (_) {},
          onOverridesChanged: (_) {},
          onThemeChanged: (_) {},
        ),
      ),
    );

    expect(find.text('排版'), findsNothing);
    expect(find.text('翻页方式'), findsOneWidget);
  });

  testWidgets('面板沿用宿主应用字体，语义色不受浅色硬编码影响', (tester) async {
    late ThemeData captured;
    final theme = ReaderTheme.custom(
      background: const Color(0xFFEEE1C8),
      text: const Color(0xFF35291B),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: '应用宋体'),
        home: ReaderPanelTheme(
          theme: theme,
          child: Builder(
            builder: (context) {
              captured = Theme.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    expect(captured.textTheme.bodyMedium?.fontFamily, '应用宋体');
    expect(captured.textTheme.bodySmall?.fontFamily, '应用宋体');
    expect(captured.listTileTheme.titleTextStyle?.fontFamily, '应用宋体');
    expect(ReaderDrawerStyle.surfaceOf(captured), theme.background);
    expect(ReaderDrawerStyle.textOf(captured), theme.text);
    expect(
      ReaderDrawerStyle.secondaryOf(captured),
      captured.colorScheme.onSurfaceVariant,
    );
    expect(
      ReaderDrawerStyle.dividerOf(captured),
      captured.colorScheme.outlineVariant,
    );
    expect(ReaderDrawerStyle.selectedRingOf(captured), theme.text);
  });

  testWidgets('抽屉内容共用凝光底板，设置面板不叠加实色背景', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderFrostedSurface(
          child: SettingsPanel(
            section: SettingsSection.theme,
            overrides: ReaderSettingsDefaults.overrides,
            themeId: ReaderTheme.white.id,
            onOverridesChanged: (_) {},
            onThemeChanged: (_) {},
          ),
        ),
      ),
    );
    expect(
      tester
          .widget<Material>(
            find.byKey(const ValueKey('settings-panel-surface')),
          )
          .color,
      Colors.transparent,
    );
    expect(tester.takeException(), isNull);
  });

  for (final theme in [ReaderTheme.white, ReaderTheme.black]) {
    testWidgets('翻页选项与开关适配${theme.id}主题，控件边缘仍可点击', (tester) async {
      tester.view
        ..physicalSize = const Size(360, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      bool? keepScreenOn;
      PageTurnMode? selectedMode;
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderPanelTheme(
            theme: theme,
            child: Scaffold(
              body: SettingsPanel(
                section: SettingsSection.settings,
                overrides: ReaderSettingsDefaults.overrides,
                themeId: theme.id,
                onOverridesChanged: (_) {},
                onThemeChanged: (_) {},
                pageTurnMode: PageTurnMode.cover,
                onPageTurnModeChanged: (mode) => selectedMode = mode,
                keepScreenOn: true,
                onKeepScreenOnChanged: (value) => keepScreenOn = value,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final settings = find.byType(SettingsPanel);
      final scheme = Theme.of(tester.element(settings)).colorScheme;
      final option = find.byKey(
        ValueKey('settings-page-turn-${PageTurnMode.cover.id}'),
      );
      final optionSurface = tester.widget<Material>(
        find.descendant(of: option, matching: find.byType(Material)),
      );
      expect(optionSurface.color, scheme.primaryContainer);
      expect(tester.getSize(option).height, greaterThanOrEqualTo(44));
      await tester.tap(option);
      expect(selectedMode, PageTurnMode.cover);
      final toggle = find.byKey(const ValueKey('settings-keep-screen-on'));
      final track = tester.widget<AnimatedContainer>(
        find.descendant(of: toggle, matching: find.byType(AnimatedContainer)),
      );
      expect((track.decoration! as BoxDecoration).color, scheme.primary);
      expect(tester.getSize(toggle), const Size(44, 44));
      await tester.tapAt(tester.getCenter(toggle) + const Offset(0, 16));
      expect(keepScreenOn, isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}
