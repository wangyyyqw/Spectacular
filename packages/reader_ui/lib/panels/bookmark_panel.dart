import 'package:flutter/material.dart';

import '../icons/app_icon.dart';
import '../reader_session.dart';

/// 书签面板（P4-13）：列表 + 点击跳转 + 删除。
class BookmarkPanel extends StatelessWidget {
  /// 创建书签面板。
  const BookmarkPanel({
    super.key,
    required this.bookmarks,
    required this.onSelect,
    required this.onDelete,
    this.onAdd,
    this.onBack,
    this.emptyHint = '还没有书签',
  });

  /// 书签列表（已按位置排序）。
  final List<ReaderBookmark> bookmarks;

  /// 点击书签（跳转）。
  final ValueChanged<ReaderBookmark> onSelect;

  /// 删除书签。
  final ValueChanged<ReaderBookmark> onDelete;

  /// 新增书签；null 时不显示入口。
  final VoidCallback? onAdd;

  /// 返回回调（嵌在菜单 sheet 内时显示返回按钮）。
  final VoidCallback? onBack;

  /// 空态提示。
  final String emptyHint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                    icon: const AppIcon(AppGlyph.arrowBack, size: 20),
                    onPressed: onBack,
                    tooltip: '返回',
                  ),
                Text('书签', style: theme.textTheme.titleMedium),
                const Spacer(),
                Text(
                  '共 ${bookmarks.length} 条',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                if (onAdd != null)
                  IconButton(
                    key: const ValueKey<String>('drawer-add-bookmark'),
                    onPressed: onAdd,
                    tooltip: '加书签',
                    icon: const AppIcon(AppGlyph.bookmarkAdd, size: 18),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: bookmarks.isEmpty
                ? Center(
                    child: Text(
                      emptyHint,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: bookmarks.length,
                    itemBuilder: (context, index) {
                      final bookmark = bookmarks[index];
                      return ListTile(
                        key: ValueKey<String>('bookmark-row-${bookmark.id}'),
                        dense: true,
                        leading: AppIcon(
                          AppGlyph.bookmark,
                          size: 18,
                          color: theme.colorScheme.primary,
                        ),
                        title: Text(
                          bookmark.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          [
                            _formatTime(bookmark.createdAt),
                            if (bookmark.needsRelocation) '待确认 · 点击重新定位',
                            if (bookmark.needsRelocation &&
                                bookmark.relocationReason != null)
                              bookmark.relocationReason!,
                          ].join('\n'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                        trailing: IconButton(
                          tooltip: '删除书签',
                          icon: const AppIcon(AppGlyph.delete, size: 18),
                          onPressed: () => onDelete(bookmark),
                        ),
                        onTap: () => onSelect(bookmark),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  static String _formatTime(DateTime time) {
    final local = time.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}
