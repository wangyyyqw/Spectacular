import 'package:flutter/material.dart';

import '../reader_session.dart';

/// 书签面板（P4-13）：列表 + 点击跳转 + 删除。
class BookmarkPanel extends StatelessWidget {
  /// 创建书签面板。
  const BookmarkPanel({
    super.key,
    required this.bookmarks,
    required this.onSelect,
    required this.onDelete,
    this.onBack,
    this.emptyHint = '还没有书签',
  });

  /// 书签列表（已按位置排序）。
  final List<ReaderBookmark> bookmarks;

  /// 点击书签（跳转）。
  final ValueChanged<ReaderBookmark> onSelect;

  /// 删除书签。
  final ValueChanged<ReaderBookmark> onDelete;

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
                    icon: const Icon(Icons.arrow_back, size: 20),
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
                        leading: Icon(
                          Icons.bookmark_outline,
                          size: 18,
                          color: theme.colorScheme.primary,
                        ),
                        title: Text(
                          bookmark.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          _formatTime(bookmark.createdAt),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                        trailing: IconButton(
                          tooltip: '删除书签',
                          icon: const Icon(Icons.delete_outline, size: 18),
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
