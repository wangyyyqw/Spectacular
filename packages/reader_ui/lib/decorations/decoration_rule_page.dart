import 'package:flutter/material.dart';

import '../reader_ui_diagnostics.dart';

import '../annotations/text_value_dialog.dart';

import '../icons/app_icon.dart';
import 'decoration_rule_editor.dart';
import 'decoration_rule_preview.dart';
import 'decoration_rules.dart';
import 'decoration_image_store.dart';
import 'decoration_highlight.dart';
import 'decoration_rule_defaults.dart';
import '../panels/settings_panel.dart' show ReaderFontOption;
import '../theme/reader_frosted_popup.dart';

/// 本书与全局作用域的自动装饰规则管理页。
class ReaderDecorationRulePage extends StatefulWidget {
  /// 创建规则管理页。
  const ReaderDecorationRulePage({
    super.key,
    required this.store,
    required this.bookId,
    required this.onPreview,
    this.errors = const {},
    this.images,
    this.inkMode = false,
    this.fonts = const [],
  });

  /// 规则持久化接口。
  final ReaderDecorationRuleStore store;

  /// 当前书籍 UUID。
  final String bookId;

  /// 当前章的临时预览。
  final Future<List<ReaderDecorationRulePreview>> Function(ReaderDecorationRule)
  onPreview;

  /// 本次会话被跳过的规则及原因。
  final Map<String, String> errors;
  final ReaderDecorationImageStore? images;
  final bool inkMode;
  final List<ReaderFontOption> fonts;
  @override
  State<ReaderDecorationRulePage> createState() =>
      _ReaderDecorationRulePageState();
}

class _ReaderDecorationRulePageState extends State<ReaderDecorationRulePage> {
  List<ReaderDecorationRuleGroup> _groups = const [];
  List<ReaderDecorationRule> _rules = const [];
  bool _global = false;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<ReaderDecorationNamedStyle> _styles = readerDecorationBuiltInStyles;
  Set<String>? _globalSelection;
  @override
  void initState() {
    super.initState();
    _load();
  }

  String? get _scope => _global ? null : widget.bookId;

  Future<void> _load() async {
    try {
      final groups = await widget.store.listGroups();
      final rules = await widget.store.listRules();
      final prefs = widget.store;
      final styles = prefs is ReaderDecorationRulePreferences
          ? await (prefs as ReaderDecorationRulePreferences).listStyles()
          : readerDecorationBuiltInStyles;
      final selection = prefs is ReaderDecorationRulePreferences
          ? await (prefs as ReaderDecorationRulePreferences)
                .loadGlobalRuleSelection()
          : null;
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _rules = rules;
        _styles = styles;
        _globalSelection = selection;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '规则读取失败，请重试';
        });
      }
    }
  }

  Future<void> _operate(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await _load();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FormatException ? error.message : '操作失败，请重试',
        );
        ReaderUiDiagnostics.record(
          'decoration_rule_operation_failed',
          error: error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<ReaderDecorationRuleGroup> get _scopeGroups =>
      _groups.where((group) => group.bookId == _scope).toList()..sort(
        (left, right) => left.isDefault != right.isDefault
            ? left.isDefault
                  ? 1
                  : -1
            : left.sortOrder.compareTo(right.sortOrder),
      );
  List<ReaderDecorationRule> _groupRules(String groupId) =>
      _rules.where((rule) => rule.groupId == groupId).toList()
        ..sort((left, right) => left.sortOrder.compareTo(right.sortOrder));

  Future<String?> _groupName([ReaderDecorationRuleGroup? group]) =>
      showReaderDialog<String>(
        context: context,
        builder: (_) => ReaderTextValueDialog(
          title: group == null ? '新建规则分组' : '重命名分组',
          label: '分组名称',
          initialValue: group?.name ?? '',
          validate: (value) => value.isEmpty ? '请输入分组名称' : null,
        ),
      );

  Future<void> _addGroup() async {
    final name = await _groupName();
    if (name == null || !mounted) return;
    final orders =
        _scopeGroups
            .where((group) => !group.isDefault)
            .map((group) => group.sortOrder)
            .toList()
          ..sort();
    await _operate(
      () => widget.store.saveGroup(
        ReaderDecorationRuleGroup(
          id: 'group-${DateTime.now().microsecondsSinceEpoch}',
          bookId: _scope,
          name: name,
          sortOrder: (orders.lastOrNull ?? -1) + 1,
        ),
      ),
    );
  }

  Future<void> _rename(ReaderDecorationRuleGroup group) async {
    final name = await _groupName(group);
    if (name != null && mounted) {
      await _operate(() => widget.store.saveGroup(group.copyWith(name: name)));
    }
  }

  Future<void> _deleteGroup(ReaderDecorationRuleGroup group) async {
    final confirmed = await _confirm(
      '删除分组“${group.name}”？',
      '组内规则会移入同作用域的默认组末尾，不会丢失。',
    );
    if (confirmed && mounted) {
      await _operate(() => widget.store.removeGroup(group.id));
    }
  }

  Future<void> _editRule(
    ReaderDecorationRuleGroup group, [
    ReaderDecorationRule? rule,
  ]) async {
    final rules = _groupRules(group.id);
    final initial =
        rule ??
        ReaderDecorationRule(
          id: 'rule-${DateTime.now().microsecondsSinceEpoch}',
          groupId: group.id,
          pattern: '',
          style: const ReaderDecorationRuleStyle(
            highlight: ReaderDecorationHighlight(),
          ),
          sortOrder: (rules.lastOrNull?.sortOrder ?? -1) + 1,
        );
    final next = await showReaderBottomSheet<ReaderDecorationRule>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ReaderDecorationRuleEditor(
        rule: initial,
        onPreview: widget.onPreview,
        images: widget.images,
        inkMode: widget.inkMode,
        fonts: widget.fonts,
        styles: _styles,
      ),
    );
    if (next != null && mounted) {
      await _operate(() => widget.store.saveRule(next));
    } else if (mounted) {
      setState(() {});
    }
  }

  Future<void> _deleteRule(ReaderDecorationRule rule) async {
    if (await _confirm('删除这条规则？', '规则命中的原文不会被删除，装饰效果会停止应用。') && mounted) {
      await _operate(() => widget.store.removeRule(rule.id));
    }
  }

  Future<bool> _confirm(String title, String content) async =>
      await showReaderDialog<bool>(
        context: context,
        builder: (context) => ReaderFrostedAlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除'),
            ),
          ],
        ),
      ) ??
      false;

  void _reorderGroups(int oldIndex, int newIndex) {
    final groups = _scopeGroups;
    if (_busy || groups[oldIndex].isDefault) return;
    final moved = groups.removeAt(oldIndex);
    final defaultIndex = groups.indexWhere((group) => group.isDefault);
    groups.insert(
      newIndex.clamp(0, defaultIndex < 0 ? groups.length : defaultIndex),
      moved,
    );
    _operate(
      () =>
          widget.store.reorderGroups(groups.map((group) => group.id).toList()),
    );
  }

  void _reorderRules(String groupId, int oldIndex, int newIndex) {
    if (_busy) return;
    final rules = _groupRules(groupId);
    rules.insert(newIndex, rules.removeAt(oldIndex));
    _operate(
      () => widget.store.reorderRules(
        groupId,
        rules.map((rule) => rule.id).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groups = _scopeGroups;
    return Scaffold(
      appBar: AppBar(
        title: const Text('自动装饰规则'),
        actions: [
          if (widget.store is ReaderDecorationRulePreferences)
            IconButton(
              tooltip: '管理装饰样式',
              onPressed: _busy ? null : _manageStyles,
              icon: const AppIcon(AppGlyph.edit),
            ),
          IconButton(
            key: const ValueKey<String>('rule-add-group'),
            tooltip: '新建分组',
            onPressed: _busy || _loading ? null : _addGroup,
            icon: const AppIcon(AppGlyph.folderAdd),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<bool>(
              selectedIcon: const AppIcon(AppGlyph.check),
              segments: const [
                ButtonSegment(value: false, label: Text('本书')),
                ButtonSegment(value: true, label: Text('全局')),
              ],
              selected: {_global},
              onSelectionChanged: _busy
                  ? null
                  : (value) => setState(() => _global = value.first),
            ),
          ),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          if (!_global && widget.store is ReaderDecorationRulePreferences)
            SwitchListTile(
              title: const Text('跟随全局规则'),
              subtitle: const Text('关闭后可单独选择本书启用的全局规则'),
              value: _globalSelection == null,
              onChanged: _busy
                  ? null
                  : (value) => _operate(
                      () => (widget.store as ReaderDecorationRulePreferences)
                          .saveGlobalRuleSelection(
                            value
                                ? null
                                : _rules
                                      .where(
                                        (r) =>
                                            r.enabled &&
                                            _groups.any(
                                              (g) =>
                                                  g.id == r.groupId &&
                                                  g.bookId == null,
                                            ),
                                      )
                                      .map((r) => r.id)
                                      .toSet(),
                          ),
                    ),
            ),
          if (!_global && _globalSelection != null)
            Wrap(
              spacing: 8,
              children: [
                for (final rule in _rules.where(
                  (r) =>
                      _groups.any((g) => g.id == r.groupId && g.bookId == null),
                ))
                  FilterChip(
                    label: Text(rule.name ?? rule.pattern),
                    selected: _globalSelection!.contains(rule.id),
                    onSelected: _busy
                        ? null
                        : (selected) => _operate(() {
                            final ids = {..._globalSelection!};
                            if (selected) {
                              ids.add(rule.id);
                            } else {
                              ids.remove(rule.id);
                            }
                            return (widget.store
                                    as ReaderDecorationRulePreferences)
                                .saveGlobalRuleSelection(ids);
                          }),
                  ),
              ],
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!),
                        TextButton(onPressed: _load, child: const Text('重试')),
                      ],
                    ),
                  )
                : ReorderableListView(
                    buildDefaultDragHandles: false,
                    padding: const EdgeInsets.all(12),
                    onReorderItem: _reorderGroups,
                    children: [
                      for (var index = 0; index < groups.length; index++)
                        _groupCard(groups[index], index),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _groupCard(ReaderDecorationRuleGroup group, int index) {
    final rules = _groupRules(group.id);
    return Card(
      key: ValueKey<String>('rule-group-${group.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
        child: Column(
          children: [
            Row(
              children: [
                if (!group.isDefault)
                  ReorderableDragStartListener(
                    index: index,
                    enabled: !_busy,
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: AppIcon(AppGlyph.dragHandle),
                    ),
                  ),
                Expanded(
                  child: Text(
                    group.name,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (group.isDefault)
                  const Tooltip(
                    message: '默认组固定在最后，不能删除',
                    child: AppIcon(AppGlyph.lock, size: 16),
                  ),
                Switch(
                  value: group.enabled,
                  onChanged: _busy
                      ? null
                      : (value) => _operate(
                          () => widget.store.saveGroup(
                            group.copyWith(enabled: value),
                          ),
                        ),
                ),
                PopupMenuButton<String>(
                  icon: const AppIcon(AppGlyph.more),
                  enabled: !_busy,
                  tooltip: '管理分组',
                  onSelected: (value) =>
                      value == 'rename' ? _rename(group) : _deleteGroup(group),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'rename', child: Text('重命名')),
                    if (!group.isDefault)
                      const PopupMenuItem(value: 'delete', child: Text('删除分组')),
                  ],
                ),
              ],
            ),
            if (rules.isEmpty)
              const Padding(padding: EdgeInsets.all(8), child: Text('该组没有规则')),
            ReorderableListView.builder(
              shrinkWrap: true,
              primary: false,
              buildDefaultDragHandles: false,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: rules.length,
              onReorderItem: (oldIndex, newIndex) =>
                  _reorderRules(group.id, oldIndex, newIndex),
              itemBuilder: (context, ruleIndex) =>
                  _ruleCard(group, rules[ruleIndex], ruleIndex),
            ),
            TextButton.icon(
              key: ValueKey<String>('rule-add-${group.id}'),
              onPressed: _busy ? null : () => _editRule(group),
              icon: const AppIcon(AppGlyph.add),
              label: const Text('新建规则'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ruleCard(
    ReaderDecorationRuleGroup group,
    ReaderDecorationRule rule,
    int index,
  ) => ListTile(
    key: ValueKey<String>('rule-row-${rule.id}'),
    contentPadding: EdgeInsets.zero,
    leading: ReorderableDragStartListener(
      index: index,
      enabled: !_busy,
      child: const SizedBox(
        width: 44,
        height: 44,
        child: AppIcon(AppGlyph.dragHandle),
      ),
    ),
    title: Text(
      rule.name?.isNotEmpty == true ? rule.name! : rule.pattern,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
    subtitle: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${rule.effectiveType.label}${rule.pattern.isEmpty ? '' : ' · ${rule.pattern}'}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (widget.errors[rule.id] case final error?)
          Text(
            error,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    ),
    onTap: _busy ? null : () => _editRule(group, rule),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Switch(
          value: rule.enabled,
          onChanged: _busy
              ? null
              : (value) => _operate(
                  () => widget.store.saveRule(rule.copyWith(enabled: value)),
                ),
        ),
        IconButton(
          tooltip: '删除规则',
          onPressed: _busy ? null : () => _deleteRule(rule),
          icon: const AppIcon(AppGlyph.delete),
        ),
      ],
    ),
  );

  Future<void> _manageStyles() async {
    await showReaderBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('装饰样式', style: Theme.of(context).textTheme.titleLarge),
                for (final style in _styles)
                  ListTile(
                    title: Text(style.name),
                    subtitle: Text(style.builtIn ? '内置样式' : '自定义样式'),
                    onTap: () {
                      Navigator.pop(context);
                      _editStyle(style);
                    },
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!style.builtIn)
                          IconButton(
                            tooltip: '删除样式',
                            icon: const AppIcon(AppGlyph.delete),
                            onPressed: () {
                              Navigator.pop(context);
                              _operate(
                                () =>
                                    (widget.store
                                            as ReaderDecorationRulePreferences)
                                        .removeStyle(style.id),
                              );
                            },
                          ),
                        IconButton(
                          tooltip: '复制样式',
                          icon: const AppIcon(AppGlyph.copy),
                          onPressed: () {
                            Navigator.pop(context);
                            _editStyle(style, copy: true);
                          },
                        ),
                      ],
                    ),
                  ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _editStyle(null);
                  },
                  child: const Text('新建样式'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _editStyle(
    ReaderDecorationNamedStyle? style, {
    bool copy = false,
  }) async {
    final name = await showReaderDialog<String>(
      context: context,
      builder: (_) => ReaderTextValueDialog(
        title: copy ? '复制装饰样式' : '装饰样式名称',
        label: '名称',
        initialValue: style == null ? '' : '${style.name}${copy ? ' 副本' : ''}',
        validate: (value) => value.trim().isEmpty ? '请输入名称' : null,
      ),
    );
    if (!mounted || name == null) return;
    final id = copy || style == null
        ? 'style-${DateTime.now().microsecondsSinceEpoch}'
        : style.id;
    final draft = await showReaderBottomSheet<ReaderDecorationRule>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => ReaderDecorationRuleEditor(
        styleOnly: true,
        rule: ReaderDecorationRule(
          id: id,
          groupId: '',
          pattern: '',
          style: style?.style ?? const ReaderDecorationRuleStyle(),
        ),
        onPreview: widget.onPreview,
        images: widget.images,
        fonts: widget.fonts,
      ),
    );
    if (!mounted || draft == null) return;
    await _operate(
      () => (widget.store as ReaderDecorationRulePreferences).saveStyle(
        ReaderDecorationNamedStyle(
          id: id,
          name: name,
          style: draft.style,
          builtIn: style?.builtIn == true && !copy,
        ),
      ),
    );
  }
}
