import 'package:flutter/material.dart';

import '../icons/app_icon.dart';
import '../reader_session.dart';
import '../theme/reader_common_widgets.dart';
import '../theme/reader_frosted_surface.dart';
import '../theme/reader_ink.dart';

/// 书签面板（P4-13）：列表 + 点击跳转 + 删除。
class BookmarkPanel extends StatelessWidget {
  /// 创建书签面板。
  const BookmarkPanel({
    super.key,
    required this.bookmarks,
    required this.onSelect,
    required this.onDelete,
    this.emptyHint = '还没有书签',
  });

  /// 书签列表（已按位置排序）。
  final List<ReaderBookmark> bookmarks;

  /// 点击书签（跳转）。
  final ValueChanged<ReaderBookmark> onSelect;

  /// 删除书签。
  final ValueChanged<ReaderBookmark> onDelete;

  /// 空态提示。
  final String emptyHint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: ReaderFrostedSurface.panelColorOf(context),
      child: Theme(
        data: quietInk(theme),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: bookmarks.isEmpty
                  ? ReaderEmptyState(
                      icon: AppGlyph.bookmark,
                      title: emptyHint,
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 8),
                      itemCount: bookmarks.length,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        indent: 48,
                        endIndent: 16,
                        color: theme.colorScheme.outlineVariant,
                      ),
                      itemBuilder: (context, index) {
                        final bookmark = bookmarks[index];
                        final (:title, :snippet) = _splitLabel(bookmark.label);
                        final subtitle = <String>[
                          if (snippet.isNotEmpty) snippet,
                          if (bookmark.needsRelocation) '待确认 · 点击重新定位',
                          if (bookmark.needsRelocation &&
                              bookmark.relocationReason != null)
                            bookmark.relocationReason!,
                        ].join('\n');
                        return InkWell(
                          key: ValueKey<String>('bookmark-row-${bookmark.id}'),
                          onTap: () => onSelect(bookmark),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                            child: Row(
                              children: [
                                AppIcon(
                                  AppGlyph.bookmark,
                                  size: 18,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.titleSmall,
                                      ),
                                      if (subtitle.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          subtitle,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: theme
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: '删除书签',
                                  visualDensity: VisualDensity.compact,
                                  constraints: const BoxConstraints.tightFor(
                                    width: 36,
                                    height: 36,
                                  ),
                                  padding: EdgeInsets.zero,
                                  icon: const AppIcon(
                                    AppGlyph.delete,
                                    size: 18,
                                  ),
                                  onPressed: () => onDelete(bookmark),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// 书签标签形如「章节 · 第 N 页 · 页面文字」：拆出标题与页面文字，
  /// 列表不展示页码与添加时间。
  static ({String title, String snippet}) _splitLabel(String label) {
    final match = RegExp(
      r' · 第 \d+ 页(?: · (.*))?$',
      dotAll: true,
    ).firstMatch(label);
    if (match == null) return (title: label, snippet: '');
    return (
      title: label.substring(0, match.start),
      snippet: match.group(1) ?? '',
    );
  }
}
