import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/panels/settings_panel.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/theme/reader_panel_theme.dart';
import 'package:reader_ui/theme/reader_frosted_surface.dart';
import 'package:reader_ui/theme/reader_theme.dart';
import 'package:reader_ui/theme/reader_drawer_style.dart';

void main() {
  testWidgets('背景取色覆盖面板并传入弹层，墨水模式保持单色', (tester) async {
    const ink = ReaderTheme(
      id: 'ink',
      name: '墨水',
      background: Colors.white,
      text: Colors.black,
    );
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFFBF9C62));
    late ThemeData captured;
    Widget content(ReaderTheme theme) => ReaderPanelTheme(
      theme: theme,
      child: Builder(
        builder: (context) {
          captured = Theme.of(context);
          return TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => ReaderPanelTheme(
                theme: theme,
                child: Builder(
                  builder: (context) {
                    captured = Theme.of(context);
                    return const AlertDialog(content: Text('取色弹层'));
                  },
                ),
              ),
            ),
            child: const Text('打开弹层'),
          );
        },
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderPanelColorScope(
          scheme: scheme,
          child: content(ReaderTheme.white),
        ),
      ),
    );
    expect(captured.colorScheme, scheme);
    expect(captured.dialogTheme.backgroundColor, scheme.surface);
    expect(
      captured.filledButtonTheme.style!.backgroundColor!.resolve({}),
      scheme.primary,
    );
    await tester.tap(find.text('打开弹层'));
    await tester.pumpAndSettle();
    expect(captured.colorScheme, scheme);
    expect(find.text('取色弹层'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderPanelColorScope(scheme: scheme, child: content(ink)),
      ),
    );
    expect(captured.colorScheme.primary, ink.text);
    expect(captured.colorScheme.surface, ink.background);
  });

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
    expect(
      (captured.dialogTheme.shape as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(24),
    );
    expect(
      (captured.popupMenuTheme.shape as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(16),
    );
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
}
