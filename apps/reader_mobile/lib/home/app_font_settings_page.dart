import 'package:flutter/material.dart';
import 'package:reader_ui/theme/reader_ui_components.dart';
import 'package:reader_ui/theme/reader_font_preview.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';

import '../library/library_store.dart';
import '../theme/app_theme.dart';

/// 选择、导入和移除应用界面字体；字体文件与清单由宿主统一存储。
class AppFontSettingsPage extends StatefulWidget {
  const AppFontSettingsPage({
    super.key,
    required this.fonts,
    required this.selectedFamily,
    required this.onSelect,
    required this.onImport,
    required this.onRemove,
  });

  final List<ReaderFontEntry> fonts;
  final String selectedFamily;
  final Future<void> Function(String family) onSelect;
  final Future<ReaderFontEntry?> Function() onImport;
  final Future<void> Function(String family) onRemove;

  @override
  State<AppFontSettingsPage> createState() => _AppFontSettingsPageState();
}

class _AppFontSettingsPageState extends State<AppFontSettingsPage> {
  late final List<ReaderFontEntry> _fonts = List.of(widget.fonts);
  late String _selected = widget.selectedFamily;
  String? _error;
  bool _busy = false;

  Future<void> _select(String family) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSelect(family);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = _messageOf(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final font = await widget.onImport();
      if (font == null || !mounted) return;
      _fonts
        ..removeWhere((item) => item.family == font.family)
        ..add(font);
      await widget.onSelect(font.family);
      if (!mounted) return;
      _selected = font.family;
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = _messageOf(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(ReaderFontEntry font) async {
    if (_busy || !await _confirmRemove(font) || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onRemove(font.family);
      if (!mounted) return;
      setState(() {
        _fonts.removeWhere((item) => item.family == font.family);
        if (_selected == font.family) {
          _selected = AppFonts.defaultFamily;
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = _messageOf(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmRemove(ReaderFontEntry font) => showReaderConfirmDialog(
    context: context,
    title: '移除“${font.displayName}”？',
    message: _selected == font.family
        ? '移除后应用字体将恢复为思源宋体，可随时重新导入。'
        : '从本机移除该字体文件，可随时重新导入。',
    confirmLabel: '移除字体',
    destructive: true,
    confirmKey: const ValueKey('app-font-remove-confirm'),
  );

  static String _messageOf(Object error) =>
      error is FormatException ? error.message : '字体操作失败，请重试';

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: !_busy,
    child: ReaderSettingsScaffold(
      title: const Text('应用字体'),
      children: [
        ReaderFontPreview(
          textKey: const ValueKey('app-font-preview'),
          sample: '山水之间，字里行间。\nAa Bb 0123456789',
          family: _selected,
          fallback: _selected == AppFonts.defaultFamily
              ? null
              : AppFonts.fallback,
        ),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        if (_error != null)
          ReaderInlineNotice(
            key: const ValueKey('app-font-error'),
            message: _error!,
            isError: true,
          ),
        const SizedBox(height: ReaderUiTokens.spacingXl),
        _fontList(),
      ],
    ),
  );

  Widget _fontList() => ReaderSectionGroup(
    children: [
      ListTile(
        key: const ValueKey('app-font-default'),
        enabled: !_busy,
        selected: _selected == AppFonts.defaultFamily,
        title: const Text('思源宋体'),
        trailing: _selected == AppFonts.defaultFamily
            ? const AppIcon(AppGlyph.check, size: 20)
            : null,
        onTap: () => _select(AppFonts.defaultFamily),
      ),
      for (final font in _fonts) _fontTile(font),
      ListTile(
        key: const ValueKey('app-font-import'),
        enabled: !_busy,
        leading: const AppIcon(AppGlyph.upload),
        title: Text(_busy ? '正在处理字体…' : '导入本地字体'),
        subtitle: const Text('支持 TTF、OTF，最大 50MB'),
        onTap: _busy ? null : _import,
      ),
    ],
  );

  Widget _fontTile(ReaderFontEntry font) => ListTile(
    key: ValueKey('app-font-${font.family}'),
    enabled: !_busy,
    selected: _selected == font.family,
    title: Text(font.displayName),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_selected == font.family) const AppIcon(AppGlyph.check, size: 20),
        PopupMenuButton<String>(
          key: ValueKey('app-font-actions-${font.family}'),
          tooltip: '管理${font.displayName}',
          enabled: !_busy,
          icon: const AppIcon(AppGlyph.more),
          onSelected: (_) => _remove(font),
          itemBuilder: (_) => const [
            PopupMenuItem<String>(value: 'remove', child: Text('移除字体')),
          ],
        ),
      ],
    ),
    onTap: () => _select(font.family),
  );
}
