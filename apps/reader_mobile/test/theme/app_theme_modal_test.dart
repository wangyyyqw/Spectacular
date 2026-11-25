import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/theme/app_theme.dart';
import 'package:reader_mobile/home/discover_choice_dialog.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';

void main() {
  test('日间和夜间主题使用一致的弹层几何与间距', () {
    for (final brightness in Brightness.values) {
      final theme = buildAppTheme(brightness: brightness);
      final dialogShape = theme.dialogTheme.shape! as RoundedRectangleBorder;
      final sheetShape =
          theme.bottomSheetTheme.shape! as RoundedRectangleBorder;
      final menuShape = theme.popupMenuTheme.shape! as RoundedRectangleBorder;

      expect(dialogShape.borderRadius, BorderRadius.circular(24));
      expect(
        sheetShape.borderRadius,
        const BorderRadius.vertical(top: Radius.circular(24)),
      );
      expect(menuShape.borderRadius, BorderRadius.circular(16));
      expect(
        theme.dialogTheme.insetPadding,
        const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      );
      expect(theme.bottomSheetTheme.constraints?.maxWidth, 680);
    }
  });

  test('Material 3 样式切换框架控件并保留应用颜色体系', () {
    final classic = buildAppTheme(uiStyle: AppUiStyle.classic);
    final material3 = buildAppTheme(uiStyle: AppUiStyle.material3);

    expect(classic.useMaterial3, isFalse);
    expect(material3.useMaterial3, isTrue);
    expect(material3.colorScheme, classic.colorScheme);
    expect(
      (material3.cardTheme.shape! as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(12),
    );
    expect(
      (classic.cardTheme.shape! as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(4),
    );
    expect(material3.inputDecorationTheme.border, isA<OutlineInputBorder>());
    expect(
      (material3.inputDecorationTheme.border! as OutlineInputBorder)
          .borderRadius,
      BorderRadius.circular(12),
    );
  });

  for (final style in AppUiStyle.values) {
    for (final brightness in Brightness.values) {
      for (final dynamicColor in [false, true]) {
        testWidgets(
          '${style.name}/${brightness.name}/取色$dynamicColor 输入、按钮和选择状态保持语义与几何',
          (tester) async {
            final theme = buildAppTheme(
              uiStyle: style,
              brightness: brightness,
              colorScheme: dynamicColor
                  ? ColorScheme.fromSeed(
                      seedColor: Colors.purple,
                      brightness: brightness,
                    )
                  : null,
            );
            final colors = theme.colorScheme;
            final md3 = style == AppUiStyle.material3;
            await tester.pumpWidget(
              MaterialApp(
                theme: theme,
                home: Scaffold(
                  body: SingleChildScrollView(
                    child: Column(
                      children: [
                        const TextField(
                          key: ValueKey('正常输入'),
                          decoration: InputDecoration(labelText: '名称'),
                        ),
                        const TextField(
                          key: ValueKey('错误输入'),
                          decoration: InputDecoration(errorText: '请输入名称'),
                        ),
                        const TextField(key: ValueKey('禁用输入'), enabled: false),
                        FilledButton(onPressed: () {}, child: const Text('填充')),
                        ElevatedButton(
                          onPressed: () {},
                          child: const Text('浮起'),
                        ),
                        const FilledButton(onPressed: null, child: Text('禁用')),
                        const Card(child: Text('卡片')),
                        const ListTile(selected: true, title: Text('选中行')),
                        ChoiceChip(
                          label: const Text('标签'),
                          selected: true,
                          onSelected: (_) {},
                        ),
                        SegmentedButton<int>(
                          segments: const [
                            ButtonSegment(value: 1, label: Text('选中')),
                            ButtonSegment(value: 2, label: Text('其他')),
                          ],
                          selected: const {1},
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            InputDecorator input(String key) => tester.widget<InputDecorator>(
              find.descendant(
                of: find.byKey(ValueKey(key)),
                matching: find.byType(InputDecorator),
              ),
            );
            for (final key in ['正常输入', '错误输入', '禁用输入']) {
              final decoration = input(key).decoration;
              for (final border in [
                decoration.enabledBorder,
                decoration.focusedBorder,
                decoration.disabledBorder,
                decoration.errorBorder,
                decoration.focusedErrorBorder,
              ]) {
                expect(
                  (border! as OutlineInputBorder).borderRadius,
                  BorderRadius.circular(md3 ? 12 : 4),
                );
              }
            }
            await tester.tap(find.byKey(const ValueKey('正常输入')));
            await tester.pumpAndSettle();
            expect(input('正常输入').isFocused, isTrue);
            final focusBorder =
                input('正常输入').decoration.focusedBorder! as OutlineInputBorder;
            expect(focusBorder.borderSide.color, colors.primary);
            expect(focusBorder.borderSide.width, md3 ? 2 : 1);
            expect(input('错误输入').decoration.errorText, '请输入名称');
            expect(input('禁用输入').decoration.enabled, isFalse);

            final filled = theme.filledButtonTheme.style!;
            expect(filled.foregroundColor!.resolve({}), colors.onPrimary);
            expect(
              filled.foregroundColor!.resolve({WidgetState.disabled}),
              colors.onSurface.withValues(alpha: .38),
            );
            expect(
              theme.elevatedButtonTheme.style!.backgroundColor!.resolve({}),
              md3 ? colors.surfaceContainerLow : colors.primary,
            );
            expect(
              (filled.shape!.resolve({})! as RoundedRectangleBorder)
                  .borderRadius,
              BorderRadius.circular(md3 ? 20 : 4),
            );
            expect(filled.textStyle!.resolve({})!.fontSize, 14);
            expect(
              theme.listTileTheme.selectedColor,
              colors.onPrimaryContainer,
            );
            expect(
              WidgetStateProperty.resolveAs<Color>(
                theme.chipTheme.labelStyle!.color!,
                {WidgetState.selected},
              ),
              colors.onPrimaryContainer,
            );
            expect(
              theme.menuButtonTheme.style!.foregroundColor!.resolve({
                WidgetState.disabled,
              }),
              colors.onSurface.withValues(alpha: .38),
            );
            expect(
              theme.segmentedButtonTheme.style!.foregroundColor!.resolve({
                WidgetState.selected,
              }),
              colors.onSecondaryContainer,
            );
            expect(
              theme.checkboxTheme.checkColor!.resolve({
                WidgetState.error,
                WidgetState.selected,
              }),
              colors.onError,
            );
            expect(
              theme.switchTheme.trackColor!.resolve({
                WidgetState.disabled,
                WidgetState.selected,
              }),
              colors.onSurface.withValues(alpha: .12),
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    testWidgets('${style.name} 发现筛选项选中配色与点击结果完整', (tester) async {
      final scheme = ColorScheme.fromSeed(
        seedColor: Colors.teal,
        brightness: Brightness.dark,
      );
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(uiStyle: style, colorScheme: scheme),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showReaderDialog<String>(
                    context: context,
                    builder: (_) => DiscoverChoiceDialog<String>(
                      title: '分类',
                      options: const ['文学', '历史'],
                      labelFor: (value) => value,
                      selected: '文学',
                    ),
                  );
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      final selected = find.byKey(const ValueKey('discover-choice-文学'));
      final container = tester.widget<Container>(
        find.descendant(of: selected, matching: find.byType(Container)).first,
      );
      expect(
        (container.decoration! as BoxDecoration).color,
        scheme.primaryContainer,
      );
      expect(
        tester.widget<Text>(find.text('文学')).style!.color,
        scheme.onPrimaryContainer,
      );
      await tester.tap(find.byKey(const ValueKey('discover-choice-历史')));
      await tester.pumpAndSettle();
      expect(result, '历史');
      expect(tester.takeException(), isNull);
    });
  }
}
