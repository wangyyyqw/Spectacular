import '../css/computed_style.dart';

/// 整页背景（书籍 `body` / `html` 声明的 `background-image`）。
///
/// 只参与绘制、不参与分页：整章每页共用同一份背景，按
/// `background-size / repeat / position` 语义铺在页面矩形上。
/// 阅读器主题背景色仍在它下面，书籍背景图盖在上面（书里有什么就是什么）。
class PageBackground {
  /// 创建整页背景。
  const PageBackground({
    required this.imageUrl,
    this.size = const CssBackgroundSize.keyword(CssBackgroundSizeMode.auto),
    this.repeat = CssBackgroundRepeat.repeat,
    this.position = const CssBackgroundPosition(
      x: CssLength(0, isPercent: true),
      y: CssLength(0, isPercent: true),
    ),
  });

  /// 已解析成书内资源路径的图片地址。
  final String imageUrl;

  /// 背景尺寸（默认 auto，按原图尺寸）。
  final CssBackgroundSize size;

  /// 平铺方式（默认 repeat）。
  final CssBackgroundRepeat repeat;

  /// 背景位置（默认左上）。
  final CssBackgroundPosition position;

  @override
  bool operator ==(Object other) =>
      other is PageBackground && other.imageUrl == imageUrl;

  @override
  int get hashCode => imageUrl.hashCode;
}
