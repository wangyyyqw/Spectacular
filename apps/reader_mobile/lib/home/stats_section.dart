import 'package:flutter/material.dart';

/// 统计页细线分区：标题、右侧摘要、可选说明与内容。
class StatsSection extends StatelessWidget {
  /// 创建分区。
  const StatsSection({
    super.key,
    required this.title,
    this.detail,
    this.caption,
    this.showDivider = true,
    required this.child,
  });

  final String title;
  final String? detail;
  final String? caption;
  final bool showDivider;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showDivider) ...[
          const SizedBox(height: 24),
          Container(height: 1, color: theme.colorScheme.outlineVariant),
          const SizedBox(height: 16),
        ],
        SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 6,
            children: [
              Semantics(
                container: true,
                header: true,
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ),
              if (detail != null)
                Text(
                  detail!,
                  style: TextStyle(fontSize: 12, color: muted, height: 1.3),
                ),
            ],
          ),
        ),
        if (caption != null) ...[
          const SizedBox(height: 5),
          Text(
            caption!,
            style: TextStyle(fontSize: 12, color: muted, height: 1.4),
          ),
        ],
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}
