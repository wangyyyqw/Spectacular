import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/theme/reader_drawer_style.dart';

import 'desktop_layout.dart';

const desktopBookPageMaxWidth = 1440.0;

AppBar bookSearchBar(
  BuildContext context, {
  required String section,
  required String keyPrefix,
  required TextEditingController controller,
  required String searchLabel,
  required VoidCallback onSearch,
  required String actionLabel,
  required Widget actionIcon,
  required Key actionKey,
  required VoidCallback? onAction,
  required String desktopAction,
  required double availableWidth,
  FocusNode? focusNode,
  VoidCallback? onTap,
  ValueChanged<String>? onChanged,
  ValueChanged<String>? onSubmitted,
  Widget? clearButton,
}) {
  final theme = Theme.of(context);
  final desktop = usesDesktopLayout(context);
  final roomy = desktop && availableWidth >= 640;
  final color = ReaderDrawerStyle.searchSurfaceOf(theme);
  final shadow = theme.colorScheme.shadow.withValues(alpha: .12);
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(20),
    borderSide: BorderSide.none,
  );
  final field = Material(
    key: ValueKey('$keyPrefix-search-surface'),
    color: color,
    elevation: 3,
    borderRadius: border.borderRadius,
    surfaceTintColor: Colors.transparent,
    shadowColor: shadow,
    child: TextField(
      key: ValueKey('$keyPrefix-search-field'),
      controller: controller,
      focusNode: focusNode,
      onTap: onTap,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: '搜索书名或作者',
        filled: true,
        isDense: true,
        fillColor: color,
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        border: border,
        enabledBorder: border,
        focusedBorder: border,
        prefixIconConstraints: const BoxConstraints.tightFor(
          width: 40,
          height: 40,
        ),
        suffixIconConstraints: const BoxConstraints.tightFor(
          width: 40,
          height: 40,
        ),
        prefixIcon: IconButton(
          tooltip: searchLabel,
          onPressed: onSearch,
          icon: const AppIcon(AppGlyph.search),
        ),
        suffixIcon: clearButton,
      ),
    ),
  );
  return AppBar(
    automaticallyImplyLeading: false,
    toolbarHeight: desktop ? 64 : 56,
    titleSpacing: 16,
    title: desktop
        ? Row(
            children: [
              if (roomy) ...[
                Text(section, style: theme.textTheme.titleLarge),
                const SizedBox(width: 24),
              ],
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: field,
                  ),
                ),
              ),
            ],
          )
        : field,
    actions: [
      Padding(
        padding: const EdgeInsets.only(right: 16),
        child: Center(
          child: roomy
              ? FilledButton.tonalIcon(
                  key: actionKey,
                  onPressed: onAction,
                  icon: actionIcon,
                  label: Text(desktopAction),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    visualDensity: VisualDensity.standard,
                  ),
                )
              : Material(
                  color: color,
                  borderRadius: border.borderRadius,
                  elevation: 2,
                  surfaceTintColor: Colors.transparent,
                  shadowColor: shadow,
                  child: IconButton(
                    key: actionKey,
                    tooltip: actionLabel,
                    onPressed: onAction,
                    icon: actionIcon,
                    color: theme.colorScheme.primary,
                    constraints: const BoxConstraints.tightFor(
                      width: 44,
                      height: 44,
                    ),
                    style: desktop
                        ? null
                        : const ButtonStyle(
                            overlayColor: WidgetStatePropertyAll(
                              Colors.transparent,
                            ),
                          ),
                  ),
                ),
        ),
      ),
    ],
  );
}
