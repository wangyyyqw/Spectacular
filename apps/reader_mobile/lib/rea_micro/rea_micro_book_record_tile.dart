import 'package:flutter/material.dart';

import '../home/reading_book_list.dart';
import 'rea_micro_models.dart';

/// 统计与阅读记录共用的云端书籍卡片。
class ReaMicroBookRecordTile extends StatelessWidget {
  const ReaMicroBookRecordTile({
    super.key,
    required this.record,
    required this.onHide,
    this.onOpen,
    this.linked = false,
  });

  final ReaMicroBookRecord record;
  final VoidCallback? onHide;
  final VoidCallback? onOpen;
  final bool linked;

  @override
  Widget build(BuildContext context) => ReadingBookTile(
    item: cloudReadingBookItem(
      record,
      linked: linked,
      onOpen: onOpen,
      onHide: onHide,
    ),
  );
}

ReadingBookItem cloudReadingBookItem(
  ReaMicroBookRecord record, {
  bool linked = false,
  VoidCallback? onOpen,
  VoidCallback? onHide,
  int recentOrder = 0,
  Key? rowKey,
  int? days,
  bool daysCumulative = false,
}) => ReadingBookItem(
  id: '${record.bookId}',
  title: record.name,
  author: record.author,
  duration: Duration(seconds: record.totalReadTimeSeconds),
  days: days ?? record.readDays,
  daysCumulative: daysCumulative,
  recentOrder: record.lastReadTime > 0 ? record.lastReadTime : recentOrder,
  percent: (record.progress * 100).round().clamp(0, 100),
  linked: linked,
  finished: record.finished,
  statusIcon: linked ? Icons.cloud_done_outlined : Icons.cloud_outlined,
  statusLabel: linked ? '已关联本地书籍' : '仅云端记录',
  onOpen: onOpen,
  onHide: record.bookId > 0 ? onHide : null,
  rowKey: rowKey,
  coverBuilder: (width, height) =>
      _Cover(url: record.cover, width: width, height: height),
);

class _Cover extends StatelessWidget {
  const _Cover({required this.url, required this.width, required this.height});
  final String url;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget fallback() => ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.menu_book_outlined,
        color: theme.colorScheme.onSurfaceVariant,
        size: 20,
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: width,
        height: height,
        child: url.isEmpty
            ? fallback()
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback(),
              ),
      ),
    );
  }
}
