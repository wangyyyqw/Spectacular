import 'package:flutter/material.dart';
import 'package:reader_ui/theme/reader_ui_style.dart';
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
/// `'pin'` 切换置顶状态，`'reamicro-link'` 进入阅微关联与公开阅读，
/// `'booklists'` 选择所属书单。
class BookDetailSheet extends StatelessWidget {
  /// 创建详情面板。
  const BookDetailSheet({
    super.key,
    required this.entry,
    required this.library,
    this.onlineSourceName,
    this.linkedPublisherName,
    this.linkedPublisherNameFuture,
    this.progress,
    this.readingDuration = Duration.zero,
    this.readingSessions = const <ReadingSession>[],
    this.pinned = false,
    this.onOpenOnlineSource,
  });

  /// 书籍条目。
  final BookEntry entry;

  /// 书库（查询待定位记录和章节重划分能力）。
  final LibraryStore library;

  /// 书籍关联的在线书源名称；为空表示尚未关联。
  final String? onlineSourceName;

  /// 阅微关联的出版方名称；null 表示未关联，旧关联的名称可为空。
  final String? linkedPublisherName;

  /// 旧关联的名称补齐任务；不等待网络就能展示和使用菜单。
  final Future<String>? linkedPublisherNameFuture;

  /// 已保存的阅读位置；没有进度时显示已读 0 章。
  final ReaderProgress? progress;

  /// 本书累计有效阅读时长，与图书详情的统计口径一致。
  final Duration readingDuration;

  /// 全部阅读会话；图表只汇总当前书籍最近 7 天的记录。
  final List<ReadingSession> readingSessions;

  /// 本书是否已置顶。
  final bool pinned;
  final VoidCallback? onOpenOnlineSource;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasOnlineSource = onlineSourceName?.isNotEmpty ?? false;
    final metadataStyle = theme.textTheme.bodyMedium?.copyWith(
      height: 1.25,
      color: theme.colorScheme.onSurfaceVariant,
    );
    final recentDurations = recentBookReadingDurations(
      readingSessions,
      bookId: entry.id,
      now: DateTime.now(),
    );
    final hasRecentReading = recentDurations.any(
      (duration) => duration > Duration.zero,
    );
    final spineCount = entry.spineCount ?? 0;
    final chapterProgress = spineCount <= 0
        ? null
        : (((progress?.spineIndex ?? -1) + 1).clamp(0, spineCount)) /
              spineCount;
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
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Text(
                          entry.title.replaceAll(RegExp(r'\s+'), ' ').trim(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontSize: 15,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (!hasOnlineSource) const Spacer(),
                        Text(
                          entry.author.isEmpty ? '未知作者' : entry.author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: metadataStyle,
                        ),
                        const SizedBox(height: 4),
                        if (!hasOnlineSource) const Spacer(),
                        FutureBuilder<String>(
                          future: linkedPublisherNameFuture,
                          initialData: linkedPublisherName,
                          builder: (context, snapshot) {
                            final linked = linkedPublisherName != null;
                            final name = snapshot.data?.trim() ?? '';
                            return Material(
                              type: MaterialType.transparency,
                              child: InkWell(
                                key: const ValueKey(
                                  'book-detail-public-reading',
                                ),
                                onTap: () =>
                                    Navigator.of(context).pop('reamicro-link'),
                                child: Text(
                                  linked
                                      ? (name.isEmpty ? '已关联' : name)
                                      : '未关联',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: metadataStyle,
                                ),
                              ),
                            );
                          },
                        ),
                        if (hasOnlineSource) ...[
                          const SizedBox(height: 4),
                          Material(
                            type: MaterialType.transparency,
                            child: InkWell(
                              key: const ValueKey('book-detail-online-source'),
                              onTap: onOpenOnlineSource,
                              child: Text(
                                '在线来源：$onlineSourceName',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: metadataStyle?.copyWith(
                                  color: onOpenOnlineSource == null
                                      ? null
                                      : theme.colorScheme.primary,
                                ),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 4),
                        if (!hasOnlineSource) const Spacer(),
                        Text(
                          '已读 ${formatReadingDuration(readingDuration)}',
                          key: const ValueKey('book-detail-reading-summary'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: metadataStyle,
                        ),
                        if (chapterProgress != null) ...[
                          if (hasOnlineSource)
                            const Spacer()
                          else
                            const SizedBox(height: 4),
                          Semantics(
                            label: formatReadingChapters(
                              progress?.spineIndex,
                              entry.spineCount,
                            ),
                            child: ExcludeSemantics(
                              child: SizedBox(
                                width: double.infinity,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(2),
                                  child: LinearProgressIndicator(
                                    key: const ValueKey(
                                      'book-detail-chapter-progress',
                                    ),
                                    value: chapterProgress,
                                    minHeight: 3,
                                    color: theme.colorScheme.primary,
                                    backgroundColor: theme
                                        .colorScheme
                                        .surfaceContainerHighest,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (hasRecentReading) ...[
              const SizedBox(height: 16),
              BookReadingChart(durations: recentDurations),
            ],
            if (hasRecentReading)
              const SizedBox(height: 20)
            else
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
            _DetailMenu(entry: entry, library: library, pinned: pinned),
          ],
        ),
      ),
    );
  }
}

class _DetailMenu extends StatefulWidget {
  const _DetailMenu({
    required this.entry,
    required this.library,
    required this.pinned,
  });

  final BookEntry entry;
  final LibraryStore library;
  final bool pinned;

  @override
  State<_DetailMenu> createState() => _DetailMenuState();
}

class _DetailMenuState extends State<_DetailMenu> {
  late final Future<bool> _rechapter = TxtBookService(widget.library)
      .canRechapter(widget.entry);

  Widget _card(List<Widget> children, {Key? key}) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: key,
      color: scheme.surface,
      shape: ReaderUiStyle.cardShapeOf(Theme.of(context)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: _rechapter,
    builder: (context, snapshot) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card(key: const ValueKey('book-detail-actions'), [
          _DetailActionPair(
            left: _DetailAction(
              key: const ValueKey<String>('book-detail-booklists'),
              icon: AppGlyph.bookmarkAdd,
              label: '书单',
              onTap: () => Navigator.of(context).pop('booklists'),
            ),
            right: _DetailAction(
              key: const ValueKey<String>('book-detail-open-page'),
              icon: AppGlyph.menuBook,
              label: '详情',
              onTap: () => Navigator.of(context).pop('detail'),
            ),
          ),
          const _MenuDivider(),
          _DetailActionPair(
            left: _DetailAction(
              key: const ValueKey<String>('book-detail-create-group'),
              icon: AppGlyph.folderMove,
              label: '分组',
              onTap: () => Navigator.of(context).pop('create-group'),
            ),
            right: _DetailAction(
              key: const ValueKey<String>('book-detail-pin'),
              icon: AppGlyph.pushPin,
              label: widget.pinned ? '取消置顶' : '置顶',
              onTap: () => Navigator.of(context).pop('pin'),
            ),
          ),
          const _MenuDivider(),
          _DetailActionPair(
            left: _DetailAction(
              key: const ValueKey<String>('book-detail-update'),
              icon: AppGlyph.refresh,
              label: '更新',
              onTap: () => Navigator.of(context).pop('update'),
            ),
            right: _DetailAction(
              key: const ValueKey<String>('book-detail-export'),
              icon: AppGlyph.upload,
              label: '导出',
              onTap: () => Navigator.of(context).pop('export'),
            ),
          ),
          if (snapshot.data == true) ...[
            const _MenuDivider(),
            _DetailAction(
              key: const ValueKey<String>('book-detail-chapters'),
              icon: AppGlyph.listBulleted,
              label: '章节正则',
              onTap: () => Navigator.of(context).pop('chapters'),
            ),
          ],
        ]),
        const SizedBox(height: 10),
        _card(key: const ValueKey('book-detail-delete-actions'), [
          _DetailAction(
            key: const ValueKey<String>('book-detail-delete'),
            icon: AppGlyph.delete,
            label: '删除',
            destructive: true,
            onTap: () => Navigator.of(context).pop('delete'),
          ),
        ]),
      ],
    ),
  );
}

class _MenuDivider extends StatelessWidget {
  const _MenuDivider();

  @override
  Widget build(BuildContext context) => Divider(
    height: 1,
    thickness: 1,
    indent: 48,
    color: Theme.of(context).colorScheme.outlineVariant,
  );
}

class _DetailActionPair extends StatelessWidget {
  const _DetailActionPair({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
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

class _DetailAction extends StatelessWidget {
  const _DetailAction({
    super.key,
    required this.icon,
    required this.label,
    this.destructive = false,
    required this.onTap,
  });

  final AppGlyph icon;
  final String label;
  final bool destructive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = destructive ? scheme.error : scheme.onSurface;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
      minLeadingWidth: 22,
      horizontalTitleGap: 12,
      leading: AppIcon(icon, size: 22, color: color),
      title: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(fontSize: 15, color: color),
      ),
      trailing: AppIcon(AppGlyph.chevronRight, size: 20, color: scheme.outline),
      onTap: onTap,
    );
  }
}
