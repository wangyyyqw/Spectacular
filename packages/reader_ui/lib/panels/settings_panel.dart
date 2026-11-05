import 'package:flutter/material.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/font_face.dart';
import 'package:reader_core/css/reader_overrides.dart';

import '../paging/page_turn_mode.dart';
import 'custom_theme_dialog.dart';
import '../theme/reader_background.dart';
import '../theme/reader_theme.dart';

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

  /// 其它开关（墨水屏 / 恢复默认）。
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

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
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
      _fontFamily = widget.overrides.fontFamily;
      _overrideEmbeddedFonts = widget.overrides.overrideEmbeddedFonts;
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

  String get _sectionTitle => switch (widget.section) {
    SettingsSection.all || SettingsSection.type => '排版',
    SettingsSection.theme => '主题',
    SettingsSection.settings => '设置',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      key: const ValueKey<String>('settings-panel-surface'),
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 20, 4),
            child: Row(
              children: [
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
                    onPressed: _busyFont
                        ? null
                        : () {
                            setState(() {
                              _fontSize = ReaderSettingsDefaults.fontSize;
                              _fontFamily = null;
                              _overrideEmbeddedFonts = false;
                              _lineHeight = ReaderSettingsDefaults.lineHeight;
                              _paragraphSpacing =
                                  ReaderSettingsDefaults.paragraphSpacing;
                              _horizontalPadding =
                                  ReaderSettingsDefaults.horizontalPadding;
                            });
                            widget.onReset!();
                          },
                    child: const Text('恢复默认'),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              children: [
                if (widget.section == SettingsSection.all ||
                    widget.section == SettingsSection.type) ...[
                  Text('字体', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _fontChoice(
                        key: 'settings-font-book',
                        label: '书籍字体',
                        value: null,
                      ),
                      _fontChoice(
                        key: 'settings-font-song',
                        label: '宋体',
                        value: ReaderSettingsDefaults.fontSong,
                      ),
                      _fontChoice(
                        key: 'settings-font-hei',
                        label: '黑体',
                        value: ReaderSettingsDefaults.fontSans,
                      ),
                    ],
                  ),
                  if (widget.onPickFont != null || _customFonts.isNotEmpty)
                    _customFontControls(),
                  const SizedBox(height: 12),
                  _slider(
                    key: 'settings-font-size',
                    label: '字号',
                    value: _fontSize,
                    min: 12,
                    max: 28,
                    divisions: 16,
                    display: _fontSize.toStringAsFixed(0),
                    onChanged: (value) {
                      setState(() => _fontSize = value);
                      _emit();
                    },
                  ),
                  _slider(
                    key: 'settings-line-height',
                    label: '行高',
                    value: _lineHeight,
                    min: 1.2,
                    max: 2.4,
                    divisions: 12,
                    display: _lineHeight.toStringAsFixed(1),
                    onChanged: (value) {
                      setState(() => _lineHeight = value);
                      _emit();
                    },
                  ),
                  _slider(
                    key: 'settings-paragraph-spacing',
                    label: '段间距',
                    value: _paragraphSpacing,
                    min: 0,
                    max: 24,
                    divisions: 24,
                    display: _paragraphSpacing.toStringAsFixed(0),
                    onChanged: (value) {
                      setState(() => _paragraphSpacing = value);
                      _emit();
                    },
                  ),
                  if (!widget.marginsActive)
                    _slider(
                      key: 'settings-padding',
                      label: '页边距',
                      value: _horizontalPadding,
                      min: 8,
                      max: 40,
                      divisions: 16,
                      display: _horizontalPadding.toStringAsFixed(0),
                      onChanged: (value) {
                        setState(() => _horizontalPadding = value);
                        _emit();
                      },
                    ),
                  if (widget.onOpenMarginEditor != null) ...[
                    const SizedBox(height: 8),
                    _EntryButton(
                      key: const ValueKey<String>('settings-margin-editor'),
                      icon: Icons.aspect_ratio,
                      label: '边距调节器',
                      onTap: widget.onOpenMarginEditor!,
                    ),
                  ],
                ],
                if (widget.section == SettingsSection.all ||
                    widget.section == SettingsSection.theme) ...[
                  Text('主题', style: theme.textTheme.titleSmall),
                  if (widget.inkMode) ...[
                    const SizedBox(height: 6),
                    Text(
                      '墨水屏模式固定为纯黑白，关闭后可调整主题与背景',
                      key: const ValueKey<String>('settings-ink-theme-hint'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final item in ReaderTheme.themes)
                        _themeSwatch(
                          key: 'settings-theme-${item.id}',
                          theme: item,
                          selected:
                              !widget.inkMode && item.id == widget.themeId,
                          onTap: widget.inkMode
                              ? null
                              : () => widget.onThemeChanged(item.id),
                        ),
                      if (widget.customTheme case final custom?)
                        _themeSwatch(
                          key: 'settings-theme-custom',
                          theme: custom,
                          selected:
                              !widget.inkMode && custom.id == widget.themeId,
                          onTap: widget.inkMode
                              ? null
                              : () => widget.onThemeChanged(custom.id),
                        ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const ValueKey('settings-custom-theme-edit'),
                      onPressed: widget.inkMode ? null : _editTheme,
                      icon: const Icon(Icons.palette_outlined, size: 18),
                      label: Text(
                        widget.customTheme == null ? '自定义配色' : '编辑自定义配色',
                      ),
                    ),
                  ),
                  if (widget.onBackgroundChanged != null) ...[
                    const SizedBox(height: 16),
                    Text('背景', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final item in ReaderBackground.all)
                          _backgroundChip(
                            key: 'settings-bg-${item.id}',
                            background: item,
                            selected:
                                !widget.inkMode &&
                                item.id == widget.backgroundId,
                            onTap: widget.inkMode
                                ? null
                                : () => widget.onBackgroundChanged!(item.id),
                          ),
                      ],
                    ),
                    if (widget.onPickBackgroundImage != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          key: const ValueKey('settings-background-image'),
                          onPressed:
                              widget.inkMode || widget.pickingBackgroundImage
                              ? null
                              : widget.onPickBackgroundImage,
                          icon: const Icon(Icons.image_outlined, size: 18),
                          label: Text(
                            widget.pickingBackgroundImage
                                ? '正在载入图片…'
                                : ReaderBackground.byId(widget.backgroundId)
                                      .isImage
                                ? '更换背景图片'
                                : '选择背景图片',
                          ),
                        ),
                      ),
                    if (ReaderBackground.byId(widget.backgroundId).isImage)
                      const Text('图片背景已启用'),
                  ],
                ],
                if (widget.section == SettingsSection.all ||
                    widget.section == SettingsSection.settings) ...[
                  if (widget.onPageTurnModeChanged != null) ...[
                    const Text('翻页方式'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final mode in PageTurnMode.values)
                          ChoiceChip(
                            key: ValueKey('settings-page-turn-${mode.id}'),
                            label: Text(mode.label),
                            selected: mode == widget.pageTurnMode,
                            onSelected: (_) =>
                                widget.onPageTurnModeChanged!(mode),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (widget.onOpenTapZoneEditor != null) ...[
                    _EntryButton(
                      key: const ValueKey<String>('settings-tap-zones'),
                      icon: Icons.grid_on,
                      label: '点击区域设置',
                      onTap: widget.onOpenTapZoneEditor!,
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (widget.onInkModeChanged != null) ...[
                    const SizedBox(height: 12),
                    SwitchListTile(
                      key: const ValueKey<String>('settings-ink-mode'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('墨水屏模式'),
                      subtitle: const Text('纯黑白、禁用背景纹理、高亮改为下划线'),
                      value: widget.inkMode,
                      onChanged: widget.onInkModeChanged,
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fontChoice({
    required String key,
    required String label,
    required String? value,
  }) {
    return ChoiceChip(
      key: ValueKey<String>(key),
      label: Text(label),
      selected: _fontFamily == value,
      showCheckmark: false,
      onSelected: _busyFont ? null : (_) => _selectFont(value),
    );
  }

  Widget _customFontControls() {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        const SizedBox(height: 8),
        Row(children: [_customFontDropdown(), _fontImportButton()]),
        SwitchListTile(
          key: const ValueKey<String>('settings-override-embedded-fonts'),
          contentPadding: EdgeInsets.zero,
          title: Text('全书使用自定义字体', style: textTheme.bodyLarge),
          subtitle: Text(
            _isCustomFont
                ? (_overrideEmbeddedFonts ? '屏蔽 EPUB 内嵌字体' : '保留 EPUB 内嵌字体')
                : '选择自定义字体后可开启',
            style: textTheme.bodySmall,
          ),
          value: _isCustomFont && _overrideEmbeddedFonts,
          onChanged: !_isCustomFont || _busyFont
              ? null
              : (value) {
                  setState(() => _overrideEmbeddedFonts = value);
                  _emit();
                },
        ),
      ],
    );
  }

  Widget _customFontDropdown() {
    final textStyle = Theme.of(context).textTheme.bodyMedium;
    final selected = _customFonts.any((font) => font.family == _fontFamily)
        ? _fontFamily
        : null;
    return Expanded(
      child: DropdownButton<String>(
        key: const ValueKey<String>('settings-custom-font'),
        isExpanded: true,
        value: selected,
        style: textStyle,
        hint: Text('自定义字体', style: textStyle),
        items: [
          for (final font in _customFonts)
            DropdownMenuItem(
              value: font.family,
              child: Text(
                font.label,
                style: textStyle,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: _busyFont ? null : _selectSavedFont,
      ),
    );
  }

  Widget _fontImportButton() => Padding(
    padding: const EdgeInsets.only(left: 8),
    child: TextButton.icon(
      key: const ValueKey<String>('settings-import-font'),
      onPressed: widget.onPickFont == null || _busyFont ? null : _pickFont,
      icon: _busyFont
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.add, size: 18),
      label: Text(_loadingFont ? '加载中' : (_pickingFont ? '导入中' : '导入字体')),
    ),
  );

  Widget _slider({
    required String key,
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String display,
    required ValueChanged<double> onChanged,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: theme.textTheme.bodyMedium),
              const Spacer(),
              Text(
                display,
                key: ValueKey<String>('$key-value'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
          Slider(
            key: ValueKey<String>(key),
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _backgroundChip({
    required String key,
    required ReaderBackground background,
    required bool selected,
    required VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    return Opacity(
      opacity: onTap == null ? 0.42 : 1,
      child: InkWell(
        key: ValueKey<String>(key),
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Text(background.name, style: theme.textTheme.bodySmall),
        ),
      ),
    );
  }

  Widget _themeSwatch({
    required String key,
    required ReaderTheme theme,
    required bool selected,
    required VoidCallback? onTap,
  }) {
    return Opacity(
      opacity: onTap == null ? 0.42 : 1,
      child: InkWell(
        key: ValueKey<String>(key),
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Container(
          width: 64,
          height: 44,
          decoration: BoxDecoration(
            color: theme.background,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            theme.name,
            style: TextStyle(color: theme.text, fontSize: 12),
          ),
        ),
      ),
    );
  }
}

/// 列表入口按钮（设计稿 `.type-btn`：填充底、圆角 18、右侧箭头）。
class _EntryButton extends StatelessWidget {
  const _EntryButton({
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
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.onSurface.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          height: 36,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                icon,
                size: 16,
                color: scheme.onSurface.withValues(alpha: 0.8),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(fontSize: 12, color: scheme.onSurface),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                size: 16,
                color: scheme.onSurface.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
