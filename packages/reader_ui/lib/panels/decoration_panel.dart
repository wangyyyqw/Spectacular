import 'package:flutter/material.dart';
import 'package:reader_core/api.dart';
import 'package:reader_core/position/cfi.dart';

import '../decorations/decoration.dart';
import '../icons/app_icon.dart';
import '../theme/reader_frosted_surface.dart';
import '../theme/reader_drawer_style.dart';

/// 只管理手工装饰的抽屉页签。
class ReaderDecorationPanel extends StatefulWidget {
  /// 创建装饰管理列表。
  const ReaderDecorationPanel({
    super.key,
    required this.decorations,
    required this.toc,
    required this.onSelect,
    required this.onEdit,
    required this.onRemove,
    required this.onRules,
    this.ruleCount = 0,
    this.rulesEnabled = true,
  });

  /// 本书手工装饰。
  final List<ReaderDecoration> decorations;

  /// 章节目录。
  final List<TocEntry> toc;

  /// 跳转或关联待修复装饰。
  final ValueChanged<ReaderDecoration> onSelect;

  /// 打开编辑器。
  final ValueChanged<ReaderDecoration> onEdit;

  /// 删除装饰，确认由调用方执行。
  final ValueChanged<ReaderDecoration> onRemove;

  /// 打开自动装饰规则。
  final VoidCallback onRules;

  /// 当前可见作用域的规则数。
  final int ruleCount;

  /// 是否有启用的规则。
  final bool rulesEnabled;
  @override
  State<ReaderDecorationPanel> createState() => _ReaderDecorationPanelState();
}

class _ReaderDecorationPanelState extends State<ReaderDecorationPanel> {
  final _search = TextEditingController();
  String _query = '';
  bool _readingOrder = false;
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _chapter(ReaderDecoration decoration) {
    final cfi = EpubCfi.parse(decoration.startCfi);
    final spine = cfi == null ? null : spineIndexOfCfi(cfi);
    if (spine == null) return '位置待确认';
    final entries = flattenToc(widget.toc)
        .map((row) => row.entry)
        .where((entry) => entry.spineIndex == spine);
    final preceding = entries
        .where((entry) => entry.cfi == null || entry.cfi!.compareTo(cfi!) <= 0)
        .toList();
    return preceding.lastOrNull?.title ??
        entries.firstOrNull?.title ??
        '第 ${spine + 1} 章';
  }

  List<ReaderDecoration> get _items {
    final query = _query.trim().toLowerCase();
    final items = widget.decorations
        .where(
          (item) =>
              query.isEmpty ||
              item.quote.toLowerCase().contains(query) ||
              _chapter(item).toLowerCase().contains(query) ||
              item.style.summary.toLowerCase().contains(query),
        )
        .toList();
    items.sort((left, right) {
      if (_readingOrder) {
        final leftCfi = EpubCfi.parse(left.startCfi);
        final rightCfi = EpubCfi.parse(right.startCfi);
        if (leftCfi != null && rightCfi != null) {
          final result = leftCfi.compareTo(rightCfi);
          if (result != 0) return result;
        }
      }
      return right.updatedAt.compareTo(left.updatedAt);
    });
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final theme = Theme.of(context);
    final muted = ReaderDrawerStyle.mutedOf(theme);
    final searchBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(20),
      borderSide: BorderSide.none,
    );
    final searchStyle = theme.textTheme.bodyMedium!.copyWith(
      fontSize: 14,
      height: 1.5,
      fontWeight: FontWeight.w400,
      color: ReaderDrawerStyle.textOf(theme),
    );
    return Material(
      color: ReaderFrostedSurface.panelColorOf(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            title: const Text('装饰'),
            subtitle: Text('共 ${widget.decorations.length} 条手工装饰'),
            trailing: PopupMenuButton<bool>(
              key: const ValueKey<String>('decoration-sort'),
              tooltip: '装饰排序',
              initialValue: _readingOrder,
              onSelected: (value) => setState(() => _readingOrder = value),
              icon: const AppIcon(AppGlyph.sort),
              itemBuilder: (_) => [
                appCheckedMenuItem(
                  value: false,
                  checked: !_readingOrder,
                  child: const Text('最近更新'),
                ),
                appCheckedMenuItem(
                  value: true,
                  checked: _readingOrder,
                  child: const Text('阅读顺序'),
                ),
              ],
            ),
          ),
          ListTile(
            key: const ValueKey<String>('decoration-rules-entry'),
            leading: const AppIcon(AppGlyph.autoFix),
            title: const Text('自动装饰规则'),
            subtitle: Text(
              widget.ruleCount == 0
                  ? '暂无规则'
                  : '${widget.ruleCount} 条规则 · ${widget.rulesEnabled ? '已启用' : '未启用'}',
            ),
            trailing: const AppIcon(AppGlyph.chevronRight),
            onTap: widget.onRules,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 10, 24, 12),
            child: Material(
              key: const ValueKey('decoration-search-surface'),
              color: ReaderDrawerStyle.searchSurfaceOf(theme),
              borderRadius: searchBorder.borderRadius,
              elevation: 3,
              surfaceTintColor: Colors.transparent,
              shadowColor: ReaderDrawerStyle.searchShadowOf(theme),
              child: TextField(
                key: const ValueKey<String>('decoration-search'),
                controller: _search,
                onChanged: (value) => setState(() => _query = value),
                textInputAction: TextInputAction.search,
                style: searchStyle,
                cursorColor: ReaderDrawerStyle.textOf(theme),
                decoration: InputDecoration(
                  hintText: '搜索原文、章节或样式',
                  hintStyle: searchStyle.copyWith(color: muted),
                  isDense: true,
                  filled: true,
                  fillColor: ReaderDrawerStyle.searchSurfaceOf(theme),
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  border: searchBorder,
                  enabledBorder: searchBorder,
                  focusedBorder: searchBorder,
                  prefixIconConstraints: const BoxConstraints.tightFor(
                    width: 40,
                    height: 40,
                  ),
                  suffixIconConstraints: const BoxConstraints.tightFor(
                    width: 40,
                    height: 40,
                  ),
                  prefixIcon: AppIcon(AppGlyph.search, size: 20, color: muted),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清除搜索',
                          icon: AppIcon(AppGlyph.close, size: 18, color: muted),
                          onPressed: () {
                            _search.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          Expanded(
            child: items.isEmpty
                ? Center(child: Text(_query.isEmpty ? '还没有手工装饰' : '没有匹配的装饰'))
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) =>
                        _card(context, items[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, ReaderDecoration item) => Card(
    margin: EdgeInsets.zero,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(4),
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: ListTile(
      key: ValueKey<String>('decoration-row-${item.id}'),
      contentPadding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
      onTap: () => widget.onSelect(item),
      title: Text(item.quote, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.needsRelocation)
            Text(
              '待修复 · 点击关联原文',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 6),
          Text(
            item.style.summary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            '${_chapter(item)} · ${_time(item.updatedAt)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      trailing: PopupMenuButton<String>(
        icon: const AppIcon(AppGlyph.more),
        key: ValueKey<String>('decoration-actions-${item.id}'),
        tooltip: '管理装饰',
        onSelected: (value) =>
            value == 'edit' ? widget.onEdit(item) : widget.onRemove(item),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'edit', child: Text('编辑装饰')),
          PopupMenuItem(value: 'remove', child: Text('删除装饰')),
        ],
      ),
    ),
  );

  String _time(DateTime time) {
    final local = time.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }
}
