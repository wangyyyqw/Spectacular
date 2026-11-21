import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';

import 'ye_she_visuals.dart';

/// 阅微物品原图编号；与道具的 propId 一一对应。
const Set<int> yeShePropIconIds = <int>{
  1,
  2,
  3,
  4,
  5,
  6,
  7,
  8,
  9,
  10,
  11,
  12,
  13,
  14,
  15,
  16,
  17,
  18,
  19,
  29,
};

/// 返回物品原图资源；未知道具使用调用方的图标兜底。
String? yeShePropIconAsset(int propId) => yeShePropIconIds.contains(propId)
    ? 'assets/ye_she/items/shrine_prop_$propId.png'
    : null;

/// 野社物品图标：优先使用阅微原图，缺图时回退到本地图标。
class YeSheItemIcon extends StatelessWidget {
  /// 创建物品图标。
  const YeSheItemIcon({
    super.key,
    required this.propId,
    this.size = 24,
    this.fallbackGlyph = AppGlyph.folder,
    this.fallbackColor,
  });

  /// 阅微道具编号。
  final int propId;

  /// 显示边长。
  final double size;

  /// 缺图时的图标。
  final AppGlyph fallbackGlyph;

  /// 缺图时的图标颜色。
  final Color? fallbackColor;

  @override
  Widget build(BuildContext context) {
    final asset = yeShePropIconAsset(propId);
    if (asset == null) {
      return SizedBox(
        width: size,
        height: size,
        child: Center(
          child: AppIcon(
            fallbackGlyph,
            size: size * 0.78,
            color:
                fallbackColor ?? Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return Image.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) => SizedBox(
        width: size,
        height: size,
        child: Center(
          child: AppIcon(
            fallbackGlyph,
            size: size * 0.78,
            color:
                fallbackColor ?? Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// 野社本地图片：固定尺寸、圆角裁切，缺图时显示纸色占位。
class YeSheAssetImage extends StatelessWidget {
  /// 创建本地图片。
  const YeSheAssetImage({
    super.key,
    required this.asset,
    this.width = 56,
    this.height = 56,
    this.borderRadius = 8,
    this.fit = BoxFit.cover,
    this.semanticsLabel,
    this.fallbackGlyph = AppGlyph.image,
  });

  /// 资源路径。
  final String asset;

  /// 宽度。
  final double width;

  /// 高度。
  final double height;

  /// 圆角。
  final double borderRadius;

  /// 裁切方式。
  final BoxFit fit;

  /// 无障碍描述。
  final String? semanticsLabel;

  /// 缺图时的图标。
  final AppGlyph fallbackGlyph;

  @override
  Widget build(BuildContext context) {
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: width,
        height: height,
        child: asset.trim().isEmpty
            ? _placeholder(context)
            : Image.asset(
                asset.trim(),
                width: width,
                height: height,
                fit: fit,
                filterQuality: FilterQuality.medium,
                errorBuilder: (context, error, stackTrace) =>
                    _placeholder(context),
              ),
      ),
    );
    final label = semanticsLabel;
    if (label == null || label.trim().isEmpty) return image;
    return Semantics(image: true, label: label, child: image);
  }

  Widget _placeholder(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: YeSheTokens.wash(context),
      child: Center(
        child: AppIcon(
          fallbackGlyph,
          size: width < 36 ? 14 : 20,
          color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}
