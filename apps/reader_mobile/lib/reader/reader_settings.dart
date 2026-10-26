import 'dart:convert';

import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_ui/theme/reader_margins.dart';
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
    this.backgroundId = 'none',
    this.inkMode = false,
    this.margins,
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

  /// 背景 id（P4-22：none/paper/wood/gray）。
  final String backgroundId;

  /// 墨水屏模式（P4-23）。
  final bool inkMode;

  /// 页边距（P8-10 边距调节器）；null 表示用默认 padding + 系统安全区。
  final ReaderMargins? margins;

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
    String backgroundId = 'none',
    bool inkMode = false,
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
    backgroundId: backgroundId,
    inkMode: inkMode,
    margins: margins,
  );

  /// 复制并替换背景。
  ReaderSettings copyWithBackground(String id) => ReaderSettings(
    fontSize: fontSize,
    lineHeight: lineHeight,
    paragraphSpacing: paragraphSpacing,
    horizontalPadding: horizontalPadding,
    themeId: themeId,
    backgroundId: id,
    inkMode: inkMode,
    margins: margins,
  );

  /// 复制并替换墨水屏开关。
  ReaderSettings copyWithInkMode(bool enabled) => ReaderSettings(
    fontSize: fontSize,
    lineHeight: lineHeight,
    paragraphSpacing: paragraphSpacing,
    horizontalPadding: horizontalPadding,
    themeId: themeId,
    backgroundId: backgroundId,
    inkMode: enabled,
    margins: margins,
  );

  /// 复制并替换页边距。
  ReaderSettings copyWithMargins(ReaderMargins value) => ReaderSettings(
    fontSize: fontSize,
    lineHeight: lineHeight,
    paragraphSpacing: paragraphSpacing,
    horizontalPadding: horizontalPadding,
    themeId: themeId,
    backgroundId: backgroundId,
    inkMode: inkMode,
    margins: value,
  );

  @override
  bool operator ==(Object other) =>
      other is ReaderSettings &&
      other.fontSize == fontSize &&
      other.lineHeight == lineHeight &&
      other.paragraphSpacing == paragraphSpacing &&
      other.horizontalPadding == horizontalPadding &&
      other.themeId == themeId &&
      other.backgroundId == backgroundId &&
      other.inkMode == inkMode &&
      other.margins == margins;

  @override
  int get hashCode => Object.hash(
    fontSize,
    lineHeight,
    paragraphSpacing,
    horizontalPadding,
    themeId,
    backgroundId,
    inkMode,
    margins,
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

  /// 页边距（JSON）。
  static const String keyMargins = 'reader.margins';
  static const String keyThemeId = 'reader.themeId';
  static const String keyBackgroundId = 'reader.backgroundId';
  static const String keyInkMode = 'reader.inkMode';

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
      backgroundId: await _library.getSetting(keyBackgroundId) ?? 'none',
      inkMode: (await _library.getSetting(keyInkMode)) == 'true',
      margins: _readMargins(await _library.getSetting(keyMargins)),
    );
  }

  /// 保存设置（逐项 upsert）。
  /// 读取页边距 JSON（损坏时按未设置处理）。
  static ReaderMargins? _readMargins(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      return ReaderMargins.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
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
    await _library.setSetting(keyBackgroundId, settings.backgroundId);
    await _library.setSetting(keyInkMode, settings.inkMode.toString());
    final margins = settings.margins;
    await _library.setSetting(
      keyMargins,
      margins == null ? '' : jsonEncode(margins.toJson()),
    );
  }

  static double? _readDouble(String? value) {
    if (value == null) {
      return null;
    }
    return double.tryParse(value);
  }
}
