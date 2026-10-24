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

  /// 五套主题：白 / 米黄 / 灰 / 深色 / 纯黑。
  static const white = ReaderTheme(
    id: 'white',
    name: '白',
    background: Color(0xFFFFFFFF),
    text: Color(0xFF1A1A1A),
  );
  static const sepia = ReaderTheme(
    id: 'sepia',
    name: '米黄',
    background: Color(0xFFF5ECD9),
    text: Color(0xFF3A2E1E),
  );
  static const gray = ReaderTheme(
    id: 'gray',
    name: '灰',
    background: Color(0xFFD8D8D8),
    text: Color(0xFF2B2B2B),
  );
  static const dark = ReaderTheme(
    id: 'dark',
    name: '深色',
    background: Color(0xFF2B2B2B),
    text: Color(0xFFE6E6E6),
  );
  static const black = ReaderTheme(
    id: 'black',
    name: '纯黑',
    background: Color(0xFF000000),
    text: Color(0xFFDDDDDD),
  );

  /// 全部主题。
  static const themes = <ReaderTheme>[white, sepia, gray, dark, black];

  /// 按 id 取主题，未知 id 回退白色。
  static ReaderTheme byId(String id) =>
      themes.firstWhere((theme) => theme.id == id, orElse: () => white);
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
