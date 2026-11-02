import 'package:flutter/material.dart';

/// 首屏加载骨架（P2-27）：立刻出现，分页完成后由内容平滑替换。
class ReaderLoadingSkeleton extends StatefulWidget {
  /// 创建骨架。
  const ReaderLoadingSkeleton({super.key, this.progress, this.title});

  /// 整书进度（0～1）；为 null 时显示不确定进度。
  final double? progress;

  /// 正在打开的书名。
  final String? title;

  @override
  State<ReaderLoadingSkeleton> createState() => _ReaderLoadingSkeletonState();
}

class _ReaderLoadingSkeletonState extends State<ReaderLoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _shimmer
        ..stop()
        ..value = 0;
    } else if (!_shimmer.isAnimating) {
      _shimmer.repeat();
    }
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = theme.colorScheme.onSurface.withValues(alpha: 0.06);
    final highlightColor = theme.colorScheme.onSurface.withValues(alpha: 0.13);
    final title = widget.title?.trim();
    final hasTitle = title != null && title.isNotEmpty;
    return LayoutBuilder(
      builder: (context, constraints) {
        // 按可用高度决定骨架行数，避免小视口溢出。
        final available = constraints.maxHeight.isFinite
            ? constraints.maxHeight - 76 - (hasTitle ? 58 : 0)
            : 240.0;
        final rows = (available / 30).floor().clamp(0, 8);
        return Padding(
          key: const ValueKey<String>('reader-loading-skeleton'),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              LinearProgressIndicator(value: widget.progress),
              const SizedBox(height: 18),
              if (hasTitle) ...[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  '正在排版…',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
              ] else
                const SizedBox(height: 6),
              if (rows > 0)
                AnimatedBuilder(
                  animation: _shimmer,
                  builder: (context, _) {
                    final begin = -1.6 + _shimmer.value * 3.2;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        for (var i = 0; i < rows; i++) ...<Widget>[
                          FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: i == rows - 1 ? 0.55 : 1,
                            child: Container(
                              height: 14,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(4),
                                gradient: LinearGradient(
                                  begin: Alignment(begin, 0),
                                  end: Alignment(begin + 1, 0),
                                  colors: <Color>[
                                    baseColor,
                                    highlightColor,
                                    baseColor,
                                  ],
                                  stops: const <double>[0.2, 0.5, 0.8],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ],
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}
