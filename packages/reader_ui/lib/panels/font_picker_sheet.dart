import 'package:flutter/material.dart';

import 'package:reader_core/css/font_face.dart';

import '../icons/app_icon.dart';
import '../theme/reader_frosted_popup.dart';

/// 宿主保存的字体标识与名称，UI 不读取字体文件。
class ReaderFontOption {
  const ReaderFontOption({required this.family, required this.label});

  final String family;
  final String label;
}

/// 包装可空族名，区分「书籍字体」与取消选择。
class ReaderFontSelection {
  const ReaderFontSelection(this.family);

  final String? family;
}

enum _FontAction { preview, rename, remove }

/// 字体选择、试读和管理；用户选择预览时才加载大字库。
class ReaderFontPickerSheet extends StatefulWidget {
  const ReaderFontPickerSheet({
    super.key,
    required this.fonts,
    required this.selected,
    this.onLoad,
    this.onRename,
    this.onRemove,
  });

  final List<ReaderFontOption> fonts;
  final String? selected;
  final Future<void> Function(String family)? onLoad;
  final Future<ReaderFontOption> Function(String family, String name)? onRename;
  final Future<void> Function(String family)? onRemove;

  @override
  State<ReaderFontPickerSheet> createState() => _ReaderFontPickerSheetState();
}

class _ReaderFontPickerSheetState extends State<ReaderFontPickerSheet> {
  late final List<ReaderFontOption> _fonts = List.of(widget.fonts);
  late String? _selected = widget.selected;
  late String? _preview = widget.selected;
  String? _error;
  bool _busy = false;

  Future<bool> _run(Future<void> Function() action) async {
    if (_busy) return false;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      return true;
    } catch (error) {
      if (mounted) {
        setState(
          () =>
              _error = error is FormatException ? error.message : '字体操作失败，请重试',
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _choose(String? family) async {
    final success = await _run(() async {
      if (family?.startsWith('user_') ?? false) {
        await widget.onLoad?.call(family!);
      }
    });
    if (success && mounted) {
      Navigator.of(context).pop(ReaderFontSelection(family));
    }
  }

  Future<void> _act(ReaderFontOption font, _FontAction action) async {
    switch (action) {
      case _FontAction.preview:
        final success = await _run(
          () async => widget.onLoad?.call(font.family),
        );
        if (success && mounted) setState(() => _preview = font.family);
      case _FontAction.rename:
        final name = await _renamePrompt(context, font.label);
        if (name == null || !mounted) return;
        await _run(() async {
          final renamed = await widget.onRename!(font.family, name);
          if (mounted) setState(() => _fonts[_fonts.indexOf(font)] = renamed);
        });
      case _FontAction.remove:
        if (!await _confirmRemove(font) || !mounted) return;
        await _run(() async {
          await widget.onRemove!(font.family);
          if (!mounted) return;
          setState(() {
            _fonts.remove(font);
            if (_selected == font.family) _selected = null;
            if (_preview == font.family) _preview = null;
          });
        });
    }
  }

  Future<bool> _confirmRemove(ReaderFontOption font) async =>
      await showReaderDialog<bool>(
        context: context,
        builder: (context) => ReaderFrostedAlertDialog(
          title: Text('移除“${font.label}”？'),
          content: Text(
            _selected == font.family
                ? '当前字体移除后将使用书籍字体。可随时重新导入。'
                : '从应用中移除字体文件，可随时重新导入。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const ValueKey('font-remove-confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('移除字体'),
            ),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .78,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(context),
          _previewBox(context),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          if (_error != null) _errorBanner(context),
          Flexible(child: _fontList()),
        ],
      ),
    ),
  );

  Widget _heading(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
    child: Row(
      children: [
        Expanded(
          child: Text('选择字体', style: Theme.of(context).textTheme.titleMedium),
        ),
        IconButton(
          tooltip: '关闭字体选择',
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          icon: const AppIcon(AppGlyph.close),
        ),
      ],
    ),
  );

  Widget _errorBanner(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
    child: Semantics(
      liveRegion: true,
      child: Text(
        _error!,
        key: const ValueKey('font-picker-error'),
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    ),
  );

  Widget _fontList() => ListView(
    shrinkWrap: true,
    children: [
      _tile(key: 'settings-font-book', label: '书籍字体', family: null),
      _tile(
        key: 'settings-font-song',
        label: '宋体',
        family: FontFamilyAliases.song,
      ),
      _tile(key: 'settings-font-hei', label: '黑体', family: 'sans-serif'),
      for (final font in _fonts)
        _tile(
          key: 'settings-custom-font-${font.family}',
          label: font.label,
          family: font.family,
          font: font,
        ),
    ],
  );

  Widget _previewBox(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      '清风翻过书页，阅读从这里开始。\nAa Bb 0123456789',
      key: const ValueKey('font-preview-text'),
      style: TextStyle(
        fontFamily: _preview == null
            ? null
            : FontFamilyAliases.resolve(_preview!) ?? _preview,
        fontSize: 18,
        height: 1.6,
      ),
    ),
  );

  Widget _tile({
    required String key,
    required String label,
    required String? family,
    ReaderFontOption? font,
  }) => ListTile(
    key: ValueKey(key),
    enabled: !_busy,
    selected: _selected == family,
    title: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 14,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    ),
    onTap: () => _choose(family),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_selected == family) const AppIcon(AppGlyph.check, size: 20),
        if (font != null) _fontMenu(font),
      ],
    ),
  );

  Widget _fontMenu(ReaderFontOption font) => PopupMenuButton<_FontAction>(
    key: ValueKey('font-actions-${font.family}'),
    tooltip: '管理${font.label}',
    enabled: !_busy,
    icon: const AppIcon(AppGlyph.more),
    onSelected: (action) => _act(font, action),
    itemBuilder: (_) => [
      const PopupMenuItem(value: _FontAction.preview, child: Text('试读预览')),
      if (widget.onRename != null)
        const PopupMenuItem(value: _FontAction.rename, child: Text('重命名')),
      if (widget.onRemove != null)
        const PopupMenuItem(value: _FontAction.remove, child: Text('移除字体')),
    ],
  );
}

Future<String?> _renamePrompt(BuildContext context, String initial) =>
    showReaderDialog<String>(
      context: context,
      builder: (_) => _FontRenameDialog(initial: initial),
    );

class _FontRenameDialog extends StatefulWidget {
  const _FontRenameDialog({required this.initial});

  final String initial;

  @override
  State<_FontRenameDialog> createState() => _FontRenameDialogState();
}

class _FontRenameDialogState extends State<_FontRenameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ReaderFrostedAlertDialog(
    title: const Text('字体名称'),
    content: TextField(
      key: const ValueKey('font-rename-input'),
      controller: _controller,
      autofocus: true,
      maxLength: 60,
      decoration: const InputDecoration(labelText: '名称'),
      onChanged: (_) => setState(() {}),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(
        key: const ValueKey('font-rename-confirm'),
        onPressed: _controller.text.trim().isEmpty
            ? null
            : () => Navigator.of(context).pop(_controller.text.trim()),
        child: const Text('保存名称'),
      ),
    ],
  );
}
