import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/font_face.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_ui/panels/settings_panel.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/tap_zones.dart';
import 'package:reader_ui/theme/reader_theme.dart';

void main() {
  testWidgets('设置面板：字号/行高/段距/边距滑块与主题切换（P4-21）', (tester) async {
    final changes = <ReaderOverrides>[];
    final themes = <String>[];
    var reset = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsPanel(
            overrides: ReaderSettingsDefaults.overrides,
            themeId: 'white',
            onOverridesChanged: changes.add,
            onThemeChanged: themes.add,
            onReset: () => reset = true,
          ),
        ),
      ),
    );

    expect(find.text('排版'), findsOneWidget);
    for (final key in <String>[
      'settings-font-size',
      'settings-line-height',
      'settings-paragraph-spacing',
      'settings-padding',
    ]) {
      expect(find.byKey(ValueKey<String>(key)), findsOneWidget, reason: key);
    }
    expect(
      find.text(ReaderSettingsDefaults.fontSize.toStringAsFixed(0)),
      findsWidgets,
    );

    // 拖字号滑块：值变化并回调。
    final slider = find.byKey(const ValueKey<String>('settings-font-size'));
    await tester.drag(slider, const Offset(80, 0));
    await tester.pumpAndSettle();
    expect(changes, isNotEmpty);
    expect(changes.last.fontSize, greaterThan(ReaderSettingsDefaults.fontSize));

    // 点主题块切换。
    await tester.tap(
      find.byKey(const ValueKey<String>('settings-theme-sepia')),
    );
    await tester.pump();
    expect(themes.single, 'sepia');

    // 恢复默认。
    await tester.tap(find.byKey(const ValueKey<String>('settings-reset')));
    await tester.pump();
    expect(reset, isTrue);
    final label = tester.widget<Text>(
      find.byKey(const ValueKey<String>('settings-font-size-value')),
    );
    expect(
      label.data,
      ReaderSettingsDefaults.fontSize.toStringAsFixed(0),
      reason: '恢复默认后面板字号回到默认',
    );
  });

  testWidgets('背景选择：点纸纹回调背景 id（P4-22）', (tester) async {
    final backgrounds = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsPanel(
            section: SettingsSection.theme,
            overrides: ReaderSettingsDefaults.overrides,
            themeId: 'white',
            backgroundId: 'none',
            onOverridesChanged: (_) {},
            onThemeChanged: (_) {},
            onBackgroundChanged: backgrounds.add,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey<String>('settings-bg-wood')));
    await tester.pump();
    expect(backgrounds.single, 'wood');
  });

  testWidgets('墨水屏模式禁用主题与背景选择', (tester) async {
    final themes = <String>[];
    final backgrounds = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsPanel(
            section: SettingsSection.theme,
            overrides: ReaderSettingsDefaults.overrides,
            themeId: 'white',
            backgroundId: 'none',
            inkMode: true,
            onOverridesChanged: (_) {},
            onThemeChanged: themes.add,
            onBackgroundChanged: backgrounds.add,
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey<String>('settings-ink-theme-hint')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey<String>('settings-title')))
          .data,
      '主题',
    );
    for (final key in <String>['settings-theme-black', 'settings-bg-wood']) {
      expect(
        tester.widget<InkWell>(find.byKey(ValueKey<String>(key))).onTap,
        isNull,
      );
    }
    expect(themes, isEmpty);
    expect(backgrounds, isEmpty);
  });

  testWidgets('设置面板可切换正文字体', (tester) async {
    expect(
      FontFamilyAliases.resolve(ReaderSettingsDefaults.fontSans),
      FontFamilyAliases.hei,
      reason: '黑体选项必须命中中文无衬线回退链',
    );
    final changes = <ReaderOverrides>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsPanel(
            section: SettingsSection.type,
            overrides: ReaderSettingsDefaults.overrides,
            themeId: 'white',
            onOverridesChanged: changes.add,
            onThemeChanged: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('settings-font-picker')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('settings-font-song')));
    await tester.pumpAndSettle();

    expect(changes.single.fontFamily, FontFamilyAliases.song);

    await tester.tap(
      find.byKey(const ValueKey<String>('settings-font-picker')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('settings-font-hei')));
    await tester.pumpAndSettle();
    expect(changes.last.fontFamily, ReaderSettingsDefaults.fontSans);
  });

  testWidgets('设置面板支持返回按钮', (tester) async {
    var back = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsPanel(
            overrides: ReaderSettingsDefaults.overrides,
            themeId: ReaderTheme.pink.id,
            onOverridesChanged: (_) {},
            onThemeChanged: (_) {},
            onBack: () => back = true,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey<String>('settings-back')));
    expect(back, isTrue);
    // 当前主题高亮（pink 选中）。
    expect(
      find.byKey(const ValueKey<String>('settings-theme-pink')),
      findsOneWidget,
    );
  });

  testWidgets('设置段可打开九宫格点击区域编辑页', (tester) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsPanel(
            section: SettingsSection.settings,
            overrides: ReaderSettingsDefaults.overrides,
            themeId: 'white',
            onOverridesChanged: (_) {},
            onThemeChanged: (_) {},
            onOpenTapZoneEditor: () => opened = true,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey<String>('settings-tap-zones')));
    expect(opened, isTrue);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey<String>('settings-title')))
          .data,
      '设置',
    );
  });

  testWidgets('设置段可切换翻页方式', (tester) async {
    final changes = <PageTurnMode>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsPanel(
            section: SettingsSection.settings,
            overrides: ReaderSettingsDefaults.overrides,
            themeId: 'white',
            pageTurnMode: PageTurnMode.cover,
            onPageTurnModeChanged: changes.add,
            onOverridesChanged: (_) {},
            onThemeChanged: (_) {},
          ),
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('settings-page-turn-scroll')),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('settings-page-turn-scroll')),
    );
    expect(changes, [PageTurnMode.scroll]);
  });

  testWidgets('设置段可切换全屏点击、屏幕常亮和音量键翻页', (tester) async {
    ReaderTapZones? zones;
    bool? keepScreenOn;
    bool? volumeKeyPaging;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsPanel(
            section: SettingsSection.settings,
            overrides: ReaderSettingsDefaults.overrides,
            themeId: 'white',
            onOverridesChanged: (_) {},
            onThemeChanged: (_) {},
            onTapZonesChanged: (value) => zones = value,
            onKeepScreenOnChanged: (value) => keepScreenOn = value,
            onVolumeKeyPagingChanged: (value) => volumeKeyPaging = value,
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('settings-fullscreen-next')),
    );
    expect(zones, ReaderTapZones.fullScreenNext);
    await tester.tap(
      find.byKey(const ValueKey<String>('settings-keep-screen-on')),
    );
    expect(keepScreenOn, isTrue);
    await tester.tap(
      find.byKey(const ValueKey<String>('settings-volume-key-paging')),
    );
    expect(volumeKeyPaging, isTrue);
  });
}
