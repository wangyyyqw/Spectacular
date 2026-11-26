import 'package:flutter/material.dart';

/// 补足 [ColorScheme] 之外的语义颜色，确保业务状态与图表色随软件主题和墨水屏切换。
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.starFilled,
    required this.starEmpty,
    required this.bookCoverBorder,
    required this.dividerSubtle,
  });

  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;
  final Color starFilled;
  final Color starEmpty;
  final Color bookCoverBorder;
  final Color dividerSubtle;

  /// 读取当前上下文语义色，缺省时按当前主题亮度回退。
  static AppSemanticColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AppSemanticColors>() ??
        (theme.brightness == Brightness.dark ? darkDefault : lightDefault);
  }

  static const lightDefault = AppSemanticColors(
    success: Color(0xFF2E7D4A),
    onSuccess: Colors.white,
    successContainer: Color(0xFFE6F4EB),
    onSuccessContainer: Color(0xFF1A4F2D),
    warning: Color(0xFF9A6218),
    onWarning: Colors.white,
    warningContainer: Color(0xFFFAF0DE),
    onWarningContainer: Color(0xFF633E0B),
    starFilled: Color(0xFF1D1D1F),
    starEmpty: Color(0xFF858891),
    bookCoverBorder: Color(0xFFE2E4E8),
    dividerSubtle: Color(0xFFE2E4E8),
  );

  static const darkDefault = AppSemanticColors(
    success: Color(0xFF72C990),
    onSuccess: Color(0xFF0E2918),
    successContainer: Color(0xFF193624),
    onSuccessContainer: Color(0xFFC0EACE),
    warning: Color(0xFFE6B465),
    onWarning: Color(0xFF332106),
    warningContainer: Color(0xFF3B2C16),
    onWarningContainer: Color(0xFFF6DEB5),
    starFilled: Color(0xFFE4E4E7),
    starEmpty: Color(0xFF85858D),
    bookCoverBorder: Color(0xFF353538),
    dividerSubtle: Color(0xFF353538),
  );

  /// 墨水屏纯黑白高对比语义色。
  static const ink = AppSemanticColors(
    success: Colors.black,
    onSuccess: Colors.white,
    successContainer: Colors.white,
    onSuccessContainer: Colors.black,
    warning: Colors.black,
    onWarning: Colors.white,
    warningContainer: Colors.white,
    onWarningContainer: Colors.black,
    starFilled: Colors.black,
    starEmpty: Colors.black,
    bookCoverBorder: Colors.black,
    dividerSubtle: Colors.black,
  );

  @override
  AppSemanticColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? starFilled,
    Color? starEmpty,
    Color? bookCoverBorder,
    Color? dividerSubtle,
  }) => AppSemanticColors(
    success: success ?? this.success,
    onSuccess: onSuccess ?? this.onSuccess,
    successContainer: successContainer ?? this.successContainer,
    onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
    warning: warning ?? this.warning,
    onWarning: onWarning ?? this.onWarning,
    warningContainer: warningContainer ?? this.warningContainer,
    onWarningContainer: onWarningContainer ?? this.onWarningContainer,
    starFilled: starFilled ?? this.starFilled,
    starEmpty: starEmpty ?? this.starEmpty,
    bookCoverBorder: bookCoverBorder ?? this.bookCoverBorder,
    dividerSubtle: dividerSubtle ?? this.dividerSubtle,
  );

  @override
  AppSemanticColors lerp(covariant ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      successContainer: Color.lerp(successContainer, other.successContainer, t)!,
      onSuccessContainer: Color.lerp(onSuccessContainer, other.onSuccessContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      warningContainer: Color.lerp(warningContainer, other.warningContainer, t)!,
      onWarningContainer: Color.lerp(onWarningContainer, other.onWarningContainer, t)!,
      starFilled: Color.lerp(starFilled, other.starFilled, t)!,
      starEmpty: Color.lerp(starEmpty, other.starEmpty, t)!,
      bookCoverBorder: Color.lerp(bookCoverBorder, other.bookCoverBorder, t)!,
      dividerSubtle: Color.lerp(dividerSubtle, other.dividerSubtle, t)!,
    );
  }
}
