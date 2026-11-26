import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reader_ui/theme/reader_ui_style.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';

import 'rea_micro_controller.dart';
import 'rea_micro_book_record_tile.dart';
import 'rea_micro_models.dart';
import '../home/reading_book_list.dart';

/// 阅微阅读记录与标注书籍。
class ReaMicroRecordsPage extends StatefulWidget {
  /// 创建页面。
  const ReaMicroRecordsPage({super.key, required this.controller});

  /// 阅微状态控制器。
  final ReaMicroController controller;

  @override
  State<ReaMicroRecordsPage> createState() => _ReaMicroRecordsPageState();
}

class _ReaMicroRecordsPageState extends State<ReaMicroRecordsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  ReaMicroRecordPeriod _period = ReaMicroRecordPeriod.month;
  DateTime _anchor = DateTime.now();
  List<ReaMicroBookRecord> _records = const <ReaMicroBookRecord>[];
  List<ReaMicroMarkBook> _markBooks = const <ReaMicroMarkBook>[];
  bool _loadingRecords = true;
  bool _loadingMarkBooks = true;
  String? _recordsError;
  String? _markBooksError;
  int _recordsRequest = 0;
  int _markBooksRequest = 0;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    widget.controller.pageRefresh.addListener(_refresh);
    unawaited(widget.controller.initialize());
    unawaited(_loadRecords());
    unawaited(_loadMarkBooks());
  }

  @override
  void dispose() {
    widget.controller.pageRefresh.removeListener(_refresh);
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadRecords() async {
    final request = ++_recordsRequest;
    setState(() {
      _loadingRecords = true;
      _recordsError = null;
    });
    try {
      final records = await widget.controller.loadBookRecords(_period, _anchor);
      if (!mounted || request != _recordsRequest) return;
      setState(() {
        _records = records;
        _loadingRecords = false;
      });
    } catch (error) {
      if (!mounted || request != _recordsRequest) return;
      setState(() {
        _recordsError = error.toString();
        _loadingRecords = false;
      });
    }
  }

  Future<void> _loadMarkBooks() async {
    final request = ++_markBooksRequest;
    setState(() {
      _loadingMarkBooks = true;
      _markBooksError = null;
    });
    try {
      final books = await widget.controller.loadMarkBooks();
      if (!mounted || request != _markBooksRequest) return;
      final sorted = List<ReaMicroMarkBook>.of(books)
        ..sort((left, right) {
          final compared = right.markCount.compareTo(left.markCount);
          return compared != 0 ? compared : left.name.compareTo(right.name);
        });
      setState(() {
        _markBooks = sorted;
        _loadingMarkBooks = false;
      });
    } catch (error) {
      if (!mounted || request != _markBooksRequest) return;
      setState(() {
        _markBooksError = error.toString();
        _loadingMarkBooks = false;
      });
    }
  }

  Future<void> _refresh() async {
    await Future.wait<void>(<Future<void>>[_loadRecords(), _loadMarkBooks()]);
  }

  Future<void> _changePeriod(ReaMicroRecordPeriod period) async {
    if (_period == period) return;
    setState(() => _period = period);
    await _loadRecords();
  }

  Future<void> _shiftPeriod(int direction) async {
    final next = switch (_period) {
      ReaMicroRecordPeriod.week => _anchor.add(Duration(days: 7 * direction)),
      ReaMicroRecordPeriod.month => DateTime(
        _anchor.year,
        _anchor.month + direction,
        1,
      ),
      ReaMicroRecordPeriod.year => DateTime(_anchor.year + direction, 1, 1),
    };
    setState(() => _anchor = next);
    await _loadRecords();
  }

  Future<void> _hideRecord(ReaMicroBookRecord record) async {
    final confirmed = await showReaderDialog<bool>(
      context: context,
      builder: (context) => ReaderFrostedAlertDialog(
        title: const Text('隐藏阅读记录？'),
        content: Text('将从阅微阅读记录中隐藏《${record.name}》，不会删除本地书籍。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('隐藏'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final result = await widget.controller.hideBookRecord(record.bookId);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(result.message)));
    if (result.success) {
      setState(() {
        _records = <ReaMicroBookRecord>[
          for (final item in _records)
            if (item.bookId != record.bookId) item,
        ];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('阅读记录与标注'),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            onPressed: _loadingRecords || _loadingMarkBooks ? null : _refresh,
            icon: _loadingRecords || _loadingMarkBooks
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: <Widget>[
            Tab(text: '阅读记录 ${_records.length}'),
            Tab(text: '标注书籍 ${_markBooks.length}'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: <Widget>[
          _buildRecordsTab(context),
          _buildMarkBooksTab(context),
        ],
      ),
    );
  }

  Widget _buildRecordsTab(BuildContext context) {
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: _loadRecords,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: <Widget>[
          SegmentedButton<ReaMicroRecordPeriod>(
            key: const ValueKey<String>('reamicro-record-period'),
            segments: const <ButtonSegment<ReaMicroRecordPeriod>>[
              ButtonSegment<ReaMicroRecordPeriod>(
                value: ReaMicroRecordPeriod.week,
                label: Text('周'),
              ),
              ButtonSegment<ReaMicroRecordPeriod>(
                value: ReaMicroRecordPeriod.month,
                label: Text('月'),
              ),
              ButtonSegment<ReaMicroRecordPeriod>(
                value: ReaMicroRecordPeriod.year,
                label: Text('年'),
              ),
            ],
            selected: <ReaMicroRecordPeriod>{_period},
            onSelectionChanged: (selection) =>
                unawaited(_changePeriod(selection.first)),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              IconButton(
                tooltip: '上一周期',
                onPressed: _loadingRecords ? null : () => _shiftPeriod(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  _periodLabel(_period, _anchor),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              IconButton(
                tooltip: '下一周期',
                onPressed: _loadingRecords ? null : () => _shiftPeriod(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          if (_recordsError != null) ...<Widget>[
            _Banner(text: _recordsError!),
            const SizedBox(height: 10),
          ],
          if (_loadingRecords && _records.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 42),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_records.isEmpty)
            const _EmptyHint('该周期没有阅微阅读记录。')
          else
            ReadingBookList(
              title: '阅读记录',
              allKey: const ValueKey('reamicro-records-all'),
              books: [
                for (var index = 0; index < _records.length; index++)
                  cloudReadingBookItem(
                    _records[index],
                    linked: widget.controller.syncBooks.values.any(
                      (identity) =>
                          identity.userBookId == _records[index].bookId,
                    ),
                    onHide: () => _hideRecord(_records[index]),
                    recentOrder: -index,
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildMarkBooksTab(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadMarkBooks,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: <Widget>[
          if (_markBooksError != null) ...<Widget>[
            _Banner(text: _markBooksError!),
            const SizedBox(height: 10),
          ],
          if (_loadingMarkBooks && _markBooks.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 42),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_markBooks.isEmpty)
            const _EmptyHint('阅微账号还没有划线或想法。')
          else
            Card(
              child: Column(
                children: <Widget>[
                  for (var index = 0; index < _markBooks.length; index++) ...[
                    if (index > 0) const Divider(height: 1),
                    _MarkBookTile(book: _markBooks[index]),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MarkBookTile extends StatelessWidget {
  const _MarkBookTile({required this.book});

  final ReaMicroMarkBook book;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _Cover(url: book.cover),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  book.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (book.author.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    book.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: <Widget>[
                    _MetricChip(label: '划线', value: book.underlineCount),
                    _MetricChip(label: '想法', value: book.thoughtCount),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: ReaderUiStyle.chipRadiusOf(theme),
      ),
      child: Text('$label $value', style: theme.textTheme.bodySmall),
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

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.error;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text, style: TextStyle(color: color)),
    );
  }
}

String _periodLabel(ReaMicroRecordPeriod period, DateTime anchor) {
  switch (period) {
    case ReaMicroRecordPeriod.week:
      final start = DateTime(
        anchor.year,
        anchor.month,
        anchor.day,
      ).subtract(Duration(days: anchor.weekday - DateTime.monday));
      final end = start.add(const Duration(days: 6));
      return '${start.month}月${start.day}日 - ${end.month}月${end.day}日';
    case ReaMicroRecordPeriod.month:
      return '${anchor.year} 年 ${anchor.month} 月';
    case ReaMicroRecordPeriod.year:
      return '${anchor.year} 年';
  }
}
