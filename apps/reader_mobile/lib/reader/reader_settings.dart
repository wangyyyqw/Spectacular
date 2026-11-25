import 'dart:convert';
import 'dart:ui' show Brightness;

import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_ui/annotations/annotation.dart';
import 'package:reader_ui/annotations/mark_settings.dart';
import 'package:reader_ui/bookmarks/bookmark_style.dart';
import 'package:reader_ui/footnote_dialog.dart';
import 'package:reader_ui/paging/page_turn_mode.dart';
import 'package:reader_ui/panels/settings_panel.dart';
import 'package:reader_ui/page_furniture/corner_info.dart';
import 'package:reader_ui/theme/reader_margins.dart';
import 'package:reader_ui/theme/reader_theme.dart';
import 'package:reader_ui/tap_zones.dart';

import '../library/library_store.dart';

/// 听书使用的语音引擎。
enum ReaderTtsMode {
  /// 系统语音引擎。
  system,

  /// 离线伴听引擎。
  offline;

  /// 从持久化值解析；旧设置默认系统语音。
  static ReaderTtsMode fromId(String? value) =>
      value == offline.name ? offline : system;
}

/// 听书偏好。
class ReaderTtsSettings {
  /// 创建听书偏好。
  const ReaderTtsSettings({
    this.mode = ReaderTtsMode.system,
    this.rate = 0.5,
    this.pitch = 1,
    this.volume = 1,
    this.autoTurnPage = true,
    this.voiceName = '',
    this.voiceLocale = '',
    this.narratorVoiceId = '',
    this.dialogueVoiceId = '',
    this.narratorSpeed = 1,
    this.dialogueSpeed = 1,
    this.narratorSpeakerId = 0,
  });

  /// 语音引擎。
  final ReaderTtsMode mode;

  /// 语速（0～1，平台默认正常语速约为 0.5）。
  final double rate;

  /// 音调。
  final double pitch;

  /// 音量。
  final double volume;

  /// 读完当前页后是否自动翻页。
  final bool autoTurnPage;

  /// 选中的系统音色名称；为空时使用系统默认音色。
  final String voiceName;

  /// 选中音色的语言区域。
  final String voiceLocale;

  /// 离线旁白音色标识。
  final String narratorVoiceId;

  /// 离线对白音色标识；为空时跟随旁白。
  final String dialogueVoiceId;

  /// 离线旁白语速（1 为模型原始语速）。
  final double narratorSpeed;

  /// 离线对白语速（1 为模型原始语速）。
  final double dialogueSpeed;

  /// 多说话人音色的旁白说话人编号。
  final int narratorSpeakerId;

  /// 是否选择了明确的系统音色。
  bool get hasVoice =>
      voiceName.trim().isNotEmpty && voiceLocale.trim().isNotEmpty;

  /// 是否选择了离线旁白音色。
  bool get hasOfflineVoice => narratorVoiceId.trim().isNotEmpty;

  /// 默认听书偏好。
  static const ReaderTtsSettings defaults = ReaderTtsSettings();

  /// 复制并替换指定字段。
  ReaderTtsSettings copyWith({
    ReaderTtsMode? mode,
    double? rate,
    double? pitch,
    double? volume,
    bool? autoTurnPage,
    String? voiceName,
    String? voiceLocale,
    String? narratorVoiceId,
    String? dialogueVoiceId,
    double? narratorSpeed,
    double? dialogueSpeed,
    int? narratorSpeakerId,
  }) => ReaderTtsSettings(
    mode: mode ?? this.mode,
    rate: rate ?? this.rate,
    pitch: pitch ?? this.pitch,
    volume: volume ?? this.volume,
    autoTurnPage: autoTurnPage ?? this.autoTurnPage,
    voiceName: voiceName ?? this.voiceName,
    voiceLocale: voiceLocale ?? this.voiceLocale,
    narratorVoiceId: narratorVoiceId ?? this.narratorVoiceId,
    dialogueVoiceId: dialogueVoiceId ?? this.dialogueVoiceId,
    narratorSpeed: narratorSpeed ?? this.narratorSpeed,
    dialogueSpeed: dialogueSpeed ?? this.dialogueSpeed,
    narratorSpeakerId: narratorSpeakerId ?? this.narratorSpeakerId,
  );

  /// 从 JSON 还原。
  factory ReaderTtsSettings.fromJson(Map<String, Object?> json) =>
      ReaderTtsSettings(
        mode: ReaderTtsMode.fromId(
          json['mode'] is String ? json['mode']! as String : null,
        ),
        rate: _double(json['rate'], defaults.rate).clamp(0.1, 1),
        pitch: _double(json['pitch'], defaults.pitch).clamp(0.5, 2),
        volume: _double(json['volume'], defaults.volume).clamp(0, 1),
        autoTurnPage: json['autoTurnPage'] is bool
            ? json['autoTurnPage']! as bool
            : defaults.autoTurnPage,
        voiceName: json['voiceName'] is String
            ? json['voiceName']! as String
            : defaults.voiceName,
        voiceLocale: json['voiceLocale'] is String
            ? json['voiceLocale']! as String
            : defaults.voiceLocale,
        narratorVoiceId: json['narratorVoiceId'] is String
            ? json['narratorVoiceId']! as String
            : defaults.narratorVoiceId,
        dialogueVoiceId: json['dialogueVoiceId'] is String
            ? json['dialogueVoiceId']! as String
            : defaults.dialogueVoiceId,
        narratorSpeed: _double(
          json['narratorSpeed'],
          defaults.narratorSpeed,
        ).clamp(0.5, 2),
        dialogueSpeed: _double(
          json['dialogueSpeed'],
          defaults.dialogueSpeed,
        ).clamp(0.5, 2),
        narratorSpeakerId: json['narratorSpeakerId'] is int
            ? (json['narratorSpeakerId']! as int).clamp(0, 999)
            : defaults.narratorSpeakerId,
      );

  /// 序列化。
  Map<String, Object?> toJson() => <String, Object?>{
    'mode': mode.name,
    'rate': rate,
    'pitch': pitch,
    'volume': volume,
    'autoTurnPage': autoTurnPage,
    'voiceName': voiceName,
    'voiceLocale': voiceLocale,
    'narratorVoiceId': narratorVoiceId,
    'dialogueVoiceId': dialogueVoiceId,
    'narratorSpeed': narratorSpeed,
    'dialogueSpeed': dialogueSpeed,
    'narratorSpeakerId': narratorSpeakerId,
  };

  static double _double(Object? value, double fallback) =>
      value is num ? value.toDouble() : fallback;

  @override
  bool operator ==(Object other) =>
      other is ReaderTtsSettings &&
      other.mode == mode &&
      other.rate == rate &&
      other.pitch == pitch &&
      other.volume == volume &&
      other.autoTurnPage == autoTurnPage &&
      other.voiceName == voiceName &&
      other.voiceLocale == voiceLocale &&
      other.narratorVoiceId == narratorVoiceId &&
      other.dialogueVoiceId == dialogueVoiceId &&
      other.narratorSpeed == narratorSpeed &&
      other.dialogueSpeed == dialogueSpeed &&
      other.narratorSpeakerId == narratorSpeakerId;

  @override
  int get hashCode => Object.hash(
    mode,
    rate,
    pitch,
    volume,
    autoTurnPage,
    voiceName,
    voiceLocale,
    narratorVoiceId,
    dialogueVoiceId,
    narratorSpeed,
    dialogueSpeed,
    narratorSpeakerId,
  );
}

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
    this.dayThemeId = ReaderSettingsDefaults.themeId,
    this.nightThemeId = 'black',
    this.backgroundId = 'none',
    this.backgroundImageOpacity = ReaderSettingsDefaults.backgroundImageOpacity,
    this.customThemeId,
    this.inkMode = false,
    this.margins,
    this.cornerInfo = ReaderCornerInfo.defaults,
    this.tapZones = ReaderTapZones.defaults,
    this.pageTurnMode = PageTurnMode.cover,
    this.keepScreenOn = false,
    this.volumeKeyPaging = false,
    this.markSettings = const ReaderMarkSettings(),
    this.bookmarkStyle = const ReaderBookmarkStyle(),
    this.footnoteStyle = ReaderFootnoteStyle.dialog,
    this.tts = ReaderTtsSettings.defaults,
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

  /// 日间和夜间分别记住上次选择的配色。
  final String dayThemeId;
  final String nightThemeId;

  /// 上次保存的自定义配色，切换内置主题后仍可复用。
  final String? customThemeId;

  /// 自定义主题对象。
  ReaderTheme? get customTheme => ReaderTheme.customById(customThemeId);

  /// 背景 id（P4-22：none/paper/wood/gray）。
  final String backgroundId;

  /// 导入图片的可见强度，1 为原色、0 为主题底色。
  final double backgroundImageOpacity;

  /// 墨水屏模式（P4-23）。
  final bool inkMode;

  /// 页边距（P8-10 边距调节器）；null 表示用默认 padding + 系统安全区。
  final ReaderMargins? margins;

  /// 页眉页脚四角的信息类型。
  final ReaderCornerInfo cornerInfo;

  /// 九宫格点击区域。
  final ReaderTapZones tapZones;

  /// 翻页方式；只影响交互与动画，不参与正文排版。
  final PageTurnMode pageTurnMode;

  /// 阅读时保持屏幕常亮。
  final bool keepScreenOn;

  /// 用音量键翻页。
  final bool volumeKeyPaging;

  /// 划线的默认外观和自定义颜色。
  final ReaderMarkSettings markSettings;

  /// 阅读页右上角书签的全局外观。
  final ReaderBookmarkStyle bookmarkStyle;

  /// 阅读页注释的展示样式。
  final ReaderFootnoteStyle footnoteStyle;

  /// 听书偏好。
  final ReaderTtsSettings tts;

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

  /// 旧设置仍从当前主题恢复，对侧模式使用各自保存的配色。
  ReaderTheme themeForBrightness(Brightness brightness) {
    final current = theme;
    if (current.isDark == (brightness == Brightness.dark)) return current;
    return ReaderTheme.byId(
      brightness == Brightness.dark ? nightThemeId : dayThemeId,
    ).resolveForBrightness(brightness);
  }

  /// 从排版覆盖与主题还原（设置面板回调 → 持久化用）。
  static ReaderSettings fromOverrides(
    ReaderOverrides overrides, {
    required String themeId,
    String dayThemeId = ReaderSettingsDefaults.themeId,
    String nightThemeId = 'black',
    String backgroundId = 'none',
    double backgroundImageOpacity =
        ReaderSettingsDefaults.backgroundImageOpacity,
    String? customThemeId,
    bool inkMode = false,
    ReaderCornerInfo cornerInfo = ReaderCornerInfo.defaults,
    PageTurnMode pageTurnMode = PageTurnMode.cover,
    bool keepScreenOn = false,
    bool volumeKeyPaging = false,
    ReaderMarkSettings markSettings = const ReaderMarkSettings(),
    ReaderBookmarkStyle bookmarkStyle = const ReaderBookmarkStyle(),
    ReaderFootnoteStyle footnoteStyle = ReaderFootnoteStyle.dialog,
    ReaderTtsSettings tts = ReaderTtsSettings.defaults,
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
    dayThemeId: dayThemeId,
    nightThemeId: nightThemeId,
    customThemeId: customThemeId,
    backgroundId: backgroundId,
    backgroundImageOpacity: backgroundImageOpacity,
    inkMode: inkMode,
    cornerInfo: cornerInfo,
    pageTurnMode: pageTurnMode,
    keepScreenOn: keepScreenOn,
    volumeKeyPaging: volumeKeyPaging,
    markSettings: markSettings,
    bookmarkStyle: bookmarkStyle,
    footnoteStyle: footnoteStyle,
    tts: tts,
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
    dayThemeId: dayThemeId,
    nightThemeId: nightThemeId,
    customThemeId: customThemeId,
    backgroundId: backgroundId,
    backgroundImageOpacity: backgroundImageOpacity,
    inkMode: inkMode,
    cornerInfo: cornerInfo,
    margins: margins,
    tapZones: tapZones,
    pageTurnMode: pageTurnMode,
    keepScreenOn: keepScreenOn,
    volumeKeyPaging: volumeKeyPaging,
    markSettings: markSettings,
    bookmarkStyle: bookmarkStyle,
    footnoteStyle: footnoteStyle,
    tts: tts,
  );

  /// 复制并替换字体，保留其它阅读设置。
  ReaderSettings copyWithFont(String? family) => ReaderSettings(
    fontSize: fontSize,
    fontFamily: family,
    overrideEmbeddedFonts: family == null ? false : overrideEmbeddedFonts,
    lineHeight: lineHeight,
    paragraphSpacing: paragraphSpacing,
    horizontalPadding: horizontalPadding,
    themeId: themeId,
    dayThemeId: dayThemeId,
    nightThemeId: nightThemeId,
    customThemeId: customThemeId,
    backgroundId: backgroundId,
    backgroundImageOpacity: backgroundImageOpacity,
    inkMode: inkMode,
    cornerInfo: cornerInfo,
    margins: margins,
    tapZones: tapZones,
    pageTurnMode: pageTurnMode,
    keepScreenOn: keepScreenOn,
    volumeKeyPaging: volumeKeyPaging,
    markSettings: markSettings,
    bookmarkStyle: bookmarkStyle,
    footnoteStyle: footnoteStyle,
    tts: tts,
  );

  /// 复制并替换主题。
  ReaderSettings copyWithTheme(String id) {
    final next = ReaderTheme.byId(id);
    return ReaderSettings(
      fontSize: fontSize,
      fontFamily: fontFamily,
      overrideEmbeddedFonts: overrideEmbeddedFonts,
      lineHeight: lineHeight,
      paragraphSpacing: paragraphSpacing,
      horizontalPadding: horizontalPadding,
      themeId: id,
      dayThemeId: next.isDark ? themeForBrightness(Brightness.light).id : id,
      nightThemeId: next.isDark ? id : themeForBrightness(Brightness.dark).id,
      customThemeId: ReaderTheme.customById(id)?.id ?? customThemeId,
      backgroundId: backgroundId,
      backgroundImageOpacity: backgroundImageOpacity,
      inkMode: inkMode,
      cornerInfo: cornerInfo,
      margins: margins,
      tapZones: tapZones,
      pageTurnMode: pageTurnMode,
      keepScreenOn: keepScreenOn,
      volumeKeyPaging: volumeKeyPaging,
      markSettings: markSettings,
      bookmarkStyle: bookmarkStyle,
      footnoteStyle: footnoteStyle,
      tts: tts,
    );
  }

  /// 复制并替换背景。
  ReaderSettings copyWithBackground(String id) => ReaderSettings(
    fontSize: fontSize,
    fontFamily: fontFamily,
    overrideEmbeddedFonts: overrideEmbeddedFonts,
    lineHeight: lineHeight,
    paragraphSpacing: paragraphSpacing,
    horizontalPadding: horizontalPadding,
    themeId: themeId,
    dayThemeId: dayThemeId,
    nightThemeId: nightThemeId,
    customThemeId: customThemeId,
    backgroundId: id,
    backgroundImageOpacity: backgroundImageOpacity,
    inkMode: inkMode,
    cornerInfo: cornerInfo,
    margins: margins,
    tapZones: tapZones,
    pageTurnMode: pageTurnMode,
    keepScreenOn: keepScreenOn,
    volumeKeyPaging: volumeKeyPaging,
    markSettings: markSettings,
    bookmarkStyle: bookmarkStyle,
    footnoteStyle: footnoteStyle,
    tts: tts,
  );

  /// 修改图片淡化程度，保留全部阅读设置。
  ReaderSettings copyWithBackgroundImageOpacity(double opacity) =>
      ReaderSettings(
        fontSize: fontSize,
        fontFamily: fontFamily,
        overrideEmbeddedFonts: overrideEmbeddedFonts,
        lineHeight: lineHeight,
        paragraphSpacing: paragraphSpacing,
        horizontalPadding: horizontalPadding,
        themeId: themeId,
        dayThemeId: dayThemeId,
        nightThemeId: nightThemeId,
        customThemeId: customThemeId,
        backgroundId: backgroundId,
        backgroundImageOpacity: opacity,
        inkMode: inkMode,
        cornerInfo: cornerInfo,
        margins: margins,
        tapZones: tapZones,
        pageTurnMode: pageTurnMode,
        keepScreenOn: keepScreenOn,
        volumeKeyPaging: volumeKeyPaging,
        markSettings: markSettings,
        bookmarkStyle: bookmarkStyle,
        footnoteStyle: footnoteStyle,
        tts: tts,
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
    dayThemeId: dayThemeId,
    nightThemeId: nightThemeId,
    customThemeId: customThemeId,
    backgroundId: backgroundId,
    backgroundImageOpacity: backgroundImageOpacity,
    inkMode: enabled,
    cornerInfo: cornerInfo,
    margins: margins,
    tapZones: tapZones,
    pageTurnMode: pageTurnMode,
    keepScreenOn: keepScreenOn,
    volumeKeyPaging: volumeKeyPaging,
    markSettings: markSettings,
    bookmarkStyle: bookmarkStyle,
    footnoteStyle: footnoteStyle,
    tts: tts,
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
    dayThemeId: dayThemeId,
    nightThemeId: nightThemeId,
    customThemeId: customThemeId,
    backgroundId: backgroundId,
    backgroundImageOpacity: backgroundImageOpacity,
    inkMode: inkMode,
    cornerInfo: cornerInfo,
    margins: value,
    tapZones: tapZones,
    pageTurnMode: pageTurnMode,
    keepScreenOn: keepScreenOn,
    volumeKeyPaging: volumeKeyPaging,
    markSettings: markSettings,
    bookmarkStyle: bookmarkStyle,
    footnoteStyle: footnoteStyle,
    tts: tts,
  );

  /// 修改四角显示，保留全部阅读偏好。
  ReaderSettings copyWithCornerInfo(ReaderCornerInfo value) => ReaderSettings(
    fontSize: fontSize,
    fontFamily: fontFamily,
    overrideEmbeddedFonts: overrideEmbeddedFonts,
    lineHeight: lineHeight,
    paragraphSpacing: paragraphSpacing,
    horizontalPadding: horizontalPadding,
    themeId: themeId,
    dayThemeId: dayThemeId,
    nightThemeId: nightThemeId,
    customThemeId: customThemeId,
    backgroundId: backgroundId,
    backgroundImageOpacity: backgroundImageOpacity,
    inkMode: inkMode,
    margins: margins,
    cornerInfo: value,
    tapZones: tapZones,
    pageTurnMode: pageTurnMode,
    keepScreenOn: keepScreenOn,
    volumeKeyPaging: volumeKeyPaging,
    markSettings: markSettings,
    bookmarkStyle: bookmarkStyle,
    footnoteStyle: footnoteStyle,
    tts: tts,
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
    dayThemeId: dayThemeId,
    nightThemeId: nightThemeId,
    customThemeId: customThemeId,
    backgroundId: backgroundId,
    backgroundImageOpacity: backgroundImageOpacity,
    inkMode: inkMode,
    cornerInfo: cornerInfo,
    margins: margins,
    tapZones: value,
    pageTurnMode: pageTurnMode,
    keepScreenOn: keepScreenOn,
    volumeKeyPaging: volumeKeyPaging,
    markSettings: markSettings,
    bookmarkStyle: bookmarkStyle,
    footnoteStyle: footnoteStyle,
    tts: tts,
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
    dayThemeId: dayThemeId,
    nightThemeId: nightThemeId,
    customThemeId: customThemeId,
    backgroundId: backgroundId,
    backgroundImageOpacity: backgroundImageOpacity,
    inkMode: inkMode,
    cornerInfo: cornerInfo,
    margins: margins,
    tapZones: tapZones,
    pageTurnMode: value,
    keepScreenOn: keepScreenOn,
    volumeKeyPaging: volumeKeyPaging,
    markSettings: markSettings,
    bookmarkStyle: bookmarkStyle,
    footnoteStyle: footnoteStyle,
    tts: tts,
  );

  /// 复制并替换屏幕常亮开关。
  ReaderSettings copyWithKeepScreenOn(bool enabled) => ReaderSettings(
    fontSize: fontSize,
    fontFamily: fontFamily,
    overrideEmbeddedFonts: overrideEmbeddedFonts,
    lineHeight: lineHeight,
    paragraphSpacing: paragraphSpacing,
    horizontalPadding: horizontalPadding,
    themeId: themeId,
    dayThemeId: dayThemeId,
    nightThemeId: nightThemeId,
    customThemeId: customThemeId,
    backgroundId: backgroundId,
    backgroundImageOpacity: backgroundImageOpacity,
    inkMode: inkMode,
    cornerInfo: cornerInfo,
    margins: margins,
    tapZones: tapZones,
    pageTurnMode: pageTurnMode,
    keepScreenOn: enabled,
    volumeKeyPaging: volumeKeyPaging,
    markSettings: markSettings,
    bookmarkStyle: bookmarkStyle,
    footnoteStyle: footnoteStyle,
    tts: tts,
  );

  /// 复制并替换音量键翻页开关。
  ReaderSettings copyWithVolumeKeyPaging(bool enabled) => ReaderSettings(
    fontSize: fontSize,
    fontFamily: fontFamily,
    overrideEmbeddedFonts: overrideEmbeddedFonts,
    lineHeight: lineHeight,
    paragraphSpacing: paragraphSpacing,
    horizontalPadding: horizontalPadding,
    themeId: themeId,
    dayThemeId: dayThemeId,
    nightThemeId: nightThemeId,
    customThemeId: customThemeId,
    backgroundId: backgroundId,
    backgroundImageOpacity: backgroundImageOpacity,
    inkMode: inkMode,
    cornerInfo: cornerInfo,
    margins: margins,
    tapZones: tapZones,
    pageTurnMode: pageTurnMode,
    keepScreenOn: keepScreenOn,
    volumeKeyPaging: enabled,
    markSettings: markSettings,
    bookmarkStyle: bookmarkStyle,
    footnoteStyle: footnoteStyle,
    tts: tts,
  );

  /// 修改划线偏好，保留全部正文排版与阅读交互设置。
  ReaderSettings copyWithMarkSettings(ReaderMarkSettings value) =>
      ReaderSettings(
        fontSize: fontSize,
        fontFamily: fontFamily,
        overrideEmbeddedFonts: overrideEmbeddedFonts,
        lineHeight: lineHeight,
        paragraphSpacing: paragraphSpacing,
        horizontalPadding: horizontalPadding,
        themeId: themeId,
        dayThemeId: dayThemeId,
        nightThemeId: nightThemeId,
        customThemeId: customThemeId,
        backgroundId: backgroundId,
        backgroundImageOpacity: backgroundImageOpacity,
        inkMode: inkMode,
        cornerInfo: cornerInfo,
        margins: margins,
        tapZones: tapZones,
        pageTurnMode: pageTurnMode,
        keepScreenOn: keepScreenOn,
        volumeKeyPaging: volumeKeyPaging,
        markSettings: value,
        bookmarkStyle: bookmarkStyle,
        footnoteStyle: footnoteStyle,
        tts: tts,
      );

  /// 修改书签样式，保留全部正文排版与阅读交互设置。
  ReaderSettings copyWithBookmarkStyle(ReaderBookmarkStyle value) =>
      ReaderSettings(
        fontSize: fontSize,
        fontFamily: fontFamily,
        overrideEmbeddedFonts: overrideEmbeddedFonts,
        lineHeight: lineHeight,
        paragraphSpacing: paragraphSpacing,
        horizontalPadding: horizontalPadding,
        themeId: themeId,
        dayThemeId: dayThemeId,
        nightThemeId: nightThemeId,
        customThemeId: customThemeId,
        backgroundId: backgroundId,
        backgroundImageOpacity: backgroundImageOpacity,
        inkMode: inkMode,
        cornerInfo: cornerInfo,
        margins: margins,
        tapZones: tapZones,
        pageTurnMode: pageTurnMode,
        keepScreenOn: keepScreenOn,
        volumeKeyPaging: volumeKeyPaging,
        markSettings: markSettings,
        bookmarkStyle: value,
        footnoteStyle: footnoteStyle,
        tts: tts,
      );

  /// 修改阅读页注释样式，保留其它阅读偏好。
  ReaderSettings copyWithFootnoteStyle(ReaderFootnoteStyle value) =>
      ReaderSettings(
        fontSize: fontSize,
        fontFamily: fontFamily,
        overrideEmbeddedFonts: overrideEmbeddedFonts,
        lineHeight: lineHeight,
        paragraphSpacing: paragraphSpacing,
        horizontalPadding: horizontalPadding,
        themeId: themeId,
        dayThemeId: dayThemeId,
        nightThemeId: nightThemeId,
        customThemeId: customThemeId,
        backgroundId: backgroundId,
        backgroundImageOpacity: backgroundImageOpacity,
        inkMode: inkMode,
        cornerInfo: cornerInfo,
        margins: margins,
        tapZones: tapZones,
        pageTurnMode: pageTurnMode,
        keepScreenOn: keepScreenOn,
        volumeKeyPaging: volumeKeyPaging,
        markSettings: markSettings,
        bookmarkStyle: bookmarkStyle,
        footnoteStyle: value,
        tts: tts,
      );

  /// 修改听书偏好，保留全部正文排版与阅读交互设置。
  ReaderSettings copyWithTts(ReaderTtsSettings value) => ReaderSettings(
    fontSize: fontSize,
    fontFamily: fontFamily,
    overrideEmbeddedFonts: overrideEmbeddedFonts,
    lineHeight: lineHeight,
    paragraphSpacing: paragraphSpacing,
    horizontalPadding: horizontalPadding,
    themeId: themeId,
    dayThemeId: dayThemeId,
    nightThemeId: nightThemeId,
    customThemeId: customThemeId,
    backgroundId: backgroundId,
    backgroundImageOpacity: backgroundImageOpacity,
    inkMode: inkMode,
    cornerInfo: cornerInfo,
    margins: margins,
    tapZones: tapZones,
    pageTurnMode: pageTurnMode,
    keepScreenOn: keepScreenOn,
    volumeKeyPaging: volumeKeyPaging,
    markSettings: markSettings,
    bookmarkStyle: bookmarkStyle,
    footnoteStyle: footnoteStyle,
    tts: value,
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
      other.dayThemeId == dayThemeId &&
      other.nightThemeId == nightThemeId &&
      other.customThemeId == customThemeId &&
      other.backgroundId == backgroundId &&
      other.backgroundImageOpacity == backgroundImageOpacity &&
      other.inkMode == inkMode &&
      other.margins == margins &&
      other.cornerInfo == cornerInfo &&
      other.tapZones == tapZones &&
      other.pageTurnMode == pageTurnMode &&
      other.keepScreenOn == keepScreenOn &&
      other.volumeKeyPaging == volumeKeyPaging &&
      other.markSettings == markSettings &&
      other.bookmarkStyle == bookmarkStyle &&
      other.footnoteStyle == footnoteStyle &&
      other.tts == tts;

  @override
  int get hashCode => Object.hash(
    fontSize,
    fontFamily,
    overrideEmbeddedFonts,
    lineHeight,
    paragraphSpacing,
    horizontalPadding,
    themeId,
    dayThemeId,
    nightThemeId,
    customThemeId,
    Object.hash(backgroundId, backgroundImageOpacity),
    inkMode,
    margins,
    cornerInfo,
    tapZones,
    pageTurnMode,
    keepScreenOn,
    volumeKeyPaging,
    markSettings,
    Object.hash(bookmarkStyle, footnoteStyle, tts),
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
  static const String keyCornerInfo = 'reader.cornerInfo';
  static const String keyThemeId = 'reader.themeId';
  static const String keyDayThemeId = 'reader.dayThemeId';
  static const String keyNightThemeId = 'reader.nightThemeId';
  static const String keyCustomThemeId = 'reader.customThemeId';
  static const String keyBackgroundId = 'reader.backgroundId';
  static const String keyBackgroundImageOpacity =
      'reader.backgroundImageOpacity';
  static const String keyInkMode = 'reader.inkMode';
  static const String keyPageTurnMode = 'reader.pageTurnMode';
  static const String keyKeepScreenOn = 'reader.keepScreenOn';
  static const String keyVolumeKeyPaging = 'reader.volumeKeyPaging';
  static const String keyBookmarkStyle = 'reader.bookmarkStyle';
  static const String keyFootnoteStyle = 'reader.footnoteStyle';

  /// 听书偏好（JSON）。
  static const String keyTts = 'reader.tts';
  static const String keyMarkLastColor = 'reader.mark.lastColor';
  static const String keyMarkLastStyle = 'reader.mark.lastStyle';
  static const String keyMarkStrokeWidth = 'reader.mark.strokeWidth';
  static const String keyMarkJoinBackgroundLines =
      'reader.mark.joinBackgroundLines';
  static const String keyMarkCustomColors = 'reader.mark.customColors';

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
      dayThemeId:
          await _library.getSetting(keyDayThemeId) ??
          ReaderSettingsDefaults.themeId,
      nightThemeId: await _library.getSetting(keyNightThemeId) ?? 'black',
      customThemeId: ReaderTheme.customById(
        await _library.getSetting(keyCustomThemeId),
      )?.id,
      backgroundId: await _library.getSetting(keyBackgroundId) ?? 'none',
      backgroundImageOpacity:
          (_readDouble(await _library.getSetting(keyBackgroundImageOpacity)) ??
                  ReaderSettingsDefaults.backgroundImageOpacity)
              .clamp(0, 1),
      inkMode: (await _library.getSetting(keyInkMode)) == 'true',
      margins: _readMargins(await _library.getSetting(keyMargins)),
      cornerInfo: _readCornerInfo(await _library.getSetting(keyCornerInfo)),
      tapZones: _readTapZones(await _library.getSetting(keyTapZones)),
      pageTurnMode: PageTurnMode.fromId(
        await _library.getSetting(keyPageTurnMode),
      ),
      keepScreenOn: (await _library.getSetting(keyKeepScreenOn)) == 'true',
      volumeKeyPaging:
          (await _library.getSetting(keyVolumeKeyPaging)) == 'true',
      markSettings: await _loadMarkSettings(),
      tts: _readTts(await _library.getSetting(keyTts)),
      bookmarkStyle: _readBookmarkStyle(
        await _library.getSetting(keyBookmarkStyle),
      ),
      footnoteStyle: ReaderFootnoteStyle.fromId(
        await _library.getSetting(keyFootnoteStyle),
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

  static ReaderCornerInfo _readCornerInfo(String? raw) {
    try {
      return ReaderCornerInfo.fromJson(jsonDecode(raw ?? '{}'));
    } on FormatException {
      return ReaderCornerInfo.defaults;
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

  static ReaderTtsSettings _readTts(String? raw) {
    if (raw == null || raw.isEmpty) return ReaderTtsSettings.defaults;
    try {
      final value = jsonDecode(raw);
      return value is Map<String, Object?>
          ? ReaderTtsSettings.fromJson(value)
          : ReaderTtsSettings.defaults;
    } catch (_) {
      return ReaderTtsSettings.defaults;
    }
  }

  /// 读取正文字体；自定义字体的文件可用性由打开阅读页时校验。
  static String? _readFontFamily(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return raw == ReaderSettingsDefaults.fontSong ||
            RegExp(r'^user_[0-9a-f]{64}$').hasMatch(raw)
        ? raw
        : null;
  }

  static ReaderBookmarkStyle _readBookmarkStyle(String? raw) {
    try {
      return ReaderBookmarkStyle.fromJson(jsonDecode(raw ?? '{}'));
    } on FormatException {
      return const ReaderBookmarkStyle();
    }
  }

  Future<ReaderMarkSettings> _loadMarkSettings() async {
    final color = int.tryParse(
      await _library.getSetting(keyMarkLastColor) ?? '',
    );
    final style = int.tryParse(
      await _library.getSetting(keyMarkLastStyle) ?? '',
    );
    final width = _readDouble(await _library.getSetting(keyMarkStrokeWidth));
    List<int> colors = const [];
    try {
      final raw = jsonDecode(
        await _library.getSetting(keyMarkCustomColors) ?? '[]',
      );
      if (raw is List<Object?>) {
        colors = raw
            .whereType<int>()
            .where((value) => value >= 0 && value <= 0xffffffff)
            .toSet()
            .take(8)
            .toList(growable: false);
      }
    } on FormatException {
      colors = const [];
    }
    return ReaderMarkSettings(
      lastColor: color != null && color >= 0 && color <= 0xffffffff
          ? color
          : defaultHighlightColor,
      lastStyle:
          ReaderAnnotationStyle.values.any(
            (value) => value.storageValue == style,
          )
          ? ReaderAnnotationStyle.fromStorage(style)
          : ReaderAnnotationStyle.underline,
      strokeWidth: const [1.0, 1.8, 2.6].contains(width) ? width! : 1.8,
      joinBackgroundLines:
          await _library.getSetting(keyMarkJoinBackgroundLines) == 'true',
      customColors: colors,
    );
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
    await _library.setSetting(keyDayThemeId, settings.dayThemeId);
    await _library.setSetting(keyNightThemeId, settings.nightThemeId);
    await _library.setSetting(keyCustomThemeId, settings.customThemeId ?? '');
    await _library.setSetting(keyBackgroundId, settings.backgroundId);
    await _library.setSetting(
      keyBackgroundImageOpacity,
      settings.backgroundImageOpacity.toString(),
    );
    await _library.setSetting(keyInkMode, settings.inkMode.toString());
    await _library.setSetting(keyPageTurnMode, settings.pageTurnMode.id);
    await _library.setSetting(
      keyKeepScreenOn,
      settings.keepScreenOn.toString(),
    );
    await _library.setSetting(
      keyVolumeKeyPaging,
      settings.volumeKeyPaging.toString(),
    );
    final margins = settings.margins;
    await _library.setSetting(
      keyMargins,
      margins == null ? '' : jsonEncode(margins.toJson()),
    );
    await _library.setSetting(
      keyTapZones,
      jsonEncode(settings.tapZones.toJson()),
    );
    await _library.setSetting(
      keyCornerInfo,
      jsonEncode(settings.cornerInfo.toJson()),
    );
    await _library.setSetting(
      keyBookmarkStyle,
      jsonEncode(settings.bookmarkStyle.toJson()),
    );
    await _library.setSetting(keyFootnoteStyle, settings.footnoteStyle.name);
    await _library.setSetting(keyTts, jsonEncode(settings.tts.toJson()));
    final mark = settings.markSettings;
    final color = mark.lastColor >= 0 && mark.lastColor <= 0xffffffff
        ? mark.lastColor
        : defaultHighlightColor;
    final width = const [1.0, 1.8, 2.6].contains(mark.strokeWidth)
        ? mark.strokeWidth
        : 1.8;
    await _library.setSetting(keyMarkLastColor, color.toString());
    await _library.setSetting(
      keyMarkLastStyle,
      mark.lastStyle.storageValue.toString(),
    );
    await _library.setSetting(keyMarkStrokeWidth, width.toString());
    await _library.setSetting(
      keyMarkJoinBackgroundLines,
      mark.joinBackgroundLines.toString(),
    );
    await _library.setSetting(
      keyMarkCustomColors,
      jsonEncode(
        mark.customColors
            .where((value) => value >= 0 && value <= 0xffffffff)
            .toSet()
            .take(8)
            .toList(),
      ),
    );
  }

  static double? _readDouble(String? value) {
    if (value == null) {
      return null;
    }
    return double.tryParse(value);
  }
}
