import 'dart:async';

import 'package:reader_ui/theme/reader_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';
import 'package:reader_ui/theme/reader_sheet_form.dart';

import 'dictionary_client.dart';
import 'dictionary_rule.dart';
import 'dictionary_rule_client.dart';
import 'dictionary_rule_view.dart';
import 'dictionary_settings_page.dart';
import 'dictionary_store.dart';
import 'local_dictionary_store.dart';
import 'local_dictionary_view.dart';

Future<void> showDictionary(
  BuildContext context,
  DictionaryStore store,
  String text,
) => showReaderDrawer<void>(
  context: context,
  builder: (_) => DictionarySheet(store: store, text: text),
);

class DictionarySheet extends StatefulWidget {
  const DictionarySheet({
    super.key,
    required this.store,
    required this.text,
    this.client,
    this.ruleClientFactory,
  });
  final DictionaryStore store;
  final String text;
  final DictionaryClient? client;
  final DictionaryRuleClient Function()? ruleClientFactory;
  @override
  State<DictionarySheet> createState() => _DictionarySheetState();
}

class _DictionarySheetState extends State<DictionarySheet> {
  late final _client = widget.client ?? DictionaryClient();
  late final _text = TextEditingController(text: widget.text);
  DictionaryState? _state;
  List<LocalDictionaryEntry> _locals = [];
  LocalDictionarySession? _session;
  DictionaryRuleClient? _ruleClient;
  String? _sourceId;
  List<String> _suggestions = [];
  bool _localMiss = false;
  bool _resultHtml = false;
  String? _resultBaseUrl;
  String? _presetId, _result, _error;
  bool _loading = true;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _generation++;
    _client.close();
    _ruleClient?.close();
    _text.dispose();
    unawaited(_session?.close());
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DictionarySheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store || oldWidget.text != widget.text) {
      _generation++;
      _state = null;
      _sourceId = null;
      _result = null;
      _resultHtml = false;
      _resultBaseUrl = null;
      _error = null;
      _loading = true;
      _text.text = widget.text;
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    try {
      final state = await widget.store.load();
      final locals = (await widget.store.locals.load())
          .where((entry) => entry.enabled)
          .toList();
      if (!mounted || generation != _generation) return;
      final enabledRules = state.rules.where((rule) => rule.enabled).toList();
      final sources = {
        for (final entry in locals) 'local:${entry.id}',
        for (final api in state.apis.where((api) => api.enabled))
          'ai:${api.id}',
        for (final rule in enabledRules) rule.sourceId,
      };
      setState(() {
        _state = state;
        _locals = locals;
        _sourceId = sources.contains(state.settings.sourceId)
            ? state.settings.sourceId
            : locals.isNotEmpty
            ? 'local:${locals.first.id}'
            : state.api != null
            ? 'ai:${state.api!.id}'
            : null;
        _presetId = state.preset.id;
      });
      await _query();
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _error = '词典设置读取失败，请重试';
        });
      }
    }
  }

  DictionaryApi? get _api => _state?.apis
      .where((api) => api.enabled && 'ai:${api.id}' == _sourceId)
      .firstOrNull;

  LocalDictionaryEntry? get _local =>
      _locals.where((entry) => 'local:${entry.id}' == _sourceId).firstOrNull;

  DictionaryRule? get _rule => _state?.rules
      .where((rule) => rule.enabled && rule.sourceId == _sourceId)
      .firstOrNull;

  List<(String, String)> get _sources {
    final state = _state;
    if (state == null) return const [];
    return [
      for (final entry in _locals) ('local:${entry.id}', '本地 · ${entry.name}'),
      for (final api in state.apis.where((api) => api.enabled))
        ('ai:${api.id}', 'AI · ${api.label}'),
      for (final rule in state.rules.where((rule) => rule.enabled))
        (rule.sourceId, '在线 · ${rule.name}'),
    ];
  }

  Future<void> _query() async {
    final state = _state;
    if (state == null) return;
    final generation = ++_generation;
    final api = _api;
    final local = _local;
    final rule = _rule;
    final text = _text.text.trim();
    final oldSession = _session;
    final oldRuleClient = _ruleClient;
    setState(() {
      _session = null;
      _ruleClient = null;
      _loading = api != null || local != null || rule != null;
      _result = null;
      _resultHtml = false;
      _resultBaseUrl = null;
      _error = null;
      _localMiss = false;
      _suggestions = [];
    });
    unawaited(oldSession?.close());
    oldRuleClient?.close();
    if (api == null && local == null && rule == null) return;
    LocalDictionarySession? session;
    DictionaryRuleClient? ruleClient;
    try {
      if (text.isEmpty) throw const DictionaryException('请输入要查询的词语');
      if (local != null) {
        session = await widget.store.locals.open(local);
        final result = await session.lookup(text);
        if (mounted && generation == _generation) {
          setState(() {
            _result = result;
            _session = session;
            _localMiss = result == null;
            _suggestions = _localMiss ? session!.suggest(text) : [];
          });
        } else {
          await session.close();
        }
      } else if (rule != null) {
        ruleClient = (widget.ruleClientFactory ?? DictionaryRuleClient.new)();
        _ruleClient = ruleClient;
        final result = await ruleClient.lookup(rule: rule, word: text);
        if (mounted && generation == _generation) {
          setState(() {
            _result = result.value;
            _resultHtml = result.html;
            _resultBaseUrl = result.baseUrl;
            _ruleClient = null;
          });
        }
      } else {
        final result = await _client.lookup(
          api: api!,
          preset: state.presets.firstWhere((p) => p.id == _presetId),
          text: text,
          disableThinking: state.settings.disableThinking,
        );
        if (mounted && generation == _generation) {
          setState(() => _result = result);
        }
      }
    } catch (error) {
      await session?.close();
      if (mounted && generation == _generation) {
        setState(
          () => _error = switch (error) {
            DictionaryException() => error.message,
            LocalDictionaryException() => error.message,
            DictionaryRuleException() => error.message,
            _ => '查询失败，请重试',
          },
        );
      }
    } finally {
      ruleClient?.close();
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          if (identical(_ruleClient, ruleClient)) _ruleClient = null;
        });
      }
    }
  }

  void _selectWord(String word) {
    _text.text = word;
    _query();
  }

  Future<void> _selectSource(String? id) async {
    if (id == null || id == _sourceId) return;
    setState(() => _sourceId = id);
    final query = _query();
    try {
      await widget.store.changeSettings(
        (settings) => settings.copyWith(sourceId: id),
      );
    } catch (_) {
      if (mounted) setState(() => _error = '默认词典保存失败，本次查询仍可使用');
    }
    await query;
  }

  Future<void> _selectPreset(String? id) async {
    if (id == null || id == _presetId || _state == null) return;
    setState(() => _presetId = id);
    final query = _query();
    if (!_state!.settings.singleUsePreset) {
      try {
        await widget.store.changeSettings((s) => s.copyWith(presetId: id));
      } catch (_) {
        if (mounted) setState(() => _error = '默认预设保存失败，本次查询仍可使用');
      }
    }
    await query;
  }

  Future<void> _configure() async {
    _generation++;
    final session = _session;
    final ruleClient = _ruleClient;
    setState(() {
      _session = null;
      _ruleClient = null;
      _result = null;
      _resultHtml = false;
    });
    ruleClient?.close();
    await session?.close();
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => DictionarySettingsPage(store: widget.store),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) => ReaderSheetForm(
    key: const ValueKey('dictionary-sheet'),
    title: const Text('词典'),
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('dictionary-query-text'),
          controller: _text,
          decoration: const InputDecoration(labelText: '查询词语'),
          onSubmitted: (_) => _query(),
        ),
        const SizedBox(height: 16),
        if (_sources.isNotEmpty) ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (id, label) in _sources)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      key: ValueKey('dictionary-source-$id'),
                      label: Text(label),
                      selected: id == _sourceId,
                      onSelected: (_) => _selectSource(id),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (_api != null)
          ReaderDropdownButtonFormField<String>(
            key: const ValueKey('dictionary-query-preset'),
            initialValue: _presetId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '释义预设'),
            items: [
              for (final p in _state!.presets)
                DropdownMenuItem(value: p.id, child: Text(p.name)),
            ],
            onChanged: _selectPreset,
          ),
        const SizedBox(height: 16),
        if (_sourceId == null && !_loading && _error == null)
          Text(_sources.isEmpty ? '请先配置释义服务、本地词典或在线词典规则。' : '请选择上方词典来源后查询。'),
        if (_localMiss) ...[
          const Text('本地词典未找到该词条。可修改词语、切换词典，或手动选择 AI 释义。'),
          if (_suggestions.isNotEmpty)
            Wrap(
              spacing: 8,
              children: [
                for (final word in _suggestions)
                  ActionChip(
                    label: Text(word),
                    onPressed: () => _selectWord(word),
                  ),
              ],
            ),
        ],
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (_result != null)
          _session != null
              ? LocalDictionaryView(
                  key: ObjectKey(_session),
                  session: _session!,
                  definition: _result!,
                  onLookup: _selectWord,
                )
              : _resultHtml
              ? DictionaryRuleView(
                  key: ObjectKey((_result, _resultBaseUrl)),
                  html: _result!,
                  baseUrl: _resultBaseUrl ?? 'about:blank',
                )
              : SelectableText(
                  _result!,
                  key: const ValueKey('dictionary-result'),
                ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (_api != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              '模型：${_api!.model}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    ),
    actions: [
      TextButton(onPressed: _configure, child: const Text('词典设置')),
      FilledButton(
        key: const ValueKey('dictionary-query-retry'),
        onPressed: _loading || _sourceId == null ? null : _query,
        child: const Text('重新查询'),
      ),
    ],
  );
}
