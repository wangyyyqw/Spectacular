import 'package:flutter/material.dart';

import 'package:reader_core/position/cfi.dart';

import '../annotations/annotation.dart';
import '../annotations/annotation_editor_sheet.dart'
    show ReaderAnnotationEditorSheet;
import '../icons/app_icon.dart';
import '../theme/reader_frosted_popup.dart';
import '../theme/reader_frosted_surface.dart';

/// 阅读器内的想法与划线列表，装饰不进入此面板。
///
/// 列表按更新时间倒序展示，支持按类型筛选、跳转原文和打开编辑弹层。
class AnnotationPanel extends StatefulWidget {
  /// 创建标注面板。
  const AnnotationPanel({
    super.key,
    required this.annotations,
    required this.onSelect,
    required this.onEdit,
    this.onDelete,
    this.onRecolor,
    this.chapterTitleOf,
    this.onBack,
    this.emptyHint = '还没有划线或想法',
    this.inkMode = false,
  });

  /// 全书标注。
  final List<ReaderAnnotation> annotations;

  /// 点击标注，跳转到原文位置。
  final ValueChanged<ReaderAnnotation> onSelect;

  /// 打开标注编辑弹层。
  final ValueChanged<ReaderAnnotation> onEdit;

  /// 批量删除标注。
  final Future<void> Function(List<ReaderAnnotation>)? onDelete;

  /// 批量更换标注颜色。
  final Future<void> Function(List<ReaderAnnotation>, int)? onRecolor;

  /// 标注所在章节标题。
  final String? Function(ReaderAnnotation)? chapterTitleOf;

  /// 返回回调（嵌在菜单 sheet 内时显示返回按钮）。
  final VoidCallback? onBack;

  /// 空态提示。
  final String emptyHint;

  /// 墨水屏模式：标记色统一显示为黑色，并隐藏无效的换色入口。
  final bool inkMode;

  @override
  State<AnnotationPanel> createState() => _AnnotationPanelState();
}

enum _AnnotationFilter { all, note, highlight }

enum _AnnotationSort {
  updated('最近更新'),
  position('阅读顺序');

  const _AnnotationSort(this.label);

  final String label;
}

class _AnnotationPanelState extends State<AnnotationPanel> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedIds = <String>{};
  final Set<String> _expandedIds = <String>{};
  late _AnnotationFilter _filter;
  _AnnotationSort _sort = _AnnotationSort.updated;
  String _query = '';
  bool _selecting = false;
  bool _deleting = false;
  bool _recoloring = false;

  @override
  void initState() {
    super.initState();
    _filter = _AnnotationFilter.all;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AnnotationPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ids = widget.annotations.map((item) => item.id).toSet();
    _selectedIds.removeWhere((id) => !ids.contains(id));
    _expandedIds.removeWhere((id) => !ids.contains(id));
    if (widget.onDelete == null || widget.annotations.isEmpty) {
      _selecting = false;
      _selectedIds.clear();
    }
  }

  List<ReaderAnnotation> get _sorted {
    final items = List<ReaderAnnotation>.of(widget.annotations);
    if (_sort == _AnnotationSort.updated) {
      items.sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
      return items;
    }
    items.sort((left, right) {
      final leftCfi = EpubCfi.parse(left.startCfi);
      final rightCfi = EpubCfi.parse(right.startCfi);
      if (leftCfi != null && rightCfi != null) {
        final byPosition = leftCfi.compareTo(rightCfi);
        if (byPosition != 0) {
          return byPosition;
        }
      } else if (leftCfi == null && rightCfi != null) {
        return 1;
      } else if (leftCfi != null && rightCfi == null) {
        return -1;
      }
      return right.updatedAt.compareTo(left.updatedAt);
    });
    return items;
  }

  List<ReaderAnnotation> get _searched {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) {
      return _sorted;
    }
    return _sorted
        .where((item) {
          final chapterTitle = _chapterTitleOf(item)?.toLowerCase() ?? '';
          return item.quote.toLowerCase().contains(query) ||
              (item.note?.toLowerCase().contains(query) ?? false) ||
              chapterTitle.contains(query);
        })
        .toList(growable: false);
  }

  String? _chapterTitleOf(ReaderAnnotation annotation) {
    final title = widget.chapterTitleOf?.call(annotation)?.trim();
    return title == null || title.isEmpty ? null : title;
  }

  List<ReaderAnnotation> _filtered(List<ReaderAnnotation> items) {
    return switch (_filter) {
      _AnnotationFilter.all => items,
      _AnnotationFilter.note =>
        items
            .where((item) => item.type == ReaderAnnotationType.thought)
            .toList(growable: false),
      _AnnotationFilter.highlight =>
        items
            .where((item) => item.type == ReaderAnnotationType.mark)
            .toList(growable: false),
    };
  }

  void _setFilter(_AnnotationFilter filter) {
    setState(() {
      _filter = filter;
      _selectedIds.clear();
    });
  }

  void _setQuery(String value) {
    setState(() {
      _query = value;
      _selectedIds.clear();
    });
  }

  void _enterSelection() {
    setState(() => _selecting = true);
  }

  void _toggleSelection(String id) {
    setState(() {
      if (!_selectedIds.add(id)) {
        _selectedIds.remove(id);
      }
    });
  }

  void _toggleSelectAll(List<ReaderAnnotation> items) {
    final visibleIds = items.map((item) => item.id).toSet();
    final allSelected =
        visibleIds.isNotEmpty && visibleIds.every(_selectedIds.contains);
    setState(() {
      if (allSelected) {
        _selectedIds.removeAll(visibleIds);
      } else {
        _selectedIds.addAll(visibleIds);
      }
    });
  }

  void _exitSelection() {
    setState(() {
      _selecting = false;
      _selectedIds.clear();
    });
  }

  Future<void> _deleteSelected() async {
    final delete = widget.onDelete;
    if (delete == null || _selectedIds.isEmpty || _deleting) {
      return;
    }
    final selected = <ReaderAnnotation>[
      for (final annotation in widget.annotations)
        if (_selectedIds.contains(annotation.id)) annotation,
    ];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ReaderFrostedAlertDialog(
        title: Text('删除 ${selected.length} 条标注？'),
        content: const Text('选中的想法和划线都会删除，且不可恢复。'),
        actions: [
          TextButton(
            key: const ValueKey<String>('annotation-batch-confirm-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey<String>('annotation-batch-confirm-delete'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _deleting = true);
    try {
      await delete(selected);
      if (!mounted) {
        return;
      }
      _exitSelection();
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(const SnackBar(content: Text('删除标注失败，请重试')));
    } finally {
      if (mounted) {
        setState(() => _deleting = false);
      }
    }
  }

  Future<void> _recolorSelected() async {
    final recolor = widget.onRecolor;
    if (recolor == null || _selectedIds.isEmpty || _recoloring) {
      return;
    }
    final selected = <ReaderAnnotation>[
      for (final annotation in widget.annotations)
        if (_selectedIds.contains(annotation.id)) annotation,
    ];
    final color = await showDialog<int>(
      context: context,
      builder: (context) => _BatchColorDialog(count: selected.length),
    );
    if (color == null || !mounted) {
      return;
    }
    setState(() => _recoloring = true);
    try {
      await recolor(selected, color);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(const SnackBar(content: Text('更换标注颜色失败，请重试')));
      }
    } finally {
      if (mounted) {
        setState(() => _recoloring = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = _deleting || _recoloring;
    final searched = _searched;
    final items = _filtered(searched);
    final noteCount = searched
        .where((item) => item.type == ReaderAnnotationType.thought)
        .length;
    final highlightCount = searched.length - noteCount;
    final filtering =
        _query.trim().isNotEmpty || _filter != _AnnotationFilter.all;
    final allVisibleSelected =
        items.isNotEmpty &&
        items.every((annotation) => _selectedIds.contains(annotation.id));
    return Material(
      color: ReaderFrostedSurface.panelColorOf(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
            child: Row(
              children: [
                if (_selecting)
                  IconButton(
                    key: const ValueKey<String>('annotation-batch-exit'),
                    icon: const AppIcon(AppGlyph.close, size: 20),
                    onPressed: busy ? null : _exitSelection,
                    tooltip: '退出选择',
                  )
                else if (widget.onBack != null)
                  IconButton(
                    icon: const AppIcon(AppGlyph.arrowBack, size: 20),
                    onPressed: widget.onBack,
                    tooltip: '返回',
                  ),
                Expanded(
                  child: Text(
                    _selecting ? '已选 ${_selectedIds.length} 条' : '标注',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (_selecting) ...[
                  TextButton(
                    key: const ValueKey<String>('annotation-batch-select-all'),
                    onPressed: busy || items.isEmpty
                        ? null
                        : () => _toggleSelectAll(items),
                    child: Text(allVisibleSelected ? '取消全选' : '全选'),
                  ),
                  if (widget.onRecolor != null && !widget.inkMode)
                    IconButton(
                      key: const ValueKey<String>('annotation-batch-recolor'),
                      tooltip: '更换颜色',
                      onPressed: busy || _selectedIds.isEmpty
                          ? null
                          : _recolorSelected,
                      icon: _recoloring
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const AppIcon(AppGlyph.palette, size: 20),
                    ),
                  IconButton(
                    key: const ValueKey<String>('annotation-batch-delete'),
                    tooltip: '删除选中标注',
                    onPressed: busy || _selectedIds.isEmpty
                        ? null
                        : _deleteSelected,
                    icon: _deleting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const AppIcon(AppGlyph.delete, size: 20),
                  ),
                ] else ...[
                  Text(
                    filtering
                        ? '显示 ${items.length} / ${widget.annotations.length} 条'
                        : '共 ${widget.annotations.length} 条',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  PopupMenuButton<_AnnotationSort>(
                    key: const ValueKey<String>('annotation-sort'),
                    tooltip: '标注排序',
                    initialValue: _sort,
                    onSelected: (value) => setState(() => _sort = value),
                    icon: const AppIcon(AppGlyph.sort, size: 20),
                    itemBuilder: (_) => <PopupMenuEntry<_AnnotationSort>>[
                      for (final sort in _AnnotationSort.values)
                        appCheckedMenuItem<_AnnotationSort>(
                          key: ValueKey<String>('annotation-sort-${sort.name}'),
                          value: sort,
                          checked: sort == _sort,
                          child: Text(sort.label),
                        ),
                    ],
                  ),
                  if (widget.onDelete != null && items.isNotEmpty)
                    IconButton(
                      key: const ValueKey<String>('annotation-batch-manage'),
                      tooltip: '批量管理',
                      onPressed: _enterSelection,
                      icon: const AppIcon(AppGlyph.checklist, size: 20),
                    ),
                ],
              ],
            ),
          ),
          ...<Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: TextField(
                key: const ValueKey<String>('annotation-search-input'),
                controller: _searchController,
                onChanged: _setQuery,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: '搜索原文、想法或章节',
                  prefixIcon: const AppIcon(AppGlyph.search, size: 20),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          key: const ValueKey<String>(
                            'annotation-search-clear',
                          ),
                          onPressed: () {
                            _searchController.clear();
                            _setQuery('');
                          },
                          tooltip: '清除搜索',
                          icon: const AppIcon(AppGlyph.close, size: 18),
                        ),
                  isDense: true,
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerLow,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  _FilterChip(
                    chipKey: const ValueKey<String>('annotation-filter-all'),
                    label: '全部',
                    count: searched.length,
                    selected: _filter == _AnnotationFilter.all,
                    onSelected: () => _setFilter(_AnnotationFilter.all),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    chipKey: const ValueKey<String>(
                      'annotation-filter-highlights',
                    ),
                    label: '划线',
                    count: highlightCount,
                    selected: _filter == _AnnotationFilter.highlight,
                    onSelected: () => _setFilter(_AnnotationFilter.highlight),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    chipKey: const ValueKey<String>('annotation-filter-notes'),
                    label: '想法',
                    count: noteCount,
                    selected: _filter == _AnnotationFilter.note,
                    onSelected: () => _setFilter(_AnnotationFilter.note),
                  ),
                ],
              ),
            ),
          ],
          const Divider(height: 1),
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Text(
                      _emptyText,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final annotation = items[index];
                      return _AnnotationCard(
                        annotation: annotation,
                        chapterTitle: _chapterTitleOf(annotation),
                        inkMode: widget.inkMode,
                        selecting: _selecting,
                        selected: _selectedIds.contains(annotation.id),
                        expanded: _expandedIds.contains(annotation.id),
                        onToggleSelection: () =>
                            _toggleSelection(annotation.id),
                        onSelect: () => widget.onSelect(annotation),
                        onEdit: () => widget.onEdit(annotation),
                        onToggleExpanded: () {
                          setState(() {
                            if (!_expandedIds.add(annotation.id)) {
                              _expandedIds.remove(annotation.id);
                            }
                          });
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String get _emptyText {
    if (_query.trim().isNotEmpty) {
      return '没有匹配的划线或想法';
    }
    return switch (_filter) {
      _AnnotationFilter.note => '还没有想法',
      _AnnotationFilter.highlight => '还没有划线',
      _AnnotationFilter.all => widget.emptyHint,
    };
  }
}

class _BatchColorDialog extends StatelessWidget {
  const _BatchColorDialog({required this.count});

  final int count;

  String _keyValue(int color) =>
      '0x${color.toRadixString(16).toUpperCase().padLeft(8, '0')}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ReaderFrostedAlertDialog(
      title: Text('更换 $count 条标注的颜色'),
      content: Wrap(
        spacing: 14,
        runSpacing: 14,
        children: [
          for (final option in ReaderAnnotationEditorSheet.colors)
            Semantics(
              button: true,
              label: option.label,
              child: InkResponse(
                key: ValueKey<String>(
                  'annotation-batch-color-${_keyValue(option.value)}',
                ),
                onTap: () => Navigator.of(context).pop(option.value),
                radius: 24,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Color(option.value),
                    shape: BoxShape.circle,
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                ),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey<String>('annotation-batch-color-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.chipKey,
    required this.label,
    required this.count,
    required this.selected,
    required this.onSelected,
  });

  final Key chipKey;
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ChoiceChip(
      key: chipKey,
      selected: selected,
      onSelected: (_) => onSelected(),
      showCheckmark: false,
      label: Text('$label $count'),
      labelStyle: TextStyle(
        fontSize: 12,
        color: selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
      ),
      selectedColor: scheme.secondaryContainer,
      visualDensity: VisualDensity.compact,
      side: BorderSide(
        color: selected ? Colors.transparent : scheme.outlineVariant,
      ),
    );
  }
}

class _AnnotationCard extends StatelessWidget {
  const _AnnotationCard({
    required this.annotation,
    required this.chapterTitle,
    required this.inkMode,
    required this.selecting,
    required this.selected,
    required this.expanded,
    required this.onToggleSelection,
    required this.onSelect,
    required this.onEdit,
    required this.onToggleExpanded,
  });

  final ReaderAnnotation annotation;
  final String? chapterTitle;
  final bool inkMode;
  final bool selecting;
  final bool selected;
  final bool expanded;
  final VoidCallback onToggleSelection;
  final VoidCallback onSelect;
  final VoidCallback onEdit;
  final VoidCallback onToggleExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isNote = annotation.type == ReaderAnnotationType.thought;
    final color = inkMode
        ? const Color(0xFF000000)
        : Color(annotation.color ?? defaultHighlightColor);
    final note = annotation.note?.trim();
    final hasNote = note != null && note.isNotEmpty;
    final noteNeedsExpansion =
        hasNote && (note.length > 66 || '\n'.allMatches(note).length >= 2);
    final borderRadius = BorderRadius.circular(4);
    return Material(
      color: selected
          ? theme.colorScheme.onSurface.withValues(alpha: 0.06)
          : theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius,
        side: BorderSide(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey<String>('annotation-row-${annotation.id}'),
        onTap: selecting ? onToggleSelection : onSelect,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              AppIcon(
                                isNote ? AppGlyph.note : AppGlyph.highlighter,
                                size: 16,
                                color: color.computeLuminance() > 0.72
                                    ? theme.colorScheme.onSurfaceVariant
                                    : color,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  isNote
                                      ? '想法'
                                      : '划线 · ${annotation.style.label}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              if (chapterTitle != null) ...[
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    chapterTitle!,
                                    key: ValueKey<String>(
                                      'annotation-chapter-${annotation.id}',
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ),
                              ] else
                                const Spacer(),
                              Text(
                                _formatTime(annotation.updatedAt),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (annotation.needsRelocation) ...[
                            Text(
                              '待修复 · 点击关联原文',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.error,
                              ),
                            ),
                            if (annotation.relocationReason != null)
                              Text(
                                annotation.relocationReason!,
                                style: theme.textTheme.bodySmall,
                              ),
                            const SizedBox(height: 8),
                          ],
                          if (!hasNote)
                            Text(
                              annotation.quote,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                height: 1.45,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          if (hasNote) ...[
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                note,
                                key: ValueKey<String>(
                                  'annotation-note-${annotation.id}',
                                ),
                                maxLines: expanded ? null : 3,
                                overflow: expanded
                                    ? TextOverflow.visible
                                    : TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  height: 1.5,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            if (noteNeedsExpansion)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  key: ValueKey<String>(
                                    'annotation-expand-${annotation.id}',
                                  ),
                                  onPressed: onToggleExpanded,
                                  style: TextButton.styleFrom(
                                    minimumSize: const Size(44, 44),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                  ),
                                  icon: AppIcon(
                                    expanded
                                        ? AppGlyph.chevronUp
                                        : AppGlyph.chevronDown,
                                    size: 18,
                                  ),
                                  label: Text(expanded ? '收起想法' : '展开想法'),
                                ),
                              ),
                            const SizedBox(height: 8),
                            Text(
                              annotation.quote,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                height: 1.45,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (selecting)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 8, 8, 8),
                      child: Checkbox(
                        key: ValueKey<String>(
                          'annotation-checkbox-${annotation.id}',
                        ),
                        value: selected,
                        onChanged: (_) => onToggleSelection(),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: IconButton(
                        key: ValueKey<String>(
                          'annotation-edit-${annotation.id}',
                        ),
                        onPressed: onEdit,
                        tooltip: '编辑标注',
                        constraints: const BoxConstraints(
                          minWidth: 44,
                          minHeight: 44,
                        ),
                        icon: const AppIcon(AppGlyph.more, size: 20),
                      ),
                    ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 4,
              child: ColoredBox(
                key: ValueKey<String>('annotation-color-bar-${annotation.id}'),
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatTime(DateTime time) {
    final local = time.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}
