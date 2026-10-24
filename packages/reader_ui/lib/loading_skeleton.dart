import 'package:flutter/material.dart';

/// 首屏加载骨架（P2-27）：立刻出现，分页完成后由内容平滑替换。
class ReaderLoadingSkeleton extends StatelessWidget {
  /// 创建骨架。
  const ReaderLoadingSkeleton({super.key, this.progress});

  /// 整书进度（0～1）；为 null 时显示不确定进度。
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface
        .withValues(alpha: 0.08);
    return LayoutBuilder(
      builder: (context, constraints) {
        // 按可用高度决定骨架行数，避免小视口溢出。
        final available = constraints.maxHeight.isFinite
            ? constraints.maxHeight - 76
            : 240.0;
        final rows = (available / 30).floor().clamp(1, 8);
        return Padding(
          key: const ValueKey<String>('reader-loading-skeleton'),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 24),
              for (var i = 0; i < rows; i++) ...<Widget>[
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: i == rows - 1 ? 0.55 : 1,
                  child: Container(
                    height: 14,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ],
          ),
        );
      },
    );
  }
}
