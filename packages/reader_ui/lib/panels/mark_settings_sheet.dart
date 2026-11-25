import 'package:flutter/material.dart';

import '../theme/reader_ui_style.dart';

import '../annotations/annotation_appearance_editor.dart';
import '../annotations/annotation_quote_preview.dart';
import '../annotations/mark_settings.dart';
import '../icons/app_icon.dart';
import '../theme/reader_frosted_surface.dart';

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
  @override
  Widget build(BuildContext context) => Material(
    color: ReaderFrostedSurface.panelColorOf(context),
    borderRadius: ReaderUiStyle.sheetRadius,
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
                        '划线设置',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        tooltip: '关闭',
                        icon: const AppIcon(AppGlyph.close),
                      ),
                    ],
                  ),
                  const Text('快捷划线使用这里的默认样式和默认颜色；自定义颜色长按可删除。'),
                  const SizedBox(height: 12),
                  AnnotationQuotePreview(
                    quote: '划线标记阅读重点，想法记录此刻思考。',
                    color: _settings.lastColor,
                    style: _settings.lastStyle,
                    opacity: _settings.lastStyle.defaultOpacity,
                    strokeWidth: _settings.strokeWidth,
                    inkMode: widget.inkMode,
                  ),
                  const SizedBox(height: 12),
                  ReaderAnnotationAppearanceEditor(
                    color: _settings.lastColor,
                    style: _settings.lastStyle,
                    opacity: _settings.lastStyle.defaultOpacity,
                    settings: _settings,
                    inkMode: widget.inkMode,
                    showOpacity: false,
                    onColor: (value) => setState(
                      () => _settings = _settings.copyWith(lastColor: value),
                    ),
                    onStyle: (value) => setState(
                      () => _settings = _settings.copyWith(lastStyle: value),
                    ),
                    onSettings: (value) => setState(
                      () => _settings = _settings.copyWith(
                        strokeWidth: value.strokeWidth,
                        joinBackgroundLines: value.joinBackgroundLines,
                        customColors: value.customColors,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey<String>('mark-settings-save'),
                onPressed: () => Navigator.of(context).pop(_settings),
                child: const Text('保存划线设置'),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
