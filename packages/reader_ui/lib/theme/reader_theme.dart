import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:reader_core/css/reader_overrides.dart';

/// 阅读主题：背景色与文字色成对定义（P2-23）。
///
/// 五套主题的正文对比度均 ≥ 4.5:1（WCAG AA），切换只换颜色、不触发重新分页
/// （字号/行高/页边距不变）。
class ReaderTheme {
  /// 创建主题。
  const ReaderTheme({
    required this.id,
    required this.name,
    required this.background,
    required this.text,
  });

  /// 主题标识（持久化用）。
  final String id;

  /// 显示名。
  final String name;

  /// 页面背景色。
  final Color background;

  /// 正文颜色。
  final Color text;

  /// 次要文字仍保持足够反差，页眉页脚在日夜主题下均可辨认。
  Color get sub => text.withValues(alpha: 0.76);

  /// 分隔线色（设计稿 `--line`：正文色 12%）。
  Color get line => text.withValues(alpha: 0.12);

  /// 填充色（设计稿 `--fill`：正文色 8%，用于按钮/控件底）。
  Color get fill => text.withValues(alpha: 0.08);

  /// 控件强调色使用正文墨色，日夜主题都保持清晰对比。
  Color get accent => text;

  /// 相对亮度（WCAG）。
  double get luminance {
    final bg = _relativeLuminance(background);
    final fg = _relativeLuminance(text);
    final lighter = bg > fg ? bg : fg;
    final darker = bg > fg ? fg : bg;
    return (lighter + 0.05) / (darker + 0.05);
  }

  /// 主题对应的正文/背景覆盖。
  ReaderOverrides toOverrides() =>
      ReaderOverrides(textColor: text, backgroundColor: background);

  /// 五套主题：白 / 米黄 / 粉 / 浅绿 / 纯黑。
  static const white = ReaderTheme(
    id: 'white',
    name: '白',
    background: Color(0xFFFFFFFF),
    text: Color(0xFF333333),
  );
  static const sepia = ReaderTheme(
    id: 'sepia',
    name: '米黄',
    background: Color(0xFFFDF2E3),
    text: Color(0xFF333333),
  );
  static const pink = ReaderTheme(
    id: 'pink',
    name: '粉',
    background: Color(0xFFFCE8EA),
    text: Color(0xFF333333),
  );
  static const green = ReaderTheme(
    id: 'green',
    name: '浅绿',
    background: Color(0xFFDCEBE1),
    text: Color(0xFF333333),
  );
  static const black = ReaderTheme(
    id: 'black',
    name: '纯黑',
    background: Color(0xFF000000),
    text: Color(0xFFBABDB7),
  );

  /// 全部主题。
  static const themes = <ReaderTheme>[white, sepia, pink, green, black];

  /// 按 id 取主题，未知 id 回退白色。
  ///
  /// 旧版本的 gray / dark 标识继续兼容：gray 落到白色，dark 落到纯黑。
  static ReaderTheme byId(String id) {
    if (id == 'gray') {
      return white;
    }
    if (id == 'dark') {
      return black;
    }
    return customById(id) ??
        themes.firstWhere((theme) => theme.id == id, orElse: () => white);
  }

  /// 自定义配色以不透明 RGB 存入标识，沿用现有主题设置持久化。
  static ReaderTheme custom({required Color background, required Color text}) {
    String rgb(Color color) =>
        (color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
    return ReaderTheme(
      id: 'custom:${rgb(background)}:${rgb(text)}',
      name: '自定义',
      background: background.withValues(alpha: 1),
      text: text.withValues(alpha: 1),
    );
  }

  /// 损坏的自定义标识不参与主题恢复。
  static ReaderTheme? customById(String? id) {
    if (id == null ||
        !RegExp(r'^custom:[0-9a-fA-F]{6}:[0-9a-fA-F]{6}$').hasMatch(id)) {
      return null;
    }
    final parts = id.split(':');
    return custom(
      background: Color(0xFF000000 | int.parse(parts[1], radix: 16)),
      text: Color(0xFF000000 | int.parse(parts[2], radix: 16)),
    );
  }
}

double _relativeLuminance(Color color) {
  final value = color.toARGB32();
  double channel(int shift) {
    final component = ((value >> shift) & 0xFF) / 255.0;
    return component <= 0.03928
        ? component / 12.92
        : math.pow((component + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0);
}
