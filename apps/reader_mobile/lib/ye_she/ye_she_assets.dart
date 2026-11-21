import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';

import 'ye_she_visuals.dart';

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
