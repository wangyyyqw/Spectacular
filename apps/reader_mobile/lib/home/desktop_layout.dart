import 'package:flutter/material.dart';

/// 桌面交互由运行平台决定，窗口宽度只影响内容排布。
bool usesDesktopLayout(BuildContext context) =>
    switch (Theme.of(context).platform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => true,
      _ => false,
    };
