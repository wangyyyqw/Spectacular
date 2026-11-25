import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/theme/reader_ui_style.dart';

/// 阅微接口根地址，用于补全野社返回的相对图片路径。
const String yeSheApiBaseUrl = 'https://api.reamicro.zhendong.ltd/';

/// 把野社接口返回的头像、封面等地址补全为可直接加载的 URL。
///
/// 空字符串保持为空，交给调用方展示默认资源；`http`、`https`、`file`
/// 与 `data:` 原样返回；以 `//` 开头时补协议；以 `/` 开头的站内路径与
/// 相对路径都按阅微接口域名补全。
String yeSheImageUrl(String value, {String baseUrl = yeSheApiBaseUrl}) {
  final text = value.trim();
  if (text.isEmpty) return '';
  final uri = Uri.tryParse(text);
  if (uri != null) {
    const absoluteSchemes = <String>{'http', 'https', 'file', 'data'};
    if (absoluteSchemes.contains(uri.scheme.toLowerCase())) return text;
  }
  if (text.startsWith('//')) return 'https:$text';
  final base = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/');
  return base.resolve(text).toString();
}

/// 根据野社图片地址创建图片源；无法解析时返回 null。
ImageProvider<Object>? yeSheImageProvider(
  String value, {
  int? cacheWidth,
  String baseUrl = yeSheApiBaseUrl,
}) {
  final url = yeSheImageUrl(value, baseUrl: baseUrl);
  if (url.isEmpty) return null;
  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  try {
    final ImageProvider<Object> provider = switch (uri.scheme.toLowerCase()) {
      'data' => MemoryImage(_decodeDataImage(url)),
      'file' => FileImage(File.fromUri(uri)),
      _ => NetworkImage(url),
    };
    if (cacheWidth == null || cacheWidth <= 0) return provider;
    return ResizeImage(provider, width: cacheWidth);
  } on Object {
    return null;
  }
}

Uint8List _decodeDataImage(String url) {
  final comma = url.indexOf(',');
  if (comma < 0) throw const FormatException('图片数据缺少内容');
  final header = url.substring(0, comma);
  final payload = url.substring(comma + 1);
  if (header.contains(';base64')) return base64Decode(payload);
  return Uint8List.fromList(Uri.decodeComponent(payload).codeUnits);
}

/// 稳定散列，用于把无固定编号的野社条目映射到本地素材。
int yeSheStableSeed(String value) {
  var seed = 17;
  for (final unit in value.codeUnits) {
    seed = (seed * 31 + unit) & 0x7fffffff;
  }
  return seed;
}

/// 野社页面的纸墨配色与图片组件。
class YeSheTokens {
  const YeSheTokens._();

  /// 野社本地图片目录。
  static const String assetRoot = 'assets/ye_she/';

  /// 默认头像。
  static const String defaultAvatar = '${assetRoot}default_avatar.webp';

  /// 默认封面。
  static const String defaultCover = '${assetRoot}default_cover.png';

  /// 聚宝楼通用拍品图。
  static const String auctionFallback = '${assetRoot}shrine_auction.webp';

  /// 花笺通用图。
  static const String noteletFallback = '${assetRoot}mark_paper.webp';

  /// 徽章通用图。
  static const String medalFallback = '${assetRoot}medal_fallback.png';

  /// 名片通用图。
  static const String callingCardFallback = '${assetRoot}calling_card_cat.webp';

  /// 按拍品名称挑选本地器物图，未命中时按标识稳定回退。
  static String auctionAsset(String name, {String seed = ''}) {
    final text = name.trim();
    final matched = switch (text) {
      _ when text.contains('笔') => 5,
      _ when text.contains('砚') || text.contains('石') => 2,
      _ when text.contains('炉') || text.contains('香') => 11,
      _ when text.contains('瓶') || text.contains('瓷') => 4,
      _ when text.contains('碗') || text.contains('盏') => 13,
      _ when text.contains('盘') || text.contains('洗') => 23,
      _ when text.contains('壶') => 10,
      _ when text.contains('筒') || text.contains('竹') => 9,
      _ when text.contains('玉') || text.contains('佩') => 22,
      _ when text.contains('钱') || text.contains('刀') || text.contains('币') =>
        17,
      _ when text.contains('镇') || text.contains('兽') => 18,
      _ when text.contains('印') || text.contains('章') => 21,
      _ => 0,
    };
    final index = matched > 0
        ? matched
        : 1 + yeSheStableSeed(seed.isEmpty ? text : seed) % 23;
    return '${assetRoot}shrine_auction_$index.webp';
  }

  /// 按商路序号挑选本地城池图。
  static String cityAsset(int index) {
    final normalized = index < 0 ? 0 : index % 5;
    return '${assetRoot}shrine_city_${normalized + 1}.webp';
  }

  /// 按门客标识挑选本地人物图。
  static String retainerAsset(String seed) {
    final index = 1 + yeSheStableSeed(seed) % 16;
    return '${assetRoot}shrine_npc_$index.webp';
  }

  /// 藏印图；接口给出发行编号时优先使用对应印章。
  static String sealAsset(int propId, {String seed = ''}) {
    final index = propId >= 20 && propId <= 28
        ? propId
        : 20 + yeSheStableSeed(seed) % 9;
    return '${assetRoot}seal_$index.webp';
  }

  /// 按名片名称挑选本地图。
  static String callingCardAsset(String name) {
    final text = name.trim();
    final file = switch (text) {
      _ when text.contains('点绛') => 'calling_card_dianjiang.webp',
      _ when text.contains('惊鸿') => 'calling_card_jinghong.webp',
      _ when text.contains('月') => 'calling_card_moon.webp',
      _ when text.contains('醉花') => 'calling_card_zuihua.webp',
      _ => 'calling_card_cat.webp',
    };
    return '$assetRoot$file';
  }

  /// 按徽章发行编号挑选阅微原图。
  static String medalAsset(int propId) {
    return switch (propId) {
      33 => '${assetRoot}medal_33.png',
      34 => '${assetRoot}medal_34.png',
      35 => '${assetRoot}medal_35.png',
      36 => '${assetRoot}medal_36.png',
      37 => '${assetRoot}medal_37.png',
      38 => '${assetRoot}medal_38.png',
      39 => '${assetRoot}medal_39.png',
      40 => '${assetRoot}medal_40.png',
      41 => '${assetRoot}medal_41.png',
      42 => '${assetRoot}medal_42.png',
      44 => '${assetRoot}medal_44.png',
      45 => '${assetRoot}medal_45.png',
      _ => medalFallback,
    };
  }

  /// 商会旗帜；没有商会编号时使用默认旗帜。
  static String guildBanner(String code) {
    if (code.trim().isEmpty) return '${assetRoot}shrine_camp_0_banner.webp';
    final index = 1 + yeSheStableSeed(code) % 3;
    return '${assetRoot}shrine_camp_${index}_banner.webp';
  }

  /// 商会徽记。
  static String guildLogo(String code) {
    if (code.trim().isEmpty) return '';
    final index = 1 + yeSheStableSeed(code) % 3;
    return '${assetRoot}shrine_camp_${index}_logo.webp';
  }

  /// 朱砂色，用于印章、强调数字。
  static Color vermilion(BuildContext context) {
    final theme = Theme.of(context);
    return theme.useMaterial3
        ? theme.colorScheme.primary
        : theme.brightness == Brightness.dark
        ? const Color(0xFFE3A08C)
        : const Color(0xFFA34A34);
  }

  /// 黛青色，用于次一级强调。
  static Color jade(BuildContext context) {
    final theme = Theme.of(context);
    return theme.useMaterial3
        ? theme.colorScheme.secondary
        : theme.brightness == Brightness.dark
        ? const Color(0xFF91C0A9)
        : const Color(0xFF3F6E5A);
  }

  /// 泥金色，用于名帖与榜单。
  static Color gold(BuildContext context) {
    final theme = Theme.of(context);
    return theme.useMaterial3
        ? theme.colorScheme.tertiary
        : theme.brightness == Brightness.dark
        ? const Color(0xFFD9B574)
        : const Color(0xFF9A7434);
  }

  /// 宣纸底色。
  static Color paper(BuildContext context) =>
      Theme.of(context).colorScheme.surface;

  /// 淡墨底色。
  static Color wash(BuildContext context) {
    final theme = Theme.of(context);
    return theme.useMaterial3
        ? theme.colorScheme.surfaceContainerLow
        : theme.brightness == Brightness.dark
        ? const Color(0xFF24282A)
        : const Color(0xFFF3F1EB);
  }

  /// 卡片描边。
  static Color line(BuildContext context) =>
      Theme.of(context).colorScheme.outlineVariant;

  /// 页头渐变。
  static LinearGradient headerGradient(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[
        scheme.surfaceContainerLow,
        theme.useMaterial3
            ? scheme.surfaceContainer
            : dark
            ? const Color(0xFF262A2B)
            : const Color(0xFFF2EEE3),
        scheme.surfaceContainerLow,
      ],
      stops: const <double>[0, 0.55, 1],
    );
  }

  /// 卡片阴影使用极轻的墨色，避免纸面显得厚重。
  static List<BoxShadow> cardShadow(BuildContext context) => <BoxShadow>[
    BoxShadow(
      color: Theme.of(context).shadowColor.withValues(alpha: 0.045),
      blurRadius: 14,
      offset: const Offset(0, 4),
    ),
  ];
}

/// 圆形头像：网络加载、加载占位、失败回退与默认头像共用同一尺寸。
class YeSheAvatar extends StatelessWidget {
  const YeSheAvatar({
    super.key,
    required this.url,
    this.size = 40,
    this.ringColor,
    this.semanticsLabel = '头像',
  });

  final String url;
  final double size;
  final Color? ringColor;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final avatar = ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: yeSheImageUrl(url).isEmpty
            ? _fallback(context)
            : _network(context),
      ),
    );
    final ring = ringColor;
    return Semantics(
      image: true,
      label: semanticsLabel,
      child: ring == null
          ? avatar
          : Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.surface,
                border: Border.all(color: ring, width: 1.4),
              ),
              child: avatar,
            ),
    );
  }

  Widget _network(BuildContext context) {
    final cacheWidth = (size * MediaQuery.devicePixelRatioOf(context)).round();
    final provider = yeSheImageProvider(url, cacheWidth: cacheWidth);
    if (provider == null) return _fallback(context, failed: true);
    return Image(
      image: provider,
      width: size,
      height: size,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) return child;
        return _placeholder(context);
      },
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return _placeholder(context);
      },
      errorBuilder: (context, error, stackTrace) =>
          _fallback(context, failed: true),
    );
  }

  Widget _placeholder(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: YeSheTokens.wash(context),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Center(
            child: AppIcon(
              AppGlyph.profile,
              size: size * 0.46,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
          Positioned.fill(
            child: Center(
              child: SizedBox.square(
                dimension: size * 0.62,
                child: CircularProgressIndicator(
                  strokeWidth: 1.4,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallback(BuildContext context, {bool failed = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Image.asset(
          YeSheTokens.defaultAvatar,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => ColoredBox(
            color: YeSheTokens.wash(context),
            child: Center(
              child: AppIcon(
                AppGlyph.profile,
                size: size * 0.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        if (failed && size >= 30)
          Align(
            alignment: Alignment.bottomRight,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: scheme.surface,
                shape: BoxShape.circle,
                border: Border.all(color: YeSheTokens.line(context)),
              ),
              child: AppIcon(
                AppGlyph.brokenImage,
                size: size * 0.22,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

/// 矩形封面：固定尺寸、圆角裁切，网络失败时落到指定本地图。
class YeSheCover extends StatelessWidget {
  const YeSheCover({
    super.key,
    required this.url,
    this.width = 56,
    this.height = 76,
    this.borderRadius = 8,
    this.fallbackAsset = YeSheTokens.defaultCover,
    this.semanticsLabel = '封面',
  });

  final String url;
  final double width;
  final double height;
  final double borderRadius;
  final String fallbackAsset;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    final cacheWidth = width.isFinite
        ? (width * MediaQuery.devicePixelRatioOf(context)).round()
        : null;
    final provider = yeSheImageProvider(url, cacheWidth: cacheWidth);
    return Semantics(
      image: true,
      label: semanticsLabel,
      child: ClipRRect(
        borderRadius: radius,
        child: SizedBox(
          width: width,
          height: height,
          child: provider == null
              ? _fallback(context)
              : Image(
                  image: provider,
                  width: width,
                  height: height,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.medium,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return _placeholder(context);
                  },
                  errorBuilder: (context, error, stackTrace) =>
                      _fallback(context),
                ),
        ),
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    return ColoredBox(
      color: YeSheTokens.wash(context),
      child: Center(
        child: AppIcon(
          AppGlyph.image,
          size: 22,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _fallback(BuildContext context) {
    return Image.asset(
      fallbackAsset,
      width: width,
      height: height,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => _placeholder(context),
    );
  }
}

/// 野社本地水墨横幅，带统一暗角保证叠加文字可读。
class YeSheBanner extends StatelessWidget {
  const YeSheBanner({
    super.key,
    required this.asset,
    this.height = 104,
    this.label,
    this.caption,
    this.trailing,
  });

  final String asset;
  final double height;
  final String? label;
  final String? caption;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Image.asset(
            asset.contains('/') ? asset : '${YeSheTokens.assetRoot}$asset',
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            errorBuilder: (context, error, stackTrace) =>
                ColoredBox(color: YeSheTokens.wash(context)),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Colors.black.withValues(alpha: dark ? 0.22 : 0.02),
                  Colors.black.withValues(alpha: dark ? 0.58 : 0.42),
                ],
              ),
            ),
          ),
          if (label != null || caption != null || trailing != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 12, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        if (label != null)
                          Text(
                            label!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  shadows: const <Shadow>[
                                    Shadow(
                                      color: Color(0x66000000),
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                          ),
                        if (caption != null)
                          Text(
                            caption!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.86),
                                ),
                          ),
                      ],
                    ),
                  ),
                  ?trailing,
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 数值胶囊。
class YeSheStatChip extends StatelessWidget {
  const YeSheStatChip({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.color,
  });

  final String label;
  final String value;
  final AppGlyph? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = color ?? scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: YeSheTokens.line(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            AppIcon(icon!, size: 13, color: tint),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: tint),
          ),
          const SizedBox(width: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// 名次徽记：前三名使用金、银、铜色。
class YeSheRankBadge extends StatelessWidget {
  const YeSheRankBadge({super.key, required this.rank, this.size = 30});

  final int rank;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (rank) {
      1 => (const Color(0xFFD6AE62), const Color(0xFF3D2A0D)),
      2 => (const Color(0xFFC3C7C9), const Color(0xFF33383A)),
      3 => (const Color(0xFFC58A63), const Color(0xFF3B2114)),
      _ => (YeSheTokens.wash(context), scheme.onSurfaceVariant),
    };
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        shape: BoxShape.circle,
        border: Border.all(
          color: rank <= 3
              ? Colors.white.withValues(alpha: 0.55)
              : YeSheTokens.line(context),
        ),
      ),
      child: Text(
        '$rank',
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: foreground, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// 较小的标签，用于品质、状态和分类。
class YeSheTag extends StatelessWidget {
  const YeSheTag(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.1),
        borderRadius: ReaderUiStyle.chipRadiusOf(Theme.of(context)),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: tint),
      ),
    );
  }
}

/// 空态占位。
class YeSheEmpty extends StatelessWidget {
  const YeSheEmpty(this.text, {super.key, this.icon = AppGlyph.info});

  final String text;
  final AppGlyph icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: YeSheTokens.wash(context),
        borderRadius: ReaderUiStyle.controlRadiusOf(Theme.of(context)),
      ),
      child: Row(
        children: <Widget>[
          AppIcon(
            icon,
            size: 18,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

/// 小节标题。
class YeSheSectionLabel extends StatelessWidget {
  const YeSheSectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 3,
          height: 13,
          decoration: BoxDecoration(
            color: YeSheTokens.vermilion(context),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}
