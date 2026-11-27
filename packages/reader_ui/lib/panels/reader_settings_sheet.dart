import 'package:flutter/material.dart';

import '../icons/app_icon.dart';
import '../theme/reader_frosted_surface.dart';
import '../theme/reader_ui_style.dart';

/// 设置菜单共用的固定高度面板：支持标题栏、滚动正文和可选的固定底部操作栏。
class ReaderSettingsSheet extends StatelessWidget {
  const ReaderSettingsSheet({
    super.key,
    this.title,
    this.onClose,
    this.footer,
    required this.header,
    required this.child,
  });

  final String? title;
  final VoidCallback? onClose;
  final Widget? footer;
  final Widget header;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return SizedBox(
      height:
          MediaQuery.sizeOf(context).height *
          ReaderUiStyle.settingsSheetHeightFraction,
      child: Material(
        color: ReaderFrostedSurface.panelColorOf(context),
        borderRadius: ReaderUiStyle.sheetRadius,
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 8, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title!,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: colors.onSurface,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '关闭',
                        color: colors.onSurfaceVariant,
                        constraints: const BoxConstraints(
                          minWidth: 44,
                          minHeight: 44,
                        ),
                        onPressed: onClose ?? () => Navigator.maybePop(context),
                        icon: const AppIcon(AppGlyph.close, size: 20),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: header,
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: child,
                ),
              ),
              if (footer != null) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                  child: SizedBox(width: double.infinity, child: footer!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
