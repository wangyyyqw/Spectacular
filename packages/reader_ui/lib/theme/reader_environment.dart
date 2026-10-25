import 'package:flutter/painting.dart';

import 'reader_theme.dart';

/// 阅读环境（P4-23，§42.2）：设备级降级策略，不是主题的替代品。
class ReaderEnvironment {
  /// 创建环境。
  const ReaderEnvironment({this.isEink = false, this.isDark = false});

  /// 是否墨水屏模式。
  final bool isEink;

  /// 是否深色。
  final bool isDark;

  /// 墨水屏专用主题：纯白底 + 纯黑字，对比度 21:1（WCAG AAA）。
  ///
  /// 墨水屏只认黑白两级，灰阶过渡会留残影，所以不用任何中间色。
  static const ReaderTheme inkTheme = ReaderTheme(
    id: 'ink',
    name: '墨水屏',
    background: Color(0xFFFFFFFF),
    text: Color(0xFF000000),
  );

  /// 生效主题：墨水屏强制纯黑白，其余用用户主题。
  ReaderTheme resolveTheme(ReaderTheme theme) => isEink ? inkTheme : theme;

  /// 是否允许背景纹理（墨水屏禁用，§42.2 背景图降级为纯色）。
  bool get allowsBackgroundImage => !isEink;
}
