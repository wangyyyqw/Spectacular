import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_ui/panels/settings_panel.dart';
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
    expect(find.text(ReaderSettingsDefaults.fontSize.toStringAsFixed(0)),
        findsWidgets);

    // 拖字号滑块：值变化并回调。
    final slider = find.byKey(const ValueKey<String>('settings-font-size'));
    await tester.drag(slider, const Offset(80, 0));
    await tester.pumpAndSettle();
    expect(changes, isNotEmpty);
    expect(changes.last.fontSize, greaterThan(ReaderSettingsDefaults.fontSize));

    // 点主题块切换。
    await tester.tap(find.byKey(const ValueKey<String>('settings-theme-sepia')));
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
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('settings-bg-wood')),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const ValueKey<String>('settings-bg-wood')));
    await tester.pump();
    expect(backgrounds.single, 'wood');
  });

  testWidgets('设置面板支持返回按钮', (tester) async {
    var back = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsPanel(
            overrides: ReaderSettingsDefaults.overrides,
            themeId: ReaderTheme.gray.id,
            onOverridesChanged: (_) {},
            onThemeChanged: (_) {},
            onBack: () => back = true,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey<String>('settings-back')));
    expect(back, isTrue);
    // 当前主题高亮（gray 选中）。
    expect(
      find.byKey(const ValueKey<String>('settings-theme-gray')),
      findsOneWidget,
    );
  });
}
