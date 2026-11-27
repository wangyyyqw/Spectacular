import 'package:flutter/material.dart';

import 'reader_ui_style.dart';

/// 统一的设计度量与间距规范：Classic 与 Material 3 两套风格共用节奏，
/// 通过 `ReaderUiStyle` 派生各自圆角、边框与阴影层次。
abstract final class ReaderUiTokens {
  static const double spacingXs = 4;
  static const double spacingSm = 8;
  static const double spacingMd = 12;
  static const double spacingLg = 16;
  static const double spacingXl = 20;
  static const double spacing2xl = 24;

  static const double pageMaxWidth = 680;
  static const double sheetMaxWidth = 680;
  static const double dialogMaxWidth = 480;

  static const EdgeInsets pagePadding = EdgeInsets.fromLTRB(16, 12, 16, 24);
  static const EdgeInsets sheetContentPadding = EdgeInsets.fromLTRB(
    20,
    12,
    20,
    16,
  );
  static const EdgeInsets sheetHeaderPadding = EdgeInsets.fromLTRB(
    20,
    12,
    12,
    8,
  );
  static const EdgeInsets sheetActionsPadding = EdgeInsets.fromLTRB(
    20,
    10,
    20,
    16,
  );
  static const EdgeInsets cardContentPadding = EdgeInsets.all(16);
}

/// 统一的设置页 / 详情页分组容器：标题 + 统一样式卡片 + 内部细分隔线。
///
/// 在 Classic 下呈现锐利细描边分组卡片；在 Material 3 下呈现柔和圆角表面卡片。
class ReaderSectionGroup extends StatelessWidget {
  const ReaderSectionGroup({
    super.key,
    this.title,
    this.footer,
    required this.children,
    this.trailing,
    this.showDividers = true,
    this.dividerIndent = 16,
  });

  final String? title;
  final String? footer;
  final Widget? trailing;
  final List<Widget> children;
  final bool showDividers;
  final double dividerIndent;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final headerColor = theme.useMaterial3
        ? colors.primary
        : colors.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title != null || trailing != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Row(
              children: [
                if (title != null)
                  Expanded(
                    child: Text(
                      title!,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: headerColor,
                        fontWeight: FontWeight.w600,
                        letterSpacing: theme.useMaterial3 ? 0.2 : 0,
                      ),
                    ),
                  ),
                ?trailing,
              ],
            ),
          ),
        ],
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < children.length; index++) ...[
                if (showDividers && index > 0)
                  Divider(
                    height: 1,
                    indent: dividerIndent,
                    endIndent: dividerIndent,
                  ),
                children[index],
              ],
            ],
          ),
        ),
        if (footer != null) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              footer!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// 统一的设置页滚动骨架：标准 `Scaffold` + `AppBar` + 居中限宽滚动列表。
class ReaderSettingsScaffold extends StatelessWidget {
  const ReaderSettingsScaffold({
    super.key,
    required this.title,
    required this.children,
    this.actions,
    this.fixedHeader,
    this.maxWidth = ReaderUiTokens.pageMaxWidth,
    this.padding = ReaderUiTokens.pagePadding,
    this.floatingActionButton,
    this.bottomNavigationBar,
  });

  final Widget title;
  final List<Widget> children;
  final List<Widget>? actions;
  final Widget? fixedHeader;
  final double maxWidth;
  final EdgeInsetsGeometry padding;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;

  @override
  Widget build(BuildContext context) {
    final list = ListView(padding: padding, children: children);
    return Scaffold(
      appBar: AppBar(title: title, actions: actions),
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: fixedHeader == null
                ? list
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(padding: padding, child: fixedHeader),
                      Expanded(child: list),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// 统一的空态 / 错误态占位视图。
class ReaderEmptyState extends StatelessWidget {
  const ReaderEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.action,
  });

  final Widget icon;
  final String title;
  final String? description;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: theme.useMaterial3
                      ? colors.surfaceContainerHigh
                      : colors.surfaceContainerLow,
                  borderRadius: ReaderUiStyle.cardRadiusOf(theme),
                  border: theme.useMaterial3
                      ? null
                      : Border.all(color: colors.outlineVariant),
                ),
                alignment: Alignment.center,
                child: IconTheme(
                  data: IconThemeData(size: 28, color: colors.onSurfaceVariant),
                  child: icon,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (description != null) ...[
                const SizedBox(height: 8),
                Text(
                  description!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ],
              if (action != null) ...[const SizedBox(height: 20), action!],
            ],
          ),
        ),
      ),
    );
  }
}

/// 统一的状态/错误提示横幅（替代散落各处的裸红色 Text）。
class ReaderInlineNotice extends StatelessWidget {
  const ReaderInlineNotice({
    super.key,
    required this.message,
    this.isError = false,
    this.icon,
    this.trailing,
  });

  final String message;
  final bool isError;
  final Widget? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final bg = isError ? colors.errorContainer : colors.surfaceContainerLow;
    final fg = isError ? colors.onErrorContainer : colors.onSurface;
    final borderColor = isError
        ? colors.error.withValues(alpha: 0.35)
        : colors.outlineVariant;
    return Semantics(
      liveRegion: isError,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: ReaderUiStyle.controlRadiusOf(theme),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              IconTheme(
                data: IconThemeData(size: 18, color: fg),
                child: icon!,
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: fg,
                  height: 1.4,
                ),
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
      ),
    );
  }
}

/// 底部/抽屉动作选项定义，用于 `showReaderActionSheet` 与 `showReaderOptionSheet`。
class ReaderSheetAction<T> {
  const ReaderSheetAction({
    this.key,
    required this.value,
    required this.title,
    this.subtitle,
    this.icon,
    this.destructive = false,
    this.selected = false,
    this.enabled = true,
  });

  final Key? key;
  final T value;
  final String title;
  final String? subtitle;
  final Widget? icon;
  final bool destructive;
  final bool selected;
  final bool enabled;
}
