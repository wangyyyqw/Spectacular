import 'package:flutter/material.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/reader_overrides.dart';

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
    this.backgroundId = 'none',
    this.onBackgroundChanged,
    this.inkMode = false,
    this.onInkModeChanged,
    this.onReset,
    this.onBack,
    this.section = SettingsSection.all,
  });

  /// 初始排版覆盖。
  final ReaderOverrides overrides;

  /// 当前主题 id。
  final String themeId;

  /// 排版变化（调用方应立即应用并持久化）。
  final ValueChanged<ReaderOverrides> onOverridesChanged;

  /// 主题变化。
  final ValueChanged<String> onThemeChanged;

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

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  late double _fontSize = widget.overrides.fontSize ??
      ReaderSettingsDefaults.fontSize;
  late double _lineHeight = widget.overrides.lineHeight ??
      ReaderSettingsDefaults.lineHeight;
  late double _paragraphSpacing = widget.overrides.paragraphSpacing ??
      ReaderSettingsDefaults.paragraphSpacing;
  late double _horizontalPadding =
      widget.overrides.padding?.left ?? ReaderSettingsDefaults.horizontalPadding;

  ReaderOverrides _build() => ReaderOverrides(
    fontSize: _fontSize,
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
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
                Text('排版', style: theme.textTheme.titleMedium),
                const Spacer(),
                if (widget.onReset != null)
                  TextButton(
                    key: const ValueKey<String>('settings-reset'),
                    onPressed: () {
                      setState(() {
                        _fontSize = ReaderSettingsDefaults.fontSize;
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
                ],
                if (widget.section == SettingsSection.all ||
                    widget.section == SettingsSection.theme) ...[
                Text('主题', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final item in ReaderTheme.themes)
                      _themeSwatch(
                        key: 'settings-theme-${item.id}',
                        theme: item,
                        selected: item.id == widget.themeId,
                        onTap: () => widget.onThemeChanged(item.id),
                      ),
                  ],
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
                              !widget.inkMode && item.id == widget.backgroundId,
                          onTap: () => widget.onBackgroundChanged!(item.id),
                        ),
                    ],
                  ),
                ],
                ],
                if (widget.section == SettingsSection.all ||
                    widget.section == SettingsSection.settings) ...[
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
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      key: ValueKey<String>(key),
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Text(background.name, style: theme.textTheme.bodySmall),
      ),
    );
  }

  Widget _themeSwatch({
    required String key,
    required ReaderTheme theme,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: ValueKey<String>(key),
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        width: 64,
        height: 44,
        decoration: BoxDecoration(
          color: theme.background,
          borderRadius: BorderRadius.circular(10),
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
    );
  }
}
