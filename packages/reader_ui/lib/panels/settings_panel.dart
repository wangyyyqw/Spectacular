import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/font_face.dart';
import 'package:reader_core/css/reader_overrides.dart';

import '../annotations/mark_settings.dart';
import '../icons/app_icon.dart';
import '../paging/page_turn_mode.dart';
import '../page_furniture/corner_info.dart';
import '../tap_zones.dart';
import '../theme/reader_background.dart';
import '../theme/reader_drawer_style.dart';
import '../theme/reader_frosted_surface.dart';
import '../theme/reader_theme.dart';
import 'custom_theme_dialog.dart';
import 'corner_info_editor.dart';
import 'font_picker_sheet.dart';

export 'font_picker_sheet.dart' show ReaderFontOption;

/// 阅读设置默认值（P4-21，与 Reeden/阅微的默认一致）。
abstract final class ReaderSettingsDefaults {
  /// 字号。
  static const double fontSize = 17;

  /// 行高倍数。
  static const double lineHeight = 1.6;

  /// 段间距。
  static const double paragraphSpacing = 10;

  /// 页边距（左右）。
  static const double horizontalPadding = 20;

  /// 内置宋体字族。
  static const String fontSong = FontFamilyAliases.song;

  /// 系统无衬线字族；经字体别名映射到系统中文字体回退链。
  static const String fontSans = 'sans-serif';

  /// 默认主题。
  static const String themeId = 'white';

  /// 默认覆盖设置。
  static const ReaderOverrides overrides = ReaderOverrides(
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
}

/// 设置面板的分段（设计稿把「主题 / 排版 / 设置」拆成三个抽屉面板）。
enum SettingsSection {
  /// 全部（旧菜单用）。
  all,

  /// 排版：字号/行高/段距/页边距。
  type,

  /// 主题与背景。
  theme,

  /// 其它开关（翻页方式、边角信息与阅读开关）。
  settings,
}

/// 设置面板（P4-21）：字号/行高/段距/页边距/主题，改动即时生效。
///
/// 翻页动画等「不触发重排」的项按 §42.3 与排版参数分开，这里只放排版与主题。
class SettingsPanel extends StatefulWidget {
  /// 创建设置面板。
  const SettingsPanel({
    super.key,
    required this.overrides,
    required this.themeId,
    required this.onOverridesChanged,
    required this.onThemeChanged,
    this.customTheme,
    this.backgroundImageLoader,
    this.onPickBackgroundImage,
    this.customFonts = const [],
    this.onPickFont,
    this.onLoadFont,
    this.onRenameFont,
    this.onRemoveFont,
    this.cornerInfo = ReaderCornerInfo.defaults,
    this.onCornerInfoChanged,
    this.pickingBackgroundImage = false,
    this.backgroundId = 'none',
    this.onBackgroundChanged,
    this.inkMode = false,
    this.onInkModeChanged,
    this.onReset,
    this.onBack,
    this.section = SettingsSection.all,
    this.onOpenMarginEditor,
    this.onOpenTapZoneEditor,
    this.onOpenMarkSettings,
    this.markSettings = const ReaderMarkSettings(),
    this.marginsActive = false,
    this.pageTurnMode = PageTurnMode.cover,
    this.onPageTurnModeChanged,
    this.tapZones = ReaderTapZones.defaults,
    this.onTapZonesChanged,
    this.keepScreenOn = false,
    this.onKeepScreenOnChanged,
    this.volumeKeyPaging = false,
    this.onVolumeKeyPagingChanged,
  });

  /// 初始排版覆盖。
  final ReaderOverrides overrides;

  /// 当前主题 id。
  final String themeId;

  /// 排版变化（调用方应立即应用并持久化）。
  final ValueChanged<ReaderOverrides> onOverridesChanged;

  /// 主题变化。
  final ValueChanged<String> onThemeChanged;

  /// 上次保存的自定义配色，切换内置主题后仍可复用。
  final ReaderTheme? customTheme;

  /// 宿主提供图片数据，UI 不访问文件系统。
  final Future<Uint8List> Function(String id)? backgroundImageLoader;

  /// 已导入的字体。
  final List<ReaderFontOption> customFonts;

  /// 宿主选择、校验并注册字体，取消返回 null。
  final Future<ReaderFontOption?> Function()? onPickFont;

  /// 使用已保存字体前，由宿主注册到排版引擎。
  final Future<void> Function(String family)? onLoadFont;

  /// 自定义字体管理由宿主更新文件和清单。
  final Future<ReaderFontOption> Function(String family, String name)?
  onRenameFont;
  final Future<void> Function(String family)? onRemoveFont;

  final ReaderCornerInfo cornerInfo;
  final ValueChanged<ReaderCornerInfo>? onCornerInfoChanged;

  /// 由宿主选择并保存图片。
  final VoidCallback? onPickBackgroundImage;

  /// 选择、解码图片期间禁止重复操作。
  final bool pickingBackgroundImage;

  /// 当前背景 id（P4-22）。
  final String backgroundId;

  /// 背景变化（纹理或纯色）。
  final ValueChanged<String>? onBackgroundChanged;

  /// 墨水屏模式（P4-23）。
  final bool inkMode;

  /// 墨水屏开关变化。
  final ValueChanged<bool>? onInkModeChanged;

  /// 恢复默认。
  final VoidCallback? onReset;

  /// 返回回调（嵌在菜单 sheet 内时显示返回按钮）。
  final VoidCallback? onBack;

  /// 只渲染某一段（设计稿抽屉面板按段拆分）。
  final SettingsSection section;

  /// 打开边距调节器（排版段入口）。
  final VoidCallback? onOpenMarginEditor;

  /// 打开九宫格点击区域编辑页（设置段入口）。
  final VoidCallback? onOpenTapZoneEditor;

  /// 打开划线外观与自定义颜色设置。
  final VoidCallback? onOpenMarkSettings;

  /// 当前划线默认外观。
  final ReaderMarkSettings markSettings;

  /// 已用边距调节器接管页边距时隐藏旧的统一页边距滑块。
  final bool marginsActive;

  /// 动画设置单独回调，不写入排版覆盖。
  final PageTurnMode pageTurnMode;
  final ValueChanged<PageTurnMode>? onPageTurnModeChanged;

  /// 九宫格点击区域配置。
  final ReaderTapZones tapZones;

  /// 九宫格点击区域变化。
  final ValueChanged<ReaderTapZones>? onTapZonesChanged;

  /// 阅读时保持屏幕常亮。
  final bool keepScreenOn;

  /// 屏幕常亮开关变化。
  final ValueChanged<bool>? onKeepScreenOnChanged;

  /// 用音量键翻页。
  final bool volumeKeyPaging;

  /// 音量键翻页开关变化。
  final ValueChanged<bool>? onVolumeKeyPagingChanged;

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  static const Duration _sliderCommitDelay = Duration(milliseconds: 80);

  static const List<PageTurnMode> _pageTurnOrder = <PageTurnMode>[
    PageTurnMode.coverStack,
    PageTurnMode.cover,
    PageTurnMode.simulationBessel,
    PageTurnMode.simulation3d,
    PageTurnMode.scroll,
    PageTurnMode.slideHorizontal,
    PageTurnMode.none,
  ];

  late double _fontSize =
      widget.overrides.fontSize ?? ReaderSettingsDefaults.fontSize;
  late String? _fontFamily = widget.overrides.fontFamily;
  late bool _overrideEmbeddedFonts = widget.overrides.overrideEmbeddedFonts;
  late List<ReaderFontOption> _customFonts = List.of(widget.customFonts);
  late ReaderCornerInfo _cornerInfo = widget.cornerInfo;
  bool _pickingFont = false;
  bool _choosingFont = false;
  late double _lineHeight =
      widget.overrides.lineHeight ?? ReaderSettingsDefaults.lineHeight;
  late double _paragraphSpacing =
      widget.overrides.paragraphSpacing ??
      ReaderSettingsDefaults.paragraphSpacing;
  late double _horizontalPadding =
      widget.overrides.padding?.left ??
      ReaderSettingsDefaults.horizontalPadding;
  Timer? _sliderCommitTimer;
  ReaderOverrides? _pendingSliderOverrides;

  ReaderOverrides _build() => ReaderOverrides(
    fontSize: _fontSize,
    fontFamily: _fontFamily,
    overrideEmbeddedFonts: _overrideEmbeddedFonts,
    lineHeight: _lineHeight,
    paragraphSpacing: _paragraphSpacing,
    padding: CssEdges(
      top: 16,
      right: _horizontalPadding,
      bottom: 16,
      left: _horizontalPadding,
    ),
  );

  void _emit({bool immediate = false}) {
    _pendingSliderOverrides = _build();
    _sliderCommitTimer?.cancel();
    if (immediate) {
      _flushSliderOverrides();
      return;
    }
    _sliderCommitTimer = Timer(_sliderCommitDelay, _flushSliderOverrides);
  }

  void _flushSliderOverrides() {
    _sliderCommitTimer?.cancel();
    _sliderCommitTimer = null;
    final next = _pendingSliderOverrides;
    _pendingSliderOverrides = null;
    if (next != null) {
      widget.onOverridesChanged(next);
    }
  }

  @override
  void dispose() {
    _sliderCommitTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SettingsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.overrides.fingerprint != widget.overrides.fingerprint) {
      _fontSize = widget.overrides.fontSize ?? ReaderSettingsDefaults.fontSize;
      _fontFamily = widget.overrides.fontFamily;
      _overrideEmbeddedFonts = widget.overrides.overrideEmbeddedFonts;
      _lineHeight =
          widget.overrides.lineHeight ?? ReaderSettingsDefaults.lineHeight;
      _paragraphSpacing =
          widget.overrides.paragraphSpacing ??
          ReaderSettingsDefaults.paragraphSpacing;
      _horizontalPadding =
          widget.overrides.padding?.left ??
          ReaderSettingsDefaults.horizontalPadding;
    }
    if (oldWidget.customFonts != widget.customFonts) {
      _customFonts = List.of(widget.customFonts);
    }
    if (oldWidget.cornerInfo != widget.cornerInfo) {
      _cornerInfo = widget.cornerInfo;
    }
  }

  bool get _isCustomFont => _fontFamily?.startsWith('user_') ?? false;
  bool get _busyFont => _pickingFont || _choosingFont;

  void _selectFont(String? family) {
    if (_fontFamily == family) return;
    setState(() {
      if (!_isCustomFont || !(family?.startsWith('user_') ?? false)) {
        _overrideEmbeddedFonts = false;
      }
      _fontFamily = family;
    });
    _emit(immediate: true);
  }

  Future<void> _pickFont() async {
    final pick = widget.onPickFont;
    if (pick == null || _busyFont) return;
    setState(() => _pickingFont = true);
    try {
      final font = await pick();
      if (!mounted || font == null) return;
      setState(() {
        _customFonts = {
          for (final saved in _customFonts) saved.family: saved,
          font.family: font,
        }.values.toList();
      });
      _selectFont(font.family);
    } catch (error) {
      if (!mounted) return;
      _showFontError('字体导入失败', error);
    } finally {
      if (mounted) setState(() => _pickingFont = false);
    }
  }

  void _showFontError(String action, Object error) {
    final message = error is FormatException
        ? error.message
        : '请重新导入有效的 TTF 或 OTF 字体文件';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$action：$message')));
  }

  Future<void> _editTheme() async {
    final result = await showDialog<ReaderTheme>(
      context: context,
      builder: (_) => CustomThemeDialog(
        theme: widget.customTheme ?? ReaderTheme.byId(widget.themeId),
      ),
    );
    if (mounted && result != null) widget.onThemeChanged(result.id);
  }

  String get _fontLabel {
    if (_fontFamily == null) return '书籍字体';
    if (_fontFamily == ReaderSettingsDefaults.fontSong) return '宋体';
    if (_fontFamily == ReaderSettingsDefaults.fontSans) return '黑体';
    return _customFonts
            .where((font) => font.family == _fontFamily)
            .firstOrNull
            ?.label ??
        '自定义字体';
  }

  Future<void> _showFontPicker() async {
    if (_busyFont) return;
    setState(() => _choosingFont = true);
    final selection = await showModalBottomSheet<ReaderFontSelection>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => ReaderFontPickerSheet(
        fonts: _customFonts,
        selected: _fontFamily,
        onLoad: widget.onLoadFont,
        onRename: widget.onRenameFont == null
            ? null
            : (family, name) async {
                final renamed = await widget.onRenameFont!(family, name);
                if (mounted) {
                  setState(
                    () => _customFonts = [
                      for (final font in _customFonts)
                        font.family == family ? renamed : font,
                    ],
                  );
                }
                return renamed;
              },
        onRemove: widget.onRemoveFont == null
            ? null
            : (family) async {
                await widget.onRemoveFont!(family);
                if (!mounted) return;
                setState(
                  () =>
                      _customFonts.removeWhere((font) => font.family == family),
                );
                if (_fontFamily == family) _selectFont(null);
              },
      ),
    );
    if (mounted) setState(() => _choosingFont = false);
    if (selection != null && mounted) _selectFont(selection.family);
  }

  String get _sectionTitle => switch (widget.section) {
    SettingsSection.all || SettingsSection.type => '排版',
    SettingsSection.theme => '主题',
    SettingsSection.settings => '设置',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final full = widget.section == SettingsSection.all;
    return Material(
      key: const ValueKey<String>('settings-panel-surface'),
      color: ReaderFrostedSurface.panelColorOf(
        context,
        fallback: ReaderDrawerStyle.surfaceOf(theme),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (full)
            _buildHeader(theme)
          else
            SizedBox(
              height: 0,
              child: Opacity(
                opacity: 0,
                child: Text(
                  _sectionTitle,
                  key: const ValueKey<String>('settings-title'),
                ),
              ),
            ),
          Expanded(
            child: ListView(
              padding: switch (widget.section) {
                SettingsSection.all => const EdgeInsets.fromLTRB(20, 8, 20, 16),
                SettingsSection.type => const EdgeInsets.fromLTRB(
                  20,
                  16,
                  20,
                  20,
                ),
                SettingsSection.theme => const EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  20,
                ),
                SettingsSection.settings => const EdgeInsets.fromLTRB(
                  16,
                  10,
                  16,
                  16,
                ),
              },
              children: switch (widget.section) {
                SettingsSection.all => <Widget>[
                  ..._typeChildren(theme, legacyPadding: true),
                  const SizedBox(height: 24),
                  ..._themeChildren(theme),
                  const SizedBox(height: 24),
                  ..._settingsChildren(theme, includeReset: false),
                ],
                SettingsSection.type => _typeChildren(theme),
                SettingsSection.theme => _themeChildren(theme),
                SettingsSection.settings => _settingsChildren(theme),
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 20, 4),
          child: Row(
            children: <Widget>[
              if (widget.onBack != null)
                IconButton(
                  key: const ValueKey<String>('settings-back'),
                  icon: const AppIcon(AppGlyph.arrowBack, size: 20),
                  onPressed: widget.onBack,
                  tooltip: '返回',
                ),
              Text(
                _sectionTitle,
                key: const ValueKey<String>('settings-title'),
                style: theme.textTheme.titleMedium,
              ),
              const Spacer(),
              if (widget.onReset != null)
                TextButton(
                  key: const ValueKey<String>('settings-reset'),
                  onPressed: _busyFont ? null : _reset,
                  child: const Text('恢复默认'),
                ),
            ],
          ),
        ),
        Divider(height: 1, color: ReaderDrawerStyle.dividerOf(theme)),
      ],
    );
  }

  void _reset() {
    _sliderCommitTimer?.cancel();
    _sliderCommitTimer = null;
    _pendingSliderOverrides = null;
    setState(() {
      _fontSize = ReaderSettingsDefaults.fontSize;
      _fontFamily = null;
      _overrideEmbeddedFonts = false;
      _lineHeight = ReaderSettingsDefaults.lineHeight;
      _paragraphSpacing = ReaderSettingsDefaults.paragraphSpacing;
      _horizontalPadding = ReaderSettingsDefaults.horizontalPadding;
    });
    widget.onReset?.call();
  }

  List<Widget> _typeChildren(ThemeData theme, {bool legacyPadding = false}) {
    return <Widget>[
      _typographyRow(
        theme: theme,
        label: '字号',
        value: _fontSize,
        min: 12,
        max: 32,
        step: 1,
        divisions: 20,
        display: _fontSize.toStringAsFixed(0),
        sliderKey: 'settings-font-size',
        onChanged: (value) {
          setState(() => _fontSize = value);
          _emit();
        },
      ),
      _typographyRow(
        theme: theme,
        label: '行高',
        value: _lineHeight,
        min: 1.2,
        max: 3.0,
        step: 0.1,
        divisions: 18,
        display: _lineHeight.toStringAsFixed(1),
        sliderKey: 'settings-line-height',
        onChanged: (value) {
          setState(() => _lineHeight = value);
          _emit();
        },
      ),
      _typographyRow(
        theme: theme,
        label: '段距',
        value: _paragraphSpacing,
        min: 0,
        max: 40,
        step: 1,
        divisions: 40,
        display: _paragraphSpacing.toStringAsFixed(0),
        sliderKey: 'settings-paragraph-spacing',
        onChanged: (value) {
          setState(() => _paragraphSpacing = value);
          _emit();
        },
      ),
      if (legacyPadding && !widget.marginsActive)
        _legacyPaddingSlider(theme, key: 'settings-padding'),
      if (widget.onOpenMarginEditor != null) ...<Widget>[
        _WideActionButton(
          key: const ValueKey<String>('settings-margin-editor'),
          icon: AppGlyph.pageMargin,
          label: '边距调节',
          onTap: widget.onOpenMarginEditor!,
        ),
        const SizedBox(height: 24),
      ],
      Container(
        padding: const EdgeInsets.only(top: 20),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: ReaderDrawerStyle.dividerOf(theme)),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              '字体设置',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: ReaderDrawerStyle.textOf(theme),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: _FontButton(
                    key: const ValueKey<String>('settings-font-picker'),
                    icon: AppGlyph.textFields,
                    label: '选择字体',
                    onPressed: _busyFont ? null : _showFontPicker,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _FontButton(
                    key: const ValueKey<String>('settings-import-font'),
                    icon: AppGlyph.upload,
                    label: _pickingFont ? '导入中' : '导入自定义字体',
                    onPressed: widget.onPickFont == null || _busyFont
                        ? null
                        : _pickFont,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '当前：$_fontLabel',
              key: const ValueKey('settings-current-font'),
              style: TextStyle(
                fontSize: 12,
                color: ReaderDrawerStyle.textOf(theme),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '支持 TTF、OTF，最大 50MB。缺字会使用内置字体补全。',
              style: TextStyle(
                fontSize: 11,
                color: ReaderDrawerStyle.secondaryOf(theme),
              ),
            ),
            const SizedBox(height: 8),
            _compactSwitchRow(
              key: const ValueKey<String>('settings-override-embedded-fonts'),
              label: '全书使用自定义字体',
              value: _isCustomFont && _overrideEmbeddedFonts,
              onChanged: !_isCustomFont || _busyFont
                  ? null
                  : (value) {
                      setState(() => _overrideEmbeddedFonts = value);
                      _emit(immediate: true);
                    },
            ),
          ],
        ),
      ),
    ];
  }

  Widget _typographyRow({
    required ThemeData theme,
    required String label,
    required double value,
    required double min,
    required double max,
    required double step,
    required int divisions,
    required String display,
    required String sliderKey,
    required ValueChanged<double> onChanged,
  }) {
    final clamped = value.clamp(min, max).toDouble();
    void setValue(double next) {
      final rounded = (next.clamp(min, max) / step).round() * step;
      onChanged(double.parse(rounded.toStringAsFixed(2)));
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: ReaderDrawerStyle.textOf(theme),
              ),
            ),
          ),
          _StepButton(
            key: ValueKey<String>('$sliderKey-decrement'),
            icon: AppGlyph.remove,
            onTap: clamped <= min
                ? null
                : () {
                    setValue(clamped - step);
                    _flushSliderOverrides();
                  },
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  activeTrackColor: ReaderDrawerStyle.textOf(theme),
                  inactiveTrackColor: ReaderDrawerStyle.optionBorderOf(theme),
                  thumbColor: ReaderDrawerStyle.surfaceOf(theme),
                  thumbShape: _OutlinedThumbShape(
                    color: ReaderDrawerStyle.textOf(theme),
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 16,
                  ),
                  overlayColor: ReaderDrawerStyle.textOf(theme)
                      .withValues(alpha: 0.08),
                  trackShape: const RoundedRectSliderTrackShape(),
                  tickMarkShape: SliderTickMarkShape.noTickMark,
                ),
                child: Slider(
                  key: ValueKey<String>(sliderKey),
                  value: clamped,
                  min: min,
                  max: max,
                  divisions: divisions,
                  onChanged: setValue,
                  onChangeEnd: (_) => _flushSliderOverrides(),
                ),
              ),
            ),
          ),
          _StepButton(
            key: ValueKey<String>('$sliderKey-increment'),
            icon: AppGlyph.add,
            onTap: clamped >= max
                ? null
                : () {
                    setValue(clamped + step);
                    _flushSliderOverrides();
                  },
          ),
          SizedBox(
            width: 36,
            child: Text(
              display,
              key: ValueKey<String>('$sliderKey-value'),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 14,
                color: ReaderDrawerStyle.secondaryOf(theme),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legacyPaddingSlider(ThemeData theme, {required String key}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                '页边距',
                style: TextStyle(
                  fontSize: 13,
                  color: ReaderDrawerStyle.textOf(theme),
                ),
              ),
              const Spacer(),
              Text(
                _horizontalPadding.toStringAsFixed(0),
                style: TextStyle(
                  fontSize: 12,
                  color: ReaderDrawerStyle.mutedOf(theme),
                ),
              ),
            ],
          ),
          Slider(
            key: ValueKey<String>(key),
            value: _horizontalPadding.clamp(8, 40),
            min: 8,
            max: 40,
            divisions: 16,
            onChanged: (value) {
              setState(() => _horizontalPadding = value);
              _emit();
            },
            onChangeEnd: (_) => _flushSliderOverrides(),
          ),
        ],
      ),
    );
  }

  List<Widget> _themeChildren(ThemeData theme) {
    final text = ReaderDrawerStyle.textOf(theme);
    final muted = ReaderDrawerStyle.mutedOf(theme);
    return <Widget>[
      Text(
        '纯色',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          height: 18 / 13,
          color: text,
        ),
      ),
      if (widget.inkMode) ...<Widget>[
        const SizedBox(height: 6),
        Text(
          '墨水屏模式固定为纯黑白，关闭后可调整主题与背景',
          key: const ValueKey<String>('settings-ink-theme-hint'),
          style: TextStyle(fontSize: 12, color: muted),
        ),
      ],
      const SizedBox(height: 4),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: <Widget>[
            for (final item in ReaderTheme.themes) ...<Widget>[
              _themeCircle(
                key: 'settings-theme-${item.id}',
                color: item.background,
                selected: !widget.inkMode && item.id == widget.themeId,
                onTap: widget.inkMode
                    ? null
                    : () => widget.onThemeChanged(item.id),
              ),
              const SizedBox(width: 12),
            ],
            _customColorCircle(),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Text(
        '纹理',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          height: 18 / 13,
          color: text,
        ),
      ),
      const SizedBox(height: 10),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            for (
              var index = 0;
              index < ReaderBackground.all.length;
              index++
            ) ...<Widget>[
              if (index > 0) const SizedBox(width: 8),
              _backgroundOption(
                key: 'settings-bg-${ReaderBackground.all[index].id}',
                label: ReaderBackground.all[index].name,
                selected:
                    !widget.inkMode &&
                    ReaderBackground.all[index].id == widget.backgroundId,
                onTap: widget.inkMode || widget.onBackgroundChanged == null
                    ? null
                    : () => widget.onBackgroundChanged!(
                        ReaderBackground.all[index].id,
                      ),
              ),
            ],
          ],
        ),
      ),
      if (widget.onBackgroundChanged != null) ...<Widget>[
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            '图片',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 18 / 13,
              color: text,
            ),
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: <Widget>[
              for (final background in <ReaderBackground>[
                ReaderBackground.paper,
                ReaderBackground.wood,
                ReaderBackground.gray,
                ReaderBackground.parchment,
              ]) ...<Widget>[
                _builtInImageTile(
                  key: 'settings-image-${background.id}',
                  background: background,
                  selected: background.id == widget.backgroundId,
                  onTap: widget.inkMode
                      ? null
                      : () => widget.onBackgroundChanged!(background.id),
                ),
                const SizedBox(width: 12),
              ],
              if (ReaderBackground.byId(widget.backgroundId).isImage &&
                  widget.backgroundImageLoader != null) ...<Widget>[
                _UserBackgroundThumbnail(
                  key: const ValueKey<String>('settings-image-current'),
                  id: widget.backgroundId,
                  loader: widget.backgroundImageLoader!,
                  selected: true,
                ),
                const SizedBox(width: 12),
              ],
              if (widget.onPickBackgroundImage != null)
                _AddImageTile(
                  key: const ValueKey<String>('settings-background-image'),
                  busy: widget.pickingBackgroundImage,
                  onTap: widget.inkMode || widget.pickingBackgroundImage
                      ? null
                      : widget.onPickBackgroundImage,
                ),
            ],
          ),
        ),
      ],
    ];
  }

  List<Widget> _settingsChildren(ThemeData theme, {bool includeReset = true}) {
    return <Widget>[
      if (widget.onOpenMarkSettings != null) ...[
        Text(
          '划线',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: ReaderDrawerStyle.textOf(theme),
          ),
        ),
        const SizedBox(height: 4),
        _SettingsEntryRow(
          key: const ValueKey<String>('settings-mark'),
          icon: AppGlyph.formatUnderlined,
          label: '默认样式、颜色与线宽',
          onTap: widget.onOpenMarkSettings!,
        ),
        Text(
          '${widget.markSettings.lastStyle.label} · '
          '${widget.markSettings.strokeWidth.toStringAsFixed(1)}dp · '
          '自定义颜色 ${widget.markSettings.customColors.length}/8',
          style: TextStyle(
            fontSize: 12,
            color: ReaderDrawerStyle.secondaryOf(theme),
          ),
        ),
        const SizedBox(height: 12),
        _SettingsDivider(color: ReaderDrawerStyle.dividerOf(theme)),
        const SizedBox(height: 12),
      ],
      Text(
        '选择翻页方式',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: ReaderDrawerStyle.textOf(theme),
        ),
      ),
      const SizedBox(height: 8),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(
          children: <Widget>[
            for (
              var index = 0;
              index < _pageTurnOrder.length;
              index++
            ) ...<Widget>[
              if (index > 0) const SizedBox(width: 6),
              _PageTurnOption(
                key: ValueKey<String>(
                  'settings-page-turn-${_pageTurnOrder[index].id}',
                ),
                label: _shortPageTurnLabel(_pageTurnOrder[index]),
                selected: widget.pageTurnMode == _pageTurnOrder[index],
                onTap: widget.onPageTurnModeChanged == null
                    ? null
                    : () =>
                          widget.onPageTurnModeChanged!(_pageTurnOrder[index]),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 10),
      _SettingsDivider(color: ReaderDrawerStyle.dividerOf(theme)),
      const SizedBox(height: 10),
      Text(
        '边角信息设置',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: ReaderDrawerStyle.textOf(theme),
        ),
      ),
      const SizedBox(height: 6),
      CornerInfoEditor(
        info: _cornerInfo,
        onChanged: widget.onCornerInfoChanged == null
            ? null
            : (info) {
                setState(() => _cornerInfo = info);
                widget.onCornerInfoChanged!(info);
              },
      ),
      const SizedBox(height: 10),
      _SettingsDivider(color: ReaderDrawerStyle.dividerOf(theme)),
      _compactSwitchRow(
        key: const ValueKey<String>('settings-fullscreen-next'),
        label: '全屏点击下一页',
        value: widget.tapZones.isFullScreenNext,
        onChanged: widget.onTapZonesChanged == null
            ? null
            : (value) => widget.onTapZonesChanged!(
                value ? ReaderTapZones.fullScreenNext : ReaderTapZones.defaults,
              ),
      ),
      _SettingsDivider(color: ReaderDrawerStyle.dividerOf(theme)),
      _compactSwitchRow(
        key: const ValueKey<String>('settings-keep-screen-on'),
        label: '屏幕常亮',
        value: widget.keepScreenOn,
        onChanged: widget.onKeepScreenOnChanged,
      ),
      _SettingsDivider(color: ReaderDrawerStyle.dividerOf(theme)),
      _compactSwitchRow(
        key: const ValueKey<String>('settings-volume-key-paging'),
        label: '音量键翻页',
        value: widget.volumeKeyPaging,
        onChanged: widget.onVolumeKeyPagingChanged,
      ),
      if (widget.onOpenTapZoneEditor != null ||
          widget.onInkModeChanged != null ||
          (includeReset && widget.onReset != null)) ...<Widget>[
        const SizedBox(height: 12),
        _SettingsDivider(color: ReaderDrawerStyle.dividerOf(theme)),
        const SizedBox(height: 8),
        if (widget.onOpenTapZoneEditor != null)
          _SettingsEntryRow(
            key: const ValueKey<String>('settings-tap-zones'),
            icon: AppGlyph.grid,
            label: '点击区域设置',
            onTap: widget.onOpenTapZoneEditor!,
          ),
        if (widget.onInkModeChanged != null)
          _compactSwitchRow(
            key: const ValueKey<String>('settings-ink-mode'),
            label: '墨水屏模式',
            value: widget.inkMode,
            onChanged: widget.onInkModeChanged,
          ),
        if (includeReset && widget.onReset != null)
          Align(
            alignment: Alignment.center,
            child: TextButton(
              key: const ValueKey<String>('settings-reset'),
              onPressed: _busyFont ? null : _reset,
              child: Text(
                '恢复默认',
                style: TextStyle(
                  fontSize: 12,
                  color: ReaderDrawerStyle.mutedOf(theme),
                ),
              ),
            ),
          ),
      ],
    ];
  }

  Widget _compactSwitchRow({
    required Key key,
    required String label,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    final text = ReaderDrawerStyle.textOf(Theme.of(context));
    return SizedBox(
      height: 44,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 14, color: text)),
          ),
          _CompactSwitch(key: key, value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _themeCircle({
    required String key,
    required Color color,
    required bool selected,
    required VoidCallback? onTap,
    bool dashed = false,
    bool showPlus = false,
    Color plusColor = ReaderDrawerStyle.textSecondary,
  }) {
    final theme = Theme.of(context);
    final dark = color.computeLuminance() < 0.35;
    return Opacity(
      opacity: onTap == null ? 0.42 : 1,
      child: InkWell(
        key: ValueKey<String>(key),
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox.square(
          dimension: 44,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: dashed ? ReaderDrawerStyle.optionFillOf(theme) : color,
              shape: BoxShape.circle,
              border: dashed
                  ? null
                  : selected
                  ? Border.all(
                      color: dark
                          ? ReaderDrawerStyle.surface
                          : ReaderDrawerStyle.selectedRing,
                      width: 2.5,
                    )
                  : Border.all(
                      color: theme.brightness == Brightness.dark
                          ? theme.colorScheme.outlineVariant
                          : Colors.black.withValues(alpha: 0.08),
                    ),
              boxShadow: selected
                  ? <BoxShadow>[
                      BoxShadow(
                        color: ReaderDrawerStyle.selectedRing.withValues(
                          alpha: dark ? 1 : 0.2,
                        ),
                        blurRadius: dark ? 0 : 6,
                        spreadRadius: dark ? 1.5 : 0,
                        offset: dark ? Offset.zero : const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: CustomPaint(
              painter: dashed
                  ? _DashedCirclePainter(
                      color: ReaderDrawerStyle.faintOf(theme),
                    )
                  : null,
              child: showPlus
                  ? AppIcon(
                      AppGlyph.add,
                      size: 20,
                      color: dark
                          ? ReaderDrawerStyle.surface
                          : dashed
                          ? ReaderDrawerStyle.secondaryOf(theme)
                          : plusColor,
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }

  Widget _customColorCircle() {
    final custom = widget.customTheme;
    final circle = custom == null
        ? _themeCircle(
            key: 'settings-custom-theme-picker',
            color: Colors.transparent,
            dashed: true,
            showPlus: true,
            selected: false,
            onTap: widget.inkMode ? null : _editTheme,
          )
        : _themeCircle(
            key: 'settings-theme-custom',
            color: custom.background,
            showPlus: true,
            plusColor: custom.text,
            selected: !widget.inkMode && custom.id == widget.themeId,
            onTap: widget.inkMode
                ? null
                : () => widget.onThemeChanged(custom.id),
          );
    return KeyedSubtree(
      key: const ValueKey<String>('settings-custom-theme-edit'),
      child: circle,
    );
  }

  Widget _backgroundOption({
    required String key,
    required String label,
    required bool selected,
    required VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final surface = ReaderDrawerStyle.surfaceOf(theme);
    return Opacity(
      opacity: onTap == null ? 0.42 : 1,
      child: InkWell(
        key: ValueKey<String>(key),
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Container(
          padding: selected
              ? const EdgeInsets.symmetric(horizontal: 13, vertical: 5)
              : const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: selected
                  ? ReaderDrawerStyle.textOf(theme)
                  : ReaderDrawerStyle.optionBorderOf(theme),
              width: selected ? 2 : 1,
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              fontSize: 13,
              height: 18 / 13,
              fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
              color: ReaderDrawerStyle.textOf(theme),
            ),
          ),
        ),
      ),
    );
  }

  Widget _builtInImageTile({
    required String key,
    required ReaderBackground background,
    required bool selected,
    required VoidCallback? onTap,
  }) {
    final colors = switch (background.id) {
      'wood' => const <Color>[Color(0xFF8A5A38), Color(0xFF4A2E1C)],
      'gray' => const <Color>[Color(0xFFF5F7FA), Color(0xFFC3CFE2)],
      'parchment' => const <Color>[Color(0xFFF3D9A4), Color(0xFFD8AE68)],
      _ => const <Color>[Color(0xFFFDFBFB), Color(0xFFEBEDEE)],
    };
    return Opacity(
      opacity: onTap == null ? 0.42 : 1,
      child: InkWell(
        key: ValueKey<String>(key),
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: _ImageTileFrame(
          selected: selected,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colors,
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _shortPageTurnLabel(PageTurnMode mode) => switch (mode) {
    PageTurnMode.coverStack => '堆叠',
    PageTurnMode.cover => '覆盖',
    PageTurnMode.simulationBessel => '仿真',
    PageTurnMode.simulation3d => '3D',
    PageTurnMode.scroll => '滚动',
    PageTurnMode.slideHorizontal => '滑动',
    PageTurnMode.none => '无',
  };
}

class _FontButton extends StatelessWidget {
  const _FontButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final AppGlyph icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: ReaderDrawerStyle.textOf(theme),
        disabledForegroundColor: ReaderDrawerStyle.faintOf(theme),
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        backgroundColor: ReaderDrawerStyle.surfaceOf(theme),
        side: BorderSide(color: ReaderDrawerStyle.optionBorderOf(theme)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          AppIcon(icon, size: 16),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _WideActionButton extends StatelessWidget {
  const _WideActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final AppGlyph icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = ReaderDrawerStyle.textOf(theme);
    return Material(
      color: ReaderDrawerStyle.optionFillOf(theme),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: ReaderDrawerStyle.dividerOf(theme)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: 44,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              AppIcon(icon, size: 18, color: text),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(fontSize: 14, color: text)),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({super.key, required this.icon, required this.onTap});

  final AppGlyph icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: ReaderDrawerStyle.optionFillOf(theme),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox.square(
          dimension: 32,
          child: AppIcon(
            icon,
            size: 18,
            color: onTap == null
                ? ReaderDrawerStyle.faintOf(theme)
                : ReaderDrawerStyle.textOf(theme),
          ),
        ),
      ),
    );
  }
}

class _OutlinedThumbShape extends SliderComponentShape {
  const _OutlinedThumbShape({required this.color});

  final Color color;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size.square(16);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final fill = Paint()..color = sliderTheme.thumbColor ?? Colors.white;
    final outline = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, 8, fill);
    canvas.drawCircle(center, 7, outline);
  }
}

class _CompactSwitch extends StatelessWidget {
  const _CompactSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return Semantics(
      button: true,
      toggled: value,
      enabled: enabled,
      child: Opacity(
        opacity: enabled ? 1 : 0.42,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? () => onChanged!(!value) : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 42,
            height: 22,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: value ? const Color(0xFF5EC27D) : const Color(0xFFE5E5E5),
              borderRadius: BorderRadius.circular(11),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 18,
                height: 18,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 3,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PageTurnOption extends StatelessWidget {
  const _PageTurnOption({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Opacity(
      opacity: onTap == null ? 0.42 : 1,
      child: Material(
        color: selected
            ? const Color(0xFFE8F5E9)
            : ReaderDrawerStyle.optionFillOf(theme),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(
            color: selected ? const Color(0xFFA5D6A7) : Colors.transparent,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                color: selected
                    ? const Color(0xFF2E7D32)
                    : ReaderDrawerStyle.textOf(theme),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(height: 1, color: color);
}

class _SettingsEntryRow extends StatelessWidget {
  const _SettingsEntryRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final AppGlyph icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = ReaderDrawerStyle.textOf(theme);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 44,
        child: Row(
          children: <Widget>[
            AppIcon(
              icon,
              size: 18,
              color: ReaderDrawerStyle.secondaryOf(theme),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label, style: TextStyle(fontSize: 14, color: text)),
            ),
            AppIcon(
              AppGlyph.chevronRight,
              size: 18,
              color: ReaderDrawerStyle.mutedOf(theme),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageTileFrame extends StatelessWidget {
  const _ImageTileFrame({required this.selected, required this.child});

  final bool selected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 160,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected ? const Color(0xFF5EC27D) : Colors.transparent,
          width: 2,
        ),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(6), child: child),
    );
  }
}

class _AddImageTile extends StatelessWidget {
  const _AddImageTile({super.key, required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.6 : 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 72,
          height: 160,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFF0F0F0)),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x08000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: SizedBox.square(
            dimension: 45,
            child: busy
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : CustomPaint(
                    painter: const _DashedCirclePainter(
                      color: Color(0xFFCCCCCC),
                    ),
                    child: const AppIcon(
                      AppGlyph.add,
                      size: 22,
                      color: Color(0xFF666666),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _UserBackgroundThumbnail extends StatefulWidget {
  const _UserBackgroundThumbnail({
    super.key,
    required this.id,
    required this.loader,
    required this.selected,
  });

  final String id;
  final Future<Uint8List> Function(String id) loader;
  final bool selected;

  @override
  State<_UserBackgroundThumbnail> createState() =>
      _UserBackgroundThumbnailState();
}

class _UserBackgroundThumbnailState extends State<_UserBackgroundThumbnail> {
  late Future<Uint8List> _bytes = widget.loader(widget.id);

  @override
  void didUpdateWidget(covariant _UserBackgroundThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id || oldWidget.loader != widget.loader) {
      _bytes = widget.loader(widget.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _ImageTileFrame(
      selected: widget.selected,
      child: FutureBuilder<Uint8List>(
        future: _bytes,
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes == null) {
            return const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[Color(0xFFE7E7E7), Color(0xFFBDBDBD)],
                ),
              ),
              child: Center(
                child: AppIcon(
                  AppGlyph.image,
                  size: 24,
                  color: Color(0xFF777777),
                ),
              ),
            );
          }
          return Image.memory(
            bytes,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => const ColoredBox(
              color: Color(0xFFEEEEEE),
              child: Center(
                child: AppIcon(
                  AppGlyph.brokenImage,
                  size: 24,
                  color: Color(0xFF999999),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DashedCirclePainter extends CustomPainter {
  const _DashedCirclePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()
      ..addOval(
        Rect.fromCircle(
          center: size.center(Offset.zero),
          radius: size.shortestSide / 2 - 0.75,
        ),
      );
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + 4).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += 7;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedCirclePainter oldDelegate) =>
      oldDelegate.color != color;
}
