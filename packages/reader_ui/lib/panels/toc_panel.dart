import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:reader_core/api.dart';
import 'package:reader_core/position/cfi.dart';

import '../icons/app_icon.dart';
import '../theme/reader_drawer_style.dart';

/// 目录面板（P4-11）：层级缩进、多级折叠、当前章高亮、点击跳转。
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
    this.readingDuration,
    this.scrollController,
    this.onBack,
    this.onChapterRules,
    this.emptyHint = '本书没有目录',
  });

  /// 目录树（嵌套结构）。
  final List<TocEntry> entries;

  /// 当前章 spine 序号（高亮用）。
  final int currentSpineIndex;

  /// 当前位置 CFI（用于多个目录项指向同一 spine 时定位当前项）。
  final String? currentCfi;
  final ValueListenable<Duration>? readingDuration;

  /// 选择回调（点击目录项）。
  final ValueChanged<TocEntry> onSelect;

  /// 滚动控制器（调用方传入时用于控制目录滚动）。
  final ScrollController? scrollController;

  /// 返回回调（嵌在菜单 sheet 内时显示返回按钮）。
  final VoidCallback? onBack;
  final VoidCallback? onChapterRules;

  /// 无目录时的提示。
  final String emptyHint;

  @override
  State<TocPanel> createState() => _TocPanelState();
}

class _TocPanelState extends State<TocPanel> {
  static const double _rowExtent = 40;
  static const double _listBottomPadding = 16;

  final ScrollController _fallbackController = ScrollController();
  final Set<TocEntry> _expanded = Set<TocEntry>.identity();

  ScrollController get _scrollController =>
      widget.scrollController ?? _fallbackController;

  @override
  void initState() {
    super.initState();
    _expandCurrentPath();
    _scheduleCenterCurrentRow();
  }

  @override
  void didUpdateWidget(covariant TocPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entries != widget.entries ||
        oldWidget.scrollController != widget.scrollController) {
      _expanded.clear();
      _expandCurrentPath();
      _scheduleCenterCurrentRow();
    } else if (oldWidget.currentSpineIndex != widget.currentSpineIndex ||
        oldWidget.currentCfi != widget.currentCfi) {
      _expandCurrentPath();
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

  void _expandCurrentPath() {
    final active = _activeEntry(flattenToc(widget.entries));
    if (active == null) {
      return;
    }
    final path = _pathToEntry(widget.entries, active);
    _expanded.addAll(path);
    if (active.children.isNotEmpty) {
      _expanded.add(active);
    }
  }

  List<TocEntry> _pathToEntry(List<TocEntry> entries, TocEntry target) {
    for (final entry in entries) {
      if (identical(entry, target)) {
        return <TocEntry>[entry];
      }
      final childPath = _pathToEntry(entry.children, target);
      if (childPath.isNotEmpty) {
        return <TocEntry>[entry, ...childPath];
      }
    }
    return const <TocEntry>[];
  }

  List<TocRow> _visibleRows() {
    final rows = <TocRow>[];

    void append(List<TocEntry> entries, int depth) {
      for (final entry in entries) {
        rows.add((entry: entry, depth: depth));
        if (entry.children.isNotEmpty && _expanded.contains(entry)) {
          append(entry.children, depth + 1);
        }
      }
    }

    append(widget.entries, 1);
    return rows;
  }

  void _toggleEntry(TocEntry entry) {
    setState(() {
      if (!_expanded.remove(entry)) {
        _expanded.add(entry);
      }
    });
  }

  void _expandAll() {
    setState(() {
      for (final row in flattenToc(widget.entries)) {
        if (row.entry.children.isNotEmpty) {
          _expanded.add(row.entry);
        }
      }
    });
  }

  void _collapseAll() {
    setState(() {
      _expanded.clear();
      final active = _activeEntry(flattenToc(widget.entries));
      if (active != null) {
        final path = _pathToEntry(widget.entries, active);
        if (path.length > 1) {
          _expanded.addAll(path.take(path.length - 1));
        }
      }
    });
    _scheduleCenterCurrentRow();
  }

  void _locateCurrent() {
    setState(() {
      final active = _activeEntry(flattenToc(widget.entries));
      if (active != null) {
        final path = _pathToEntry(widget.entries, active);
        if (path.length > 1) {
          _expanded.addAll(path.take(path.length - 1));
        }
      }
    });
    _scheduleCenterCurrentRow();
  }

  void _centerCurrentRow() {
    final active = _activeEntry(flattenToc(widget.entries));
    if (active == null) {
      return;
    }
    final rows = _visibleRows();
    final index = rows.indexWhere((row) => identical(row.entry, active));
    if (index < 0) {
      return;
    }
    final controller = _scrollController;
    if (!controller.hasClients) {
      return;
    }
    final position = controller.position;
    final target =
        index * _rowExtent + _rowExtent / 2 - position.viewportDimension / 2;
    final offset = target
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if ((position.pixels - offset).abs() >= 0.5) {
      controller.jumpTo(offset);
    }
  }

  TocEntry? _activeEntry(List<TocRow> rows) {
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
        return rows[active].entry;
      }
    }
    final fallback = rows.indexWhere(
      (row) => row.entry.spineIndex == widget.currentSpineIndex,
    );
    return fallback < 0 ? null : rows[fallback].entry;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = ReaderDrawerStyle.surfaceOf(theme);
    final text = ReaderDrawerStyle.textOf(theme);
    final muted = ReaderDrawerStyle.mutedOf(theme);
    final faint = ReaderDrawerStyle.faintOf(theme);
    final allRows = flattenToc(widget.entries);
    final rows = _visibleRows();
    final active = _activeEntry(allRows);
    return Material(
      color: surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Row(
              children: [
                Flexible(
                  child: ValueListenableBuilder<Duration>(
                    valueListenable:
                        widget.readingDuration ??
                        const AlwaysStoppedAnimation<Duration>(Duration.zero),
                    builder: (context, duration, _) {
                      final minutes = duration.inMinutes;
                      final hours = minutes ~/ 60;
                      final label = hours > 0
                          ? '累计阅读 $hours 小时 ${minutes % 60} 分钟'
                          : '累计阅读 $minutes 分钟';
                      return Text(
                        label,
                        key: const ValueKey<String>('toc-reading-duration'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 18 / 13,
                        ).copyWith(color: text),
                      );
                    },
                  ),
                ),
                const Spacer(),
                Text(
                  '共 ${allRows.length} 章',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
                const SizedBox(width: 12),
                _TocArrows(onExpand: _expandAll, onCollapse: _collapseAll),
                const SizedBox(width: 12),
                _TocToolButton(
                  buttonKey: const ValueKey<String>('toc-locate-current'),
                  tooltip: '回到当前章',
                  icon: AppGlyph.listBulleted,
                  onTap: active == null ? null : _locateCurrent,
                ),
              ],
            ),
          ),
          if (widget.onChapterRules != null)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: TextButton(
                  key: const ValueKey('toc-chapter-rules'),
                  onPressed: widget.onChapterRules,
                  child: const Text('章节正则'),
                ),
              ),
            ),
          Expanded(
            child: rows.isEmpty
                ? Center(
                    child: Text(
                      widget.emptyHint,
                      style: TextStyle(fontSize: 14, color: muted),
                    ),
                  )
                : RawScrollbar(
                    controller: _scrollController,
                    thumbVisibility: true,
                    thumbColor: const Color(0xFFCCCCCC),
                    thickness: 4,
                    radius: const Radius.circular(2),
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.only(
                        bottom: _listBottomPadding,
                      ),
                      itemExtent: _rowExtent,
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        final current = identical(row.entry, active);
                        final missing = row.entry.missing;
                        final expanded = _expanded.contains(row.entry);
                        final hasChildren = row.entry.children.isNotEmpty;
                        return ListTile(
                          key: ValueKey<String>(
                            'toc-row-${row.entry.spineIndex}-${row.entry.title}',
                          ),
                          dense: true,
                          selected: current && !missing,
                          selectedColor: text,
                          tileColor: Colors.transparent,
                          selectedTileColor: Colors.transparent,
                          contentPadding: EdgeInsets.only(
                            left: row.depth == 1
                                ? 22
                                : 58 + (row.depth - 2) * 18,
                            right: 24,
                          ),
                          title: Row(
                            children: [
                              if (row.depth == 1 && hasChildren) ...[
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFE5E9EF),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 12),
                              ],
                              Expanded(
                                child: Text(
                                  missing
                                      ? '${row.entry.title}（章节缺失）'
                                      : row.entry.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: 'serif',
                                    fontSize: 14,
                                    color: missing
                                        ? muted
                                        : theme.brightness == Brightness.dark
                                        ? text
                                        : const Color(0xFF555B64),
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          trailing: hasChildren
                              ? SizedBox.square(
                                  dimension: 24,
                                  child: InkWell(
                                    key: ValueKey<String>(
                                      'toc-toggle-${row.entry.spineIndex}-'
                                      '${row.entry.title}',
                                    ),
                                    customBorder: const CircleBorder(),
                                    onTap: () => _toggleEntry(row.entry),
                                    child: AppIcon(
                                      expanded
                                          ? AppGlyph.chevronDown
                                          : AppGlyph.chevronUp,
                                      size: 14,
                                      color: theme.brightness == Brightness.dark
                                          ? faint
                                          : const Color(0xFF171A1F),
                                    ),
                                  ),
                                )
                              : null,
                          onTap: missing
                              ? null
                              : () => widget.onSelect(row.entry),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _TocToolButton extends StatelessWidget {
  const _TocToolButton({
    required this.buttonKey,
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final Key buttonKey;
  final String tooltip;
  final AppGlyph icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        key: buttonKey,
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox.square(
          dimension: 16,
          child: AppIcon(
            icon,
            size: 16,
            color: onTap == null
                ? ReaderDrawerStyle.faintOf(theme)
                : ReaderDrawerStyle.mutedOf(theme),
          ),
        ),
      ),
    );
  }
}

/// 参考稿的上下箭头组合：上半展开，下半收起。
class _TocArrows extends StatelessWidget {
  const _TocArrows({required this.onExpand, required this.onCollapse});

  final VoidCallback onExpand;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    final color = ReaderDrawerStyle.mutedOf(Theme.of(context));
    return SizedBox(
      width: 16,
      height: 16,
      child: Stack(
        children: <Widget>[
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 8,
            child: Semantics(
              button: true,
              label: '展开全部',
              child: InkWell(
                key: const ValueKey<String>('toc-expand-all'),
                onTap: onExpand,
                child: CustomPaint(
                  painter: _TocArrowPainter(upper: true, color: color),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 8,
            child: Semantics(
              button: true,
              label: '收起全部',
              child: InkWell(
                key: const ValueKey<String>('toc-collapse-all'),
                onTap: onCollapse,
                child: CustomPaint(
                  painter: _TocArrowPainter(upper: false, color: color),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TocArrowPainter extends CustomPainter {
  const _TocArrowPainter({required this.upper, required this.color});

  final bool upper;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    if (upper) {
      path
        ..moveTo(4.7, 6.4)
        ..lineTo(8, 3.1)
        ..lineTo(11.3, 6.4);
    } else {
      path
        ..moveTo(4.7, 1.6)
        ..lineTo(8, 4.9)
        ..lineTo(11.3, 1.6);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _TocArrowPainter oldDelegate) =>
      oldDelegate.upper != upper || oldDelegate.color != color;
}
