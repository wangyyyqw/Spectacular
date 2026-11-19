import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/panels/settings_panel.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/theme/reader_panel_theme.dart';
import 'package:reader_ui/theme/reader_frosted_surface.dart';
import 'package:reader_ui/theme/reader_theme.dart';

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
    expect(find.text('选择翻页方式'), findsOneWidget);
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
