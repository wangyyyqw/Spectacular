import 'package:reader_ui/theme/reader_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';
import 'package:reader_ui/theme/reader_sheet_form.dart';

import 'dictionary_client.dart';
import 'dictionary_settings_page.dart';
import 'dictionary_store.dart';

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
  });
  final DictionaryStore store;
  final String text;
  final DictionaryClient? client;
  @override
  State<DictionarySheet> createState() => _DictionarySheetState();
}

class _DictionarySheetState extends State<DictionarySheet> {
  late final _client = widget.client ?? DictionaryClient();
  DictionaryState? _state;
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
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DictionarySheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store || oldWidget.text != widget.text) {
      _generation++;
      _state = null;
      _result = null;
      _error = null;
      _loading = true;
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    try {
      final state = await widget.store.load();
      if (!mounted || generation != _generation) return;
      setState(() {
        _state = state;
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

  Future<void> _query() async {
    final state = _state;
    if (state == null) return;
    final generation = ++_generation;
    final api = state.api;
    setState(() {
      _loading = api != null;
      _result = null;
      _error = null;
    });
    if (api == null) return;
    try {
      final result = await _client.lookup(
        api: api,
        preset: state.presets.firstWhere((p) => p.id == _presetId),
        text: widget.text,
        disableThinking: state.settings.disableThinking,
      );
      if (mounted && generation == _generation) {
        setState(() => _result = result);
      }
    } on DictionaryException catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = error.message);
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
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
    await showReaderDrawer<void>(
      context: context,
      builder: (_) => DictionarySettingsPage(store: widget.store),
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
        SelectableText(
          widget.text,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        if (_state != null)
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
        if (_state?.api == null && !_loading && _error == null)
          const Text('请先配置词典释义服务，再查询选中文字。'),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (_result != null)
          SelectableText(_result!, key: const ValueKey('dictionary-result')),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (_state?.api != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              '模型：${_state!.api!.model}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    ),
    actions: [
      TextButton(onPressed: _configure, child: const Text('词典设置')),
      FilledButton(
        key: const ValueKey('dictionary-query-retry'),
        onPressed: _loading || _state?.api == null ? null : _query,
        child: const Text('重新查询'),
      ),
    ],
  );
}
