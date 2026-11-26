import 'package:flutter/material.dart';

/// 首页、阅读菜单与编辑表单共用的控件和表面规范。
abstract final class ReaderUiStyle {
  static const controlCorner = 12.0;
  static const cardCorner = 20.0;
  static const panelCorner = 24.0;
  static const controlRadius = BorderRadius.all(Radius.circular(controlCorner));
  static const cardRadius = BorderRadius.all(Radius.circular(cardCorner));
  static const panelRadius = BorderRadius.all(Radius.circular(panelCorner));
  static const sheetRadius = BorderRadius.vertical(
    top: Radius.circular(panelCorner),
  );
  static const controlShape = RoundedRectangleBorder(
    borderRadius: controlRadius,
  );
  static const cardShape = RoundedRectangleBorder(borderRadius: cardRadius);
  static const panelShape = RoundedRectangleBorder(borderRadius: panelRadius);
  static const controlSize = Size(44, 44);
  static const controlPadding = EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 10,
  );

  /// 页面内容统一水平内边距与标准表单间距。
  static const pagePadding = EdgeInsets.fromLTRB(16, 12, 16, 24);
  static const sheetContentPadding = EdgeInsets.fromLTRB(20, 14, 20, 16);
  static const dialogContentPadding = EdgeInsets.fromLTRB(24, 12, 24, 16);
  static const dialogActionsPadding = EdgeInsets.fromLTRB(20, 4, 20, 16);
  static const double sheetDragHandleHeight = 28;
  static const double settingsSheetHeightFraction = 0.64;

  static ShapeBorder cardShapeOf(ThemeData theme) =>
      theme.cardTheme.shape ??
      cardShape.copyWith(
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      );

  static BoxDecoration cardDecorationOf(ThemeData theme) => BoxDecoration(
    color: theme.colorScheme.surface,
    borderRadius: cardRadius,
    border: Border.all(color: theme.colorScheme.outlineVariant),
  );

  /// 危险操作主按钮样式，供所有删除/清空确认框统一复用。
  static ButtonStyle destructiveFilledButtonOf(ThemeData theme) {
    final colors = theme.colorScheme;
    return FilledButton.styleFrom(
      backgroundColor: colors.error,
      foregroundColor: colors.onError,
      textStyle: theme.textTheme.labelLarge,
      shape: controlShape,
      padding: controlPadding,
      minimumSize: controlSize,
      elevation: 0,
    );
  }
}

/// 使用当前软件主题的语义色与字体统一界面外观。
ThemeData applyReaderUiStyle(ThemeData base) {
  final surfaces = _surfaces(_overlays(base));
  final actions = _actions(surfaces);
  final inputs = _inputs(actions);
  return _feedback(_selections(inputs));
}

ThemeData _surfaces(ThemeData base) {
  final colors = base.colorScheme;
  final card = ReaderUiStyle.cardShape.copyWith(
    side: BorderSide(color: colors.outlineVariant),
  );
  return base.copyWith(
    dividerTheme: base.dividerTheme.copyWith(
      color: colors.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    cardTheme: base.cardTheme.copyWith(
      color: colors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: card,
    ),
    popupMenuTheme: base.popupMenuTheme.copyWith(
      color: colors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      shape: ReaderUiStyle.controlShape.copyWith(
        side: BorderSide(color: colors.outlineVariant),
      ),
      textStyle: base.textTheme.bodyMedium,
    ),
    progressIndicatorTheme: base.progressIndicatorTheme.copyWith(
      color: colors.primary,
      linearTrackColor: colors.surfaceContainerHighest,
      circularTrackColor: colors.surfaceContainerHighest,
      linearMinHeight: 3,
    ),
  );
}

ThemeData _overlays(ThemeData base) {
  final colors = base.colorScheme;
  return base.copyWith(
    dialogTheme: base.dialogTheme.copyWith(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: colors.onSurface,
      ),
      contentTextStyle: base.textTheme.bodyMedium?.copyWith(
        height: 1.5,
        color: colors.onSurfaceVariant,
      ),
      shape: ReaderUiStyle.panelShape.copyWith(
        side: BorderSide(color: colors.outlineVariant),
      ),
      actionsPadding: ReaderUiStyle.dialogActionsPadding,
    ),
    bottomSheetTheme: base.bottomSheetTheme.copyWith(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: ReaderUiStyle.sheetRadius,
      ),
    ),
  );
}

ThemeData _actions(ThemeData base) {
  final colors = base.colorScheme;
  final filled = _filledStyle(base);
  return base.copyWith(
    filledButtonTheme: FilledButtonThemeData(style: filled),
    elevatedButtonTheme: ElevatedButtonThemeData(style: filled),
    outlinedButtonTheme: OutlinedButtonThemeData(style: _outlinedStyle(base)),
    textButtonTheme: TextButtonThemeData(style: _textStyle(base)),
    floatingActionButtonTheme: base.floatingActionButtonTheme.copyWith(
      backgroundColor: colors.primary,
      foregroundColor: colors.onPrimary,
      elevation: 0,
      shape: ReaderUiStyle.controlShape,
    ),
  );
}

ButtonStyle _filledStyle(ThemeData base) {
  final colors = base.colorScheme;
  return FilledButton.styleFrom(
    backgroundColor: colors.primary,
    foregroundColor: colors.onPrimary,
    disabledBackgroundColor: colors.onSurface.withValues(alpha: .12),
    disabledForegroundColor: colors.onSurface.withValues(alpha: .38),
    textStyle: base.textTheme.labelLarge,
    shape: ReaderUiStyle.controlShape,
    padding: ReaderUiStyle.controlPadding,
    minimumSize: ReaderUiStyle.controlSize,
    elevation: 0,
  );
}

ButtonStyle _outlinedStyle(ThemeData base) => OutlinedButton.styleFrom(
  foregroundColor: base.colorScheme.primary,
  disabledForegroundColor: base.colorScheme.onSurface.withValues(alpha: .38),
  textStyle: base.textTheme.labelLarge,
  shape: ReaderUiStyle.controlShape,
  padding: ReaderUiStyle.controlPadding,
  side: BorderSide(color: base.colorScheme.outlineVariant),
  minimumSize: ReaderUiStyle.controlSize,
);

ButtonStyle _textStyle(ThemeData base) => TextButton.styleFrom(
  foregroundColor: base.colorScheme.primary,
  textStyle: base.textTheme.labelLarge,
  shape: ReaderUiStyle.controlShape,
  padding: ReaderUiStyle.controlPadding,
  minimumSize: ReaderUiStyle.controlSize,
);

ThemeData _inputs(ThemeData base) {
  final colors = base.colorScheme;
  return base.copyWith(
    inputDecorationTheme: _inputDecoration(base),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: colors.primary,
      selectionColor: colors.primary.withValues(alpha: .20),
      selectionHandleColor: colors.primary,
    ),
    listTileTheme: base.listTileTheme.copyWith(
      iconColor: colors.onSurfaceVariant,
      textColor: colors.onSurface,
      selectedColor: colors.onPrimaryContainer,
      selectedTileColor: colors.primaryContainer,
      titleTextStyle: base.textTheme.bodyMedium,
      subtitleTextStyle: base.textTheme.bodySmall,
      shape: ReaderUiStyle.controlShape,
    ),
  );
}

InputDecorationThemeData _inputDecoration(ThemeData base) {
  final colors = base.colorScheme;
  final border = OutlineInputBorder(
    borderRadius: ReaderUiStyle.controlRadius,
    borderSide: BorderSide(color: colors.outlineVariant),
  );
  return base.inputDecorationTheme.copyWith(
    filled: true,
    fillColor: colors.surfaceContainerLow,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    hintStyle: base.textTheme.bodyMedium?.copyWith(
      color: colors.onSurfaceVariant,
    ),
    labelStyle: base.textTheme.bodyMedium,
    border: border,
    enabledBorder: border,
    disabledBorder: border,
    focusedBorder: border.copyWith(
      borderSide: BorderSide(color: colors.primary, width: 2),
    ),
    errorBorder: border.copyWith(borderSide: BorderSide(color: colors.error)),
    focusedErrorBorder: border.copyWith(
      borderSide: BorderSide(color: colors.error),
    ),
  );
}

Color _selectionColor(ColorScheme colors, Set<WidgetState> states) {
  if (states.contains(WidgetState.disabled)) {
    return colors.onSurface.withValues(alpha: .38);
  }
  if (states.contains(WidgetState.error)) return colors.error;
  return states.contains(WidgetState.selected)
      ? colors.primary
      : colors.onSurfaceVariant;
}

ThemeData _selections(ThemeData base) {
  final colors = base.colorScheme;
  final selection = WidgetStateProperty.resolveWith<Color>(
    (states) => _selectionColor(colors, states),
  );
  return base.copyWith(
    radioTheme: base.radioTheme.copyWith(fillColor: selection),
    checkboxTheme: _checkboxTheme(base),
    switchTheme: _switchTheme(base),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: colors.primary,
      inactiveTrackColor: colors.outlineVariant,
      thumbColor: colors.primary,
      overlayColor: colors.primary.withValues(alpha: .12),
      valueIndicatorColor: colors.inverseSurface,
      valueIndicatorTextStyle: base.textTheme.bodySmall?.copyWith(
        color: colors.onInverseSurface,
      ),
    ),
    chipTheme: _chips(base),
  );
}

CheckboxThemeData _checkboxTheme(ThemeData base) {
  final colors = base.colorScheme;
  return base.checkboxTheme.copyWith(
    fillColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.selected)
          ? _selectionColor(colors, states)
          : Colors.transparent,
    ),
    checkColor: WidgetStatePropertyAll(colors.onPrimary),
    side: WidgetStateBorderSide.resolveWith(
      (states) => BorderSide(color: _selectionColor(colors, states)),
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(4)),
    ),
  );
}

SwitchThemeData _switchTheme(ThemeData base) {
  final colors = base.colorScheme;
  return base.switchTheme.copyWith(
    thumbColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? colors.outline
          : states.contains(WidgetState.selected)
          ? colors.onPrimary
          : colors.onSurfaceVariant,
    ),
    trackColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.selected)
          ? _selectionColor(colors, states)
          : colors.surfaceContainerHighest,
    ),
  );
}

ChipThemeData _chips(ThemeData base) {
  final colors = base.colorScheme;
  return base.chipTheme.copyWith(
    backgroundColor: colors.surfaceContainerLow,
    selectedColor: colors.primaryContainer,
    secondarySelectedColor: colors.primaryContainer,
    side: BorderSide(color: colors.outlineVariant),
    shape: const StadiumBorder(),
    labelStyle: base.textTheme.bodySmall?.copyWith(color: colors.onSurface),
    secondaryLabelStyle: base.textTheme.bodySmall?.copyWith(
      color: colors.onPrimaryContainer,
    ),
    checkmarkColor: colors.onPrimaryContainer,
    elevation: 0,
    showCheckmark: false,
  );
}

ThemeData _feedback(ThemeData base) {
  final colors = base.colorScheme;
  return base.copyWith(
    tooltipTheme: base.tooltipTheme.copyWith(
      decoration: BoxDecoration(
        color: colors.inverseSurface,
        borderRadius: ReaderUiStyle.controlRadius,
      ),
      textStyle: base.textTheme.bodySmall?.copyWith(
        color: colors.onInverseSurface,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    ),
    snackBarTheme: base.snackBarTheme.copyWith(
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      backgroundColor: colors.inverseSurface,
      actionTextColor: colors.inversePrimary,
      contentTextStyle: base.textTheme.bodyMedium?.copyWith(
        color: colors.onInverseSurface,
      ),
      shape: ReaderUiStyle.controlShape,
    ),
    tabBarTheme: base.tabBarTheme.copyWith(
      labelColor: colors.primary,
      unselectedLabelColor: colors.onSurfaceVariant,
      labelStyle: base.textTheme.titleSmall,
      unselectedLabelStyle: base.textTheme.bodyMedium,
      indicator: UnderlineTabIndicator(
        borderSide: BorderSide(color: colors.primary, width: 2),
      ),
    ),
    scrollbarTheme: base.scrollbarTheme.copyWith(
      thumbColor: WidgetStatePropertyAll(
        colors.outline.withValues(alpha: .48),
      ),
      radius: const Radius.circular(999),
      thickness: const WidgetStatePropertyAll(3.5),
    ),
  );
}
