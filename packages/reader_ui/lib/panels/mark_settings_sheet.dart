import 'package:flutter/material.dart';

import '../annotations/annotation_appearance_editor.dart';
import '../annotations/annotation_quote_preview.dart';
import '../annotations/mark_settings.dart';
import '../theme/reader_section_slider.dart';
import 'reader_settings_sheet.dart';

/// 阅读设置中的划线分区。
class ReaderMarkSettingsSheet extends StatefulWidget {
  /// 创建划线设置面板。
  const ReaderMarkSettingsSheet({
    super.key,
    required this.settings,
    this.inkMode = false,
  });

  /// 当前偏好。
  final ReaderMarkSettings settings;

  /// 墨水屏模式。
  final bool inkMode;
  @override
  State<ReaderMarkSettingsSheet> createState() =>
      _ReaderMarkSettingsSheetState();
}

class _ReaderMarkSettingsSheetState extends State<ReaderMarkSettingsSheet> {
  late ReaderMarkSettings _settings = widget.settings;

  List<ReaderAnnotationAppearanceSection> get _sections => widget.inkMode
      ? const [ReaderAnnotationAppearanceSection.line]
      : const [
          ReaderAnnotationAppearanceSection.color,
          ReaderAnnotationAppearanceSection.background,
          ReaderAnnotationAppearanceSection.line,
          ReaderAnnotationAppearanceSection.width,
        ];

  String _sectionLabel(ReaderAnnotationAppearanceSection section) =>
      switch (section) {
        ReaderAnnotationAppearanceSection.all => '全部设置',
        ReaderAnnotationAppearanceSection.color => '颜色',
        ReaderAnnotationAppearanceSection.background => '背景',
        ReaderAnnotationAppearanceSection.line => '线条',
        ReaderAnnotationAppearanceSection.width => '线宽',
      };

  Widget _sectionTabs() => ReaderSectionSlider(
    key: const ValueKey<String>('mark-settings-section-tabs'),
    sections: [
      for (final section in _sections)
        (key: section.name, label: _sectionLabel(section)),
    ],
    index: _sectionIndex,
    onSelected: (index) => setState(() => _sectionIndex = index),
  );

  Widget _header() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        '快捷划线使用这里的默认样式和默认颜色；自定义颜色长按可删除。',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 12),
      AnnotationQuotePreview(
        key: const ValueKey<String>('mark-settings-preview'),
        quote: '划线标记阅读重点，想法记录此刻思考。',
        color: _settings.lastColor,
        style: _settings.lastStyle,
        opacity: _settings.lastStyle.defaultOpacity,
        strokeWidth: _settings.strokeWidth,
        inkMode: widget.inkMode,
      ),
      const SizedBox(height: 8),
      _sectionTabs(),
    ],
  );

  Widget _sectionContent() => ReaderAnnotationAppearanceEditor(
    color: _settings.lastColor,
    style: _settings.lastStyle,
    opacity: _settings.lastStyle.defaultOpacity,
    settings: _settings,
    inkMode: widget.inkMode,
    showOpacity: false,
    section: _sections[_sectionIndex],
    onColor: (value) =>
        setState(() => _settings = _settings.copyWith(lastColor: value)),
    onStyle: (value) =>
        setState(() => _settings = _settings.copyWith(lastStyle: value)),
    onSettings: (value) => setState(
      () => _settings = _settings.copyWith(
        strokeWidth: value.strokeWidth,
        joinBackgroundLines: value.joinBackgroundLines,
        customColors: value.customColors,
      ),
    ),
  );

  int _sectionIndex = 0;

  @override
  Widget build(BuildContext context) => ReaderSettingsSheet(
    key: const ValueKey<String>('mark-settings-fixed-height'),
    header: _header(),
    footer: FilledButton(
      key: const ValueKey<String>('mark-settings-save'),
      onPressed: () => Navigator.of(context).pop(_settings),
      child: const Text('保存划线设置'),
    ),
    child: _sectionContent(),
  );
}
