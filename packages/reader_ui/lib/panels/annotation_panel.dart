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
    this.onBack,
    this.emptyHint = '还没有笔记或高亮',
  });

  /// 全书标注。
  final List<ReaderAnnotation> annotations;

  /// 点击标注，跳转到原文位置。
  final ValueChanged<ReaderAnnotation> onSelect;

  /// 打开标注编辑弹层。
  final ValueChanged<ReaderAnnotation> onEdit;

  /// 返回回调（嵌在菜单 sheet 内时显示返回按钮）。
  final VoidCallback? onBack;

  /// 空态提示。
  final String emptyHint;

  @override
  State<AnnotationPanel> createState() => _AnnotationPanelState();
}

enum _AnnotationFilter { all, note, highlight }

class _AnnotationPanelState extends State<AnnotationPanel> {
  _AnnotationFilter _filter = _AnnotationFilter.all;

  List<ReaderAnnotation> get _sorted {
    return List<ReaderAnnotation>.of(widget.annotations)
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
  }

  List<ReaderAnnotation> get _visible {
    final items = _sorted;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = _visible;
    final noteCount = widget.annotations
        .where((item) => item.type == ReaderAnnotationType.note)
        .length;
    final highlightCount = widget.annotations.length - noteCount;
    return Material(
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Row(
              children: [
                if (widget.onBack != null)
                  IconButton(
                    icon: const Icon(Icons.arrow_back, size: 20),
                    onPressed: widget.onBack,
                    tooltip: '返回',
                  ),
                Text('笔记与高亮', style: theme.textTheme.titleMedium),
                const Spacer(),
                Text(
                  '共 ${widget.annotations.length} 条',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
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
                  count: widget.annotations.length,
                  selected: _filter == _AnnotationFilter.all,
                  onSelected: () =>
                      setState(() => _filter = _AnnotationFilter.all),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  chipKey: const ValueKey<String>('annotation-filter-notes'),
                  label: '笔记',
                  count: noteCount,
                  selected: _filter == _AnnotationFilter.note,
                  onSelected: () =>
                      setState(() => _filter = _AnnotationFilter.note),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  chipKey: const ValueKey<String>(
                    'annotation-filter-highlights',
                  ),
                  label: '高亮',
                  count: highlightCount,
                  selected: _filter == _AnnotationFilter.highlight,
                  onSelected: () =>
                      setState(() => _filter = _AnnotationFilter.highlight),
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
    required this.onSelect,
    required this.onEdit,
  });

  final ReaderAnnotation annotation;
  final VoidCallback onSelect;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isNote = annotation.type == ReaderAnnotationType.note;
    final color = Color(annotation.color ?? defaultHighlightColor);
    final note = annotation.note?.trim();
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey<String>('annotation-row-${annotation.id}'),
        onTap: onSelect,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: color),
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
              Align(
                alignment: Alignment.topCenter,
                child: IconButton(
                  key: ValueKey<String>('annotation-edit-${annotation.id}'),
                  onPressed: onEdit,
                  tooltip: '编辑标注',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.more_horiz, size: 20),
                ),
              ),
            ],
          ),
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
