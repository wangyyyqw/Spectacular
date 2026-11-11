import 'package:flutter/material.dart';

import '../theme/reader_theme.dart';
import 'corner_info.dart';
import 'corner_row.dart';

export 'corner_row.dart' show ReaderCornerData;

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

/// 页眉：章节名与页码为默认，四角设置可替换内容。
class ReaderPageHeader extends StatelessWidget {
  const ReaderPageHeader({
    super.key,
    required this.theme,
    required this.title,
    required this.pageLabel,
    this.inkMode = false,
    this.info = ReaderCornerInfo.defaults,
    this.data,
  });

  final ReaderTheme? theme;
  final String title;
  final String pageLabel;
  final bool inkMode;
  final ReaderCornerInfo info;
  final ReaderCornerData? data;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: PageFurniture.headerHeight,
    child: ReaderCornerRow(
      left: info.topLeft,
      right: info.topRight,
      data: data ?? ReaderCornerData(chapterTitle: title, pageLabel: pageLabel),
      theme: theme,
      inkMode: inkMode,
    ),
  );
}

/// 页脚：显示当前页信息、真实系统电量与整分钟刷新的时钟。
class ReaderPageFooter extends StatelessWidget {
  const ReaderPageFooter({
    super.key,
    required this.theme,
    required this.progress,
    this.inkMode = false,
    this.now,
    this.info = ReaderCornerInfo.defaults,
    this.data,
  });

  final ReaderTheme? theme;
  final double progress;
  final bool inkMode;
  final DateTime? now;
  final ReaderCornerInfo info;
  final ReaderCornerData? data;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: PageFurniture.footerHeight,
    child: ReaderCornerRow(
      left: info.bottomLeft,
      right: info.bottomRight,
      data: data ?? ReaderCornerData(progress: progress),
      theme: theme,
      inkMode: inkMode,
      now: now,
    ),
  );
}
