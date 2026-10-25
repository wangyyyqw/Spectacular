import 'package:flutter/material.dart';
import 'package:reader_core/api.dart';

import '../reader_session.dart';

/// 目录面板（P4-11）：层级缩进、当前章高亮、点击跳转。
///
/// 只负责展示与选择；跳转由调用方执行（`ReaderSession.jumpToChapter`）。
class TocPanel extends StatelessWidget {
  /// 创建目录面板。
  const TocPanel({
    super.key,
    required this.entries,
    required this.currentSpineIndex,
    required this.onSelect,
    this.scrollController,
    this.onBack,
    this.emptyHint = '本书没有目录',
  });

  /// 目录树（嵌套结构）。
  final List<TocEntry> entries;

  /// 当前章 spine 序号（高亮用）。
  final int currentSpineIndex;

  /// 选择回调（点击目录项）。
  final ValueChanged<TocEntry> onSelect;

  /// 滚动控制器（调用方缓存滚动位置，重开时保持）。
  final ScrollController? scrollController;

  /// 返回回调（嵌在菜单 sheet 内时显示返回按钮）。
  final VoidCallback? onBack;

  /// 无目录时的提示。
  final String emptyHint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = flattenToc(entries);
    return Material(
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                if (onBack != null)
                  IconButton(
                    icon: const Icon(Icons.arrow_back, size: 20),
                    onPressed: onBack,
                    tooltip: '返回',
                  ),
                Text('目录', style: theme.textTheme.titleMedium),
                const Spacer(),
                Text(
                  '共 ${rows.length} 章',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: rows.isEmpty
                ? Center(
                    child: Text(
                      emptyHint,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      final current =
                          row.entry.spineIndex == currentSpineIndex;
                      return ListTile(
                        key: ValueKey<String>(
                          'toc-row-${row.entry.spineIndex}-${row.entry.title}',
                        ),
                        dense: true,
                        selected: current,
                        selectedColor: theme.colorScheme.primary,
                        contentPadding: EdgeInsets.only(
                          left: 20 + (row.depth - 1) * 16,
                          right: 20,
                        ),
                        title: Text(
                          row.entry.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: current
                              ? const TextStyle(fontWeight: FontWeight.w600)
                              : null,
                        ),
                        trailing: current
                            ? Icon(
                                Icons.play_arrow,
                                size: 16,
                                color: theme.colorScheme.primary,
                              )
                            : null,
                        onTap: () => onSelect(row.entry),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
