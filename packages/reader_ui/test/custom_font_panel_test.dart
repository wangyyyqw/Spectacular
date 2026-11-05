import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_ui/panels/settings_panel.dart';
import 'package:reader_ui/theme/reader_panel_theme.dart';
import 'package:reader_ui/theme/reader_theme.dart';

const _font = ReaderFontOption(family: 'user_test', label: '测试字体');
const _otherFont = ReaderFontOption(family: 'user_other', label: '另一字体');
const _importKey = ValueKey<String>('settings-import-font');
const _dropdownKey = ValueKey<String>('settings-custom-font');
const _switchKey = ValueKey<String>('settings-override-embedded-fonts');

Widget _panel({
  ReaderOverrides overrides = ReaderSettingsDefaults.overrides,
  List<ReaderFontOption> fonts = const [],
  Future<ReaderFontOption?> Function()? pick,
  Future<void> Function(String family)? load,
  required ValueChanged<ReaderOverrides> onChanged,
}) => MaterialApp(
  home: Scaffold(
    body: SettingsPanel(
      section: SettingsSection.type,
      overrides: overrides,
      themeId: 'white',
      customFonts: fonts,
      onPickFont: pick,
      onLoadFont: load,
      onOverridesChanged: onChanged,
      onThemeChanged: (_) {},
    ),
  ),
);

void main() {
  testWidgets('五套主题中的自定义字体提示、开关和字体名称保持可读', (tester) async {
    for (final theme in ReaderTheme.themes) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReaderPanelTheme(
              theme: theme,
              child: SettingsPanel(
                key: ValueKey(theme.id),
                section: SettingsSection.type,
                overrides: const ReaderOverrides(),
                themeId: theme.id,
                customFonts: const [_font],
                onOverridesChanged: (_) {},
                onThemeChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final text in ['自定义字体', '全书使用自定义字体', '选择自定义字体后可开启']) {
        final label = find.text(text).first;
        final widget = tester.widget<Text>(label);
        final color = DefaultTextStyle.of(tester.element(label)).style
            .merge(widget.style)
            .color!;
        final ink = Color.alphaBlend(
          color,
          theme.background,
        ).computeLuminance();
        final paper = theme.background.computeLuminance();
        final contrast = ink > paper
            ? (ink + .05) / (paper + .05)
            : (paper + .05) / (ink + .05);
        expect(
          contrast,
          greaterThanOrEqualTo(4.5),
          reason: '${theme.id}:$text',
        );
      }
      await tester.tap(find.byKey(_dropdownKey));
      await tester.pumpAndSettle();
      expect(find.text(_font.label).last, findsOneWidget);
      expect(
        tester.widget<Text>(find.text(_font.label).last).style!.color,
        theme.text,
      );
      await tester.tap(find.text(_font.label).last);
      await tester.pumpAndSettle();
    }
  });
  testWidgets('已保存字体加载成功后才应用，加载失败保留旧选择', (tester) async {
    final changes = <ReaderOverrides>[];
    final pending = Completer<void>();
    final requested = <String>[];
    await tester.pumpWidget(
      _panel(
        fonts: const [_font, _otherFont],
        load: (family) async {
          requested.add(family);
          if (family == _font.family) return pending.future;
          throw const FormatException('字体文件无法读取');
        },
        onChanged: changes.add,
      ),
    );
    await tester.tap(find.byKey(_dropdownKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_font.label).last);
    await tester.pump();
    expect(requested.single, _font.family);
    expect(changes, isEmpty);
    expect(
      tester.widget<DropdownButton<String>>(find.byKey(_dropdownKey)).onChanged,
      isNull,
    );
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey<String>('settings-font-song')),
          )
          .onSelected,
      isNull,
    );
    pending.complete();
    await tester.pumpAndSettle();
    expect(changes.single.fontFamily, _font.family);

    await tester.tap(find.byKey(_dropdownKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_otherFont.label).last);
    await tester.pumpAndSettle();
    expect(requested, [_font.family, _otherFont.family]);
    expect(changes.length, 1);
    expect(
      tester.widget<DropdownButton<String>>(find.byKey(_dropdownKey)).value,
      _font.family,
    );
    expect(find.text('字体加载失败：字体文件无法读取'), findsOneWidget);
  });

  testWidgets('导入字体后默认保留内嵌字体，开关覆盖全书并可关闭', (tester) async {
    final changes = <ReaderOverrides>[];
    await tester.pumpWidget(
      _panel(pick: () async => _font, onChanged: changes.add),
    );
    expect(
      tester.widget<SwitchListTile>(find.byKey(_switchKey)).onChanged,
      isNull,
    );
    await tester.tap(find.byKey(_importKey));
    await tester.pumpAndSettle();
    expect(changes.single.fontFamily, _font.family);
    expect(changes.single.overrideEmbeddedFonts, isFalse);
    expect(
      tester.widget<DropdownButton<String>>(find.byKey(_dropdownKey)).value,
      _font.family,
    );

    await tester.tap(find.byKey(_switchKey));
    await tester.pumpAndSettle();
    expect(changes.last.overrideEmbeddedFonts, isTrue);
    await tester.tap(find.byKey(_switchKey));
    await tester.pumpAndSettle();
    expect(changes.last.overrideEmbeddedFonts, isFalse);
  });

  testWidgets('已导入字体可选择，更换自定义字体保留覆盖开关', (tester) async {
    final changes = <ReaderOverrides>[];
    await tester.pumpWidget(
      _panel(
        overrides: const ReaderOverrides(
          fontFamily: 'user_test',
          overrideEmbeddedFonts: true,
        ),
        fonts: const [_font, _otherFont],
        onChanged: changes.add,
      ),
    );
    await tester.tap(find.byKey(_dropdownKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_otherFont.label).last);
    await tester.pumpAndSettle();
    expect(changes.single.fontFamily, _otherFont.family);
    expect(changes.single.overrideEmbeddedFonts, isTrue);

    await tester.tap(find.byKey(const ValueKey<String>('settings-font-song')));
    await tester.pumpAndSettle();
    expect(changes.last.overrideEmbeddedFonts, isFalse);
    expect(
      tester.widget<SwitchListTile>(find.byKey(_switchKey)).onChanged,
      isNull,
    );
  });

  testWidgets('导入等待期间禁用重复操作，取消保持原设置', (tester) async {
    final changes = <ReaderOverrides>[];
    final pending = Completer<ReaderFontOption?>();
    var calls = 0;
    await tester.pumpWidget(
      _panel(
        pick: () {
          calls++;
          return pending.future;
        },
        onChanged: changes.add,
      ),
    );
    await tester.tap(find.byKey(_importKey));
    await tester.pump();
    expect(tester.widget<TextButton>(find.byKey(_importKey)).onPressed, isNull);
    expect(calls, 1);
    pending.complete(null);
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
    expect(
      tester.widget<TextButton>(find.byKey(_importKey)).onPressed,
      isNotNull,
    );
  });

  testWidgets('无效文件显示中文提示且可重新导入', (tester) async {
    final changes = <ReaderOverrides>[];
    var invalid = true;
    await tester.pumpWidget(
      _panel(
        pick: () async {
          if (invalid) throw const FormatException('文件不是有效字体');
          return _font;
        },
        onChanged: changes.add,
      ),
    );
    await tester.tap(find.byKey(_importKey));
    await tester.pumpAndSettle();
    expect(find.text('字体导入失败：文件不是有效字体'), findsOneWidget);
    expect(changes, isEmpty);
    invalid = false;
    await tester.tap(find.byKey(_importKey));
    await tester.pumpAndSettle();
    expect(changes.single.fontFamily, _font.family);
  });

  testWidgets('重复导入去重，外部设置恢复与面板保持一致', (tester) async {
    final changes = <ReaderOverrides>[];
    await tester.pumpWidget(
      _panel(
        overrides: const ReaderOverrides(
          fontFamily: 'user_test',
          overrideEmbeddedFonts: true,
        ),
        fonts: const [_font],
        pick: () async => _font,
        onChanged: changes.add,
      ),
    );
    await tester.tap(find.byKey(_importKey));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DropdownButton<String>>(find.byKey(_dropdownKey))
          .items!
          .length,
      1,
    );
    expect(changes, isEmpty);
    await tester.pumpWidget(
      _panel(fonts: const [_font], onChanged: changes.add),
    );
    expect(
      tester.widget<DropdownButton<String>>(find.byKey(_dropdownKey)).value,
      isNull,
    );
    expect(
      tester.widget<SwitchListTile>(find.byKey(_switchKey)).value,
      isFalse,
    );
  });
}
