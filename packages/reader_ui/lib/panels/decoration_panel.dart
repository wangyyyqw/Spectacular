import 'package:flutter/material.dart';

import '../theme/reader_ui_style.dart';

import 'package:reader_core/api.dart';
import 'package:reader_core/position/cfi.dart';

import '../decorations/decoration.dart';
import '../icons/app_icon.dart';
import '../theme/reader_common_widgets.dart';
import '../theme/reader_frosted_surface.dart';
import '../theme/reader_ink.dart';

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

  List<ReaderDecoration> get _items =>
      List<ReaderDecoration>.of(widget.decorations)
        ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Material(
      color: ReaderFrostedSurface.panelColorOf(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            key: const ValueKey<String>('decoration-rules-entry'),
            leading: const AppIcon(AppGlyph.autoFix),
            title: const Text('规则'),
            subtitle: Text(
              widget.ruleCount == 0
                  ? '暂无规则'
                  : '${widget.ruleCount} 条规则 · ${widget.rulesEnabled ? '已启用' : '未启用'}',
            ),
            trailing: const AppIcon(AppGlyph.chevronRight),
            onTap: widget.onRules,
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          Expanded(
            child: Theme(
              // 装饰列表行不显示点击高亮与水波。
              data: quietInk(Theme.of(context)),
              child: items.isEmpty
                  ? const ReaderEmptyState(
                      icon: AppGlyph.formatPaint,
                      title: '还没有手工装饰',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) =>
                          _card(context, items[index]),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, ReaderDecoration item) => Card(
    margin: EdgeInsets.zero,
    elevation: 0,
    shape: ReaderUiStyle.cardShapeOf(Theme.of(context)),
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
