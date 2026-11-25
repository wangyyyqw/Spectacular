import 'package:flutter/material.dart';

/// 默认主题使用紧凑胶囊，MD3 使用原生开关，均保留完整触控区域。
class ReaderSwitch extends StatelessWidget {
  const ReaderSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (theme.useMaterial3) {
      return SizedBox(
        width: 56,
        height: 44,
        child: Switch(value: value, onChanged: onChanged),
      );
    }
    final scheme = theme.colorScheme;
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
          borderRadius: BorderRadius.circular(22),
          onTap: enabled ? () => onChanged!(!value) : null,
          child: SizedBox(
            width: 48,
            height: 44,
            child: Center(
              child: AnimatedContainer(
                duration: duration,
                width: 42,
                height: 22,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: value
                      ? scheme.primary
                      : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(11),
                  border: value
                      ? null
                      : Border.all(color: scheme.outlineVariant),
                ),
                child: AnimatedAlign(
                  duration: duration,
                  curve: Curves.easeOut,
                  alignment: value
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: value ? scheme.onPrimary : scheme.onSurfaceVariant,
                      shape: BoxShape.circle,
                      boxShadow: const [
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
