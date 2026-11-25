import 'package:flutter/material.dart';

/// 沿用阅读设置的紧凑胶囊开关，颜色由当前页面主题提供。
class ReaderSwitch extends StatelessWidget {
  const ReaderSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final material3 = theme.useMaterial3;
    final enabled = onChanged != null;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
    return Semantics(
      toggled: value,
      enabled: enabled,
      child: Opacity(
        opacity: enabled ? 1 : .42,
        child: InkWell(
          borderRadius: BorderRadius.circular(material3 ? 24 : 22),
          onTap: enabled ? () => onChanged!(!value) : null,
          child: SizedBox(
            width: material3 ? 56 : 48,
            height: 44,
            child: Center(
              child: AnimatedContainer(
                duration: duration,
                width: material3 ? 52 : 42,
                height: material3 ? 32 : 22,
                padding: EdgeInsets.all(material3 ? 4 : 2),
                decoration: BoxDecoration(
                  color: value
                      ? material3
                            ? scheme.secondaryContainer
                            : scheme.primary
                      : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(material3 ? 16 : 11),
                  border: value
                      ? null
                      : Border.all(
                          color: material3
                              ? scheme.outline
                              : scheme.outlineVariant,
                        ),
                ),
                child: AnimatedAlign(
                  duration: duration,
                  curve: Curves.easeOut,
                  alignment: value
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    width: material3 ? (value ? 24 : 16) : 18,
                    height: material3 ? (value ? 24 : 16) : 18,
                    decoration: BoxDecoration(
                      color: value
                          ? material3
                                ? scheme.onSecondaryContainer
                                : scheme.onPrimary
                          : material3
                          ? scheme.onSurfaceVariant
                          : scheme.onSurfaceVariant,
                      shape: BoxShape.circle,
                      boxShadow: material3
                          ? null
                          : const [
                              BoxShadow(
                                color: Color(0x33000000),
                                blurRadius: 3,
                                offset: Offset(0, 1),
                              ),
                            ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 设置行共用开关尺寸、点击区域与禁用行为。
class ReaderSwitchListTile extends StatelessWidget {
  const ReaderSwitchListTile({
    super.key,
    required this.value,
    required this.onChanged,
    this.title,
    this.subtitle,
    this.secondary,
    this.contentPadding,
    this.dense,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget? title;
  final Widget? subtitle;
  final Widget? secondary;
  final EdgeInsetsGeometry? contentPadding;
  final bool? dense;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: ListTile(
      title: title,
      subtitle: subtitle,
      leading: secondary,
      contentPadding: contentPadding,
      dense: dense,
      enabled: onChanged != null,
      onTap: onChanged == null ? null : () => onChanged!(!value),
      trailing: ReaderSwitch(value: value, onChanged: onChanged),
    ),
  );
}
