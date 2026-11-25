import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reader_core/position/cfi.dart';

import '../icons/app_icon.dart';
import '../theme/reader_drawer_style.dart';
import '../theme/reader_ui_style.dart';

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
    this.focusNode,
    this.currentSpineIndex = 0,
    this.currentCfi,
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

  final FocusNode? focusNode;

  /// 打开搜索时的阅读位置，用于结果列表初始定位。
  final int currentSpineIndex;
  final String? currentCfi;

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
  final Set<int> _collapsedChapters = <int>{};
  final ScrollController _resultsController = ScrollController();
  final Key _resultsCenter = UniqueKey();

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    _resultsController.dispose();
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
    _collapsedChapters.clear();
    if (_resultsController.hasClients) _resultsController.jumpTo(0);
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

  TextStyle _textStyle(ThemeData theme) => theme.textTheme.bodyMedium!.copyWith(
    fontSize: 14,
    height: 1.5,
    fontWeight: FontWeight.w400,
    color: ReaderDrawerStyle.textOf(theme),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = ReaderDrawerStyle.mutedOf(theme);
    final border = OutlineInputBorder(
      borderRadius: ReaderUiStyle.controlRadius,
      borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
    );
    return Material(
      color: ReaderDrawerStyle.surfaceOf(theme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 10, 24, 12),
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
                  child: Material(
                    key: const ValueKey('search-input-surface'),
                    color: ReaderDrawerStyle.searchSurfaceOf(theme),
                    borderRadius: border.borderRadius,
                    elevation: 0,
                    surfaceTintColor: Colors.transparent,
                    child: TextField(
                      key: const ValueKey<String>('search-input'),
                      controller: _controller,
                      focusNode: widget.focusNode,
                      autofocus: true,
                      onChanged: _onChanged,
                      textInputAction: TextInputAction.search,
                      style: _textStyle(theme),
                      cursorColor: ReaderDrawerStyle.textOf(theme),
                      decoration: InputDecoration(
                        hintText: '搜索本书内容',
                        hintStyle: _textStyle(theme).copyWith(color: muted),
                        isDense: true,
                        filled: true,
                        fillColor: ReaderDrawerStyle.searchSurfaceOf(theme),
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        border: border,
                        enabledBorder: border,
                        focusedBorder: border.copyWith(
                          borderSide: BorderSide(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        prefixIconConstraints: const BoxConstraints.tightFor(
                          width: 40,
                          height: 40,
                        ),
                        suffixIconConstraints: const BoxConstraints.tightFor(
                          width: 40,
                          height: 40,
                        ),
                        prefixIcon: AppIcon(
                          AppGlyph.search,
                          size: 20,
                          color: muted,
                        ),
                        suffixIcon: _controller.text.isEmpty
                            ? null
                            : IconButton(
                                key: const ValueKey<String>('search-clear'),
                                icon: AppIcon(
                                  AppGlyph.close,
                                  size: 18,
                                  color: muted,
                                ),
                                onPressed: () {
                                  _controller.clear();
                                  _onChanged('');
                                },
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
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
            CircularProgressIndicator(
              color: ReaderDrawerStyle.mutedOf(theme),
              strokeWidth: 2,
            ),
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
          color: ReaderDrawerStyle.mutedOf(theme),
          backgroundColor: ReaderDrawerStyle.optionBorderOf(theme),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 10, 24, 0),
          child: Row(
            children: <Widget>[
              Text(
                '已找到 ${_results.length} 处',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ReaderDrawerStyle.mutedOf(theme),
                ),
              ),
              const Spacer(),
              Text('$_scanned/$_total 章', style: theme.textTheme.bodySmall),
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(icon, size: 28, color: ReaderDrawerStyle.faintOf(theme)),
            const SizedBox(height: 16),
            Text(
              text,
              textAlign: TextAlign.center,
              style: _textStyle(
                theme,
              ).copyWith(fontSize: 14, color: ReaderDrawerStyle.mutedOf(theme)),
            ),
          ],
        ),
      ),
    );
  }

  /// 按章分组的结果列表（§29.4：章名 + 命中上下文）：
  /// 100 条结果用 ListView.builder 懒构建，滚动不卡。
  Widget _buildResults(ThemeData theme) {
    final groups = <int, List<SearchPanelResult>>{};
    for (final result in _results) {
      groups
          .putIfAbsent(result.spineIndex, () => <SearchPanelResult>[])
          .add(result);
    }
    final rows = <Object>[];
    final chapters = groups.keys.toList()..sort();
    final current = widget.currentCfi == null
        ? null
        : EpubCfi.parse(widget.currentCfi!);
    bool atOrAfter(SearchPanelResult result) {
      if (result.spineIndex != widget.currentSpineIndex) {
        return result.spineIndex > widget.currentSpineIndex;
      }
      final cfi = result.cfi == null ? null : EpubCfi.parse(result.cfi!);
      if (current != null && cfi != null) return cfi.compareTo(current) >= 0;
      return result.charOffset >= (current?.charOffset ?? 0);
    }

    for (final chapter in chapters) {
      final hits = groups[chapter]!
        ..sort((a, b) => a.charOffset.compareTo(b.charOffset));
      rows.add(chapter);
      rows.addAll(hits);
    }
    var start = rows.indexWhere(
      (row) => row is SearchPanelResult && atOrAfter(row),
    );
    if (start < 0) {
      start = rows.indexWhere(
        (row) => row is int && row >= widget.currentSpineIndex,
      );
    }
    if (start < 0) start = rows.length - 1;
    // 位于章首时同时显示章标题；章内则从阅读位置之后的首条命中开始。
    if (start > 0 && rows[start - 1] is int) start -= 1;
    bool visible(Object row) =>
        row is int ||
        !_collapsedChapters.contains((row as SearchPanelResult).spineIndex);
    final before = rows.take(start).where(visible).toList().reversed.toList();
    final after = rows.skip(start).where(visible).toList();

    Widget buildRow(Object row) {
      if (row is int) {
        final hits = groups[row]!;
        final title = hits.first.chapterTitle.isEmpty
            ? '第 ${row + 1} 章'
            : hits.first.chapterTitle;
        final collapsed = _collapsedChapters.contains(row);
        return Padding(
          padding: const EdgeInsets.only(left: 22, right: 24),
          child: ListTile(
            key: ValueKey('search-chapter-$row'),
            minTileHeight: 40,
            minVerticalPadding: 4,
            contentPadding: EdgeInsets.zero,
            leading: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: ReaderDrawerStyle.faintOf(theme),
                shape: BoxShape.circle,
              ),
            ),
            horizontalTitleGap: 12,
            minLeadingWidth: 8,
            title: Text('$title · ${hits.length} 处', style: _textStyle(theme)),
            trailing: AppIcon(
              collapsed ? AppGlyph.chevronUp : AppGlyph.chevronDown,
              size: 14,
              color: ReaderDrawerStyle.mutedOf(theme),
            ),
            onTap: () => setState(() {
              if (!_collapsedChapters.add(row)) _collapsedChapters.remove(row);
            }),
          ),
        );
      }
      final result = row as SearchPanelResult;
      return Padding(
        padding: const EdgeInsets.only(left: 58, right: 24),
        child: ListTile(
          key: ValueKey<String>(
            'search-hit-${result.spineIndex}-${result.charOffset}',
          ),
          minTileHeight: 40,
          minVerticalPadding: 6,
          contentPadding: EdgeInsets.zero,
          title: Text.rich(
            _contextSpan(theme, result),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => widget.onSelect(result),
        ),
      );
    }

    // 两个 Sliver 共用阅读位置原点，之前的结果向上生长，之后的结果向下生长。
    return CustomScrollView(
      key: const ValueKey<String>('search-results'),
      controller: _resultsController,
      center: _resultsCenter,
      slivers: [
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => buildRow(before[index]),
            childCount: before.length,
          ),
        ),
        SliverList(
          key: _resultsCenter,
          delegate: SliverChildBuilderDelegate(
            (context, index) => buildRow(after[index]),
            childCount: after.length,
          ),
        ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 16)),
      ],
    );
  }

  /// 上下文里高亮命中词（§29.4）。
  TextSpan _contextSpan(ThemeData theme, SearchPanelResult result) {
    // 仅折叠展示空白，避免正文换行占满两行；保留结果中的原始定位信息。
    final whitespace = RegExp(r'\s+');
    final context = result.context.replaceAll(whitespace, ' ').trim();
    final query = _query.replaceAll(whitespace, ' ').trim();
    final start = query.isEmpty ? -1 : context.indexOf(query);
    final base = _textStyle(theme);
    if (start < 0) {
      return TextSpan(text: context, style: base);
    }
    final end = start + query.length;
    return TextSpan(
      style: base,
      children: [
        TextSpan(text: context.substring(0, start)),
        TextSpan(
          text: context.substring(start, end),
          style: base.copyWith(
            color: ReaderDrawerStyle.textOf(theme),
            fontWeight: FontWeight.w600,
          ),
        ),
        TextSpan(text: context.substring(end)),
      ],
    );
  }
}
