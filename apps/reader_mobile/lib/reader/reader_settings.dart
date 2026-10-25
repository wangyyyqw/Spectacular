import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_ui/panels/settings_panel.dart';
import 'package:reader_ui/theme/reader_theme.dart';

import '../library/library_store.dart';

/// 阅读排版与主题设置（P4-21）：持久化在 settings 表。
class ReaderSettings {
  /// 创建设置。
  const ReaderSettings({
    this.fontSize = ReaderSettingsDefaults.fontSize,
    this.lineHeight = ReaderSettingsDefaults.lineHeight,
    this.paragraphSpacing = ReaderSettingsDefaults.paragraphSpacing,
    this.horizontalPadding = ReaderSettingsDefaults.horizontalPadding,
    this.themeId = ReaderSettingsDefaults.themeId,
  });

  /// 字号。
  final double fontSize;

  /// 行高倍数。
  final double lineHeight;

  /// 段间距。
  final double paragraphSpacing;

  /// 左右页边距。
  final double horizontalPadding;

  /// 主题 id。
  final String themeId;

  /// 默认设置。
  static const ReaderSettings defaults = ReaderSettings();

  /// 转排版覆盖。
  ReaderOverrides get overrides => ReaderOverrides(
    fontSize: fontSize,
    lineHeight: lineHeight,
    paragraphSpacing: paragraphSpacing,
    padding: CssEdges(
      top: 16,
      right: horizontalPadding,
      bottom: 16,
      left: horizontalPadding,
    ),
  );

  /// 主题对象。
  ReaderTheme get theme => ReaderTheme.byId(themeId);

  /// 从排版覆盖与主题还原（设置面板回调 → 持久化用）。
  static ReaderSettings fromOverrides(
    ReaderOverrides overrides, {
    required String themeId,
  }) => ReaderSettings(
    fontSize: overrides.fontSize ?? ReaderSettingsDefaults.fontSize,
    lineHeight: overrides.lineHeight ?? ReaderSettingsDefaults.lineHeight,
    paragraphSpacing:
        overrides.paragraphSpacing ?? ReaderSettingsDefaults.paragraphSpacing,
    horizontalPadding:
        overrides.padding?.left ?? ReaderSettingsDefaults.horizontalPadding,
    themeId: themeId,
  );

  /// 复制并替换主题。
  ReaderSettings copyWithTheme(String id) => ReaderSettings(
    fontSize: fontSize,
    lineHeight: lineHeight,
    paragraphSpacing: paragraphSpacing,
    horizontalPadding: horizontalPadding,
    themeId: id,
  );

  @override
  bool operator ==(Object other) =>
      other is ReaderSettings &&
      other.fontSize == fontSize &&
      other.lineHeight == lineHeight &&
      other.paragraphSpacing == paragraphSpacing &&
      other.horizontalPadding == horizontalPadding &&
      other.themeId == themeId;

  @override
  int get hashCode => Object.hash(
    fontSize,
    lineHeight,
    paragraphSpacing,
    horizontalPadding,
    themeId,
  );
}

/// 阅读设置的持久化（settings 表，键前缀 `reader.`）。
class ReaderSettingsStore {
  /// 创建存储。
  ReaderSettingsStore(this._library);

  final LibraryStore _library;

  /// 设置键。
  static const String keyFontSize = 'reader.fontSize';
  static const String keyLineHeight = 'reader.lineHeight';
  static const String keyParagraphSpacing = 'reader.paragraphSpacing';
  static const String keyPadding = 'reader.padding';
  static const String keyThemeId = 'reader.themeId';

  /// 读取设置（缺失或非法值回落到默认）。
  Future<ReaderSettings> load() async {
    return ReaderSettings(
      fontSize: _readDouble(await _library.getSetting(keyFontSize)) ??
          ReaderSettingsDefaults.fontSize,
      lineHeight: _readDouble(await _library.getSetting(keyLineHeight)) ??
          ReaderSettingsDefaults.lineHeight,
      paragraphSpacing:
          _readDouble(await _library.getSetting(keyParagraphSpacing)) ??
          ReaderSettingsDefaults.paragraphSpacing,
      horizontalPadding: _readDouble(await _library.getSetting(keyPadding)) ??
          ReaderSettingsDefaults.horizontalPadding,
      themeId: await _library.getSetting(keyThemeId) ??
          ReaderSettingsDefaults.themeId,
    );
  }

  /// 保存设置（逐项 upsert）。
  Future<void> save(ReaderSettings settings) async {
    await _library.setSetting(
      keyFontSize,
      settings.fontSize.toStringAsFixed(1),
    );
    await _library.setSetting(
      keyLineHeight,
      settings.lineHeight.toStringAsFixed(1),
    );
    await _library.setSetting(
      keyParagraphSpacing,
      settings.paragraphSpacing.toStringAsFixed(1),
    );
    await _library.setSetting(
      keyPadding,
      settings.horizontalPadding.toStringAsFixed(1),
    );
    await _library.setSetting(keyThemeId, settings.themeId);
  }

  static double? _readDouble(String? value) {
    if (value == null) {
      return null;
    }
    return double.tryParse(value);
  }
}
