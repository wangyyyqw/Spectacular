import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/theme/app_theme.dart';

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
}
