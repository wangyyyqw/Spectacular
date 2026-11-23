import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';

import 'rea_micro_aggregate_search.dart';

/// 关联来源使用各平台公开图标，阅微书库沿用应用墨白图标。
class ReaMicroSourceIcon extends StatelessWidget {
  const ReaMicroSourceIcon({super.key, required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    String? asset;
    if (source == '阅微书库') {
      asset = 'assets/branding/app_icon.png';
    } else {
      for (final entry in ReaMicroAggregateSearch.sourceNames.entries) {
        if (entry.value == source) {
          asset = 'assets/rea_micro/platform_icons/${entry.key}.png';
          break;
        }
      }
    }
    if (asset == null) return const AppIcon(AppGlyph.menuBook, size: 20);
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Image.asset(
        asset,
        width: 20,
        height: 20,
        fit: BoxFit.contain,
        excludeFromSemantics: true,
      ),
    );
  }
}
