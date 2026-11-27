import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../annotations/annotation_appearance_editor.dart';
import '../bookmarks/bookmark_ribbon.dart';
import '../bookmarks/bookmark_style.dart';
import '../theme/reader_color_option.dart';
import '../theme/reader_frosted_surface.dart';
import '../theme/reader_section_slider.dart';
import '../theme/reader_switch.dart';
import '../theme/reader_ui_components.dart';
import '../theme/reader_ui_style.dart';

/// 编辑全局书签样式与下拉开关，保存前只更新预览。
class ReaderBookmarkStyleSheet extends StatefulWidget {
  const ReaderBookmarkStyleSheet({
    super.key,
    required this.style,
    this.onPickImage,
    this.imageLoader,
  });

  final ReaderBookmarkStyle style;
  final Future<String?> Function()? onPickImage;
  final Future<Uint8List> Function(String id)? imageLoader;

  @override
  State<ReaderBookmarkStyleSheet> createState() => _BookmarkStyleSheetState();
}

class _BookmarkStyleSheetState extends State<ReaderBookmarkStyleSheet> {
  late ReaderBookmarkStyle _style = widget.style;
  bool _picking = false;
  String? _error;
  int _sectionIndex = 0;

  Future<void> _pickImage() async {
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final id = await widget.onPickImage!();
      if (mounted && id != null) setState(() => _style = _style.withImage(id));
    } catch (_) {
      if (mounted) {
        setState(() => _error = '图片导入失败，请选择可读取的 PNG、JPG 或 WebP 图片（小于 20MB）');
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Widget _sectionTabs() => ReaderSectionSlider(
    key: const ValueKey('bookmark-style-section-tabs'),
    sections: const [
      (key: 'image', label: '图片'),
      (key: 'size', label: '尺寸/开关'),
      (key: 'color', label: '颜色'),
    ],
    index: _sectionIndex,
    onSelected: (index) => setState(() => _sectionIndex = index),
  );

  Widget _header(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('应用于所有书籍，显示在有书签的阅读页右上角。'),
        const SizedBox(height: 16),
        SizedBox(
          height: 112,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: ReaderUiStyle.controlRadiusOf(Theme.of(context)),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                var scale = 96 / _style.length;
                final widthScale =
                    constraints.maxWidth / (_style.rightInset + _style.width);
                if (widthScale < scale) scale = widthScale;
                if (scale > 1) scale = 1;
                return Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    Positioned(
                      top: 8,
                      right: _style.rightInset * scale,
                      child: Transform.scale(
                        scale: scale,
                        alignment: Alignment.topRight,
                        child: ReaderBookmarkRibbon(
                          style: _style,
                          color: Color(
                            _style.color ??
                                Theme.of(context).colorScheme.primary
                                    .toARGB32(),
                          ),
                          imageLoader: widget.imageLoader,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        _sectionTabs(),
      ],
    ),
  );

  List<Widget> _sectionFields() => switch (_sectionIndex) {
    0 => _imageFields(),
    1 => _sizeFields(),
    _ => _colorFields(),
  };

  List<Widget> _imageFields() => [
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton(
          key: const ValueKey('bookmark-pick-image'),
          onPressed: _picking || widget.onPickImage == null ? null : _pickImage,
          child: Text(_picking ? '正在导入…' : '选择本地图片'),
        ),
        TextButton(
          onPressed: _picking || _style.imageId == null
              ? null
              : () => setState(() => _style = _style.withImage(null)),
          child: const Text('使用默认图标'),
        ),
      ],
    ),
    if (_error != null) ...[
      const SizedBox(height: 8),
      ReaderInlineNotice(message: _error!, isError: true),
    ],
    const SizedBox(height: 8),
    Text(
      '图片随宽度和长度缩放；透明 PNG 可保留镂空效果。',
      style: Theme.of(context).textTheme.bodySmall,
    ),
  ];

  List<Widget> _sizeFields() => [
    ReaderSwitchListTile(
      key: const ValueKey('bookmark-pull-enabled'),
      contentPadding: EdgeInsets.zero,
      title: const Text('下拉书签'),
      subtitle: const Text('分页阅读时，下拉添加或移除当前页书签'),
      value: _style.pullEnabled,
      onChanged: (value) =>
          setState(() => _style = _style.copyWith(pullEnabled: value)),
    ),
    _dimension(
      '宽度',
      _style.width,
      ReaderBookmarkStyle.minWidth,
      ReaderBookmarkStyle.maxWidth,
      (value) => setState(() => _style = _style.copyWith(width: value)),
    ),
    _dimension(
      '长度',
      _style.length,
      ReaderBookmarkStyle.minLength,
      ReaderBookmarkStyle.maxLength,
      (value) => setState(() => _style = _style.copyWith(length: value)),
    ),
    _dimension(
      '距右侧',
      _style.rightInset,
      ReaderBookmarkStyle.minRightInset,
      ReaderBookmarkStyle.maxRightInset,
      (value) => setState(() => _style = _style.copyWith(rightInset: value)),
    ),
  ];

  List<Widget> _colorFields() => [
    Text('书签颜色', style: Theme.of(context).textTheme.labelLarge),
    const SizedBox(height: 8),
    Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _defaultColorButton(),
        for (final option in ReaderAnnotationAppearanceEditor.colors)
          _colorButton(option),
      ],
    ),
  ];

  Widget _defaultColorButton() => ReaderColorOption(
    buttonKey: const ValueKey<String>('bookmark-color-default'),
    color: Theme.of(context).colorScheme.primary,
    label: '跟随正文',
    selected: _style.color == null,
    onTap: () => setState(() => _style = _style.withColor(null)),
  );

  Widget _colorButton(AnnotationColorOption option) => ReaderColorOption(
    buttonKey: ValueKey<String>('bookmark-color-${option.value}'),
    color: Color(option.value),
    label: option.label,
    selected: _style.color == option.value,
    onTap: () => setState(() => _style = _style.withColor(option.value)),
  );

  Widget _dimension(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('$label · ${value.round()}'),
      Slider(
        key: ValueKey('bookmark-$label'),
        value: value,
        min: min,
        max: max,
        divisions: (max - min).round(),
        label: '${value.round()}',
        semanticFormatterCallback: (value) => '$label ${value.round()}',
        onChanged: onChanged,
      ),
    ],
  );

  Widget _sectionContent() => SingleChildScrollView(
    key: PageStorageKey<String>('bookmark-style-section-$_sectionIndex'),
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _sectionFields(),
    ),
  );

  Widget _saveButton(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
    child: SizedBox(
      width: double.infinity,
      child: FilledButton(
        key: const ValueKey('bookmark-style-save'),
        onPressed: _picking ? null : () => Navigator.of(context).pop(_style),
        child: const Text('保存书签样式'),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => SizedBox(
    key: const ValueKey('bookmark-style-fixed-height'),
    height: MediaQuery.sizeOf(context).height * .64,
    child: Material(
      color: ReaderFrostedSurface.panelColorOf(context),
      borderRadius: ReaderUiStyle.sheetRadiusOf(Theme.of(context)),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            _header(context),
            Expanded(child: _sectionContent()),
            _saveButton(context),
          ],
        ),
      ),
    ),
  );
}
