import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../bookmarks/bookmark_ribbon.dart';
import '../bookmarks/bookmark_style.dart';
import '../icons/app_icon.dart';
import '../theme/reader_frosted_surface.dart';

/// 编辑全局书签样式，保存前只更新预览。
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

  // 声明式表单保持预览、图片和尺寸顺序，行数较多但不增加分支或状态。
  @override
  Widget build(BuildContext context) => Material(
    color: ReaderFrostedSurface.panelColorOf(context),
    child: SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        '书签样式',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: '关闭',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const AppIcon(AppGlyph.close),
                      ),
                    ],
                  ),
                  const Text('应用于所有书籍，显示在有书签的阅读页右上角。'),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: ReaderBookmarkStyle.maxLength + 12,
                    child: ColoredBox(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      child: Padding(
                        padding: EdgeInsets.only(right: _style.rightInset),
                        child: Align(
                          alignment: Alignment.topRight,
                          child: ReaderBookmarkRibbon(
                            style: _style,
                            color: Theme.of(context).colorScheme.primary,
                            imageLoader: widget.imageLoader,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        key: const ValueKey('bookmark-pick-image'),
                        onPressed: _picking
                            ? null
                            : widget.onPickImage == null
                            ? null
                            : _pickImage,
                        child: Text(_picking ? '正在导入…' : '选择本地图片'),
                      ),
                      TextButton(
                        onPressed: _picking || _style.imageId == null
                            ? null
                            : () => setState(
                                () => _style = _style.withImage(null),
                              ),
                        child: const Text('使用默认图标'),
                      ),
                    ],
                  ),
                  if (_error != null)
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  const Text('图片随宽度和长度缩放；透明 PNG 可保留镂空效果。'),
                  const SizedBox(height: 12),
                  _dimension(
                    '宽度',
                    _style.width,
                    ReaderBookmarkStyle.minWidth,
                    ReaderBookmarkStyle.maxWidth,
                    (value) =>
                        setState(() => _style = _style.copyWith(width: value)),
                  ),
                  _dimension(
                    '长度',
                    _style.length,
                    ReaderBookmarkStyle.minLength,
                    ReaderBookmarkStyle.maxLength,
                    (value) =>
                        setState(() => _style = _style.copyWith(length: value)),
                  ),
                  _dimension(
                    '距右侧',
                    _style.rightInset,
                    ReaderBookmarkStyle.minRightInset,
                    ReaderBookmarkStyle.maxRightInset,
                    (value) => setState(
                      () => _style = _style.copyWith(rightInset: value),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey('bookmark-style-save'),
                onPressed: _picking
                    ? null
                    : () => Navigator.of(context).pop(_style),
                child: const Text('保存书签样式'),
              ),
            ),
          ),
        ],
      ),
    ),
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
}
