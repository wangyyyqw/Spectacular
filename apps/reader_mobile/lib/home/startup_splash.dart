import 'dart:async';

import 'package:flutter/material.dart';

const _startupSplashIconAsset = 'assets/branding/app_icon.png';
const _startupSplashIconCacheWidth = 264;

/// 在 Flutter 首帧前解码启动图标，避免原生启动画面切换时露出空白。
Future<void> preloadStartupSplashIcon() {
  final stream = ResizeImage.resizeIfNeeded(
    _startupSplashIconCacheWidth,
    null,
    const AssetImage(_startupSplashIconAsset),
  ).resolve(const ImageConfiguration());
  final ready = Completer<void>();
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (image, _) {
      image.dispose();
      if (!ready.isCompleted) ready.complete();
    },
    onError: (_, _) {
      if (!ready.isCompleted) ready.complete();
    },
  );
  stream.addListener(listener);
  return ready.future.whenComplete(() => stream.removeListener(listener));
}

/// 冷启动开屏：入场期间准备封面，书架就绪后才淡出。
class StartupSplash extends StatefulWidget {
  const StartupSplash({super.key, required this.onFinished, this.ready = true});

  /// 动画结束（完全淡出）后回调一次。
  final VoidCallback onFinished;

  /// 书架前 12 本封面已准备好，可见封面已完成首帧绘制。
  final bool ready;

  /// 封面及时就绪时的开屏时长；未就绪则停在淡出前等待。
  static const duration = Duration(milliseconds: 800);

  @override
  State<StartupSplash> createState() => _StartupSplashState();
}

class _StartupSplashState extends State<StartupSplash>
    with SingleTickerProviderStateMixin {
  static const _fadeStart = .72;
  late final AnimationController _controller;
  late final Animation<double> _entrance;
  late final Animation<double> _veil;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: StartupSplash.duration)
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed && _controller.value == 1) {
              widget.onFinished();
            }
          });
    if (widget.ready) {
      _controller.forward();
    } else {
      _controller.animateTo(_fadeStart);
    }
    _entrance = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, .45, curve: Curves.easeOutCubic),
    );
    _veil = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(_fadeStart, 1, curve: Curves.easeInCubic),
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
              // 原生启动页已显示标识，Flutter 接手时保持可见，避免再次淡入造成白屏。
              child: Transform.translate(
                offset: Offset(0, 12 * (1 - _entrance.value)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.asset(
                        _startupSplashIconAsset,
                        width: 88,
                        height: 88,
                        cacheWidth: _startupSplashIconCacheWidth,
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
    );
  }
}
