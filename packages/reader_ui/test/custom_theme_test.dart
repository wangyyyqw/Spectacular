import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_ui/panels/settings_panel.dart';
import 'package:reader_ui/theme/reader_theme.dart';

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
    await tester.enterText(
      find.byKey(const ValueKey('custom-color-hex')),
      'EEDDBB',
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
}
