import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';

import '../book_source/book_source_discovery.dart';
import '../book_source/book_source_models.dart';
import 'discover_choice_dialog.dart';

typedef DiscoverFilterResult = ({
  BookSource source,
  Map<String, String> selection,
  BookDiscoverCategory? category,
});

/// 筛选管理保持草稿，应用后才更新发现列表。
class DiscoverFilterDialog extends StatefulWidget {
  const DiscoverFilterDialog({
    super.key,
    required this.sources,
    required this.source,
    required this.filterFor,
    required this.selections,
  });
  final List<BookSource> sources;
  final BookSource? source;
  final BookDiscoverFilter? Function(BookSource) filterFor;
  final Map<String, Map<String, String>> selections;
  @override
  State<DiscoverFilterDialog> createState() => _DiscoverFilterDialogState();
}

class _DiscoverFilterDialogState extends State<DiscoverFilterDialog> {
  late BookSource? _source = widget.source ?? widget.sources.firstOrNull;
  final Map<String, Map<String, String>> _drafts = {};
  BookDiscoverFilter? get _filter =>
      _source == null ? null : _safeFilter(_source!);
  BookDiscoverFilter? _safeFilter(BookSource source) {
    try {
      return widget.filterFor(source);
    } on Object {
      return null;
    }
  }

  Map<String, String> get _selection => _source == null
      ? {}
      : _drafts.putIfAbsent(
          _source!.id,
          () => {...?_filter?.defaults, ...?widget.selections[_source!.id]},
        );

  Future<void> _pick(BookDiscoverFilterGroup group) async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => DiscoverChoiceDialog<String>(
        title: group.name,
        options: [for (final option in group.options) option.title],
        labelFor: (title) => title,
        selected: _selection[group.name],
      ),
    );
    if (selected != null && mounted) {
      setState(() => _selection[group.name] = selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filter = _filter;
    final theme = Theme.of(context);
    return AlertDialog(
      key: const ValueKey('discover-filter-dialog'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      title: Row(
        children: [
          const Expanded(child: Text('筛选管理')),
          if (_source != null)
            Flexible(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _source!.id,
                  isDense: true,
                  icon: const AppIcon(
                    AppGlyph.chevronDown,
                    key: ValueKey('discover-source-arrow'),
                    size: 18,
                  ),
                  style: theme.textTheme.bodyMedium,
                  selectedItemBuilder: (context) => [
                    for (final source in widget.sources)
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 120),
                        child: Text(
                          source.name,
                          key: ValueKey('discover-source-name-${source.id}'),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  items: [
                    for (final source in widget.sources)
                      DropdownMenuItem(
                        value: source.id,
                        child: Text(
                          source.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (id) => setState(
                    () => _source = widget.sources.firstWhere(
                      (source) => source.id == id,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '筛选条件',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              if (filter == null)
                const Text('当前书源不支持组合筛选')
              else
                for (final group in filter.groups)
                  InkWell(
                    key: ValueKey('discover-filter-${group.name}'),
                    onTap: () => _pick(group),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Expanded(child: Text(group.name)),
                            Expanded(
                              flex: 2,
                              child: Text(
                                _selection[group.name] ??
                                    group.options.first.title,
                                textAlign: TextAlign.end,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            const AppIcon(AppGlyph.chevronRight, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      actions: [
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: filter == null
                    ? null
                    : () => setState(
                        () => _drafts[_source!.id] = filter.defaults,
                      ),
                child: const Text('重置'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _source == null
                    ? null
                    : () => Navigator.of(context).pop((
                        source: _source!,
                        selection: Map<String, String>.from(_selection),
                        category: filter?.category(_selection),
                      )),
                child: const Text('应用'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
