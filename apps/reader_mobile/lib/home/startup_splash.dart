import 'package:flutter/material.dart';

/// 冷启动开屏：盖住书架与封面预解码，约 0.8 秒后淡出。
class StartupSplash extends StatefulWidget {
  const StartupSplash({super.key, required this.onFinished});

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
  late final Animation<double> _entrance;
  late final Animation<double> _veil;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: StartupSplash.duration)
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) widget.onFinished();
          })
          ..forward();
    _entrance = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, .45, curve: Curves.easeOutCubic),
    );
    _veil = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(.72, 1, curve: Curves.easeInCubic),
      ),
    );
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
              child: Opacity(
                opacity: _entrance.value,
                child: Transform.translate(
                  offset: Offset(0, 12 * (1 - _entrance.value)),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.asset(
                          'assets/branding/app_icon.png',
                          width: 88,
                          height: 88,
                          cacheWidth: 264,
                          excludeFromSemantics: true,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        '墨屿',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          letterSpacing: 4,
                        ),
                      ),
                    ],
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
