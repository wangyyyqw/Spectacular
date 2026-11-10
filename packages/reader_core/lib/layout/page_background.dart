import 'dart:ui' show Color;

import '../css/computed_style.dart';

/// 整页背景（书籍 `body` / `html` 声明的背景色或背景图）。
///
/// 只参与绘制、不参与分页：整章每页共用同一份背景，按
/// `background-size / repeat / position` 语义铺在页面矩形上。
/// 阅读器主题背景色仍在它下面，书籍背景图盖在上面（书里有什么就是什么）。
class PageBackground {
  /// 创建整页背景。
  const PageBackground({
    this.imageUrl,
    this.backgroundColor,
    this.size = const CssBackgroundSize.keyword(CssBackgroundSizeMode.auto),
    this.repeat = CssBackgroundRepeat.repeat,
    this.position = const CssBackgroundPosition(
      x: CssLength(0, isPercent: true),
      y: CssLength(0, isPercent: true),
    ),
  }) : assert(imageUrl != null || backgroundColor != null);

  /// 已解析成书内资源路径的图片地址。
  final String? imageUrl;

  /// 书籍声明的整页背景色；null 表示透明。
  final Color? backgroundColor;

  /// 背景尺寸（默认 auto，按原图尺寸）。
  final CssBackgroundSize size;

  /// 平铺方式（默认 repeat）。
  final CssBackgroundRepeat repeat;

  /// 背景位置（默认左上）。
  final CssBackgroundPosition position;

  @override
  bool operator ==(Object other) =>
      other is PageBackground &&
      other.imageUrl == imageUrl &&
      other.backgroundColor == backgroundColor &&
      other.size == size &&
      other.repeat == repeat &&
      other.position == position;

  @override
  int get hashCode =>
      Object.hash(imageUrl, backgroundColor, size, repeat, position);
}
