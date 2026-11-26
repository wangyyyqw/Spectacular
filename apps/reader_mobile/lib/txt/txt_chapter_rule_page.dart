import 'package:flutter/material.dart';
import 'package:reader_core/editing.dart';
import 'package:reader_core/txt.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/theme/reader_common_widgets.dart';
import 'package:reader_ui/theme/reader_dropdown.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';
import 'package:reader_ui/theme/reader_sheet_form.dart';

import '../library/library_store.dart';
import '../diagnostics/reader_log.dart';
import 'txt_book_service.dart';
import 'txt_rule_store.dart';

/// 预览和提交分离；退出或改变规则不会写入当前书籍。
class TxtChapterRulePage extends StatefulWidget {
  const TxtChapterRulePage({
    super.key,
    required this.entry,
    required this.library,
    this.service,
    this.ruleStore,
  });

  final BookEntry entry;
  final LibraryStore library;
  final TxtBookService? service;
  final TxtRuleStore? ruleStore;

  @override
  State<TxtChapterRulePage> createState() => _TxtChapterRulePageState();
}

class _TxtChapterRulePageState extends State<TxtChapterRulePage> {
  late final _service = widget.service ?? TxtBookService(widget.library);
  late final _ruleStore = widget.ruleStore ?? TxtRuleStore(widget.library);
  final _pattern = TextEditingController();
  final _volume = TextEditingController();
  List<ChapterRule> _rules = const [];
  String _selection = 'auto';
  bool _caseSensitive = true;
  bool _loading = true;
  bool _scanning = false;
  bool _applying = false;
  bool _cancelled = false;
  bool _canEdit = false;
  bool _restoring = false;
  int _generation = 0;
  double? _progress;
  String? _error;
  EpubRechapterPreview? _preview;

  bool get _busy => _scanning || _applying;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _cancelled = true;
    _generation++;
    _pattern.dispose();
    _volume.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final (info, rules) = await (
        _service.info(widget.entry),
        _ruleStore.load(),
      ).wait;
      if (!mounted) return;
      setState(() {
        _rules = rules;
        _canEdit = info != null;
        if (info == null) {
          _error = '只有 TXT 转入的书籍可以使用章节正则。';
        } else {
          _setOptions(info.options);
        }
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$error';
        });
      }
    }
  }

  void _setOptions(ChapterDetectionOptions options) {
    _selection = options.mode.name;
    final rule = options.rule;
    if (rule == null) return;
    _pattern.text = rule.pattern;
    _volume.text = rule.volumePattern ?? '';
    _caseSensitive = rule.caseSensitive;
    _selection = _ruleSelection(rule.id) ?? 'custom';
  }

  String? _ruleSelection(String id) {
    if (builtInChapterRules.any((rule) => rule.id == id)) return 'builtin:$id';
    if (_rules.any((rule) => rule.id == id)) return 'saved:$id';
    return null;
  }

  ChapterRule? get _selectedRule => [...builtInChapterRules, ..._rules]
      .where(
        (rule) =>
            _selection == 'builtin:${rule.id}' ||
            _selection == 'saved:${rule.id}',
      )
      .firstOrNull;

  ChapterRule _currentRule({
    String? id,
    String? name,
    bool autoEnabled = false,
  }) => ChapterRule(
    id: id ?? _selectedRule?.id ?? 'current-book',
    name: name ?? _selectedRule?.name ?? '本书自定义规则',
    pattern: _pattern.text,
    volumePattern: _volume.text.isEmpty ? null : _volume.text,
    caseSensitive: _caseSensitive,
    autoEnabled: autoEnabled,
  );

  ChapterDetectionOptions get _options => ChapterDetectionOptions(
    mode: switch (_selection) {
      'auto' => ChapterDetectionMode.auto,
      'length' => ChapterDetectionMode.length,
      _ => ChapterDetectionMode.custom,
    },
    rule: _selection == 'auto' || _selection == 'length'
        ? null
        : _currentRule(),
    autoRules: _rules.where((rule) => rule.autoEnabled).toList(),
  );

  void _invalidate({bool custom = false}) {
    setState(() {
      if (custom) _selection = 'custom';
      _generation++;
      _preview = null;
      _error = null;
    });
  }

  void _select(String? value) {
    if (value == null || _busy) return;
    _selection = value;
    if (value.startsWith('builtin:') || value.startsWith('saved:')) {
      final source = value.startsWith('builtin:')
          ? builtInChapterRules
          : _rules;
      final id = value.substring(value.indexOf(':') + 1);
      final rule = source.firstWhere((rule) => rule.id == id);
      _pattern.text = rule.pattern;
      _volume.text = rule.volumePattern ?? '';
      _caseSensitive = rule.caseSensitive;
    }
    _invalidate();
  }

  Future<bool> _checkDraft() async {
    if (!await _service.hasDraft(widget.entry)) return true;
    if (mounted) {
      setState(() => _error = '本书有未保存的编辑草稿，请先在编辑器保存或放弃草稿，再重新分章。');
    }
    return false;
  }

  Future<void> _scan() async {
    if (_busy || !_canEdit) return;
    final generation = ++_generation;
    setState(() {
      _scanning = true;
      _cancelled = false;
      _preview = null;
      _error = null;
      _progress = null;
    });
    try {
      if (!await _checkDraft() || !mounted || _cancelled) return;
      final preview = await _service.preview(
        widget.entry,
        _options,
        isCancelled: () => !mounted || _cancelled || generation != _generation,
        onProgress: _updateProgress,
      );
      if (mounted && !_cancelled && generation == _generation) {
        setState(() => _preview = preview);
      }
    } catch (error) {
      if (mounted && !_cancelled) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  void _updateProgress(double value) {
    if (mounted && !_cancelled) setState(() => _progress = value);
  }

  Future<void> _apply() async {
    final preview = _preview;
    if (_busy || preview == null || !preview.canApply) return;
    setState(() {
      _applying = true;
      _cancelled = false;
      _error = null;
      _progress = null;
    });
    try {
      if (!await _checkDraft() || !mounted || _cancelled) return;
      await _service.apply(
        widget.entry,
        preview,
        isCancelled: () => _cancelled,
        onProgress: _updateProgress,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted && !_cancelled) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  void _cancel() {
    setState(() {
      _cancelled = true;
      _generation++;
      _preview = null;
      _error = '已取消，当前书籍未改变。';
    });
  }

  Future<void> _saveRule() async {
    final saved = await showReaderDrawer<ChapterRule>(
      context: context,
      builder: (_) => _SaveRuleDialog(rule: _currentRule()),
      waitForDismissal: true,
    );
    if (saved == null || !mounted) return;
    try {
      await _ruleStore.save(saved);
      final rules = await _ruleStore.load();
      if (!mounted) return;
      setState(() {
        _rules = rules;
        _selection = 'saved:${saved.id}';
        _generation++;
        _preview = null;
      });
      recordAppEvent('txt_rules_saved');
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _manageRules() async {
    try {
      await showReaderDrawer<void>(
        context: context,
        builder: (_) => _RuleManager(store: _ruleStore),
        waitForDismissal: true,
      );
      final rules = await _ruleStore.load();
      if (!mounted) return;
      setState(() {
        _rules = rules;
        if (_selection.startsWith('saved:') &&
            !_rules.any((rule) => 'saved:${rule.id}' == _selection)) {
          _selection = 'custom';
        }
      });
      _invalidate();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _restore() async {
    if (_busy) return;
    final confirmed = await showReaderDialog<bool>(
      context: context,
      builder: (context) => ReaderFrostedAlertDialog(
        title: const Text('恢复上一保存版本？'),
        content: const Text('书籍内容将恢复到上一次保存前。阅读进度和已有笔记会重新定位，记录不会删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _applying = true;
      _restoring = true;
      _error = null;
      _progress = null;
    });
    try {
      if (!await _checkDraft() || !mounted) return;
      await _service.restorePrevious(widget.entry);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) {
        setState(() {
          _applying = false;
          _restoring = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_applying,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('章节正则'),
        actions: [
          PopupMenuButton<String>(
            enabled: !_busy && _canEdit,
            onSelected: (_) => _restore(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'restore', child: Text('恢复上一保存版本')),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 880),
                child: _buildContents(context),
              ),
            ),
      bottomNavigationBar: _loading || !_canEdit ? null : _buildActions(),
    ),
  );

  Widget _buildContents(BuildContext context) {
    final preview = _preview;
    final boundaries =
        preview?.detection.boundaries ?? const <ChapterBoundary>[];
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      itemCount: boundaries.length + 1,
      itemBuilder: (context, index) => index > 0
          ? _chapterTile(preview!, index - 1)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.entry.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                const Text('以当前已保存的正文重新分章。先预览目录，应用后更新本书。'),
                const SizedBox(height: 20),
                if (_canEdit) ..._buildRuleFields(),
                if (_busy) ...[
                  const SizedBox(height: 16),
                  LinearProgressIndicator(value: _progress),
                  const SizedBox(height: 8),
                  Text(_applying ? '正在保存章节…' : '正在扫描当前正文…'),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  ReaderNoticeBanner(message: _error!),
                ],
                if (preview != null) ..._buildPreview(preview),
              ],
            ),
    );
  }

  List<Widget> _buildRuleFields() => [
    ReaderDropdownButtonFormField<String>(
      key: ValueKey('txt-rule-selector-$_selection'),
      initialValue: _selection,
      isExpanded: true,
      decoration: const InputDecoration(labelText: '分章方式'),
      items: [
        const DropdownMenuItem(value: 'auto', child: Text('自动识别')),
        const DropdownMenuItem(value: 'custom', child: Text('自定义正则')),
        const DropdownMenuItem(value: 'length', child: Text('按长度分节')),
        for (final rule in builtInChapterRules)
          DropdownMenuItem(
            value: 'builtin:${rule.id}',
            child: Text(rule.name, overflow: TextOverflow.ellipsis),
          ),
        for (final rule in _rules)
          DropdownMenuItem(
            value: 'saved:${rule.id}',
            child: Text('我的规则 · ${rule.name}', overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: _busy ? null : _select,
    ),
    if (_selection != 'auto' && _selection != 'length') ...[
      const SizedBox(height: 16),
      TextField(
        key: const ValueKey('txt-chapter-pattern'),
        controller: _pattern,
        enabled: !_busy,
        minLines: 2,
        maxLines: 5,
        autocorrect: false,
        enableSuggestions: false,
        decoration: const InputDecoration(
          labelText: '章节正则',
          helperText: '匹配完整的一行；标题使用该行原文，无需捕获组。',
        ),
        onChanged: (_) => _invalidate(custom: true),
      ),
      const SizedBox(height: 16),
      TextField(
        key: const ValueKey('txt-volume-pattern'),
        controller: _volume,
        enabled: !_busy,
        minLines: 1,
        maxLines: 3,
        autocorrect: false,
        enableSuggestions: false,
        decoration: const InputDecoration(labelText: '分卷正则（可选）'),
        onChanged: (_) => _invalidate(custom: true),
      ),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('区分大小写'),
        value: _caseSensitive,
        onChanged: _busy
            ? null
            : (value) {
                _caseSensitive = value!;
                _invalidate(custom: true);
              },
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: _busy ? null : _saveRule,
          child: const Text('另存为我的规则'),
        ),
      ),
    ],
    Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        onPressed: _busy ? null : _manageRules,
        child: const Text('管理我的规则'),
      ),
    ),
  ];

  List<Widget> _buildPreview(EpubRechapterPreview preview) => [
    const Divider(height: 32),
    Text(
      '目录预览 · ${preview.chapterCount} 项 · ${preview.volumeCount} 卷',
      style: Theme.of(context).textTheme.titleMedium,
    ),
    const SizedBox(height: 8),
    for (final message in {
      ...preview.detection.warnings,
      ...preview.diagnostics,
    })
      Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(message)),
  ];

  Widget _chapterTile(EpubRechapterPreview preview, int index) {
    final chapter = preview.detection.boundaries[index];
    return ExpansionTile(
      key: ValueKey('txt-preview-chapter-$index'),
      tilePadding: EdgeInsets.only(left: chapter.isVolume ? 0 : 12),
      title: Text(chapter.title),
      subtitle: chapter.isVolume ? const Text('分卷') : null,
      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SelectableText(preview.sampleForChapter(index)),
        ),
      ],
    );
  }

  Widget _buildActions() => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Row(
        children: [
          if (_busy && !_restoring)
            TextButton(
              onPressed: _cancelled ? null : _cancel,
              child: Text(_cancelled ? '正在取消…' : '取消'),
            )
          else if (!_busy)
            OutlinedButton(
              key: const ValueKey('txt-preview'),
              onPressed: _scan,
              child: const Text('预览目录'),
            ),
          const Spacer(),
          FilledButton(
            key: const ValueKey('txt-apply'),
            onPressed: !_busy && (_preview?.canApply ?? false) ? _apply : null,
            child: const Text('应用重新分章'),
          ),
        ],
      ),
    ),
  );
}

class _SaveRuleDialog extends StatefulWidget {
  const _SaveRuleDialog({required this.rule});
  final ChapterRule rule;
  @override
  State<_SaveRuleDialog> createState() => _SaveRuleDialogState();
}

class _SaveRuleDialogState extends State<_SaveRuleDialog> {
  final _name = TextEditingController();
  bool _auto = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = '请填写规则名称');
      return;
    }
    try {
      if (widget.rule.pattern.isEmpty) throw const FormatException('请填写章节正则');
      RegExp(
        widget.rule.pattern,
        unicode: true,
        caseSensitive: widget.rule.caseSensitive,
      );
      if (widget.rule.volumePattern case final value?) {
        RegExp(value, unicode: true);
      }
      Navigator.pop(
        context,
        ChapterRule(
          id: 'user-${DateTime.now().microsecondsSinceEpoch}',
          name: _name.text.trim(),
          pattern: widget.rule.pattern,
          volumePattern: widget.rule.volumePattern,
          caseSensitive: widget.rule.caseSensitive,
          autoEnabled: _auto,
        ),
      );
    } on FormatException catch (error) {
      setState(() => _error = '正则无效：${error.message}');
    }
  }

  @override
  Widget build(BuildContext context) => ReaderSheetForm(
    title: const Text('另存为我的规则'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: InputDecoration(labelText: '规则名称', errorText: _error),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _auto,
            title: const Text('参与以后 TXT 导入的自动识别'),
            onChanged: (value) => setState(() => _auto = value!),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _save, child: const Text('保存规则')),
    ],
  );
}

class _RuleManager extends StatefulWidget {
  const _RuleManager({required this.store});
  final TxtRuleStore store;
  @override
  State<_RuleManager> createState() => _RuleManagerState();
}

class _RuleManagerState extends State<_RuleManager> {
  late Future<List<ChapterRule>> _rules = widget.store.load();
  String? _error;
  Future<void> _update(
    ChapterRule rule, {
    bool? enabled,
    bool delete = false,
  }) async {
    try {
      if (delete) {
        await widget.store.delete(rule.id);
      } else {
        await widget.store.save(
          ChapterRule.fromJson({...rule.toJson(), 'autoEnabled': enabled}),
        );
      }
      if (mounted) setState(() => _rules = widget.store.load());
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) => ReaderSheetForm(
    title: const Text('我的规则'),
    content: SizedBox(
      width: 520,
      height: 340,
      child: FutureBuilder<List<ChapterRule>>(
        future: _rules,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Text('${snapshot.error}');
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rules = snapshot.data!;
          if (rules.isEmpty) {
            return const Center(
              child: Text(
                '暂无自定义规则\n在章节正则页面编辑后，可另存到这里。',
                textAlign: TextAlign.center,
              ),
            );
          }
          return ListView(
            children: [
              if (_error != null) Text(_error!),
              for (final rule in rules)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(rule.name),
                  subtitle: const Text('参与自动识别'),
                  leading: Switch(
                    value: rule.autoEnabled,
                    onChanged: (value) => _update(rule, enabled: value),
                  ),
                  trailing: IconButton(
                    tooltip: '删除规则',
                    onPressed: () => _update(rule, delete: true),
                    icon: const AppIcon(AppGlyph.delete),
                  ),
                ),
            ],
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('完成'),
      ),
    ],
  );
}
