import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../icons/app_icon.dart';
import 'decoration_highlight_editor.dart';
import 'decoration_image_store.dart';
import 'decoration_rule_preview.dart';
import 'decoration_rules.dart';
import 'decoration_style_preview.dart';
import 'style_controls.dart';

/// 规则表单，仅开放不会改变字体度量的样式。
class ReaderDecorationRuleEditor extends StatefulWidget {
  /// 创建规则编辑器。
  const ReaderDecorationRuleEditor({
    super.key,
    required this.rule,
    required this.onPreview,
    this.images,
    this.inkMode = false,
  });

  /// 新规则初值或已有规则。
  final ReaderDecorationRule rule;

  final ReaderDecorationImageStore? images;
  final bool inkMode;

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
  late bool _regex = widget.rule.isRegex;
  late bool _caseSensitive = widget.rule.caseSensitive;
  late ReaderDecorationRuleStyle _style = widget.rule.style;
  List<ReaderDecorationRulePreview> _previews = const [];
  int _previewGeneration = 0;
  bool _previewDone = false;
  bool _previewing = false;
  bool _pickingImage = false;
  String? _error;
  String? _previewError;
  bool _allowPop = false;
  bool _closing = false;
  bool _confirming = false;
  bool get _dirty =>
      _name.text.trim() != (widget.rule.name ?? '') ||
      _pattern.text != widget.rule.pattern ||
      _regex != widget.rule.isRegex ||
      _caseSensitive != widget.rule.caseSensitive ||
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
  );

  @override
  void dispose() {
    _name.dispose();
    _pattern.dispose();
    super.dispose();
  }

  void _set(String name, Object? value) => setState(() {
    _style = _style.withValues({name: value});
    _resetPreview();
  });

  void _resetPreview() {
    _previewGeneration++;
    _previews = const [];
    _previewDone = false;
    _previewError = null;
  }

  bool _validate() {
    String? error;
    if (_pattern.text.isEmpty) {
      error = '请输入匹配内容';
    } else if (_regex) {
      try {
        RegExp(_pattern.text, unicode: true, caseSensitive: _caseSensitive);
      } on FormatException {
        error = '正则格式无效，请修改规则后重新生成预览';
      }
    }
    setState(() => _error = error);
    return error == null;
  }

  Future<void> _preview() async {
    if (_previewing || !_validate()) return;
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
      if (path != null && mounted) _set('backgroundImagePath', path);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('图片无法导入，请选择 20MB 以内的本地图片')),
        );
      }
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
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
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
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
                  child: _form(context),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const ValueKey<String>('rule-save'),
                    onPressed: _previewing || _pickingImage
                        ? null
                        : () {
                            if (_validate()) _pop(_draft);
                          },
                    child: const Text('保存规则'),
                  ),
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
      Row(
        children: [
          Text('自动装饰规则', style: Theme.of(context).textTheme.titleLarge),
          const Spacer(),
          IconButton(
            onPressed: _close,
            tooltip: '关闭',
            icon: const AppIcon(AppGlyph.close),
          ),
        ],
      ),
      TextField(
        key: const ValueKey<String>('rule-name'),
        controller: _name,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(labelText: '名称（可选）'),
      ),
      const SizedBox(height: 14),
      TextField(
        key: const ValueKey<String>('rule-pattern'),
        controller: _pattern,
        minLines: 2,
        maxLines: 4,
        onChanged: (_) => setState(() {
          _error = null;
          _resetPreview();
        }),
        decoration: InputDecoration(
          labelText: '匹配内容',
          helperText: _regex
              ? r'例如：词语甲|词语乙 匹配多个词，\d+ 匹配数字。按正文文本块匹配，不跨段。'
              : '输入要自动装饰的文字，可开启正则匹配多个词或文字模式。',
          helperMaxLines: 3,
          errorText: _error,
          border: const OutlineInputBorder(),
        ),
      ),
      SwitchListTile(
        key: const ValueKey<String>('rule-regex'),
        contentPadding: EdgeInsets.zero,
        title: const Text('正则表达式'),
        subtitle: Text(_regex ? '使用 Unicode 正则' : '按文本字面量匹配'),
        value: _regex,
        onChanged: (value) => setState(() {
          _regex = value;
          _error = null;
          _resetPreview();
        }),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('区分大小写'),
        value: _caseSensitive,
        onChanged: (value) => setState(() {
          _caseSensitive = value;
          _resetPreview();
        }),
      ),
      const Divider(),
      const Text('规则不改变字体度量，不触发重排；后面的规则只覆盖已设置的同名属性。'),
      const SizedBox(height: 12),
      ReaderDecorationStylePreview(
        text: _pattern.text.isEmpty ? '规则样式预览' : _pattern.text,
        style: _style.decorationStyle,
        images: widget.images,
        inkMode: widget.inkMode,
      ),
      ReaderStyleColorField(
        label: '文字色',
        color: _style.color,
        onChanged: (value) => _set('color', value),
      ),
      AppExpansionTile(
        key: const ValueKey<String>('rule-highlight'),
        title: const Text('高亮与划线'),
        subtitle: Text(_style.highlight?.style.label ?? '底色、染色、线条与跨行连块'),
        tilePadding: EdgeInsets.zero,
        children: [
          ReaderDecorationHighlightEditor(
            value: _style.highlight,
            onChanged: (value) => _set('highlight', value?.toJson()),
          ),
        ],
      ),
      ReaderStyleColorField(
        label: '背景色',
        color: _style.backgroundColor,
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
          label: const Text('选择本地背景图'),
        ),
      if (_style.backgroundImagePath != null) ...[
        ReaderDecorationImageFitField(
          value: _style.backgroundImageFit,
          onChanged: (fit) => _set('backgroundImageFit', fit.name),
        ),
        TextButton.icon(
          key: const ValueKey<String>('rule-remove-background-image'),
          onPressed: () => _set('backgroundImagePath', null),
          icon: const AppIcon(AppGlyph.close),
          label: const Text('移除背景图'),
        ),
      ],
      if (widget.images != null)
        const Text('匹配到的文字使用同一张图片，按每行区间铺放；透明度和圆角同时作用于图片。'),
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
        label: '圆角',
        value: _style.borderRadius,
        min: 0,
        max: 20,
        divisions: 20,
        digits: 0,
        suffix: ' dp',
        onChanged: (value) => _set('borderRadius', value),
      ),
      ReaderBorderStyleField(
        value: _style.borderStyle,
        onChanged: (value) => _set('borderStyle', value.name),
      ),
      const SizedBox(height: 12),
      ReaderStyleSlider(
        label: '统一边框宽度',
        value: _style.borderWidth,
        min: 0,
        max: 6,
        divisions: 12,
        suffix: ' dp',
        onChanged: (value) => _set('borderWidth', value),
      ),
      ReaderStyleColorField(
        label: '统一边框颜色',
        color: _style.borderColor,
        clearLabel: '默认灰色',
        onChanged: (value) => _set('borderColor', value),
      ),
      OutlinedButton.icon(
        key: const ValueKey<String>('rule-preview'),
        onPressed: _previewing ? null : _preview,
        icon: _previewing
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const AppIcon(AppGlyph.preview),
        label: const Text('预览当前章（前 50 条）'),
      ),
      if (_previewError != null)
        Text(
          _previewError!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      if (!_previewing && _previews.isEmpty && _previewError == null)
        Text(_previewDone ? '当前章没有命中结果' : '预览只在当前会话计算，不保存命中结果。'),
      if (_previews.isNotEmpty)
        Text(
          '当前章命中 ${_previews.length} 条${_previews.length == 50 ? '（仅前 50 条）' : ''}',
        ),
      for (final preview in _previews)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: ReaderDecorationStylePreview(
            text: preview.text,
            style: preview.style.decorationStyle,
            images: widget.images,
            inkMode: widget.inkMode,
          ),
        ),
    ],
  );
}
