import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/reader_theme.dart';

/// 页眉/页脚槽位与组件（P8-10 页家具，样式对齐设计稿
/// `方案/设计/阅读页与阅读菜单设计.md` 的 `.page-header` / `.page-footer`）。
///
/// 设计稿参数：13px 字号、次要色 `--sub`（正文色 45%）、页眉与正文间距 16、
/// 页脚与正文间距 14、页脚左右分栏（时间 + 电池 / 进度百分比）。
abstract final class PageFurniture {
  /// 页眉行高。
  static const double headerHeight = 20;

  /// 页眉与正文间距。
  static const double headerGap = 16;

  /// 页脚行高。
  static const double footerHeight = 20;

  /// 正文与页脚间距。
  static const double footerGap = 14;

  /// 页眉 + 页脚占掉的垂直空间（分页时要扣掉）。
  static const double reservedHeight =
      headerHeight + headerGap + footerGap + footerHeight;

  /// 页眉/页脚字号。
  static const double fontSize = 13;

  /// 格式化时钟（24 小时制，无前导零）。
  static String formatClock(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';
}

/// 页眉：左章节标题（最多 56% 宽，超出省略），右页码。
class ReaderPageHeader extends StatelessWidget {
  /// 创建页眉。
  const ReaderPageHeader({
    super.key,
    required this.theme,
    required this.title,
    required this.pageLabel,
    this.inkMode = false,
  });

  /// 主题（取次要色）。
  final ReaderTheme? theme;

  /// 左侧标题。
  final String title;

  /// 右侧页码文本（如 `3/12`）。
  final String pageLabel;

  /// 墨水屏模式：不降透明度。
  final bool inkMode;

  @override
  Widget build(BuildContext context) {
    final color = inkMode
        ? (theme?.text ?? const Color(0xFF757575))
        : (theme?.sub ?? const Color(0xFF9E9E9E));
    final style = TextStyle(
      fontSize: PageFurniture.fontSize,
      letterSpacing: 0.26,
      color: color,
      decoration: TextDecoration.none,
    );
    return SizedBox(
      height: PageFurniture.headerHeight,
      child: Row(
        children: <Widget>[
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
              textAlign: TextAlign.left,
            ),
          ),
          const SizedBox(width: 12),
          Text(pageLabel, style: style, textAlign: TextAlign.right),
        ],
      ),
    );
  }
}

/// 页脚：左时间 + 电池，右全书进度百分比。
class ReaderPageFooter extends StatefulWidget {
  /// 创建页脚。
  const ReaderPageFooter({
    super.key,
    required this.theme,
    required this.progress,
    this.inkMode = false,
    this.now,
  });

  /// 主题（取次要色）。
  final ReaderTheme? theme;

  /// 全书进度（0..1）。
  final double progress;

  /// 墨水屏模式：不降透明度。
  final bool inkMode;

  /// 当前时间（测试注入；缺省用系统时间并按分钟刷新）。
  final DateTime? now;

  @override
  State<ReaderPageFooter> createState() => _ReaderPageFooterState();
}

class _ReaderPageFooterState extends State<ReaderPageFooter> {
  Timer? _clock;
  late DateTime _now = widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    if (widget.now == null) {
      // 整分钟对齐后每分钟刷新一次，避免频繁重建。
      final secondsToNextMinute = 60 - _now.second;
      _clock = Timer(Duration(seconds: secondsToNextMinute), () {
        if (!mounted) {
          return;
        }
        setState(() => _now = DateTime.now());
        _clock = Timer.periodic(const Duration(minutes: 1), (_) {
          if (mounted) {
            setState(() => _now = DateTime.now());
          }
        });
      });
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.inkMode
        ? (widget.theme?.text ?? const Color(0xFF757575))
        : (widget.theme?.sub ?? const Color(0xFF9E9E9E));
    final style = TextStyle(
      fontSize: PageFurniture.fontSize,
      letterSpacing: 0.26,
      color: color,
      decoration: TextDecoration.none,
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );
    final percent = (widget.progress.clamp(0.0, 1.0) * 100).toStringAsFixed(2);
    return SizedBox(
      height: PageFurniture.footerHeight,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(PageFurniture.formatClock(_now), style: style),
              const SizedBox(width: 8),
              _BatteryGlyph(color: color),
            ],
          ),
          Text('$percent%', style: style),
        ],
      ),
    );
  }
}

/// 设计稿里的电池图标（17×9 圆角矩形 + 右侧电极 + 62% 电量）。
class _BatteryGlyph extends StatelessWidget {
  const _BatteryGlyph({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(17, 9),
      painter: _BatteryPainter(color),
    );
  }
}

class _BatteryPainter extends CustomPainter {
  _BatteryPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = color;
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(0.6, 0.6, size.width - 3.2, size.height - 1.2),
      const Radius.circular(3),
    );
    canvas.drawRRect(body, stroke);
    // 电极
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width - 2.2, size.height / 2 - 2, 2, 4),
        const Radius.circular(0.8),
      ),
      Paint()..color = color,
    );
    // 电量 62%
    final fill = Paint()..color = color.withValues(alpha: 0.85);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(1.8, 1.8, (size.width - 5.6) * 0.62, size.height - 3.6),
        const Radius.circular(1.4),
      ),
      fill,
    );
  }

  @override
  bool shouldRepaint(_BatteryPainter oldDelegate) => oldDelegate.color != color;
}
