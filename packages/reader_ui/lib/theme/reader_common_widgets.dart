import 'package:flutter/material.dart';

import '../icons/app_icon.dart';
import 'reader_drawer_style.dart';
import 'reader_ink.dart';
import 'reader_ui_style.dart';

/// 分组卡片容器：顶部可选分组标题 + 20dp 圆角实色白卡 + 1px 细描边。
///
/// 当提供 [children] 且 [divided] 为真时，会在相邻项之间插入 16dp 缩进细分隔线，
/// 统一「我的」、网盘、同步、词典与设置等页面的分组区块外观。
class ReaderSectionCard extends StatelessWidget {
  const ReaderSectionCard({
    super.key,
    this.title,
    this.trailing,
    this.children,
    this.child,
    this.padding,
    this.divided = true,
    this.dividerIndent = 16,
    this.dividerEndIndent = 16,
  }) : assert(
         (children != null) != (child != null),
         'Either children or child must be provided.',
       );

  final String? title;
  final Widget? trailing;
  final List<Widget>? children;
  final Widget? child;
  final EdgeInsetsGeometry? padding;
  final bool divided;
  final double dividerIndent;
  final double dividerEndIndent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Widget body;
    if (child != null) {
      body = padding == null
          ? child!
          : Padding(padding: padding!, child: child);
    } else {
      final rows = children!;
      final column = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (var i = 0; i < rows.length; i++) ...[
            if (divided && i > 0)
              Divider(
                height: 1,
                indent: dividerIndent,
                endIndent: dividerEndIndent,
              ),
            rows[i],
          ],
        ],
      );
      body = padding == null
          ? column
          : Padding(padding: padding!, child: column);
    }
    final card = Material(
      color: theme.colorScheme.surface,
      shape: ReaderUiStyle.cardShapeOf(theme),
      clipBehavior: Clip.antiAlias,
      child: body,
    );
    if (title == null && trailing == null) return card;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            if (title != null)
              Expanded(
                child: Text(title!, style: theme.textTheme.labelMedium),
              ),
            ?trailing,
          ],
        ),
        const SizedBox(height: 10),
        card,
      ],
    );
  }
}

/// 全站共用的全圆角胶囊搜索框（999dp 胶囊圆角、柔和底填充，可选右侧竖线+附加按钮）。
class ReaderSearchField extends StatelessWidget {
  const ReaderSearchField({
    super.key,
    this.surfaceKey,
    this.fieldKey,
    required this.controller,
    this.focusNode,
    required this.hintText,
    this.autofocus = false,
    this.onTap,
    this.onChanged,
    this.prefixIcon,
    this.suffixIcon,
    this.trailingAction,
  });

  final Key? surfaceKey;
  final Key? fieldKey;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hintText;
  final bool autofocus;
  final VoidCallback? onTap;
  final ValueChanged<String>? onChanged;
  final Widget? prefixIcon;
  final Widget? suffixIcon;

  /// 可选右侧附属动作（如书架的「+」导入按钮），以细竖线与输入框分隔在同一胶囊内。
  final Widget? trailingAction;

  static const _pillRadius = BorderRadius.all(Radius.circular(999));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final muted = ReaderDrawerStyle.mutedOf(theme);
    final fill = trailingAction == null
        ? colors.surfaceContainerLow
        : colors.surfaceContainerHigh;
    final border = OutlineInputBorder(
      borderRadius: _pillRadius,
      borderSide: BorderSide(color: colors.outlineVariant),
    );
    final textStyle = theme.textTheme.bodyMedium?.copyWith(
      fontSize: 14,
      height: 1.5,
      fontWeight: FontWeight.w400,
      color: colors.onSurface,
    );
    if (trailingAction == null) {
      return Material(
        key: surfaceKey,
        color: fill,
        borderRadius: _pillRadius,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        child: TextField(
          key: fieldKey,
          controller: controller,
          focusNode: focusNode,
          autofocus: autofocus,
          textInputAction: TextInputAction.search,
          style: textStyle,
          cursorColor: colors.primary,
          onTap: onTap,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: textStyle?.copyWith(color: muted) ??
                TextStyle(color: muted),
            filled: true,
            isDense: true,
            fillColor: fill,
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            border: border,
            enabledBorder: border,
            focusedBorder: border.copyWith(
              borderSide: BorderSide(color: colors.primary),
            ),
            prefixIconConstraints: const BoxConstraints.tightFor(
              width: 40,
              height: 40,
            ),
            suffixIconConstraints: const BoxConstraints.tightFor(
              width: 40,
              height: 40,
            ),
            prefixIcon:
                prefixIcon ?? AppIcon(AppGlyph.search, size: 20, color: muted),
            suffixIcon: suffixIcon,
          ),
        ),
      );
    }
    return Material(
      key: surfaceKey,
      color: fill,
      shape: StadiumBorder(
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: .7)),
      ),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      child: SizedBox(
        height: 44,
        child: Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                key: fieldKey,
                controller: controller,
                focusNode: focusNode,
                autofocus: autofocus,
                textInputAction: TextInputAction.search,
                cursorColor: colors.primary,
                onTap: onTap,
                onChanged: onChanged,
                decoration: InputDecoration(
                  hintText: hintText,
                  hintStyle: TextStyle(color: muted),
                  filled: false,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  prefixIconConstraints: const BoxConstraints.tightFor(
                    width: 44,
                    height: 44,
                  ),
                  suffixIconConstraints: const BoxConstraints.tightFor(
                    width: 40,
                    height: 44,
                  ),
                  prefixIcon:
                      prefixIcon ??
                      AppIcon(AppGlyph.search, size: 20, color: muted),
                  suffixIcon: suffixIcon,
                ),
              ),
            ),
            Container(
              width: 1,
              height: 20,
              color: colors.outlineVariant,
            ),
            trailingAction!,
          ],
        ),
      ),
    );
  }
}

/// 页面内嵌错误/警告提示条，共用主题样式并播报动态更新的提示。
class ReaderNoticeBanner extends StatelessWidget {
  const ReaderNoticeBanner({
    super.key,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.icon = AppGlyph.warning,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final AppGlyph icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: colors.errorContainer,
          borderRadius: ReaderUiStyle.controlRadius,
          border: Border.all(color: colors.error.withValues(alpha: .28)),
        ),
        child: Row(
          children: <Widget>[
            AppIcon(icon, size: 18, color: colors.error),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onErrorContainer,
                ),
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(width: 8),
              TextButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// 顶栏共用的 44×44 表面图标按钮（默认支持圆形或 12dp 圆角、柔和底色与无按压水波）。
class ReaderSurfaceIconButton extends StatelessWidget {
  const ReaderSurfaceIconButton({
    super.key,
    this.buttonKey,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.color,
    this.backgroundColor,
    this.circular = false,
    this.keepDesktopHover = false,
  });

  final Key? buttonKey;
  final String tooltip;
  final Widget icon;
  final VoidCallback? onPressed;
  final Color? color;
  final Color? backgroundColor;
  final bool circular;
  final bool keepDesktopHover;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final buttonTheme = keepDesktopHover
        ? theme.copyWith(
            splashFactory: NoSplash.splashFactory,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
          )
        : quietInk(theme);
    final shape = circular
        ? CircleBorder(
            side: BorderSide(color: colors.outlineVariant.withValues(alpha: .7)),
          )
        : ReaderUiStyle.controlShape.copyWith(
            side: BorderSide(color: colors.outlineVariant),
          );
    return Material(
      color: backgroundColor ??
          (circular ? colors.surfaceContainerHigh : colors.surface),
      shape: shape,
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      child: Theme(
        data: buttonTheme,
        child: IconButton(
          key: buttonKey,
          tooltip: tooltip,
          color: color ?? colors.onSurface,
          constraints: const BoxConstraints.tightFor(width: 44, height: 44),
          padding: EdgeInsets.zero,
          onPressed: onPressed,
          icon: icon,
        ),
      ),
    );
  }
}

/// 统一的单选选项行：用于排序、主题模式、定时暂停等短选择抽屉，
/// 选中项使用主题 `primaryContainer` 高亮底色与明确勾选图标。
class ReaderOptionTile extends StatelessWidget {
  const ReaderOptionTile({
    super.key,
    this.tileKey,
    required this.title,
    this.subtitle,
    this.leading,
    this.selected = false,
    this.destructive = false,
    this.enabled = true,
    this.trailing,
    this.onTap,
  });

  final Key? tileKey;
  final String title;
  final String? subtitle;
  final Widget? leading;
  final bool selected;
  final bool destructive;
  final bool enabled;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final foreground = !enabled
        ? theme.disabledColor
        : destructive
        ? colors.error
        : selected
        ? colors.onPrimaryContainer
        : colors.onSurface;
    return Semantics(
      selected: selected,
      enabled: enabled,
      button: onTap != null,
      child: Material(
        color: selected ? colors.primaryContainer : Colors.transparent,
        shape: ReaderUiStyle.controlShape,
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          key: tileKey,
          enabled: enabled,
          selected: selected,
          selectedTileColor: Colors.transparent,
          selectedColor: colors.onPrimaryContainer,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 2,
          ),
          minLeadingWidth: 20,
          horizontalTitleGap: 12,
          leading: leading == null
              ? null
              : IconTheme(
                  data: IconThemeData(color: foreground, size: 20),
                  child: leading!,
                ),
          title: Text(
            title,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: foreground,
            ),
          ),
          subtitle: subtitle == null
              ? null
              : Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: selected
                        ? colors.onPrimaryContainer.withValues(alpha: .82)
                        : colors.onSurfaceVariant,
                  ),
                ),
          trailing:
              trailing ??
              (selected
                  ? AppIcon(
                      AppGlyph.check,
                      size: 18,
                      color: colors.onPrimaryContainer,
                    )
                  : null),
          onTap: enabled ? onTap : null,
        ),
      ),
    );
  }
}

/// 统一的页面空态 / 搜索无结果 / 加载错误展示组件：
/// 56×56 柔和圆角底板图标 + 清晰标题与说明 + 可选主/次操作按钮。
class ReaderEmptyState extends StatelessWidget {
  const ReaderEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
    this.iconColor,
    this.iconContainerColor,
    this.padding = const EdgeInsets.all(28),
  });

  final AppGlyph icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  final Color? iconColor;
  final Color? iconContainerColor;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Center(
      child: Padding(
        padding: padding,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: iconContainerColor ?? colors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: colors.outlineVariant.withValues(alpha: .7),
                  ),
                ),
                child: AppIcon(
                  icon,
                  size: 26,
                  color: iconColor ?? colors.onSurfaceVariant,
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
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: 18),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

