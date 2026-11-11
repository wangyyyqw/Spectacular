import 'package:flutter/material.dart';

import '../library/library_store.dart';
import 'book_cover_image.dart';

/// 书籍详情（P4-06）：元信息 + 导入报告（修复项与告警）。
///
/// 长按书架卡片打开；返回 `'detail'` 打开完整详情页，`'delete'` 表示删除，
/// `'create-group'` 新建分组，`'multi-select'` 进入多选。
class BookDetailSheet extends StatelessWidget {
  /// 创建详情面板。
  const BookDetailSheet({
    super.key,
    required this.entry,
    required this.library,
  });

  /// 书籍条目。
  final BookEntry entry;

  /// 书库（读导入报告）。
  final LibraryStore library;

  static const _levelLabels = <String>['完整', '已修复', '部分降级', '结构异常', '无法阅读'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        entry.author.isEmpty ? '未知作者' : entry.author,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '内容${_levelLabels[entry.readabilityLevel.clamp(0, 4)]}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                _MetaItem(label: '章节', value: '${entry.spineCount ?? 0} 章'),
                _MetaItem(label: '导入', value: _formatDate(entry.addedAt)),
                _MetaItem(
                  label: '最近阅读',
                  value: entry.lastReadAt == null
                      ? '未读'
                      : _formatDate(entry.lastReadAt!),
                ),
              ],
            ),
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
            Text('导入报告', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            FutureBuilder<List<ImportReportEntry>>(
              future: library.importReports(entry.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }
                final items = snapshot.data ?? const <ImportReportEntry>[];
                if (items.isEmpty) {
                  return Text(
                    '无修复或告警',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [for (final item in items) _ReportRow(item: item)],
                );
              },
            ),
            const Divider(height: 32),
            _DetailAction(
              key: const ValueKey<String>('book-detail-open-page'),
              icon: Icons.menu_book_outlined,
              label: '图书详情',
              onTap: () => Navigator.of(context).pop('detail'),
            ),
            _DetailAction(
              key: const ValueKey<String>('book-detail-update'),
              icon: Icons.update,
              label: '更新',
              onTap: () => Navigator.of(context).pop('update'),
            ),
            _DetailAction(
              key: const ValueKey<String>('book-detail-create-group'),
              icon: Icons.create_new_folder_outlined,
              label: '新建分组',
              onTap: () => Navigator.of(context).pop('create-group'),
            ),
            _DetailAction(
              key: const ValueKey<String>('book-detail-multi-select'),
              icon: Icons.checklist,
              label: '多选',
              onTap: () => Navigator.of(context).pop('multi-select'),
            ),
            _DetailAction(
              icon: Icons.delete_outline,
              label: '删除本书',
              destructive: true,
              onTap: () => Navigator.of(context).pop('delete'),
            ),
            const Divider(height: 16),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime time) {
    final local = time.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}';
  }
}

class _DetailAction extends StatelessWidget {
  const _DetailAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = destructive
        ? theme.colorScheme.error
        : theme.colorScheme.onSurface;
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        minLeadingWidth: 24,
        leading: Icon(icon, size: 22, color: color),
        title: Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(color: color),
        ),
        trailing: destructive
            ? null
            : Icon(
                Icons.chevron_right,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
        onTap: onTap,
      ),
    );
  }
}

class _MetaItem extends StatelessWidget {
  const _MetaItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(value, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _ReportRow extends StatelessWidget {
  const _ReportRow({required this.item});

  final ImportReportEntry item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 2 错误、1 警告、0 提示：颜色区分但不弹窗（§82.4 纪律 3）。
    final (label, color) = switch (item.severity) {
      >= 2 => ('错误', theme.colorScheme.error),
      1 => ('警告', theme.colorScheme.tertiary),
      _ => ('提示', theme.colorScheme.onSurfaceVariant),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(color: color),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.code,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(item.message, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
