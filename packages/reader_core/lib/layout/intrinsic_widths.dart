import 'dart:math' as math;

import '../css/intrinsic_width.dart';

/// 测量得到的内容盒宽，不含外边距、边框和内边距。
class IntrinsicWidths {
  const IntrinsicWidths({required this.minContent, required this.maxContent});

  static const zero = IntrinsicWidths(minContent: 0, maxContent: 0);

  final double minContent;
  final double maxContent;

  double resolve(CssIntrinsicWidth mode, double availableContentWidth) =>
      switch (mode) {
        CssIntrinsicWidth.minContent => minContent,
        CssIntrinsicWidth.maxContent => maxContent,
        CssIntrinsicWidth.fitContent => math.min(
          maxContent,
          math.max(minContent, availableContentWidth),
        ),
      };

  /// 块级后代分别占行；包含块取后代的最大占宽，不能把段落连接相加。
  IntrinsicWidths includeBlock(IntrinsicWidths child) => IntrinsicWidths(
    minContent: math.max(minContent, child.minContent),
    maxContent: math.max(maxContent, child.maxContent),
  );
}
