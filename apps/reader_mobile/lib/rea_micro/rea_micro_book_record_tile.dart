import 'package:flutter/material.dart';

import 'rea_micro_models.dart';

/// 统计与阅读记录共用的按书时长、进度与隐藏入口。
class ReaMicroBookRecordTile extends StatelessWidget {
  /// 创建记录行；支持从统计页打开本地已关联书籍。
  const ReaMicroBookRecordTile({
    super.key,
    required this.record,
    required this.onHide,
    this.onOpen,
  });

  final ReaMicroBookRecord record;
  final VoidCallback? onHide;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _Cover(url: record.cover),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          record.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${(record.progress * 100).round()}%',
                        style: theme.textTheme.labelMedium,
                      ),
                    ],
                  ),
                  if (record.author.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      record.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    children: <Widget>[
                      Text(
                        '阅读 ${_formatDuration(record.totalReadTimeSeconds)}',
                        style: theme.textTheme.bodySmall,
                      ),
                      if (record.listeningDurationSeconds > 0 &&
                          record.readingDurationSeconds > 0)
                        Text(
                          '读 ${_formatDuration(record.readingDurationSeconds)}',
                          style: theme.textTheme.bodySmall,
                        ),
                      if (record.listeningDurationSeconds > 0)
                        Text(
                          '听 ${_formatDuration(record.listeningDurationSeconds)}',
                          style: theme.textTheme.bodySmall,
                        ),
                      if (record.finished)
                        Text(
                          '已读完',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '隐藏记录',
              onPressed: record.bookId > 0 ? onHide : null,
              icon: const Icon(Icons.visibility_off_outlined, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: 42,
        height: 56,
        child: url.isEmpty
            ? ColoredBox(
                color: theme.colorScheme.surfaceContainerHighest,
                child: const Icon(Icons.menu_book_outlined, size: 20),
              )
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) => ColoredBox(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.menu_book_outlined, size: 20),
                ),
              ),
      ),
    );
  }
}

String _formatDuration(int seconds) {
  if (seconds <= 0) return '0 分钟';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return minutes <= 0 ? '<1 分钟' : '$minutes 分钟';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '$hours 小时' : '$hours 小时 $rest 分钟';
}
