import 'package:flutter/material.dart';
import 'package:reader_core/api.dart';
import 'package:reader_core/position/cfi.dart';

import '../decorations/decoration.dart';

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
    return Material(
      color: Theme.of(context).colorScheme.surface,
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
              icon: const Icon(Icons.sort),
              itemBuilder: (_) => [
                CheckedPopupMenuItem(
                  value: false,
                  checked: !_readingOrder,
                  child: const Text('最近更新'),
                ),
                CheckedPopupMenuItem(
                  value: true,
                  checked: _readingOrder,
                  child: const Text('阅读顺序'),
                ),
              ],
            ),
          ),
          ListTile(
            key: const ValueKey<String>('decoration-rules-entry'),
            leading: const Icon(Icons.auto_fix_high_outlined),
            title: const Text('自动装饰规则'),
            subtitle: Text(
              widget.ruleCount == 0
                  ? '暂无规则'
                  : '${widget.ruleCount} 条规则 · ${widget.rulesEnabled ? '已启用' : '未启用'}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: widget.onRules,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              key: const ValueKey<String>('decoration-search'),
              controller: _search,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: '搜索原文、章节或样式',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清除搜索',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
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
