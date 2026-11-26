import 'package:flutter/material.dart';

import '../theme/reader_ui_style.dart';

import '../annotations/annotation_appearance_editor.dart';
import '../annotations/annotation_quote_preview.dart';
import '../annotations/mark_settings.dart';
import '../theme/reader_frosted_surface.dart';
import '../theme/reader_section_slider.dart';

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

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('快捷划线使用这里的默认样式和默认颜色；自定义颜色长按可删除。'),
        const SizedBox(height: 16),
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
    ),
  );

  Widget _sectionContent() => SingleChildScrollView(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: ReaderAnnotationAppearanceEditor(
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
    ),
  );

  Widget _saveButton() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
    child: SizedBox(
      width: double.infinity,
      child: FilledButton(
        key: const ValueKey<String>('mark-settings-save'),
        onPressed: () => Navigator.of(context).pop(_settings),
        child: const Text('保存划线设置'),
      ),
    ),
  );

  int _sectionIndex = 0;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: const ValueKey<String>('mark-settings-fixed-height'),
    height: MediaQuery.sizeOf(context).height * .64,
    child: Material(
      color: ReaderFrostedSurface.panelColorOf(context),
      borderRadius: ReaderUiStyle.sheetRadius,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            _header(),
            Expanded(child: _sectionContent()),
            _saveButton(),
          ],
        ),
      ),
    ),
  );
}
