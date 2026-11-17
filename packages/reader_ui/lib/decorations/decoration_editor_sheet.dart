import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../icons/app_icon.dart';
import '../panels/settings_panel.dart' show ReaderFontOption;
import 'decoration_border_editor.dart';
import 'decoration_image_store.dart';
import 'decoration_style.dart';
import 'decoration_style_preview.dart';
import 'decoration_typography_editor.dart';
import 'style_controls.dart';

/// 手工装饰预设与高级属性编辑面板。
class ReaderDecorationEditorSheet extends StatefulWidget {
  /// 创建装饰编辑器，取消返回空值，保存返回完整样式。
  const ReaderDecorationEditorSheet({
    super.key,
    required this.quote,
    this.initialStyle = const ReaderDecorationStyle(),
    this.fonts = const [],
    this.onLoadFont,
    this.images,
    this.inkMode = false,
  });

  /// 原文摘录。
  final String quote;

  /// 原装饰样式。
  final ReaderDecorationStyle initialStyle;

  /// 已安装的字体，无加载回调时由宿主保证已注册。
  final List<ReaderFontOption> fonts;

  /// 在预览和保存前注册所选字体，失败时禁止保存。
  final Future<void> Function(String family)? onLoadFont;

  /// 宿主本地图片存储。
  final ReaderDecorationImageStore? images;

  /// 黑白预览模式。
  final bool inkMode;
  @override
  State<ReaderDecorationEditorSheet> createState() =>
      _ReaderDecorationEditorSheetState();
}

class _ReaderDecorationEditorSheetState
    extends State<ReaderDecorationEditorSheet> {
  late ReaderDecorationStyle _style = widget.initialStyle;
  bool _picking = false;
  bool _closing = false;
  bool _allowPop = false;
  bool _dialogVisible = false;
  bool _loadingFont = false;
  String? _fontError;
  int _fontGeneration = 0;
  final _loadedFonts = <String>{};
  bool get _dirty =>
      jsonEncode(_style.toJson()) != jsonEncode(widget.initialStyle.toJson());
  bool get _canSave => !_picking && !_loadingFont && _fontError == null;

  @override
  void initState() {
    super.initState();
    _prepareFont();
  }

  void _set(String name, Object? value) =>
      _changeStyle(_style.withValues({name: value}));

  void _changeStyle(ReaderDecorationStyle style) {
    final fontChanged = _style.fontFamily != style.fontFamily;
    setState(() {
      _style = style;
      if (fontChanged) _prepareFont();
    });
  }

  void _prepareFont() {
    final generation = ++_fontGeneration;
    final family = _style.fontFamily;
    _loadingFont = false;
    _fontError = null;
    if (family == null) return;
    if (!widget.fonts.any((font) => font.family == family)) {
      _fontError = '原字体不可用，请选择已安装字体或跟随正文';
      return;
    }
    final loadFont = widget.onLoadFont;
    if (loadFont == null || _loadedFonts.contains(family)) return;
    _loadingFont = true;
    unawaited(_loadFont(family, loadFont, generation));
  }

  Future<void> _loadFont(
    String family,
    Future<void> Function(String family) loadFont,
    int generation,
  ) async {
    String? error;
    try {
      await loadFont(family);
    } catch (_) {
      error = '字体加载失败，请选择其他字体或跟随正文';
    }
    if (!mounted || generation != _fontGeneration) return;
    setState(() {
      _loadingFont = false;
      _fontError = error;
      if (error == null) _loadedFonts.add(family);
    });
  }

  void _pop([ReaderDecorationStyle? style]) {
    if (_closing) return;
    _closing = true;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(style);
    });
  }

  Future<void> _close() async {
    if (_closing || _dialogVisible) return;
    if (!_dirty) {
      _pop();
      return;
    }
    _dialogVisible = true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('放弃未保存的装饰？'),
        content: const Text('样式修改还没有保存，离开后本次修改会丢失。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('继续编辑'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('放弃修改'),
          ),
        ],
      ),
    );
    _dialogVisible = false;
    if (discard == true && mounted) _pop();
  }

  Future<void> _pickImage() async {
    if (_picking || widget.images == null) return;
    setState(() => _picking = true);
    try {
      final path = await widget.images!.pickImage();
      if (path != null && mounted) _set('backgroundImagePath', path);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('图片无法导入，请选择 20MB 以内的本地图片')),
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_dirty || _allowPop,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_close());
    },
    child: AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Material(
        key: const ValueKey<String>('decoration-editor-sheet'),
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: _content(context),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const ValueKey<String>('decoration-save'),
                    onPressed: _canSave ? () => _pop(_style) : null,
                    icon: const AppIcon(AppGlyph.check),
                    label: const Text('保存装饰'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _content(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          const AppIcon(AppGlyph.formatPaint),
          const SizedBox(width: 8),
          Text('装饰', style: Theme.of(context).textTheme.titleLarge),
          const Spacer(),
          IconButton(
            onPressed: _close,
            tooltip: '关闭',
            icon: const AppIcon(AppGlyph.close),
          ),
        ],
      ),
      const Text('只改变选中文字的外观，不加入标注列表。'),
      const SizedBox(height: 12),
      ReaderDecorationStylePreview(
        text: widget.quote,
        style: _loadingFont || _fontError != null
            ? _style.withValues({'fontFamily': null})
            : _style,
        images: widget.images,
        inkMode: widget.inkMode,
      ),
      if (_loadingFont)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 8),
              Expanded(child: Text('正在加载字体，完成后可保存')),
            ],
          ),
        ),
      if (_fontError != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            _fontError!,
            key: const ValueKey<String>('decoration-font-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final preset in ReaderDecorationPreset.values)
            ActionChip(
              key: ValueKey<String>('decoration-preset-${preset.name}'),
              label: Text(preset.label),
              onPressed: () => _changeStyle(preset.style),
            ),
          ActionChip(
            label: const Text('重置'),
            onPressed: () => _changeStyle(const ReaderDecorationStyle()),
          ),
        ],
      ),
      AppExpansionTile(
        key: const ValueKey<String>('decoration-typography'),
        title: const Text('字体'),
        subtitle: const Text('字体、字号、字重、斜体、字距、文字色'),
        tilePadding: EdgeInsets.zero,
        children: [
          ReaderDecorationTypographyEditor(
            style: _style,
            fonts: widget.fonts,
            onChanged: _changeStyle,
          ),
        ],
      ),
      AppExpansionTile(
        title: const Text('背景'),
        subtitle: const Text('颜色、透明度、圆角、本地背景图'),
        tilePadding: EdgeInsets.zero,
        children: [_background()],
      ),
      AppExpansionTile(
        title: const Text('边框与内边距'),
        subtitle: const Text('统一或分别设置四边'),
        tilePadding: EdgeInsets.zero,
        children: [
          ReaderDecorationBorderEditor(style: _style, onChanged: _changeStyle),
        ],
      ),
    ],
  );

  Widget _background() => Column(
    children: [
      ReaderStyleColorField(
        label: '背景色',
        color: _style.backgroundColor,
        clearLabel: '无背景',
        onChanged: (value) => _set('backgroundColor', value),
      ),
      ReaderStyleSlider(
        label: '背景透明度',
        value: _style.backgroundOpacity,
        min: 0,
        max: 1,
        divisions: 100,
        digits: 2,
        onChanged: (value) => _set('backgroundOpacity', value),
      ),
      ReaderStyleSlider(
        label: '背景圆角',
        value: _style.borderRadius,
        min: 0,
        max: 20,
        divisions: 20,
        digits: 0,
        suffix: ' dp',
        onChanged: (value) => _set('borderRadius', value),
      ),
      if (widget.images != null)
        OutlinedButton.icon(
          onPressed: _picking ? null : _pickImage,
          icon: _picking
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const AppIcon(AppGlyph.image),
          label: const Text('选择本地背景图'),
        ),
      if (_style.backgroundImagePath != null)
        TextButton.icon(
          onPressed: () => _set('backgroundImagePath', null),
          icon: const AppIcon(AppGlyph.close),
          label: const Text('移除背景图'),
        ),
      const Text('背景图按 cover 裁剪。颜色和图片需保留足够对比度，避免遮挡文字。'),
      const SizedBox(height: 12),
    ],
  );
}
