import 'package:reader_ui/theme/reader_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:reader_ui/theme/reader_switch.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';
import 'package:reader_ui/theme/reader_sheet_form.dart';
import 'package:reader_ui/theme/reader_ui_components.dart';

import 'dictionary_client.dart';
import 'dictionary_store.dart';

class DictionarySettingsPage extends StatefulWidget {
  const DictionarySettingsPage({super.key, required this.store});
  final DictionaryStore store;
  @override
  State<DictionarySettingsPage> createState() => _DictionarySettingsPageState();
}

class _DictionarySettingsPageState extends State<DictionarySettingsPage> {
  DictionaryState? _state;
  String? _error;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final state = await widget.store.load();
      if (mounted) {
        setState(() {
          _state = state;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '词典设置读取失败，请重试');
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
          () => _error = error is FormatException ? error.message : '保存失败，请重试',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editApi([DictionaryApi? api]) async {
    final next = await showReaderDrawer<DictionaryApi>(
      context: context,
      builder: (_) => _ApiForm(api: api, store: widget.store),
    );
    if (next != null && mounted) {
      await _operate(() => widget.store.saveApi(next));
    }
  }

  Future<void> _editPreset(
    DictionaryPreset? preset, {
    bool copy = false,
  }) async {
    final next = await showReaderDrawer<DictionaryPreset>(
      context: context,
      builder: (_) => _PresetForm(preset: preset, copy: copy),
    );
    if (next != null && mounted) {
      await _operate(() => widget.store.savePreset(next));
    }
  }

  Future<bool> _confirm(String name) => showReaderConfirmDialog(
    context: context,
    title: '删除“$name”？',
    message: '删除后会回到可用的默认配置。',
    confirmLabel: '删除',
    destructive: true,
  );
  @override
  Widget build(BuildContext context) {
    final state = _state;
    if (state == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('词典设置')),
        body: Center(
          child: _error == null
              ? const CircularProgressIndicator()
              : ReaderEmptyState(
                  icon: const AppIcon(AppGlyph.warning),
                  title: '读取失败',
                  description: _error!,
                  action: FilledButton.tonal(
                    onPressed: _load,
                    child: const Text('重试'),
                  ),
                ),
        ),
      );
    }
    return ReaderSettingsScaffold(
      title: const Text('词典设置'),
      children: [
        if (_busy) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: ReaderUiTokens.spacingMd),
        ],
        if (_error != null) ...[
          ReaderInlineNotice(message: _error!, isError: true),
          const SizedBox(height: ReaderUiTokens.spacingMd),
        ],
        ReaderSectionGroup(
          title: '释义服务',
          trailing: TextButton.icon(
            key: const ValueKey('dictionary-api-add'),
            onPressed: _busy ? null : _editApi,
            icon: const AppIcon(AppGlyph.add, size: 18),
            label: const Text('添加释义服务'),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: ReaderDropdownButtonFormField<String>(
                key: const ValueKey('dictionary-api-select'),
                initialValue:
                    state.apis.any((a) => a.id == state.settings.apiId)
                    ? state.settings.apiId
                    : '',
                isExpanded: true,
                decoration: const InputDecoration(labelText: '当前服务'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('自动选择已启用服务')),
                  for (final api in state.apis)
                    DropdownMenuItem(value: api.id, child: Text(api.label)),
                ],
                onChanged: _busy
                    ? null
                    : (id) => _operate(
                        () => widget.store.changeSettings(
                          (s) => s.copyWith(apiId: id),
                        ),
                      ),
              ),
            ),
            for (final api in state.apis)
              ListTile(
                title: Text(api.label),
                subtitle: Text('${api.model}\n${api.baseUrl}'),
                isThreeLine: true,
                onTap: _busy ? null : () => _editApi(api),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ReaderSwitch(
                      value: api.enabled,
                      onChanged: _busy
                          ? null
                          : (value) => _operate(
                              () => widget.store.saveApi(
                                DictionaryApi(
                                  id: api.id,
                                  name: api.name,
                                  baseUrl: api.baseUrl,
                                  apiKey: api.apiKey,
                                  model: api.model,
                                  enabled: value,
                                ),
                              ),
                            ),
                    ),
                    IconButton(
                      tooltip: '删除服务',
                      icon: const AppIcon(AppGlyph.delete),
                      onPressed: _busy
                          ? null
                          : () async {
                              if (await _confirm(api.label) && mounted) {
                                await _operate(
                                  () => widget.store.removeApi(api.id),
                                );
                              }
                            },
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: ReaderUiTokens.spacingXl),
        ReaderSectionGroup(
          title: '查询选项',
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: ReaderDropdownButtonFormField<String>(
                key: ValueKey('dictionary-default-preset-${state.preset.id}'),
                initialValue: state.preset.id,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '默认预设'),
                items: [
                  for (final p in state.presets)
                    DropdownMenuItem(value: p.id, child: Text(p.name)),
                ],
                onChanged: _busy
                    ? null
                    : (id) => _operate(
                        () => widget.store.changeSettings(
                          (s) => s.copyWith(presetId: id),
                        ),
                      ),
              ),
            ),
            ReaderSwitchListTile(
              key: const ValueKey('dictionary-disable-thinking'),
              title: const Text('关闭思考'),
              subtitle: const Text('请求服务直接返回释义'),
              value: state.settings.disableThinking,
              onChanged: _busy
                  ? null
                  : (value) => _operate(
                      () => widget.store.changeSettings(
                        (s) => s.copyWith(disableThinking: value),
                      ),
                    ),
            ),
            ReaderSwitchListTile(
              key: const ValueKey('dictionary-single-use'),
              title: const Text('切换预设仅用于本次查询'),
              subtitle: const Text('关闭后，查询时切换的预设会成为下次默认值'),
              value: state.settings.singleUsePreset,
              onChanged: _busy
                  ? null
                  : (value) => _operate(
                      () => widget.store.changeSettings(
                        (s) => s.copyWith(singleUsePreset: value),
                      ),
                    ),
            ),
          ],
        ),
        const SizedBox(height: ReaderUiTokens.spacingXl),
        ReaderSectionGroup(
          title: '释义预设',
          trailing: TextButton.icon(
            key: const ValueKey('dictionary-preset-add'),
            onPressed: _busy ? null : () => _editPreset(null),
            icon: const AppIcon(AppGlyph.add, size: 18),
            label: const Text('添加自定义预设'),
          ),
          children: [
            for (final p in state.presets)
              ListTile(
                title: Text(p.name),
                subtitle: Text(
                  p.prompt,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: p.builtIn || _busy ? null : () => _editPreset(p),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: '复制预设',
                      icon: const AppIcon(AppGlyph.copy),
                      onPressed: _busy
                          ? null
                          : () => _editPreset(p, copy: true),
                    ),
                    if (!p.builtIn)
                      IconButton(
                        tooltip: '删除预设',
                        icon: const AppIcon(AppGlyph.delete),
                        onPressed: _busy
                            ? null
                            : () async {
                                if (await _confirm(p.name) && mounted) {
                                  await _operate(
                                    () => widget.store.removePreset(p.id),
                                  );
                                }
                              },
                      ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _ApiForm extends StatefulWidget {
  const _ApiForm({this.api, required this.store});
  final DictionaryStore store;
  final DictionaryApi? api;
  @override
  State<_ApiForm> createState() => _ApiFormState();
}

class _ApiFormState extends State<_ApiForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.api?.name ?? '');
  late final _url = TextEditingController(text: widget.api?.baseUrl ?? '');
  late final _key = TextEditingController(text: widget.api?.apiKey ?? '');
  late final _model = TextEditingController(text: widget.api?.model ?? '');
  final _client = DictionaryClient();
  List<String> _models = [];
  String? _message;
  bool _busy = false;
  DictionaryApi get _draft => DictionaryApi(
    id: widget.api?.id ?? 'api-${DateTime.now().microsecondsSinceEpoch}',
    name: _name.text.trim(),
    baseUrl: _url.text.trim().replaceFirst(RegExp(r'/+$'), ''),
    apiKey: _key.text.trim(),
    model: _model.text.trim(),
    enabled: widget.api?.enabled ?? true,
  );
  @override
  void dispose() {
    _client.close();
    _name.dispose();
    _url.dispose();
    _key.dispose();
    _model.dispose();
    super.dispose();
  }

  Future<void> _probe({required bool models}) async {
    if (_busy || _url.text.trim().isEmpty || _key.text.trim().isEmpty) {
      setState(() => _message = '请先填写服务地址与 API Key');
      return;
    }
    final draft = _draft;
    if (!models && draft.model.isEmpty) {
      setState(() => _message = '请先填写模型');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (models) {
        final fetched = await widget.store.library.pageCache.load(
          identity: ['词典模型', draft.baseUrl, draft.apiKey],
          fetch: () => _client.models(draft),
          encode: (models) => models,
          decode: (raw) => (raw! as List).cast<String>(),
          unavailable: (error) =>
              error is DictionaryException && error.unavailable,
        );
        if (mounted) {
          setState(() {
            _models = fetched;
            _message = '已获取 ${fetched.length} 个模型';
          });
        }
      } else {
        await _client.lookup(
          api: draft,
          preset: dictionaryBuiltInPresets.first,
          text: '词典',
        );
        if (mounted) setState(() => _message = '连接测试通过');
      }
    } on DictionaryException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ReaderSheetForm(
    title: Text(widget.api == null ? '添加释义服务' : '编辑释义服务'),
    content: Form(
      key: _form,
      child: Column(
        children: [
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: '名称（可选）'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const ValueKey('dictionary-api-url'),
            controller: _url,
            decoration: const InputDecoration(
              labelText: '服务地址',
              hintText: 'https://服务地址/v1',
            ),
            validator: (v) {
              try {
                DictionaryClient.endpoint(v ?? '');
                return null;
              } on DictionaryException catch (e) {
                return e.message;
              }
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const ValueKey('dictionary-api-key'),
            controller: _key,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(labelText: 'API Key'),
            validator: (v) => v?.trim().isEmpty ?? true ? '请输入 API Key' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const ValueKey('dictionary-api-model'),
            controller: _model,
            decoration: const InputDecoration(labelText: '模型'),
            validator: (v) => v?.trim().isEmpty ?? true ? '请输入模型' : null,
          ),
          if (_models.isNotEmpty) ...[
            const SizedBox(height: 12),
            ReaderDropdownButtonFormField<String>(
              isExpanded: true,
              decoration: const InputDecoration(labelText: '已获取模型'),
              items: [
                for (final model in _models)
                  DropdownMenuItem(value: model, child: Text(model)),
              ],
              onChanged: _busy
                  ? null
                  : (model) => setState(() => _model.text = model!),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: _busy ? null : () => _probe(models: true),
                child: const Text('获取模型'),
              ),
              OutlinedButton(
                onPressed: _busy ? null : () => _probe(models: false),
                child: const Text('测试连接'),
              ),
            ],
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(),
            ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: ReaderInlineNotice(message: _message!),
            ),
        ],
      ),
    ),
    actions: [
      FilledButton(
        key: const ValueKey('dictionary-api-save'),
        onPressed: _busy
            ? null
            : () {
                if (_form.currentState!.validate()) {
                  Navigator.pop(context, _draft);
                }
              },
        child: const Text('保存服务'),
      ),
    ],
  );
}

class _PresetForm extends StatefulWidget {
  const _PresetForm({this.preset, required this.copy});
  final DictionaryPreset? preset;
  final bool copy;
  @override
  State<_PresetForm> createState() => _PresetFormState();
}

class _PresetFormState extends State<_PresetForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(
    text: '${widget.preset?.name ?? ''}${widget.copy ? ' 副本' : ''}',
  );
  late final _prompt = TextEditingController(text: widget.preset?.prompt ?? '');
  @override
  void dispose() {
    _name.dispose();
    _prompt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ReaderSheetForm(
    title: const Text('释义预设'),
    content: Form(
      key: _form,
      child: Column(
        children: [
          TextFormField(
            key: const ValueKey('dictionary-preset-name'),
            controller: _name,
            decoration: const InputDecoration(labelText: '名称'),
            validator: (v) => v?.trim().isEmpty ?? true ? '请输入名称' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const ValueKey('dictionary-preset-prompt'),
            controller: _prompt,
            minLines: 4,
            maxLines: 10,
            decoration: const InputDecoration(
              labelText: '提示词',
              helperText: '用 {{text}} 代入选中文字；未填写占位符时追加选中文字。',
              helperMaxLines: 2,
            ),
            validator: (v) => v?.trim().isEmpty ?? true ? '请输入提示词' : null,
          ),
        ],
      ),
    ),
    actions: [
      FilledButton(
        key: const ValueKey('dictionary-preset-save'),
        onPressed: () {
          if (!_form.currentState!.validate()) return;
          Navigator.pop(
            context,
            DictionaryPreset(
              widget.preset == null || widget.copy
                  ? 'preset-${DateTime.now().microsecondsSinceEpoch}'
                  : widget.preset!.id,
              _name.text.trim(),
              _prompt.text.trim(),
            ),
          );
        },
        child: const Text('保存预设'),
      ),
    ],
  );
}
