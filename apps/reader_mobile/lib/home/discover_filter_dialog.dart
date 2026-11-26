import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reader_ui/theme/reader_ui_style.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';

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
  final FutureOr<BookDiscoverFilter?> Function(BookSource) filterFor;
  final Map<String, Map<String, String>> selections;
  @override
  State<DiscoverFilterDialog> createState() => _DiscoverFilterDialogState();
}

class _DiscoverFilterDialogState extends State<DiscoverFilterDialog> {
  late BookSource? _source = widget.source ?? widget.sources.firstOrNull;
  final Map<String, Map<String, String>> _drafts = {};
  BookDiscoverFilter? _filter;
  bool _loading = false;
  String? _error;
  int _version = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadFilter());
  }

  Future<void> _loadFilter() async {
    final source = _source;
    if (source == null) return;
    final version = ++_version;
    setState(() {
      _filter = null;
      _loading = true;
      _error = null;
    });
    try {
      final filter = await widget.filterFor(source);
      if (!mounted || version != _version) return;
      setState(() {
        _filter = filter;
        _loading = false;
      });
    } on Object {
      if (!mounted || version != _version) return;
      setState(() {
        _loading = false;
        _error = '分类加载失败，点击重试';
      });
    }
  }

  Map<String, String> get _selection => _source == null
      ? {}
      : _drafts.putIfAbsent(
          _source!.id,
          () => {...?_filter?.defaults, ...?widget.selections[_source!.id]},
        );

  Future<void> _pick(BookDiscoverFilterGroup group) async {
    final selected = await showReaderDialog<String>(
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

  Future<void> _pickSource() async {
    final source = await showReaderDialog<BookSource>(
      context: context,
      builder: (_) => DiscoverChoiceDialog<BookSource>(
        title: '切换书源',
        options: widget.sources,
        labelFor: (source) => source.name,
      ),
    );
    if (!mounted || source == null || source.id == _source?.id) return;
    setState(() => _source = source);
    unawaited(_loadFilter());
  }

  @override
  Widget build(BuildContext context) {
    final filter = _filter;
    final theme = Theme.of(context);
    return ReaderFrostedAlertDialog(
      key: const ValueKey('discover-filter-dialog'),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      title: Row(
        children: [
          const Expanded(child: Text('筛选管理')),
          if (_source != null)
            Flexible(
              child: Align(
                alignment: Alignment.centerRight,
                child: Tooltip(
                  message: '切换书源',
                  child: InkWell(
                    borderRadius: ReaderUiStyle.controlRadiusOf(
                      Theme.of(context),
                    ),
                    onTap: _pickSource,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              _source!.name,
                              key: ValueKey(
                                'discover-source-name-${_source!.id}',
                              ),
                              style: theme.textTheme.bodyMedium,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const AppIcon(
                            AppGlyph.chevronDown,
                            key: ValueKey('discover-source-arrow'),
                            size: 18,
                          ),
                        ],
                      ),
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
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 12),
                      Text('正在加载分类…'),
                    ],
                  ),
                )
              else if (_error != null)
                TextButton(onPressed: _loadFilter, child: Text(_error!))
              else if (filter == null)
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
              child: OutlinedButton(
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
