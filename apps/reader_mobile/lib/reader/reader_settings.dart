import 'dart:convert';

import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/panels/settings_panel.dart';
import 'package:reader_ui/theme/reader_margins.dart';
import 'package:reader_ui/theme/reader_theme.dart';
import 'package:reader_ui/tap_zones.dart';

import '../library/library_store.dart';

/// 阅读排版与主题设置（P4-21）：持久化在 settings 表。
class ReaderSettings {
  /// 创建设置。
  const ReaderSettings({
    this.fontSize = ReaderSettingsDefaults.fontSize,
    this.fontFamily,
    this.overrideEmbeddedFonts = false,
    this.lineHeight = ReaderSettingsDefaults.lineHeight,
    this.paragraphSpacing = ReaderSettingsDefaults.paragraphSpacing,
    this.horizontalPadding = ReaderSettingsDefaults.horizontalPadding,
    this.themeId = ReaderSettingsDefaults.themeId,
    this.backgroundId = 'none',
    this.customThemeId,
    this.inkMode = false,
    this.margins,
    this.tapZones = ReaderTapZones.defaults,
    this.pageTurnMode = PageTurnMode.cover,
  });

  /// 字号。
  final double fontSize;

  /// 正文字体族；null 表示跟随书籍样式。
  final String? fontFamily;

  /// 自定义字体是否覆盖书内实际嵌入的字体。
  final bool overrideEmbeddedFonts;

  /// 行高倍数。
  final double lineHeight;

  /// 段间距。
  final double paragraphSpacing;

  /// 左右页边距。
  final double horizontalPadding;

  /// 主题 id。
  final String themeId;

  /// 上次保存的自定义配色，切换内置主题后仍可复用。
  final String? customThemeId;

  /// 自定义主题对象。
  ReaderTheme? get customTheme => ReaderTheme.customById(customThemeId);

  /// 背景 id（P4-22：none/paper/wood/gray）。
  final String backgroundId;

  /// 墨水屏模式（P4-23）。
  final bool inkMode;

  /// 页边距（P8-10 边距调节器）；null 表示用默认 padding + 系统安全区。
  final ReaderMargins? margins;

  /// 九宫格点击区域。
  final ReaderTapZones tapZones;

  /// 翻页方式；只影响交互与动画，不参与正文排版。
  final PageTurnMode pageTurnMode;

  /// 默认设置。
  static const ReaderSettings defaults = ReaderSettings();

  /// 转排版覆盖。
  ReaderOverrides get overrides => ReaderOverrides(
    fontSize: fontSize,
    fontFamily: fontFamily,
    overrideEmbeddedFonts: overrideEmbeddedFonts,
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
    String? customThemeId,
    bool inkMode = false,
    PageTurnMode pageTurnMode = PageTurnMode.cover,
  }) => ReaderSettings(
    fontSize: overrides.fontSize ?? ReaderSettingsDefaults.fontSize,
    fontFamily: overrides.fontFamily,
    overrideEmbeddedFonts: overrides.overrideEmbeddedFonts,
    lineHeight: overrides.lineHeight ?? ReaderSettingsDefaults.lineHeight,
    paragraphSpacing:
        overrides.paragraphSpacing ?? ReaderSettingsDefaults.paragraphSpacing,
    horizontalPadding:
        overrides.padding?.left ?? ReaderSettingsDefaults.horizontalPadding,
    themeId: themeId,
    customThemeId: customThemeId,
    backgroundId: backgroundId,
    inkMode: inkMode,
    pageTurnMode: pageTurnMode,
  );

  /// 复制并替换排版设置，保留主题、背景、墨水屏、边距与点击区域。
  ReaderSettings copyWithOverrides(ReaderOverrides value) => ReaderSettings(
    fontSize: value.fontSize ?? ReaderSettingsDefaults.fontSize,
    fontFamily: value.fontFamily,
    overrideEmbeddedFonts: value.overrideEmbeddedFonts,
    lineHeight: value.lineHeight ?? ReaderSettingsDefaults.lineHeight,
    paragraphSpacing:
        value.paragraphSpacing ?? ReaderSettingsDefaults.paragraphSpacing,
    horizontalPadding:
        value.padding?.left ?? ReaderSettingsDefaults.horizontalPadding,
    themeId: themeId,
    customThemeId: customThemeId,
    backgroundId: backgroundId,
    inkMode: inkMode,
    margins: margins,
    tapZones: tapZones,
    pageTurnMode: pageTurnMode,
  );

  /// 复制并替换字体，保留其它阅读设置。
  ReaderSettings copyWithFont(String? family) => ReaderSettings(
    fontSize: fontSize,
    fontFamily: family,
    overrideEmbeddedFonts: overrideEmbeddedFonts,
    lineHeight: lineHeight,
    paragraphSpacing: paragraphSpacing,
    horizontalPadding: horizontalPadding,
    themeId: themeId,
    customThemeId: customThemeId,
    backgroundId: backgroundId,
    inkMode: inkMode,
    margins: margins,
    tapZones: tapZones,
    pageTurnMode: pageTurnMode,
  );

  /// 复制并替换主题。
  ReaderSettings copyWithTheme(String id) => ReaderSettings(
    fontSize: fontSize,
    fontFamily: fontFamily,
    overrideEmbeddedFonts: overrideEmbeddedFonts,
    lineHeight: lineHeight,
    paragraphSpacing: paragraphSpacing,
    horizontalPadding: horizontalPadding,
    themeId: id,
    customThemeId: ReaderTheme.customById(id)?.id ?? customThemeId,
    backgroundId: backgroundId,
    inkMode: inkMode,
    margins: margins,
    tapZones: tapZones,
    pageTurnMode: pageTurnMode,
  );

  /// 复制并替换背景。
  ReaderSettings copyWithBackground(String id) => ReaderSettings(
    fontSize: fontSize,
    fontFamily: fontFamily,
    overrideEmbeddedFonts: overrideEmbeddedFonts,
    lineHeight: lineHeight,
    paragraphSpacing: paragraphSpacing,
    horizontalPadding: horizontalPadding,
    themeId: themeId,
    customThemeId: customThemeId,
    backgroundId: id,
    inkMode: inkMode,
    margins: margins,
    tapZones: tapZones,
    pageTurnMode: pageTurnMode,
  );

  /// 复制并替换墨水屏开关。
  ReaderSettings copyWithInkMode(bool enabled) => ReaderSettings(
    fontSize: fontSize,
    fontFamily: fontFamily,
    overrideEmbeddedFonts: overrideEmbeddedFonts,
    lineHeight: lineHeight,
    paragraphSpacing: paragraphSpacing,
    horizontalPadding: horizontalPadding,
    themeId: themeId,
    customThemeId: customThemeId,
    backgroundId: backgroundId,
    inkMode: enabled,
    margins: margins,
    tapZones: tapZones,
    pageTurnMode: pageTurnMode,
  );

  /// 复制并替换页边距。
  ReaderSettings copyWithMargins(ReaderMargins value) => ReaderSettings(
    fontSize: fontSize,
    fontFamily: fontFamily,
    overrideEmbeddedFonts: overrideEmbeddedFonts,
    lineHeight: lineHeight,
    paragraphSpacing: paragraphSpacing,
    horizontalPadding: horizontalPadding,
    themeId: themeId,
    customThemeId: customThemeId,
    backgroundId: backgroundId,
    inkMode: inkMode,
    margins: value,
    tapZones: tapZones,
    pageTurnMode: pageTurnMode,
  );

  /// 复制并替换九宫格点击区域。
  ReaderSettings copyWithTapZones(ReaderTapZones value) => ReaderSettings(
    fontSize: fontSize,
    fontFamily: fontFamily,
    overrideEmbeddedFonts: overrideEmbeddedFonts,
    lineHeight: lineHeight,
    paragraphSpacing: paragraphSpacing,
    horizontalPadding: horizontalPadding,
    themeId: themeId,
    customThemeId: customThemeId,
    backgroundId: backgroundId,
    inkMode: inkMode,
    margins: margins,
    tapZones: value,
    pageTurnMode: pageTurnMode,
  );

  /// 复制并替换翻页方式。
  ReaderSettings copyWithPageTurnMode(PageTurnMode value) => ReaderSettings(
    fontSize: fontSize,
    fontFamily: fontFamily,
    overrideEmbeddedFonts: overrideEmbeddedFonts,
    lineHeight: lineHeight,
    paragraphSpacing: paragraphSpacing,
    horizontalPadding: horizontalPadding,
    themeId: themeId,
    customThemeId: customThemeId,
    backgroundId: backgroundId,
    inkMode: inkMode,
    margins: margins,
    tapZones: tapZones,
    pageTurnMode: value,
  );

  @override
  bool operator ==(Object other) =>
      other is ReaderSettings &&
      other.fontSize == fontSize &&
      other.fontFamily == fontFamily &&
      other.overrideEmbeddedFonts == overrideEmbeddedFonts &&
      other.lineHeight == lineHeight &&
      other.paragraphSpacing == paragraphSpacing &&
      other.horizontalPadding == horizontalPadding &&
      other.themeId == themeId &&
      other.customThemeId == customThemeId &&
      other.backgroundId == backgroundId &&
      other.inkMode == inkMode &&
      other.margins == margins &&
      other.tapZones == tapZones &&
      other.pageTurnMode == pageTurnMode;

  @override
  int get hashCode => Object.hash(
    fontSize,
    fontFamily,
    overrideEmbeddedFonts,
    lineHeight,
    paragraphSpacing,
    horizontalPadding,
    themeId,
    customThemeId,
    backgroundId,
    inkMode,
    margins,
    tapZones,
    pageTurnMode,
  );
}

/// 阅读设置的持久化（settings 表，键前缀 `reader.`）。
class ReaderSettingsStore {
  /// 创建存储。
  ReaderSettingsStore(this._library);

  final LibraryStore _library;

  /// 设置键。
  static const String keyFontSize = 'reader.fontSize';
  static const String keyFontFamily = 'reader.fontFamily';
  static const String keyOverrideEmbeddedFonts = 'reader.overrideEmbeddedFonts';
  static const String keyLineHeight = 'reader.lineHeight';
  static const String keyParagraphSpacing = 'reader.paragraphSpacing';
  static const String keyPadding = 'reader.padding';

  /// 页边距（JSON）。
  static const String keyMargins = 'reader.margins';
  static const String keyThemeId = 'reader.themeId';
  static const String keyCustomThemeId = 'reader.customThemeId';
  static const String keyBackgroundId = 'reader.backgroundId';
  static const String keyInkMode = 'reader.inkMode';
  static const String keyPageTurnMode = 'reader.pageTurnMode';

  /// 九宫格点击区域（JSON）。
  static const String keyTapZones = 'reader.tapZones';

  /// 读取设置（缺失或非法值回落到默认）。
  Future<ReaderSettings> load() async {
    return ReaderSettings(
      fontSize:
          _readDouble(await _library.getSetting(keyFontSize)) ??
          ReaderSettingsDefaults.fontSize,
      fontFamily: _readFontFamily(await _library.getSetting(keyFontFamily)),
      overrideEmbeddedFonts:
          await _library.getSetting(keyOverrideEmbeddedFonts) == 'true',
      lineHeight:
          _readDouble(await _library.getSetting(keyLineHeight)) ??
          ReaderSettingsDefaults.lineHeight,
      paragraphSpacing:
          _readDouble(await _library.getSetting(keyParagraphSpacing)) ??
          ReaderSettingsDefaults.paragraphSpacing,
      horizontalPadding:
          _readDouble(await _library.getSetting(keyPadding)) ??
          ReaderSettingsDefaults.horizontalPadding,
      themeId:
          await _library.getSetting(keyThemeId) ??
          ReaderSettingsDefaults.themeId,
      customThemeId: ReaderTheme.customById(
        await _library.getSetting(keyCustomThemeId),
      )?.id,
      backgroundId: await _library.getSetting(keyBackgroundId) ?? 'none',
      inkMode: (await _library.getSetting(keyInkMode)) == 'true',
      margins: _readMargins(await _library.getSetting(keyMargins)),
      tapZones: _readTapZones(await _library.getSetting(keyTapZones)),
      pageTurnMode: PageTurnMode.fromId(
        await _library.getSetting(keyPageTurnMode),
      ),
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

  /// 读取九宫格 JSON（缺失或损坏时用默认布局）。
  static ReaderTapZones _readTapZones(String? raw) {
    if (raw == null || raw.isEmpty) {
      return ReaderTapZones.defaults;
    }
    try {
      return ReaderTapZones.fromJson(jsonDecode(raw));
    } catch (_) {
      return ReaderTapZones.defaults;
    }
  }

  /// 读取正文字体；自定义字体的文件可用性由打开阅读页时校验。
  static String? _readFontFamily(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    const supported = <String>{
      ReaderSettingsDefaults.fontSong,
      ReaderSettingsDefaults.fontSans,
    };
    return supported.contains(raw) ||
            RegExp(r'^user_[0-9a-f]{64}$').hasMatch(raw)
        ? raw
        : null;
  }

  /// 保存设置（逐项 upsert）。
  Future<void> save(ReaderSettings settings) async {
    await _library.setSetting(
      keyFontSize,
      settings.fontSize.toStringAsFixed(1),
    );
    await _library.setSetting(keyFontFamily, settings.fontFamily ?? '');
    await _library.setSetting(
      keyOverrideEmbeddedFonts,
      settings.overrideEmbeddedFonts.toString(),
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
    await _library.setSetting(keyCustomThemeId, settings.customThemeId ?? '');
    await _library.setSetting(keyBackgroundId, settings.backgroundId);
    await _library.setSetting(keyInkMode, settings.inkMode.toString());
    await _library.setSetting(keyPageTurnMode, settings.pageTurnMode.id);
    final margins = settings.margins;
    await _library.setSetting(
      keyMargins,
      margins == null ? '' : jsonEncode(margins.toJson()),
    );
    await _library.setSetting(
      keyTapZones,
      jsonEncode(settings.tapZones.toJson()),
    );
  }

  static double? _readDouble(String? value) {
    if (value == null) {
      return null;
    }
    return double.tryParse(value);
  }
}
