import 'package:flutter/material.dart';

import 'app_brand_icon.dart';

/// 冷启动开屏：盖住书架与封面预解码，约 0.8 秒后淡出。
class StartupSplash extends StatefulWidget {
  const StartupSplash({super.key, required this.onFinished, this.ready = true});

  /// 图标始终可见，主题与首屏恢复后才开始淡出。
  final bool ready;

  /// 动画结束（完全淡出）后回调一次。
  final VoidCallback onFinished;

  /// 开屏总时长。
  static const duration = Duration(milliseconds: 800);

  @override
  State<StartupSplash> createState() => _StartupSplashState();
}

class _StartupSplashState extends State<StartupSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _veil;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: StartupSplash.duration)
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) widget.onFinished();
          });
    if (widget.ready) _controller.forward();
    _veil = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(.72, 1, curve: Curves.easeInCubic),
      ),
    );
  }

  @override
  void didUpdateWidget(StartupSplash oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.ready && !oldWidget.ready) _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AbsorbPointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Opacity(
          opacity: _veil.value,
          child: Material(
            color: theme.scaffoldBackgroundColor,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppBrandIcon(),
                  const SizedBox(height: 18),
                  Text(
                    '阅微 Extend',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
