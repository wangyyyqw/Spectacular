import 'package:flutter/material.dart';
import 'package:reader_core/api.dart';
import 'package:reader_core/position/cfi.dart';

import '../reader_session.dart';

/// 目录面板（P4-11）：层级缩进、当前章高亮、点击跳转。
///
/// 只负责展示与选择；跳转由调用方执行（`ReaderSession.jumpToChapter`）。
class TocPanel extends StatefulWidget {
  /// 创建目录面板。
  const TocPanel({
    super.key,
    required this.entries,
    required this.currentSpineIndex,
    required this.onSelect,
    this.currentCfi,
    this.scrollController,
    this.onBack,
    this.emptyHint = '本书没有目录',
  });

  /// 目录树（嵌套结构）。
  final List<TocEntry> entries;

  /// 当前章 spine 序号（高亮用）。
  final int currentSpineIndex;

  /// 当前位置 CFI（用于多个目录项指向同一 spine 时定位当前项）。
  final String? currentCfi;

  /// 选择回调（点击目录项）。
  final ValueChanged<TocEntry> onSelect;

  /// 滚动控制器（调用方传入时用于控制目录滚动）。
  final ScrollController? scrollController;

  /// 返回回调（嵌在菜单 sheet 内时显示返回按钮）。
  final VoidCallback? onBack;

  /// 无目录时的提示。
  final String emptyHint;

  @override
  State<TocPanel> createState() => _TocPanelState();
}

class _TocPanelState extends State<TocPanel> {
  static const double _rowExtent = 48;
  static const double _listPadding = 4;

  final ScrollController _fallbackController = ScrollController();

  ScrollController get _scrollController =>
      widget.scrollController ?? _fallbackController;

  @override
  void initState() {
    super.initState();
    _scheduleCenterCurrentRow();
  }

  @override
  void didUpdateWidget(covariant TocPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentSpineIndex != widget.currentSpineIndex ||
        oldWidget.currentCfi != widget.currentCfi ||
        oldWidget.entries != widget.entries ||
        oldWidget.scrollController != widget.scrollController) {
      _scheduleCenterCurrentRow();
    }
  }

  @override
  void dispose() {
    _fallbackController.dispose();
    super.dispose();
  }

  void _scheduleCenterCurrentRow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _centerCurrentRow();
      }
    });
  }

  void _centerCurrentRow() {
    final rows = flattenToc(widget.entries);
    final index = _activeRowIndex(rows);
    if (index == null) {
      return;
    }
    final controller = _scrollController;
    if (!controller.hasClients) {
      return;
    }
    final position = controller.position;
    final target =
        _listPadding +
        index * _rowExtent +
        _rowExtent / 2 -
        position.viewportDimension / 2;
    final offset = target
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if ((position.pixels - offset).abs() >= 0.5) {
      controller.jumpTo(offset);
    }
  }

  int? _activeRowIndex(List<TocRow> rows) {
    if (rows.isEmpty) {
      return null;
    }
    final current = widget.currentCfi == null
        ? null
        : EpubCfi.parse(widget.currentCfi!);
    if (current != null) {
      final shallowestDepth = rows
          .map((row) => row.depth)
          .reduce((left, right) => left < right ? left : right);
      int? active;
      EpubCfi? activeCfi;
      for (var index = 0; index < rows.length; index += 1) {
        final row = rows[index];
        final cfi = row.entry.cfi;
        if (row.depth != shallowestDepth ||
            row.entry.spineIndex != widget.currentSpineIndex ||
            cfi == null ||
            cfi.compareTo(current) > 0) {
          continue;
        }
        if (activeCfi == null || cfi.compareTo(activeCfi) >= 0) {
          active = index;
          activeCfi = cfi;
        }
      }
      if (active != null) {
        return active;
      }
    }
    final fallback = rows.indexWhere(
      (row) => row.entry.spineIndex == widget.currentSpineIndex,
    );
    return fallback < 0 ? null : fallback;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = flattenToc(widget.entries);
    final activeIndex = _activeRowIndex(rows);
    return Material(
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                if (widget.onBack != null)
                  IconButton(
                    icon: const Icon(Icons.arrow_back, size: 20),
                    onPressed: widget.onBack,
                    tooltip: '返回',
                  ),
                Text('目录', style: theme.textTheme.titleMedium),
                const Spacer(),
                Text(
                  '共 ${rows.length} 章',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: rows.isEmpty
                ? Center(
                    child: Text(
                      widget.emptyHint,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: _listPadding),
                    itemExtent: _rowExtent,
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      final current = index == activeIndex;
                      return ListTile(
                        key: ValueKey<String>(
                          'toc-row-${row.entry.spineIndex}-${row.entry.title}',
                        ),
                        dense: true,
                        selected: current,
                        selectedColor: theme.colorScheme.primary,
                        contentPadding: EdgeInsets.only(
                          left: 20 + (row.depth - 1) * 16,
                          right: 20,
                        ),
                        title: Text(
                          row.entry.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: current
                              ? const TextStyle(fontWeight: FontWeight.w600)
                              : null,
                        ),
                        trailing: current
                            ? Icon(
                                Icons.play_arrow,
                                size: 16,
                                color: theme.colorScheme.primary,
                              )
                            : null,
                        onTap: () => widget.onSelect(row.entry),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
