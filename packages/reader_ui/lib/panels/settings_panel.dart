import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/font_face.dart';
import 'package:reader_core/css/reader_overrides.dart';

import '../paging/page_turn_mode.dart';
import '../tap_zones.dart';
import '../theme/reader_background.dart';
import '../theme/reader_drawer_style.dart';
import '../theme/reader_theme.dart';
import 'custom_theme_dialog.dart';

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

/// 宿主已保存的自定义字体，界面只使用族名与显示名称。
class ReaderFontOption {
  const ReaderFontOption({required this.family, required this.label});

  final String family;
  final String label;
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
  static const Color _accent = Color(0xFF5EC27D);

  static const List<PageTurnMode> _pageTurnOrder = <PageTurnMode>[
    PageTurnMode.coverStack,
    PageTurnMode.cover,
    PageTurnMode.simulationBessel,
    PageTurnMode.scroll,
    PageTurnMode.slideHorizontal,
    PageTurnMode.none,
  ];

  late double _fontSize =
      widget.overrides.fontSize ?? ReaderSettingsDefaults.fontSize;
  late String? _fontFamily = widget.overrides.fontFamily;
  late bool _overrideEmbeddedFonts = widget.overrides.overrideEmbeddedFonts;
  late List<ReaderFontOption> _customFonts = List.of(widget.customFonts);
  bool _pickingFont = false;
  bool _loadingFont = false;
  late double _lineHeight =
      widget.overrides.lineHeight ?? ReaderSettingsDefaults.lineHeight;
  late double _paragraphSpacing =
      widget.overrides.paragraphSpacing ??
      ReaderSettingsDefaults.paragraphSpacing;
  late double _horizontalPadding =
      widget.overrides.padding?.left ??
      ReaderSettingsDefaults.horizontalPadding;

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

  void _emit() => widget.onOverridesChanged(_build());

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
    _customFonts = {
      for (final font in _customFonts) font.family: font,
      for (final font in widget.customFonts) font.family: font,
    }.values.toList();
  }

  bool get _isCustomFont => _fontFamily?.startsWith('user_') ?? false;
  bool get _busyFont => _pickingFont || _loadingFont;

  void _selectFont(String? family) {
    if (_fontFamily == family) return;
    setState(() {
      if (!_isCustomFont || !(family?.startsWith('user_') ?? false)) {
        _overrideEmbeddedFonts = false;
      }
      _fontFamily = family;
    });
    _emit();
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

  Future<void> _selectSavedFont(String? family) async {
    if (family == null || family == _fontFamily || _busyFont) return;
    final load = widget.onLoadFont;
    if (load == null) {
      _selectFont(family);
      return;
    }
    setState(() => _loadingFont = true);
    try {
      await load(family);
      if (mounted) _selectFont(family);
    } catch (error) {
      if (mounted) _showFontError('字体加载失败', error);
    } finally {
      if (mounted) setState(() => _loadingFont = false);
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

  Future<void> _showFontPicker() async {
    if (_busyFont) return;
    final panelTheme = Theme.of(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: ReaderDrawerStyle.surfaceOf(panelTheme),
      showDragHandle: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Theme(
        data: panelTheme,
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.62,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(top: 8, bottom: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0E0E0),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 4, 20, 10),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _SheetTitle(),
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: <Widget>[
                      _fontOptionTile(
                        context,
                        key: 'settings-font-book',
                        label: '书籍字体',
                        value: null,
                      ),
                      _fontOptionTile(
                        context,
                        key: 'settings-font-song',
                        label: '宋体',
                        value: ReaderSettingsDefaults.fontSong,
                      ),
                      _fontOptionTile(
                        context,
                        key: 'settings-font-hei',
                        label: '黑体',
                        value: ReaderSettingsDefaults.fontSans,
                      ),
                      for (final font in _customFonts)
                        _fontOptionTile(
                          context,
                          key: 'settings-custom-font-${font.family}',
                          label: font.label,
                          value: font.family,
                          saved: true,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _fontOptionTile(
    BuildContext sheetContext, {
    required String key,
    required String label,
    required String? value,
    bool saved = false,
  }) {
    final selected = _fontFamily == value;
    final text = ReaderDrawerStyle.textOf(Theme.of(sheetContext));
    return InkWell(
      key: ValueKey<String>(key),
      onTap: _busyFont
          ? null
          : () {
              Navigator.of(sheetContext).pop();
              if (saved) {
                _selectSavedFont(value);
              } else {
                _selectFont(value);
              }
            },
      child: SizedBox(
        height: 48,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    color: selected ? _accent : text,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (selected) const Icon(Icons.check, size: 18, color: _accent),
            ],
          ),
        ),
      ),
    );
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
      color: ReaderDrawerStyle.surfaceOf(theme),
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
                  icon: const Icon(Icons.arrow_back, size: 20),
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
          icon: Icons.aspect_ratio,
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
                    icon: Icons.text_fields,
                    label: '选择自定义字体',
                    onPressed: _busyFont ? null : _showFontPicker,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _FontButton(
                    key: const ValueKey<String>('settings-import-font'),
                    icon: Icons.file_upload_outlined,
                    label: _loadingFont
                        ? '加载中'
                        : _pickingFont
                        ? '导入中'
                        : '导入自定义字体',
                    onPressed: widget.onPickFont == null || _busyFont
                        ? null
                        : _pickFont,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _compactSwitchRow(
              key: const ValueKey<String>('settings-override-embedded-fonts'),
              label: '全书使用自定义字体',
              value: _isCustomFont && _overrideEmbeddedFonts,
              onChanged: !_isCustomFont || _busyFont
                  ? null
                  : (value) {
                      setState(() => _overrideEmbeddedFonts = value);
                      _emit();
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
            icon: Icons.remove,
            onTap: clamped <= min ? null : () => setValue(clamped - step),
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
                ),
              ),
            ),
          ),
          _StepButton(
            key: ValueKey<String>('$sliderKey-increment'),
            icon: Icons.add,
            onTap: clamped >= max ? null : () => setValue(clamped + step),
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
      const _CornerPreview(),
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
            icon: Icons.grid_on,
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
                  ? Icon(
                      Icons.add,
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
    PageTurnMode.scroll => '滚动',
    PageTurnMode.slideHorizontal => '滑动',
    PageTurnMode.none => '无',
  };
}

class _SheetTitle extends StatelessWidget {
  const _SheetTitle();

  @override
  Widget build(BuildContext context) {
    return Text(
      '选择字体',
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: ReaderDrawerStyle.textOf(Theme.of(context)),
      ),
    );
  }
}

class _FontButton extends StatelessWidget {
  const _FontButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
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
          Icon(icon, size: 16),
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

  final IconData icon;
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
              Icon(icon, size: 18, color: text),
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

  final IconData icon;
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
          child: Icon(
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

  final IconData icon;
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
            Icon(icon, size: 18, color: ReaderDrawerStyle.secondaryOf(theme)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label, style: TextStyle(fontSize: 14, color: text)),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: ReaderDrawerStyle.mutedOf(theme),
            ),
          ],
        ),
      ),
    );
  }
}

class _CornerPreview extends StatelessWidget {
  const _CornerPreview();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 86,
      child: CustomPaint(
        painter: const _DashedRoundedRectPainter(
          color: Color(0xFFDDDDDD),
          radius: 8,
        ),
        child: Stack(
          children: const <Widget>[
            Positioned(
              top: 8,
              left: 8,
              child: _CornerChip(
                key: ValueKey<String>('settings-corner-top-left'),
                label: '时间',
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: _CornerChip(
                key: ValueKey<String>('settings-corner-top-right'),
                label: '书名',
              ),
            ),
            Positioned(
              bottom: 8,
              left: 8,
              child: _CornerChip(
                key: ValueKey<String>('settings-corner-bottom-left'),
                label: '进度',
              ),
            ),
            Positioned(
              bottom: 8,
              right: 8,
              child: _CornerChip(
                key: ValueKey<String>('settings-corner-bottom-right'),
                label: '电量',
              ),
            ),
            Center(
              child: Opacity(
                opacity: 0.5,
                child: Text(
                  '点击四角按钮修改信息',
                  style: TextStyle(fontSize: 11, color: Color(0xFF999999)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CornerChip extends StatelessWidget {
  const _CornerChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFE0E0E0)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, color: Color(0xFF333333)),
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
                    child: const Icon(
                      Icons.add,
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
                child: Icon(
                  Icons.image_outlined,
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
                child: Icon(
                  Icons.broken_image_outlined,
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

class _DashedRoundedRectPainter extends CustomPainter {
  const _DashedRoundedRectPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1),
      Radius.circular(radius),
    );
    canvas.drawRRect(rect, Paint()..color = const Color(0xFFF9F9F9));
    final path = Path()..addRRect(rect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + 5).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += 9;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRoundedRectPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
