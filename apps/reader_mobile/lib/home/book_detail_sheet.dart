import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/reader_session.dart';

import '../library/library_store.dart';
import '../storage/reading_session_store.dart';
import '../txt/txt_book_service.dart';
import 'book_reading_chart.dart';
import 'book_cover_image.dart';
import 'reading_insights.dart';

/// 长按书架卡片展示书籍元信息和快捷操作。
///
/// 长按书架卡片打开；返回 `'detail'` 打开完整详情页，`'delete'` 表示删除，
/// `'create-group'` 将本书移入已有或新建分组，`'export'` 导出本书 EPUB，
/// `'pin'` 切换置顶状态。
class BookDetailSheet extends StatelessWidget {
  /// 创建详情面板。
  const BookDetailSheet({
    super.key,
    required this.entry,
    required this.library,
    this.progress,
    this.readingDuration = Duration.zero,
    this.readingSessions = const <ReadingSession>[],
    this.pinned = false,
  });

  /// 书籍条目。
  final BookEntry entry;

  /// 书库（查询待定位记录和章节重划分能力）。
  final LibraryStore library;

  /// 已保存的阅读位置；没有进度时显示已读 0 章。
  final ReaderProgress? progress;

  /// 本书累计有效阅读时长，与图书详情的统计口径一致。
  final Duration readingDuration;

  /// 全部阅读会话；图表只汇总当前书籍最近 7 天的记录。
  final List<ReadingSession> readingSessions;

  /// 本书是否已置顶。
  final bool pinned;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recentDurations = recentBookReadingDurations(
      readingSessions,
      bookId: entry.id,
      now: DateTime.now(),
    );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  BookCoverImage(
                    key: const ValueKey('book-detail-cover'),
                    book: entry,
                    width: 80,
                    height: 108,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      key: const ValueKey('book-detail-metadata'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          entry.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            height: 1.25,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          entry.author.isEmpty ? '未知作者' : entry.author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            height: 1.3,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '已读 ${formatReadingDuration(readingDuration)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            height: 1.3,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          formatReadingChapters(
                            progress?.spineIndex,
                            entry.spineCount,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            height: 1.3,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (recentDurations.any(
              (duration) => duration > Duration.zero,
            )) ...[
              const SizedBox(height: 16),
              BookReadingChart(durations: recentDurations),
            ],
            const Divider(height: 24),
            FutureBuilder<List<String>>(
              future: library.pendingLocationReasons(entry.id),
              builder: (context, snapshot) {
                final reasons = snapshot.data ?? const <String>[];
                if (reasons.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '待确认 ${reasons.length} 条',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      for (final reason in reasons)
                        Text(reason, style: theme.textTheme.bodySmall),
                      const SizedBox(height: 6),
                      Text('在阅读数据列表选择重新定位', style: theme.textTheme.bodySmall),
                    ],
                  ),
                );
              },
            ),
            SizedBox(
              width: double.infinity,
              child: Material(
                key: const ValueKey('book-detail-actions'),
                color: theme.colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    _DetailActionPair(
                      left: _DetailAction(
                        key: const ValueKey<String>('book-detail-open-page'),
                        icon: AppGlyph.menuBook,
                        label: '详情',
                        onTap: () => Navigator.of(context).pop('detail'),
                      ),
                      right: _DetailAction(
                        key: const ValueKey<String>('book-detail-pin'),
                        icon: AppGlyph.pushPin,
                        label: pinned ? '取消置顶' : '置顶',
                        onTap: () => Navigator.of(context).pop('pin'),
                      ),
                    ),
                    FutureBuilder<bool>(
                      future: TxtBookService(library).canRechapter(entry),
                      builder: (context, snapshot) => snapshot.data == true
                          ? Column(
                              children: [
                                _actionDivider(theme),
                                _DetailAction(
                                  key: const ValueKey('book-detail-chapters'),
                                  icon: AppGlyph.listBulleted,
                                  label: '章节正则',
                                  onTap: () =>
                                      Navigator.of(context).pop('chapters'),
                                ),
                              ],
                            )
                          : const SizedBox.shrink(),
                    ),
                    _actionDivider(theme),
                    _DetailActionPair(
                      left: _DetailAction(
                        key: const ValueKey<String>('book-detail-update'),
                        icon: AppGlyph.refresh,
                        label: '更新',
                        onTap: () => Navigator.of(context).pop('update'),
                      ),
                      right: _DetailAction(
                        key: const ValueKey<String>('book-detail-create-group'),
                        icon: AppGlyph.folderMove,
                        label: '分组',
                        onTap: () => Navigator.of(context).pop('create-group'),
                      ),
                    ),
                    _actionDivider(theme),
                    _DetailActionPair(
                      left: _DetailAction(
                        key: const ValueKey<String>('book-detail-export'),
                        icon: AppGlyph.upload,
                        label: '导出',
                        onTap: () => Navigator.of(context).pop('export'),
                      ),
                      right: _DetailAction(
                        key: const ValueKey<String>('book-detail-delete'),
                        icon: AppGlyph.delete,
                        label: '删除',
                        onTap: () => Navigator.of(context).pop('delete'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Divider _actionDivider(ThemeData theme) =>
    Divider(height: 1, thickness: 1, color: theme.colorScheme.outlineVariant);

class _DetailActionPair extends StatelessWidget {
  const _DetailActionPair({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: left),
          VerticalDivider(
            width: 1,
            thickness: 1,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          Expanded(child: right),
        ],
      ),
    );
  }
}

class _DetailAction extends StatelessWidget {
  const _DetailAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final AppGlyph icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurface;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      minLeadingWidth: 22,
      horizontalTitleGap: 10,
      leading: AppIcon(icon, size: 22, color: color),
      title: Text(
        label,
        style: theme.textTheme.bodyMedium?.copyWith(color: color),
      ),
      onTap: onTap,
    );
  }
}
