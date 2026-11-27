import 'dart:async';

import 'package:reader_ui/theme/reader_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:reader_ui/panels/reader_settings_sheet.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';
import 'package:reader_ui/theme/reader_section_slider.dart';

import 'dictionary_client.dart';
import 'dictionary_rule.dart';
import 'dictionary_rule_client.dart';
import 'dictionary_rule_view.dart';
import 'dictionary_store.dart';
import 'local_dictionary_store.dart';
import 'local_dictionary_view.dart';

Future<void> showDictionary(
  BuildContext context,
  DictionaryStore store,
  String text,
) => showReaderBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => DictionarySheet(store: store, text: text),
);

enum _DictionarySection {
  web('rule:', '网页'),
  local('local:', '本地'),
  ai('ai:', 'AI');

  const _DictionarySection(this.prefix, this.label);
  final String prefix;
  final String label;
}

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
  final _ruleResults = <(DictionaryRule, String), DictionaryRuleResult>{};
  (String?, String?, String)? _activeQuery;
  String? _queriedText;
  String? _sourceId;
  _DictionarySection _section = _DictionarySection.web;
  final _sectionSources = <_DictionarySection, String>{};
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
    _ruleClient?.close();
    _ruleClient = null;
    _activeQuery = null;
    _ruleResults.clear();
    _sectionSources.clear();
    setState(() {
      _loading = true;
      _error = null;
    });
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
        if (locals.isNotEmpty) {
          _sectionSources[_DictionarySection.local] =
              'local:${locals.first.id}';
        }
        if (state.api != null) {
          _sectionSources[_DictionarySection.ai] = 'ai:${state.api!.id}';
        }
        _section = _DictionarySection.web;
        if (_sourceId != null) {
          _section = _DictionarySection.values.firstWhere(
            (section) => _sourceId!.startsWith(section.prefix),
          );
          _sectionSources[_section] = _sourceId!;
        }
      });
      await _query();
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _error = '词典设置读取失败，请关闭后重新打开词典';
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

  List<(String, String)> get _sources => _sourcesFor(_section);

  List<(String, String)> _sourcesFor(_DictionarySection section) {
    final state = _state;
    if (state == null) return const [];
    return switch (section) {
      _DictionarySection.web => [
        for (final rule in state.rules.where((rule) => rule.enabled))
          (rule.sourceId, rule.name),
      ],
      _DictionarySection.local => [
        for (final entry in _locals) ('local:${entry.id}', entry.name),
      ],
      _DictionarySection.ai => [
        for (final api in state.apis.where((api) => api.enabled))
          ('ai:${api.id}', api.label),
      ],
    };
  }

  Future<void> _selectSection(int index) async {
    final section = _DictionarySection.values[index];
    if (section == _section || _state == null) return;
    final sources = _sourcesFor(section);
    final id =
        sources
            .where((source) => source.$1 == _sectionSources[section])
            .firstOrNull
            ?.$1 ??
        sources.firstOrNull?.$1;
    setState(() => _section = section);
    await _selectSource(id);
  }

  Future<void> _query() async {
    final state = _state;
    if (state == null) return;
    final api = _api;
    final local = _local;
    final rule = _rule;
    final text = _text.text.trim();
    final query = (_sourceId, api != null ? _presetId : null, text);
    if (_loading && query == _activeQuery) return;
    final generation = ++_generation;
    final oldSession = _session;
    final oldRuleClient = _ruleClient;
    setState(() {
      _session = null;
      _ruleClient = null;
      _loading = api != null || local != null || rule != null;
      _activeQuery = _loading ? query : null;
      _queriedText = text;
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
        final cacheKey = (rule, text);
        final cached = _ruleResults.remove(cacheKey);
        final DictionaryRuleResult result;
        if (cached != null) {
          result = cached;
        } else {
          ruleClient = (widget.ruleClientFactory ?? DictionaryRuleClient.new)();
          _ruleClient = ruleClient;
          result = await ruleClient.lookup(rule: rule, word: text);
        }
        if (mounted && generation == _generation) {
          _ruleResults[cacheKey] = result;
          if (_ruleResults.length > 8) {
            _ruleResults.remove(_ruleResults.keys.first);
          }
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
          _activeQuery = null;
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
    if (id == _sourceId) return;
    setState(() {
      _sourceId = id;
      if (id != null) _sectionSources[_section] = id;
    });
    final query = _query();
    if (id == null) return query;
    final generation = _generation;
    try {
      await widget.store.changeSettings(
        (settings) => settings.copyWith(sourceId: id),
      );
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = '默认词典保存失败，本次查询仍可使用');
      }
    }
    await query;
  }

  Future<void> _selectPreset(String? id) async {
    if (id == null || id == _presetId || _state == null) return;
    setState(() => _presetId = id);
    final query = _query();
    final generation = _generation;
    if (!_state!.settings.singleUsePreset) {
      try {
        await widget.store.changeSettings((s) => s.copyWith(presetId: id));
      } catch (_) {
        if (mounted && generation == _generation) {
          setState(() => _error = '默认预设保存失败，本次查询仍可使用');
        }
      }
    }
    await query;
  }

  @override
  Widget build(BuildContext context) => AnimatedPadding(
    duration: const Duration(milliseconds: 180),
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: ReaderSettingsSheet(
      key: const ValueKey('dictionary-sheet'),
      header: _header(),
      child: _content(context),
    ),
  );

  Widget _header() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ReaderSectionSlider(
        key: const ValueKey('dictionary-section-tabs'),
        sections: [
          for (final section in _DictionarySection.values)
            (key: section.name, label: section.label),
        ],
        itemKeyBuilder: (item) => ValueKey('dictionary-${item.key}'),
        index: _section.index,
        onSelected: _selectSection,
      ),
    ],
  );

  String get _emptyMessage => _sources.isNotEmpty
      ? '请选择上方词典来源后查询。'
      : switch (_section) {
          _DictionarySection.web => '暂无可用的网页词典，请前往词典设置启用或添加。',
          _DictionarySection.local => '尚未导入或启用本地词典，请前往词典设置导入。',
          _DictionarySection.ai => '尚未配置或启用 AI 释义服务，请前往词典设置添加。',
        };

  Widget _content(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_sources.isNotEmpty) ...[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (id, label) in _sources)
              ChoiceChip(
                key: ValueKey('dictionary-source-$id'),
                label: Text(label),
                selected: id == _sourceId,
                onSelected: (_) => _selectSource(id),
              ),
          ],
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
      if (_sourceId == null && !_loading && _error == null) Text(_emptyMessage),
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
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text(_state == null ? '正在读取词典设置…' : '正在查询「$_queriedText」…'),
            ],
          ),
        ),
      if (_result != null) _resultCard(context),
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
  );

  Widget _resultCard(BuildContext context) {
    final result = _result!;
    final child = _session != null
        ? LocalDictionaryView(
            key: ObjectKey(_session),
            session: _session!,
            definition: result,
            onLookup: _selectWord,
          )
        : _resultHtml
        ? DictionaryRuleView(
            key: ValueKey((result, _resultBaseUrl)),
            html: result,
            baseUrl: _resultBaseUrl ?? 'about:blank',
          )
        : SelectableText(
            result,
            key: const ValueKey('dictionary-result'),
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(fontSize: 16, height: 1.6),
          );
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('dictionary-result-card'),
      margin: const EdgeInsets.only(top: 4),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: child,
    );
  }
}
