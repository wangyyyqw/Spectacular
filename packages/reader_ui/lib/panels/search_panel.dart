import 'dart:async';

import 'package:flutter/material.dart';

import '../icons/app_icon.dart';

/// 一条搜索结果的展示模型（P4-26，§29.4）。
class SearchPanelResult {
  /// 创建结果。
  const SearchPanelResult({
    required this.spineIndex,
    required this.charOffset,
    required this.chapterTitle,
    required this.context,
    required this.matchLength,
    this.cfi,
  });

  /// 章节序号（分组用）。
  final int spineIndex;

  /// 章内字符偏移。
  final int charOffset;

  /// 章名。
  final String chapterTitle;

  /// 上下文片段（前 12 + 命中 + 后 12）。
  final String context;

  /// 命中词长度。
  final int matchLength;

  /// 命中位置 CFI（跳转用）。
  final String? cfi;
}

/// 搜索结果面板（P4-26）：输入防抖、按章分组、空态与加载态。
/// 流式搜索的一次进度快照（搜到就推，UI 逐批渲染）。
class SearchProgress {
  /// 创建快照。
  const SearchProgress({
    required this.results,
    required this.scanned,
    required this.total,
  });

  /// 当前累计结果。
  final List<SearchPanelResult> results;

  /// 已扫描章数。
  final int scanned;

  /// 章节总数。
  final int total;
}

class SearchPanel extends StatefulWidget {
  /// 创建面板。
  const SearchPanel({
    super.key,
    required this.onSearch,
    this.onSearchStream,
    required this.onSelect,
    this.onBack,
    this.debounce = const Duration(milliseconds: 300),
  });

  /// 查询回调（一次性返回全部结果）。
  final Future<List<SearchPanelResult>> Function(String query) onSearch;

  /// 流式查询回调：逐章推进结果，优先于 [onSearch]。
  final Stream<SearchProgress> Function(String query)? onSearchStream;

  /// 选中结果。
  final ValueChanged<SearchPanelResult> onSelect;

  /// 返回（嵌在菜单 sheet 内时显示）。
  final VoidCallback? onBack;

  /// 输入防抖时长（§29.4 建议 300ms）。
  final Duration debounce;

  @override
  State<SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends State<SearchPanel> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounceTimer;
  String _query = '';
  bool _loading = false;
  int _scanned = 0;
  int _total = 0;
  List<SearchPanelResult> _results = const <SearchPanelResult>[];
  Object? _error;
  int _requestToken = 0;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounceTimer?.cancel();
    _requestToken += 1;
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _query = '';
        _results = const <SearchPanelResult>[];
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() => _loading = true);
    _debounceTimer = Timer(widget.debounce, () => unawaited(_run(query)));
  }

  Future<void> _run(String query) async {
    final token = ++_requestToken;
    final stream = widget.onSearchStream;
    if (stream != null) {
      await _runStream(stream, query, token);
      return;
    }
    try {
      final results = await widget.onSearch(query);
      if (!mounted || token != _requestToken) {
        return;
      }
      setState(() {
        _query = query;
        _results = results;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || token != _requestToken) {
        return;
      }
      setState(() {
        _query = query;
        _results = const <SearchPanelResult>[];
        _loading = false;
        _error = error;
      });
    }
  }

  /// 流式执行：每来一批就刷新列表，扫完才收 loading。
  Future<void> _runStream(
    Stream<SearchProgress> Function(String query) stream,
    String query,
    int token,
  ) async {
    setState(() {
      _query = query;
      _results = const <SearchPanelResult>[];
      _scanned = 0;
      _total = 0;
      _error = null;
      _loading = true;
    });
    try {
      await for (final batch in stream(query)) {
        if (!mounted || token != _requestToken) {
          return;
        }
        final finished = batch.scanned >= batch.total || batch.total == 0;
        setState(() {
          _query = query;
          _results = batch.results;
          _scanned = batch.scanned;
          _total = batch.total;
          _loading = !finished;
        });
      }
      if (mounted && token == _requestToken) {
        setState(() => _loading = false);
      }
    } catch (error) {
      if (!mounted || token != _requestToken) {
        return;
      }
      setState(() {
        _query = query;
        _loading = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
            child: Row(
              children: [
                if (widget.onBack != null)
                  IconButton(
                    key: const ValueKey<String>('search-back'),
                    icon: const AppIcon(AppGlyph.arrowBack, size: 20),
                    onPressed: widget.onBack,
                    tooltip: '返回',
                  ),
                Expanded(
                  child: TextField(
                    key: const ValueKey<String>('search-input'),
                    controller: _controller,
                    autofocus: true,
                    onChanged: _onChanged,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: '搜索本书内容',
                      isDense: true,
                      prefixIcon: const AppIcon(AppGlyph.search, size: 20),
                      suffixIcon: _controller.text.isEmpty
                          ? null
                          : IconButton(
                              key: const ValueKey<String>('search-clear'),
                              icon: const AppIcon(AppGlyph.close, size: 18),
                              onPressed: () {
                                _controller.clear();
                                _onChanged('');
                              },
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildBody(theme)),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_controller.text.trim().isEmpty) {
      return _hint(theme, '输入关键词搜索全书', icon: AppGlyph.search);
    }
    if (_loading && _results.isEmpty) {
      return Center(
        key: const ValueKey<String>('search-loading'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            if (_total > 0) ...[
              const SizedBox(height: 12),
              Text(
                '正在搜索 $_scanned/$_total 章…',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      );
    }
    if (_error != null) {
      return _hint(theme, '搜索失败：$_error', icon: AppGlyph.error);
    }
    if (_results.isEmpty) {
      return _hint(theme, '没有找到「$_query」', icon: AppGlyph.searchOff);
    }
    final list = _buildResults(theme);
    if (!_loading) {
      return list;
    }
    return Column(
      children: <Widget>[
        LinearProgressIndicator(
          key: const ValueKey<String>('search-progress'),
          value: _total > 0 ? _scanned / _total : null,
          minHeight: 2,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Row(
            children: <Widget>[
              Text(
                '已找到 ${_results.length} 处',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              const Spacer(),
              Text(
                '$_scanned/$_total 章',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        Expanded(child: list),
      ],
    );
  }

  Widget _hint(ThemeData theme, String text, {required AppGlyph icon}) {
    return Center(
      key: const ValueKey<String>('search-empty'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(icon, size: 40, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          Text(text, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }

  /// 按章分组的结果列表（§29.4：章名 + 命中上下文）：
  /// 100 条结果用 ListView.builder 懒构建，滚动不卡。
  Widget _buildResults(ThemeData theme) {
    final groups = <int, List<SearchPanelResult>>{};
    for (final result in _results) {
      groups.putIfAbsent(result.spineIndex, () => <SearchPanelResult>[]).add(
        result,
      );
    }
    final rows = <Object>[];
    for (final entry in groups.entries) {
      final title = entry.value.first.chapterTitle.isEmpty
          ? '第 ${entry.key + 1} 章'
          : entry.value.first.chapterTitle;
      rows.add('$title · ${entry.value.length} 处');
      rows.addAll(entry.value);
    }
    return ListView.builder(
      key: const ValueKey<String>('search-results'),
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        if (row is String) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Text(
              row,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          );
        }
        final result = row as SearchPanelResult;
        return ListTile(
          key: ValueKey<String>('search-hit-${result.spineIndex}-'
              '${result.charOffset}'),
          dense: true,
          title: Text.rich(
            _contextSpan(theme, result),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => widget.onSelect(result),
        );
      },
    );
  }

  /// 上下文里高亮命中词（§29.4）。
  TextSpan _contextSpan(ThemeData theme, SearchPanelResult result) {
    final context = result.context;
    final start = _query.isEmpty ? -1 : context.indexOf(_query);
    final base = theme.textTheme.bodyMedium;
    if (start < 0) {
      return TextSpan(text: context, style: base);
    }
    final end = start + _query.length;
    return TextSpan(
      style: base,
      children: [
        TextSpan(text: context.substring(0, start)),
        TextSpan(
          text: context.substring(start, end),
          style: base?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        TextSpan(text: context.substring(end)),
      ],
    );
  }
}
