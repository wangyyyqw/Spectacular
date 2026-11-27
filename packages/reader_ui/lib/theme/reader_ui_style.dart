import 'package:flutter/material.dart';

/// 首页、阅读菜单与编辑表单共用的控件和表面规范。
abstract final class ReaderUiStyle {
  static const sheetDragHandleHeight = 28.0;
  static const settingsSheetHeightFraction = .64;
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

  /// 两套样式共用语义角色；尺寸按当前主题切换，专用封面不使用这些圆角。
  static BorderRadius controlRadiusOf(ThemeData theme) =>
      BorderRadius.circular(theme.useMaterial3 ? 12 : 4);
  static BorderRadius buttonRadiusOf(ThemeData theme) =>
      BorderRadius.circular(theme.useMaterial3 ? 20 : 4);
  static BorderRadius cardRadiusOf(ThemeData theme) =>
      BorderRadius.circular(theme.useMaterial3 ? 12 : 4);
  static BorderRadius chipRadiusOf(ThemeData theme) =>
      BorderRadius.circular(theme.useMaterial3 ? 8 : 4);
  static double panelCornerOf(ThemeData theme) => theme.useMaterial3 ? 28 : 24;
  static BorderRadius panelRadiusOf(ThemeData theme) =>
      BorderRadius.circular(panelCornerOf(theme));
  static BorderRadius sheetRadiusOf(ThemeData theme) =>
      BorderRadius.vertical(top: Radius.circular(panelCornerOf(theme)));
  static BorderRadius popupRadiusOf(ThemeData theme) =>
      BorderRadius.circular(theme.useMaterial3 ? 12 : 16);
  static RoundedRectangleBorder controlShapeOf(ThemeData theme) =>
      RoundedRectangleBorder(borderRadius: controlRadiusOf(theme));
  static RoundedRectangleBorder buttonShapeOf(ThemeData theme) =>
      RoundedRectangleBorder(borderRadius: buttonRadiusOf(theme));

  static ShapeBorder cardShapeOf(ThemeData theme) =>
      theme.cardTheme.shape ??
      RoundedRectangleBorder(
        borderRadius: cardRadiusOf(theme),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      );

  static BoxDecoration cardDecorationOf(ThemeData theme) => BoxDecoration(
    color: theme.cardTheme.color ?? theme.colorScheme.surface,
    borderRadius: cardRadiusOf(theme),
    border: Border.all(color: theme.colorScheme.outlineVariant),
  );

  /// 统一危险按钮风格（删除、清理、放弃修改等不可逆操作）。
  static ButtonStyle destructiveFilledButtonStyle(ThemeData theme) {
    final colors = theme.colorScheme;
    return FilledButton.styleFrom(
      backgroundColor: colors.error,
      foregroundColor: colors.onError,
      disabledBackgroundColor: colors.onSurface.withValues(alpha: .12),
      disabledForegroundColor: colors.onSurface.withValues(alpha: .38),
      textStyle: theme.textTheme.labelLarge,
      shape: buttonShapeOf(theme),
      padding: controlPadding,
      minimumSize: controlSize,
      elevation: 0,
    );
  }

  /// 统一危险文本按钮风格。
  static ButtonStyle destructiveTextButtonStyle(ThemeData theme) {
    final colors = theme.colorScheme;
    return TextButton.styleFrom(
      foregroundColor: colors.error,
      disabledForegroundColor: colors.onSurface.withValues(alpha: .38),
      textStyle: theme.textTheme.labelLarge,
      shape: buttonShapeOf(theme),
      padding: controlPadding,
      minimumSize: controlSize,
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
  final card = RoundedRectangleBorder(
    borderRadius: ReaderUiStyle.cardRadiusOf(base),
    side: BorderSide(
      color: base.useMaterial3
          ? colors.outlineVariant.withValues(alpha: 0.72)
          : colors.outlineVariant,
    ),
  );
  return base.copyWith(
    dividerTheme: base.dividerTheme.copyWith(
      color: colors.outlineVariant,
      thickness: 0.8,
      space: 1,
    ),
    cardTheme: base.cardTheme.copyWith(
      color: colors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: card,
    ),
    popupMenuTheme: base.popupMenuTheme.copyWith(
      color: colors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: base.useMaterial3 ? 3 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: ReaderUiStyle.popupRadiusOf(base),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.65)),
      ),
      textStyle: base.textTheme.bodyMedium,
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
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: colors.onSurface,
      ),
      contentTextStyle: base.textTheme.bodyMedium?.copyWith(
        color: colors.onSurfaceVariant,
        height: 1.5,
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      shape: RoundedRectangleBorder(
        borderRadius: ReaderUiStyle.panelRadiusOf(base),
      ),
    ),
    bottomSheetTheme: base.bottomSheetTheme.copyWith(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalBarrierColor: Colors.black54,
      constraints: const BoxConstraints(maxWidth: 680),
      shape: RoundedRectangleBorder(
        borderRadius: ReaderUiStyle.sheetRadiusOf(base),
      ),
    ),
  );
}

ThemeData _actions(ThemeData base) {
  final colors = base.colorScheme;
  final filled = _filledStyle(base);
  return base.copyWith(
    filledButtonTheme: FilledButtonThemeData(style: filled),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: filled.copyWith(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? colors.onSurface.withValues(alpha: .12)
              : base.useMaterial3
              ? colors.surfaceContainerLow
              : colors.primary,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? colors.onSurface.withValues(alpha: .38)
              : base.useMaterial3
              ? colors.primary
              : colors.onPrimary,
        ),
        elevation: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? 0
              : base.useMaterial3
              ? 1
              : 0,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(style: _outlinedStyle(base)),
    textButtonTheme: TextButtonThemeData(style: _textStyle(base)),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: colors.onSurfaceVariant,
        disabledForegroundColor: colors.onSurface.withValues(alpha: .38),
        minimumSize: ReaderUiStyle.controlSize,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(ReaderUiStyle.controlSize),
        textStyle: WidgetStatePropertyAll(base.textTheme.labelLarge),
        shape: WidgetStatePropertyAll(ReaderUiStyle.buttonShapeOf(base)),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? colors.onSurface.withValues(alpha: .38)
              : states.contains(WidgetState.selected)
              ? colors.onSecondaryContainer
              : colors.onSurface,
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? colors.onSurface.withValues(alpha: .12)
              : states.contains(WidgetState.selected)
              ? colors.secondaryContainer
              : Colors.transparent,
        ),
      ),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(colors.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: ReaderUiStyle.popupRadiusOf(base),
          ),
        ),
      ),
    ),
    menuButtonTheme: MenuButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(ReaderUiStyle.controlSize),
        textStyle: WidgetStatePropertyAll(base.textTheme.bodyMedium),
        shape: WidgetStatePropertyAll(ReaderUiStyle.controlShapeOf(base)),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? colors.onSurface.withValues(alpha: .38)
              : colors.onSurface,
        ),
        iconColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? colors.onSurface.withValues(alpha: .38)
              : colors.onSurfaceVariant,
        ),
      ),
    ),
    floatingActionButtonTheme: base.floatingActionButtonTheme.copyWith(
      backgroundColor: colors.primary,
      foregroundColor: colors.onPrimary,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(base.useMaterial3 ? 16 : 4),
      ),
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
    shape: ReaderUiStyle.buttonShapeOf(base),
    padding: ReaderUiStyle.controlPadding,
    minimumSize: ReaderUiStyle.controlSize,
    elevation: 0,
  );
}

ButtonStyle _outlinedStyle(ThemeData base) => OutlinedButton.styleFrom(
  foregroundColor: base.colorScheme.primary,
  disabledForegroundColor: base.colorScheme.onSurface.withValues(alpha: .38),
  textStyle: base.textTheme.labelLarge,
  shape: ReaderUiStyle.buttonShapeOf(base),
  padding: ReaderUiStyle.controlPadding,
  side: BorderSide(color: base.colorScheme.outlineVariant),
  minimumSize: ReaderUiStyle.controlSize,
);

ButtonStyle _textStyle(ThemeData base) => TextButton.styleFrom(
  foregroundColor: base.colorScheme.primary,
  disabledForegroundColor: base.colorScheme.onSurface.withValues(alpha: .38),
  textStyle: base.textTheme.labelLarge,
  shape: ReaderUiStyle.buttonShapeOf(base),
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
      shape: ReaderUiStyle.controlShapeOf(base),
    ),
  );
}

InputDecorationThemeData _inputDecoration(ThemeData base) {
  final colors = base.colorScheme;
  final border = OutlineInputBorder(
    borderRadius: ReaderUiStyle.controlRadiusOf(base),
    borderSide: BorderSide(color: colors.outlineVariant),
  );
  return base.inputDecorationTheme.copyWith(
    filled: true,
    fillColor: colors.surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    hintStyle: base.textTheme.bodyMedium?.copyWith(
      color: colors.onSurfaceVariant,
    ),
    labelStyle: base.textTheme.bodyMedium,
    border: border,
    enabledBorder: border,
    disabledBorder: border.copyWith(
      borderSide: BorderSide(color: colors.onSurface.withValues(alpha: .12)),
    ),
    focusedBorder: border.copyWith(
      borderSide: BorderSide(
        color: colors.primary,
        width: base.useMaterial3 ? 2 : 1,
      ),
    ),
    errorBorder: border.copyWith(borderSide: BorderSide(color: colors.error)),
    focusedErrorBorder: border.copyWith(
      borderSide: BorderSide(
        color: colors.error,
        width: base.useMaterial3 ? 2 : 1,
      ),
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
    checkColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? colors.surface
          : states.contains(WidgetState.error)
          ? colors.onError
          : colors.onPrimary,
    ),
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
          : base.useMaterial3
          ? colors.outline
          : colors.onSurfaceVariant,
    ),
    trackOutlineColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.selected)
          ? Colors.transparent
          : states.contains(WidgetState.disabled)
          ? colors.onSurface.withValues(alpha: .12)
          : colors.outline,
    ),
    trackColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? colors.onSurface.withValues(alpha: .12)
          : states.contains(WidgetState.selected)
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
    shape: RoundedRectangleBorder(
      borderRadius: ReaderUiStyle.chipRadiusOf(base),
    ),
    labelStyle: base.textTheme.bodySmall?.copyWith(
      color: WidgetStateColor.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? colors.onSurface.withValues(alpha: .38)
            : states.contains(WidgetState.selected)
            ? colors.onPrimaryContainer
            : colors.onSurface,
      ),
    ),
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
    progressIndicatorTheme: base.progressIndicatorTheme.copyWith(
      color: colors.primary,
      linearTrackColor: colors.surfaceContainerHighest,
      circularTrackColor: colors.surfaceContainerHighest,
    ),
    tooltipTheme: base.tooltipTheme.copyWith(
      decoration: BoxDecoration(
        color: colors.inverseSurface,
        borderRadius: ReaderUiStyle.controlRadiusOf(base),
      ),
      textStyle: base.textTheme.bodySmall?.copyWith(
        color: colors.onInverseSurface,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    ),
    snackBarTheme: base.snackBarTheme.copyWith(
      behavior: SnackBarBehavior.floating,
      backgroundColor: colors.inverseSurface,
      contentTextStyle: base.textTheme.bodyMedium?.copyWith(
        color: colors.onInverseSurface,
      ),
      actionTextColor: colors.inversePrimary,
      elevation: base.useMaterial3 ? 2 : 0,
      shape: ReaderUiStyle.controlShapeOf(base),
    ),
    tabBarTheme: base.tabBarTheme.copyWith(
      labelColor: colors.primary,
      unselectedLabelColor: colors.onSurfaceVariant,
      labelStyle: base.textTheme.titleSmall,
      unselectedLabelStyle: base.textTheme.bodyMedium,
      dividerColor: colors.outlineVariant,
      indicator: UnderlineTabIndicator(
        borderSide: BorderSide(color: colors.primary, width: 2),
      ),
    ),
  );
}
