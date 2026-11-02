import 'package:flutter/material.dart';

import '../annotations/annotation.dart';

/// 阅读器内的笔记与高亮列表。
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
    this.onBack,
    this.emptyHint = '还没有笔记或高亮',
  });

  /// 全书标注。
  final List<ReaderAnnotation> annotations;

  /// 点击标注，跳转到原文位置。
  final ValueChanged<ReaderAnnotation> onSelect;

  /// 打开标注编辑弹层。
  final ValueChanged<ReaderAnnotation> onEdit;

  /// 批量删除标注。
  final Future<void> Function(List<ReaderAnnotation>)? onDelete;

  /// 返回回调（嵌在菜单 sheet 内时显示返回按钮）。
  final VoidCallback? onBack;

  /// 空态提示。
  final String emptyHint;

  @override
  State<AnnotationPanel> createState() => _AnnotationPanelState();
}

enum _AnnotationFilter { all, note, highlight }

class _AnnotationPanelState extends State<AnnotationPanel> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedIds = <String>{};
  _AnnotationFilter _filter = _AnnotationFilter.all;
  String _query = '';
  bool _selecting = false;
  bool _deleting = false;

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
    if (widget.onDelete == null || widget.annotations.isEmpty) {
      _selecting = false;
      _selectedIds.clear();
    }
  }

  List<ReaderAnnotation> get _sorted {
    return List<ReaderAnnotation>.of(widget.annotations)
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
  }

  List<ReaderAnnotation> get _searched {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) {
      return _sorted;
    }
    return _sorted
        .where(
          (item) =>
              item.quote.toLowerCase().contains(query) ||
              (item.note?.toLowerCase().contains(query) ?? false),
        )
        .toList(growable: false);
  }

  List<ReaderAnnotation> _filtered(List<ReaderAnnotation> items) {
    return switch (_filter) {
      _AnnotationFilter.all => items,
      _AnnotationFilter.note =>
        items
            .where((item) => item.type == ReaderAnnotationType.note)
            .toList(growable: false),
      _AnnotationFilter.highlight =>
        items
            .where((item) => item.type == ReaderAnnotationType.highlight)
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
      builder: (context) => AlertDialog(
        title: Text('删除 ${selected.length} 条标注？'),
        content: const Text('选中的笔记和高亮都会删除，且不可恢复。'),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final searched = _searched;
    final items = _filtered(searched);
    final noteCount = searched
        .where((item) => item.type == ReaderAnnotationType.note)
        .length;
    final highlightCount = searched.length - noteCount;
    final filtering =
        _query.trim().isNotEmpty || _filter != _AnnotationFilter.all;
    final allVisibleSelected =
        items.isNotEmpty &&
        items.every((annotation) => _selectedIds.contains(annotation.id));
    return Material(
      color: theme.colorScheme.surface,
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
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: _deleting ? null : _exitSelection,
                    tooltip: '退出选择',
                  )
                else if (widget.onBack != null)
                  IconButton(
                    icon: const Icon(Icons.arrow_back, size: 20),
                    onPressed: widget.onBack,
                    tooltip: '返回',
                  ),
                Text(
                  _selecting ? '已选 ${_selectedIds.length} 条' : '笔记与高亮',
                  style: theme.textTheme.titleMedium,
                ),
                const Spacer(),
                if (_selecting) ...[
                  TextButton(
                    key: const ValueKey<String>('annotation-batch-select-all'),
                    onPressed: _deleting || items.isEmpty
                        ? null
                        : () => _toggleSelectAll(items),
                    child: Text(allVisibleSelected ? '取消全选' : '全选'),
                  ),
                  IconButton(
                    key: const ValueKey<String>('annotation-batch-delete'),
                    tooltip: '删除选中标注',
                    onPressed: _deleting || _selectedIds.isEmpty
                        ? null
                        : _deleteSelected,
                    icon: _deleting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.delete_outline, size: 20),
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
                  if (widget.onDelete != null && items.isNotEmpty)
                    IconButton(
                      key: const ValueKey<String>('annotation-batch-manage'),
                      tooltip: '批量管理',
                      onPressed: _enterSelection,
                      icon: const Icon(Icons.checklist, size: 20),
                    ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              key: const ValueKey<String>('annotation-search-input'),
              controller: _searchController,
              onChanged: _setQuery,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: '搜索原文或笔记',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        key: const ValueKey<String>('annotation-search-clear'),
                        onPressed: () {
                          _searchController.clear();
                          _setQuery('');
                        },
                        tooltip: '清除搜索',
                        icon: const Icon(Icons.close, size: 18),
                      ),
                isDense: true,
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerLow,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
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
                  chipKey: const ValueKey<String>('annotation-filter-notes'),
                  label: '笔记',
                  count: noteCount,
                  selected: _filter == _AnnotationFilter.note,
                  onSelected: () => _setFilter(_AnnotationFilter.note),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  chipKey: const ValueKey<String>(
                    'annotation-filter-highlights',
                  ),
                  label: '高亮',
                  count: highlightCount,
                  selected: _filter == _AnnotationFilter.highlight,
                  onSelected: () => _setFilter(_AnnotationFilter.highlight),
                ),
              ],
            ),
          ),
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
                        selecting: _selecting,
                        selected: _selectedIds.contains(annotation.id),
                        onToggleSelection: () =>
                            _toggleSelection(annotation.id),
                        onSelect: () => widget.onSelect(annotation),
                        onEdit: () => widget.onEdit(annotation),
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
      return '没有匹配的笔记或高亮';
    }
    return switch (_filter) {
      _AnnotationFilter.note => '还没有笔记',
      _AnnotationFilter.highlight => '还没有高亮',
      _AnnotationFilter.all => widget.emptyHint,
    };
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
    required this.selecting,
    required this.selected,
    required this.onToggleSelection,
    required this.onSelect,
    required this.onEdit,
  });

  final ReaderAnnotation annotation;
  final bool selecting;
  final bool selected;
  final VoidCallback onToggleSelection;
  final VoidCallback onSelect;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isNote = annotation.type == ReaderAnnotationType.note;
    final color = Color(annotation.color ?? defaultHighlightColor);
    final note = annotation.note?.trim();
    final borderRadius = BorderRadius.circular(14);
    return Material(
      color: selected
          ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.45)
          : theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius,
        side: BorderSide(
          color: selected ? theme.colorScheme.primary : Colors.transparent,
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
                              Icon(
                                isNote
                                    ? Icons.sticky_note_2_outlined
                                    : Icons.border_color_outlined,
                                size: 16,
                                color: color.computeLuminance() > 0.72
                                    ? theme.colorScheme.onSurfaceVariant
                                    : color,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isNote ? '笔记' : '高亮',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
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
                          Text(
                            annotation.quote,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              height: 1.45,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (note != null && note.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface,
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Text(
                                note,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  height: 1.5,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
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
                        visualDensity: VisualDensity.compact,
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
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.more_horiz, size: 20),
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
              child: ColoredBox(color: color),
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
