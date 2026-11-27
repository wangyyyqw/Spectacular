import 'dart:async';
import 'dart:convert';

import '../theme/reader_dropdown.dart';

import 'package:flutter/material.dart';

import '../theme/reader_switch.dart';

import '../reader_ui_diagnostics.dart';

import '../icons/app_icon.dart';
import 'decoration_highlight_editor.dart';
import 'decoration_image_store.dart';
import 'decoration_image_codec.dart';
import 'decoration_nine_slice_editor.dart';
import 'decoration_rule_preview.dart';
import 'decoration_rules.dart';
import 'decoration_style.dart';
import 'decoration_style_preview.dart';
import 'decoration_rule_matching.dart';
import 'decoration_rule_css.dart';
import '../annotations/text_value_dialog.dart';
import 'decoration_rule_defaults.dart';
import 'decoration_typography_editor.dart';
import '../panels/settings_panel.dart' show ReaderFontOption;
import 'style_controls.dart';
import '../theme/reader_frosted_popup.dart';
import '../theme/reader_frosted_surface.dart';

/// 规则表单，文字与盒样式复用本项目装饰设计。
class ReaderDecorationRuleEditor extends StatefulWidget {
  /// 创建规则编辑器。
  const ReaderDecorationRuleEditor({
    super.key,
    required this.rule,
    required this.onPreview,
    this.images,
    this.inkMode = false,
    this.fonts = const [],
    this.styles = readerDecorationBuiltInStyles,
    this.styleOnly = false,
  });

  /// 新规则初值或已有规则。
  final ReaderDecorationRule rule;

  final ReaderDecorationImageStore? images;
  final bool inkMode;
  final List<ReaderFontOption> fonts;
  final List<ReaderDecorationNamedStyle> styles;
  final bool styleOnly;

  /// 在当前章计算临时前五十条命中。
  final Future<List<ReaderDecorationRulePreview>> Function(ReaderDecorationRule)
  onPreview;
  @override
  State<ReaderDecorationRuleEditor> createState() =>
      _ReaderDecorationRuleEditorState();
}

class _ReaderDecorationRuleEditorState
    extends State<ReaderDecorationRuleEditor> {
  late final _name = TextEditingController(text: widget.rule.name ?? '');
  late final _pattern = TextEditingController(text: widget.rule.pattern);
  late bool _caseSensitive = widget.rule.caseSensitive;
  late ReaderDecorationRuleStyle _style = widget.rule.style;
  late ReaderDecorationRuleType _type = widget.rule.effectiveType;
  bool get _regex => _type == ReaderDecorationRuleType.regex;
  late bool _crossParagraph = widget.rule.allowCrossParagraph;
  late String? _styleId = widget.rule.styleId;
  late String? _darkStyleId = widget.rule.darkStyleId;
  bool _dark = false;
  ReaderDecorationRuleStyle get _editingStyle => _style.forTheme(_dark);
  void _updateStyle(ReaderDecorationRuleStyle value) {
    if (_dark) {
      _darkStyleId = null;
      _style = _style.withValues({'darkStyle': value.toJson()});
    } else {
      _styleId = null;
      _style = value.withValues({'darkStyle': _style.darkStyle?.toJson()});
    }
  }

  List<ReaderDecorationRulePreview> _previews = const [];
  int _previewGeneration = 0;
  bool _previewDone = false;
  bool _previewing = false;
  bool _showAllPreviews = false;
  bool _pickingImage = false;
  String? _error;
  String? _previewError;
  bool _allowPop = false;
  bool _closing = false;
  bool _confirming = false;
  bool get _dirty =>
      _name.text.trim() != (widget.rule.name ?? '') ||
      _pattern.text != widget.rule.pattern ||
      _caseSensitive != widget.rule.caseSensitive ||
      _type != widget.rule.effectiveType ||
      _crossParagraph != widget.rule.allowCrossParagraph ||
      _styleId != widget.rule.styleId ||
      _darkStyleId != widget.rule.darkStyleId ||
      jsonEncode(_style.toJson()) != jsonEncode(widget.rule.style.toJson());
  ReaderDecorationRule get _draft => ReaderDecorationRule(
    id: widget.rule.id,
    groupId: widget.rule.groupId,
    name: _name.text.trim().isEmpty ? null : _name.text.trim(),
    pattern: _pattern.text,
    isRegex: _regex,
    caseSensitive: _caseSensitive,
    enabled: widget.rule.enabled,
    style: _style,
    sortOrder: widget.rule.sortOrder,
    type: _type,
    allowCrossParagraph: _crossParagraph,
    styleId: _styleId,
    darkStyleId: _darkStyleId,
  );

  @override
  void dispose() {
    _name.dispose();
    _pattern.dispose();
    super.dispose();
  }

  void _set(String name, Object? value) => setState(() {
    _updateStyle(_editingStyle.withValues({name: value}));
  });

  void _resetPreview() {
    _previewGeneration++;
    _previews = const [];
    _previewDone = false;
    _previewError = null;
    _showAllPreviews = false;
  }

  bool _validate() {
    if (widget.styleOnly) return true;
    String? error;
    error = validateDecorationRule(_draft.effectiveType, _pattern.text);
    setState(() => _error = error);
    return error == null;
  }

  Future<void> _preview() async {
    if (_previewing || !_validate()) return;
    FocusScope.of(context).unfocus();
    final generation = _previewGeneration;
    setState(() {
      _previewing = true;
      _previewError = null;
      _previews = const [];
    });
    try {
      final previews = await widget.onPreview(_draft);
      if (mounted && generation == _previewGeneration) {
        setState(() {
          _previews = previews.take(50).toList();
          _previewDone = true;
        });
      }
    } catch (error) {
      if (mounted && generation == _previewGeneration) {
        setState(
          () => _previewError = error.toString().replaceFirst(
            'FormatException: ',
            '',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  Future<void> _pickImage() async {
    if (_pickingImage || widget.images == null) return;
    setState(() => _pickingImage = true);
    try {
      final path = await widget.images!.pickImage();
      if (path != null) {
        final decoded = await ReaderDecorationImageCodec.decode(
          await widget.images!.loadImage(path),
        );
        final nineSlice = decoded.nineSlice;
        decoded.image.dispose();
        if (mounted) {
          setState(
            () => _updateStyle(
              _editingStyle.withValues({
                'backgroundImagePath': path,
                'backgroundImageFit':
                    (nineSlice == null
                            ? ReaderDecorationImageFit.cover
                            : ReaderDecorationImageFit.nineSlice)
                        .name,
                'backgroundImageNineSlice': nineSlice?.toJson(),
              }),
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        ReaderUiDiagnostics.record('decoration_rule_image_import_failed');
      }
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  void _insertRegex(String expression) {
    final selection = _pattern.selection;
    final start = selection.isValid ? selection.start : _pattern.text.length;
    final end = selection.isValid ? selection.end : start;
    _pattern.value = TextEditingValue(
      text: _pattern.text.replaceRange(start, end, expression),
      selection: TextSelection.collapsed(offset: start + expression.length),
    );
    setState(() {
      _error = null;
      _resetPreview();
    });
  }

  void _pop([ReaderDecorationRule? rule]) {
    if (_closing) return;
    _closing = true;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(rule);
    });
  }

  Future<void> _close() async {
    if (_closing || _confirming) return;
    if (!_dirty) {
      _pop();
      return;
    }
    _confirming = true;
    final discard = await showReaderDialog<bool>(
      context: context,
      builder: (context) => ReaderFrostedAlertDialog(
        title: const Text('放弃未保存的规则？'),
        content: const Text('本次匹配内容和样式修改将丢失。'),
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
    _confirming = false;
    if (discard == true && mounted) _pop();
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
        color: ReaderFrostedSurface.panelColorOf(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.styleOnly ? '装饰样式' : '自动装饰规则',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      onPressed: _close,
                      tooltip: '关闭',
                      icon: const AppIcon(AppGlyph.close),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: ReaderDecorationStylePreview(
                  text:
                      _previews.firstOrNull?.text ??
                      (_regex || _pattern.text.isEmpty
                          ? '让重要的文字更醒目。\n图片、底色与划线都可以在这里预览。'
                          : _pattern.text),
                  style: _editingStyle.decorationStyle,
                  images: widget.images,
                  inkMode: widget.inkMode,
                  maxLines: 2,
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: _form(context),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const ValueKey<String>('rule-preview'),
                        onPressed:
                            widget.styleOnly || _previewing || _pickingImage
                            ? null
                            : _preview,
                        icon: _previewing
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const AppIcon(AppGlyph.preview),
                        label: const Text('预览匹配'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        key: const ValueKey<String>('rule-save'),
                        onPressed: _previewing || _pickingImage
                            ? null
                            : () {
                                if (_validate()) _pop(_draft);
                              },
                        child: Text(widget.styleOnly ? '保存样式' : '保存规则'),
                      ),
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

  Widget _form(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (!widget.styleOnly) ...[
        ReaderDropdownButtonFormField<ReaderDecorationRuleType>(
          key: const ValueKey('rule-match-type'),
          initialValue: _type,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '匹配类型'),
          items: [
            for (final type in ReaderDecorationRuleType.values)
              DropdownMenuItem(value: type, child: Text(type.label)),
          ],
          onChanged: (value) => setState(() {
            _type = value!;
            _error = null;
            _resetPreview();
          }),
        ),
        const SizedBox(height: 12),
        if (_type.needsPattern)
          TextField(
            key: const ValueKey<String>('rule-pattern'),
            controller: _pattern,
            minLines: 1,
            maxLines: 4,
            onChanged: (_) => setState(() {
              _error = null;
              _resetPreview();
            }),
            decoration: InputDecoration(
              labelText: '匹配内容',
              helperText: _regex
                  ? r'例如 \d+。最多 512 字符，不支持环视、反向引用和占有量词；超限跳过。'
                  : _type == ReaderDecorationRuleType.range
                  ? '例如 【】 匹配含分隔符的范围；重复开符使用最近起点。'
                  : '按原文匹配输入的文字。',
              helperMaxLines: 3,
              errorText: _error,
            ),
          ),
        if (_type.supportsCrossParagraph)
          ReaderSwitchListTile(
            key: const ValueKey('rule-cross-paragraph'),
            contentPadding: EdgeInsets.zero,
            title: const Text('允许跨段'),
            subtitle: const Text('最多七段，保留每段原文位置'),
            value: _crossParagraph,
            onChanged: (value) => setState(() {
              _crossParagraph = value;
              _resetPreview();
            }),
          ),
        if (_regex)
          PopupMenuButton<String>(
            key: const ValueKey<String>('rule-regex-examples'),
            tooltip: '插入常用表达式',
            onSelected: _insertRegex,
            itemBuilder: (_) => const [
              PopupMenuItem(value: r'\d+', child: Text(r'数字：\d+')),
              PopupMenuItem(
                value: r'“[^”]+”|「[^」]+」|『[^』]+』',
                child: Text('引号内文字'),
              ),
              PopupMenuItem(value: r'\b[A-Za-z]+\b', child: Text('英文单词')),
            ],
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  AppIcon(AppGlyph.add, size: 18),
                  SizedBox(width: 8),
                  Text('插入常用表达式'),
                ],
              ),
            ),
          ),
        ReaderSwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('区分大小写'),
          value: _caseSensitive,
          onChanged: (value) => setState(() {
            _caseSensitive = value;
            _resetPreview();
          }),
        ),
        TextField(
          key: const ValueKey<String>('rule-name'),
          controller: _name,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: '名称（可选）'),
        ),
      ],
      const Divider(),
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: false, label: Text('日间样式')),
          ButtonSegment(value: true, label: Text('夜间样式')),
        ],
        selected: {_dark},
        onSelectionChanged: (value) => setState(() => _dark = value.first),
      ),
      const SizedBox(height: 12),
      TextButton(
        key: const ValueKey('rule-import-css'),
        onPressed: () async {
          final css = await showReaderDialog<String>(
            context: context,
            builder: (_) => ReaderTextValueDialog(
              title: '导入高亮 CSS',
              label: 'CSS 声明',
              initialValue: '',
              validate: (text) {
                try {
                  importDecorationRuleCss(_editingStyle, text);
                  return null;
                } on FormatException catch (error) {
                  return error.message;
                }
              },
            ),
          );
          if (mounted && css != null) {
            setState(
              () => _updateStyle(importDecorationRuleCss(_editingStyle, css)),
            );
          }
        },
        child: const Text('导入 CSS 到当前样式'),
      ),
      if (!widget.styleOnly)
        ReaderDropdownButtonFormField<String>(
          key: ValueKey('rule-style-reference-$_dark'),
          initialValue: (_dark ? _darkStyleId : _styleId) ?? '',
          isExpanded: true,
          decoration: const InputDecoration(labelText: '使用样式'),
          items: [
            const DropdownMenuItem(value: '', child: Text('当前规则自定义')),
            for (final style in widget.styles)
              DropdownMenuItem(value: style.id, child: Text(style.name)),
          ],
          onChanged: (value) => setState(() {
            if (value == null || value.isEmpty) {
              if (_dark) {
                _darkStyleId = null;
              } else {
                _styleId = null;
              }
            } else {
              final chosen = widget.styles
                  .firstWhere((s) => s.id == value)
                  .style;
              _updateStyle(chosen);
              if (_dark) {
                _darkStyleId = value;
              } else {
                _styleId = value;
              }
            }
          }),
        ),
      AppExpansionTile(
        key: const ValueKey('rule-typography'),
        title: const Text('字体与排版'),
        subtitle: Text(_editingStyle.typography.summary),
        tilePadding: EdgeInsets.zero,
        children: [
          ReaderDecorationTypographyEditor(
            style: _editingStyle.typography,
            fonts: widget.fonts,
            onChanged: (value) => _set('typography', value.toJson()),
          ),
          for (final (key, label, value) in [
            ('paddingTop', '上留白', _editingStyle.typography.paddingTop),
            ('paddingRight', '右留白', _editingStyle.typography.paddingRight),
            ('paddingBottom', '下留白', _editingStyle.typography.paddingBottom),
            ('paddingLeft', '左留白', _editingStyle.typography.paddingLeft),
          ])
            ReaderStyleSlider(
              label: label,
              value: value,
              min: 0,
              max: 32,
              divisions: 32,
              digits: 0,
              suffix: ' px',
              onChanged: (value) => _set(
                'typography',
                _editingStyle.typography.withValues({key: value}).toJson(),
              ),
            ),
        ],
      ),
      AppExpansionTile(
        key: const ValueKey<String>('rule-highlight'),
        title: const Text('高亮与划线'),
        subtitle: Text(_editingStyle.highlight?.style.label ?? '底色、染色、线条与跨行连块'),
        initiallyExpanded: widget.rule.style.highlight != null,
        tilePadding: EdgeInsets.zero,
        children: [
          ReaderDecorationHighlightEditor(
            value: _editingStyle.highlight,
            onChanged: (value) => _set('highlight', value?.toJson()),
            inkMode: widget.inkMode,
          ),
        ],
      ),
      AppExpansionTile(
        key: const ValueKey<String>('rule-background'),
        title: const Text('图片与背景'),
        subtitle: Text(
          _editingStyle.backgroundImagePath == null
              ? '本地图片、底色、透明度与圆角'
              : '已设置背景图 · ${_editingStyle.backgroundImageFit.label}',
        ),
        initiallyExpanded: widget.rule.style.backgroundImagePath != null,
        tilePadding: EdgeInsets.zero,
        children: [_background()],
      ),
      AppExpansionTile(
        key: const ValueKey<String>('rule-border'),
        title: const Text('边框'),
        subtitle: Text(
          _editingStyle.borderWidth == 0
              ? '未设置'
              : '${_editingStyle.borderStyle.label} · ${_editingStyle.borderWidth} dp',
        ),
        tilePadding: EdgeInsets.zero,
        children: [_border()],
      ),
      ReaderStyleColorField(
        label: '文字色',
        color: _editingStyle.color,
        onChanged: (value) => _set('color', value),
      ),
      const SizedBox(height: 12),
      _previewResults(context),
    ],
  );

  Widget _background() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ReaderStyleColorField(
        label: '背景色',
        color: _editingStyle.backgroundColor,
        clearLabel: '无背景',
        onChanged: (value) => _set('backgroundColor', value),
      ),
      if (widget.images != null)
        OutlinedButton.icon(
          key: const ValueKey<String>('rule-pick-background-image'),
          onPressed: _pickingImage ? null : _pickImage,
          icon: _pickingImage
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const AppIcon(AppGlyph.image),
          label: Text(
            _editingStyle.backgroundImagePath == null ? '选择本地背景图' : '更换背景图',
          ),
        ),
      if (_editingStyle.backgroundImagePath != null) ...[
        ReaderDecorationImageFitField(
          value: _editingStyle.backgroundImageFit,
          onChanged: (fit) => _set('backgroundImageFit', fit.name),
        ),
        if (widget.images != null)
          ReaderDecorationNineSliceButton(
            path: _editingStyle.backgroundImagePath!,
            images: widget.images!,
            value: _editingStyle.backgroundImageNineSlice,
            onChanged: (selection) => setState(() {
              _updateStyle(
                _editingStyle.withValues({
                  if (selection.path != null)
                    'backgroundImagePath': selection.path,
                  'backgroundImageFit': ReaderDecorationImageFit.nineSlice.name,
                  'backgroundImageNineSlice': selection.nineSlice.toJson(),
                }),
              );
            }),
          ),
        TextButton.icon(
          key: const ValueKey<String>('rule-remove-background-image'),
          onPressed: () => _set('backgroundImagePath', null),
          icon: const AppIcon(AppGlyph.close),
          label: const Text('移除背景图'),
        ),
      ],
      if (widget.images != null)
        Text(
          _editingStyle.backgroundImageFit == ReaderDecorationImageFit.nineSlice
              ? '点九图按每行命中文字拉伸，保留素材边角；透明度和圆角作用于完整图案。'
              : '每行命中的文字使用同一张图片；透明度和圆角同时作用于图片。',
        ),
      ReaderStyleSlider(
        label: '背景透明度',
        value: _editingStyle.backgroundOpacity,
        min: 0,
        max: 1,
        divisions: 100,
        digits: 2,
        onChanged: (value) => _set('backgroundOpacity', value),
      ),
      ReaderStyleSlider(
        label: '圆角',
        value: _editingStyle.borderRadius,
        min: 0,
        max: 20,
        divisions: 20,
        digits: 0,
        suffix: ' dp',
        onChanged: (value) => _set('borderRadius', value),
      ),
    ],
  );

  Widget _border() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ReaderBorderStyleField(
        value: _editingStyle.borderStyle,
        onChanged: (value) => _set('borderStyle', value.name),
      ),
      const SizedBox(height: 12),
      ReaderStyleSlider(
        label: '统一边框宽度',
        value: _editingStyle.borderWidth,
        min: 0,
        max: 6,
        divisions: 12,
        suffix: ' dp',
        onChanged: (value) => _set('borderWidth', value),
      ),
      ReaderStyleColorField(
        label: '统一边框颜色',
        color: _editingStyle.borderColor,
        clearLabel: '默认灰色',
        onChanged: (value) => _set('borderColor', value),
      ),
    ],
  );

  Widget _previewResults(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_previewError != null)
        Text(
          _previewError!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      if (!_previewing && _previews.isEmpty && _previewError == null)
        Text(
          _previewDone ? '当前章没有匹配，请检查表达式或切换章节。' : '点击“预览匹配”查看当前章结果，最多显示 50 条。',
        ),
      if (_previews.isNotEmpty)
        Text(
          '当前章命中 ${_previews.length} 条${_previews.length == 50 ? '（仅前 50 条）' : ''}',
        ),
      for (final preview in _previews.take(_showAllPreviews ? 50 : 5))
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: ReaderDecorationStylePreview(
            text: preview.text,
            style: _editingStyle.decorationStyle,
            images: widget.images,
            inkMode: widget.inkMode,
          ),
        ),
      if (_previews.length > 5)
        TextButton(
          key: const ValueKey<String>('rule-preview-expand'),
          onPressed: () => setState(() => _showAllPreviews = !_showAllPreviews),
          child: Text(
            _showAllPreviews ? '收起结果' : '查看其余 ${_previews.length - 5} 条',
          ),
        ),
    ],
  );
}
