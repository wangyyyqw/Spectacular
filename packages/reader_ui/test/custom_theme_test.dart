import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_ui/panels/settings_panel.dart';
import 'package:reader_ui/theme/reader_theme.dart';
import 'package:reader_ui/theme/reader_sheet_form.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';
import 'package:reader_ui/panels/custom_theme_dialog.dart';

Widget _panel(
  List<String> changes, {
  ReaderTheme? custom,
  Brightness brightness = Brightness.light,
}) => MaterialApp(
  theme: ThemeData(brightness: brightness),
  home: Scaffold(
    body: SettingsPanel(
      section: SettingsSection.theme,
      overrides: const ReaderOverrides(),
      themeId: 'white',
      customTheme: custom,
      onOverridesChanged: (_) {},
      onThemeChanged: changes.add,
    ),
  ),
);

void main() {
  testWidgets('自定义色块同样按日夜模式显示，另一模式保留新建入口', (tester) async {
    final custom = ReaderTheme.custom(
      background: Colors.black,
      text: Colors.white,
    );
    final changes = <String>[];
    await tester.pumpWidget(_panel(changes, custom: custom));
    expect(find.byKey(const ValueKey('settings-theme-custom')), findsNothing);
    expect(
      find.byKey(const ValueKey('settings-custom-theme-picker')),
      findsOneWidget,
    );
    await tester.pumpWidget(
      _panel(changes, custom: custom, brightness: Brightness.dark),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-theme-custom')));
    expect(changes, [custom.id]);
  });

  test('自定义配色按 RGB 往返，非法值安全回退', () {
    final theme = ReaderTheme.custom(
      background: const Color(0x77EEDDBB),
      text: const Color(0xFF123456),
    );
    expect(theme.id, 'custom:eeddbb:123456');
    expect(ReaderTheme.byId(theme.id).background, const Color(0xFFEEDDBB));
    expect(ReaderTheme.byId(theme.id).text, const Color(0xFF123456));
    for (final id in [
      'custom:bad:123456',
      'custom:000000:ffffff:extra',
      'custom:zzzzzz:ffffff',
    ]) {
      expect(ReaderTheme.customById(id), isNull);
      expect(ReaderTheme.byId(id), same(ReaderTheme.white));
    }
    expect(
      theme.toOverrides().fingerprint,
      ReaderTheme.white.toOverrides().fingerprint,
    );
  });

  testWidgets('自定义草稿取消不应用，保存颜色可再次选择', (tester) async {
    final changes = <String>[];
    await tester.pumpWidget(_panel(changes));
    await tester.tap(find.byKey(const ValueKey('settings-custom-theme-edit')));
    await tester.pumpAndSettle();
    expect(find.byType(ReaderSheetForm), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('custom-color-hex')),
      'EEDDBB',
    );
    await tester.pump();
    final preview = tester.widget<Container>(
      find.byKey(const ValueKey('custom-theme-preview')),
    );
    expect(
      (preview.decoration! as BoxDecoration).color,
      const Color(0xFFEEDDBB),
    );
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
    await tester.tap(find.byKey(const ValueKey('settings-custom-theme-edit')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('custom-color-hex')),
      'EE',
    );
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('custom-theme-save')))
          .onPressed,
      isNull,
    );
    await tester.enterText(
      find.byKey(const ValueKey('custom-color-hex')),
      'EEDDBB',
    );
    await tester.tap(find.text('文字色'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('custom-color-hex')),
      '223344',
    );
    await tester.tap(find.byKey(const ValueKey('custom-theme-save')));
    await tester.pumpAndSettle();
    expect(changes.single, 'custom:eeddbb:223344');
    final custom = ReaderTheme.byId(changes.single);
    await tester.pumpWidget(_panel(changes, custom: custom));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-theme-custom')));
    expect(changes.last, custom.id);
    expect(tester.takeException(), isNull);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets('${platform.name}窄屏大字号键盘下可调整 RGB 并保存配色', (tester) async {
      await tester.binding.setSurfaceSize(const Size(280, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 200);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      ReaderTheme? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: platform),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(2.4)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showReaderDrawer<ReaderTheme>(
                    context: context,
                    builder: (_) =>
                        const CustomThemeDialog(theme: ReaderTheme.white),
                  );
                },
                child: const Text('编辑主题'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('编辑主题'));
      await tester.pumpAndSettle();
      final slider = tester.widget<Slider>(
        find.byKey(const ValueKey('custom-color-红')),
      );
      slider.onChanged!(128);
      await tester.pump();
      final field = find.byKey(const ValueKey('custom-color-hex'));
      await tester.ensureVisible(field);
      await tester.enterText(field, 'AABBCC');
      await tester.pump();
      final save = find.byKey(const ValueKey('custom-theme-save'));
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      expect(tester.getRect(save).bottom, lessThanOrEqualTo(280));
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(result?.background, const Color(0xFFAABBCC));
      expect(result?.text, ReaderTheme.white.text);
      expect(tester.takeException(), isNull);
    });
  }
}
