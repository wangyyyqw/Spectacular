import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/theme/reader_ui_style.dart';

import 'ye_she_visuals.dart';

AppBar communityAppBar(
  BuildContext context, {
  required String prefix,
  required String title,
  required VoidCallback? refresh,
}) => AppBar(
  title: Text(
    title,
    key: ValueKey('$prefix-header-title'),
    style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
  ),
  actions: [
    IconButton(
      key: ValueKey('$prefix-refresh'),
      tooltip: '刷新$title',
      onPressed: refresh,
      icon: const AppIcon(AppGlyph.refresh),
    ),
  ],
);

class CommunityTabs extends StatelessWidget {
  const CommunityTabs({
    super.key,
    required this.prefix,
    required this.controller,
    required this.tabs,
  });

  final String prefix;
  final TabController controller;
  final List<(String, AppGlyph, String)> tabs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: TabBar(
        key: ValueKey('$prefix-tab-bar'),
        controller: controller,
        labelColor: scheme.onSurface,
        unselectedLabelColor: scheme.onSurfaceVariant,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: scheme.surface,
          borderRadius: ReaderUiStyle.controlRadiusOf(theme),
          border: Border.all(color: YeSheTokens.line(context)),
        ),
        dividerColor: Colors.transparent,
        overlayColor: WidgetStatePropertyAll(
          YeSheTokens.vermilion(context).withValues(alpha: .08),
        ),
        labelStyle: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        ),
        unselectedLabelStyle: theme.textTheme.labelLarge?.copyWith(
          letterSpacing: 1,
        ),
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        tabs: [
          for (final (index, (id, glyph, label)) in tabs.indexed)
            Tab(
              key: ValueKey('$prefix-tab-$id'),
              height: 42,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedBuilder(
                    animation: controller,
                    builder: (context, child) => AppIcon(
                      glyph,
                      size: 16,
                      color: controller.index == index
                          ? YeSheTokens.vermilion(context)
                          : scheme.onSurfaceVariant.withValues(alpha: .7),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
