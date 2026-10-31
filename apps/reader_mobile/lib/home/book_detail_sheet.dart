import 'dart:io';

import 'package:flutter/material.dart';

import '../library/library_store.dart';

/// 书籍详情（P4-06）：元信息 + 导入报告（修复项与告警）。
///
/// 长按书架卡片打开；返回 `'delete'` 表示用户点了删除。
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

  static const _levelLabels = <String>[
    '完整',
    '已修复',
    '部分降级',
    '结构异常',
    '无法阅读',
  ];

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
                _Cover(entry: entry),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        entry.author.isEmpty ? '未知作者' : entry.author,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '可读性：L${entry.readabilityLevel} '
                        '${_levelLabels[entry.readabilityLevel.clamp(0, 4)]}',
                        style: theme.textTheme.bodySmall,
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
                      color: theme.colorScheme.outline,
                    ),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final item in items) _ReportRow(item: item),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pop('delete'),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('删除本书'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('关闭'),
                  ),
                ),
              ],
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

class _Cover extends StatelessWidget {
  const _Cover({required this.entry});

  final BookEntry entry;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      decoration: BoxDecoration(
        color: HSLColor.fromAHSL(
          1,
          entry.coverHue.toDouble(),
          0.42,
          0.38,
        ).toColor(),
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Text(
        entry.title.isEmpty ? '书' : entry.title.characters.first,
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(color: Colors.white),
      ),
    );
    final path = entry.coverPath;
    return SizedBox(
      key: const ValueKey<String>('book-detail-cover'),
      width: 120,
      height: 90,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: path == null
            ? placeholder
            : Image.file(
                File(path),
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.cover,
                cacheWidth: 360,
                errorBuilder: (_, _, _) => placeholder,
              ),
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
            color: theme.colorScheme.outline,
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
      _ => ('提示', theme.colorScheme.outline),
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
                    color: theme.colorScheme.outline,
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
