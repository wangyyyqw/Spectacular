import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_ui/annotations/annotation_layer.dart';
import 'package:reader_ui/panels/settings_panel.dart';
import 'package:reader_ui/selection/selection_layer.dart';
import 'package:reader_ui/theme/reader_environment.dart';
import 'package:reader_ui/theme/reader_theme.dart';

void main() {
  group('墨水屏模式（P4-23，§42.2）', () {
    test('墨水屏主题是纯黑白且对比度满足 WCAG AAA', () {
      final ink = ReaderEnvironment.inkTheme;
      expect(ink.background, const Color(0xFFFFFFFF));
      expect(ink.text, const Color(0xFF000000));
      expect(ink.luminance, greaterThanOrEqualTo(7.0), reason: 'WCAG AAA ≥ 7:1');
      expect(ink.luminance, greaterThanOrEqualTo(20.0), reason: '纯黑白约 21:1');
    });

    test('墨水屏强制覆盖用户主题，且禁用背景纹理', () {
      const env = ReaderEnvironment(isEink: true);
      expect(env.resolveTheme(ReaderTheme.dark).id, 'ink');
      expect(env.allowsBackgroundImage, isFalse);
      const normal = ReaderEnvironment();
      expect(normal.resolveTheme(ReaderTheme.dark).id, 'dark');
      expect(normal.allowsBackgroundImage, isTrue);
    });

    test('墨水屏笔记圆点改为黑色，普通模式保留标记色', () {
      const marker = Color(0xFFFFC107);
      expect(
        AnnotationLayer.markerColor(inkMode: true, color: marker),
        const Color(0xFF000000),
      );
      expect(
        AnnotationLayer.markerColor(inkMode: false, color: marker),
        marker,
      );
    });

    test('墨水屏选区与手柄改为黑色，普通模式保留原色', () {
      const color = Color(0x4D5B8DEF);
      expect(
        SelectionLayer.resolveColor(inkMode: true, color: color),
        const Color(0xFF000000),
      );
      expect(
        SelectionLayer.resolveColor(inkMode: false, color: color),
        color,
      );
    });

    testWidgets('设置面板墨水屏开关触发回调', (tester) async {
      final values = <bool>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsPanel(
              overrides: ReaderSettingsDefaults.overrides,
              themeId: 'white',
              backgroundId: 'paper',
              inkMode: false,
              onOverridesChanged: (_) {},
              onThemeChanged: (_) {},
              onBackgroundChanged: (_) {},
              onInkModeChanged: values.add,
            ),
          ),
        ),
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey<String>('settings-ink-mode')),
        120,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.byKey(const ValueKey<String>('settings-ink-mode')));
      await tester.pump();
      expect(values, <bool>[true]);
    });
  });
}
