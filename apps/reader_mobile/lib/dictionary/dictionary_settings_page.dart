import 'dart:convert';

import 'package:reader_ui/theme/reader_switch.dart';
import 'package:reader_ui/theme/reader_ui_components.dart';
import 'package:reader_ui/theme/reader_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:html/parser.dart' as html;
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';
import 'package:reader_ui/theme/reader_sheet_form.dart';

import 'dictionary_client.dart';
import 'dictionary_rule.dart';
import 'dictionary_rule_client.dart';
import 'dictionary_store.dart';
import 'dictionary_model_picker.dart';
import 'local_dictionary_store.dart';

class DictionarySettingsPage extends StatefulWidget {
  const DictionarySettingsPage({super.key, required this.store});
  final DictionaryStore store;
  @override
  State<DictionarySettingsPage> createState() => _DictionarySettingsPageState();
}

class _DictionarySettingsPageState extends State<DictionarySettingsPage> {
  DictionaryState? _state;
  List<LocalDictionaryEntry> _locals = [];
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
      final locals = await widget.store.locals.load();
      if (mounted) {
        setState(() {
          _state = state;
          _locals = locals;
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
          () => _error = error is LocalDictionaryException
              ? error.message
              : error is FormatException
              ? error.message
              : '保存失败，请重试',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importLocal() => _operate(() async {
    // Android 未登记 .mdx/.mdd 的 MIME，按扩展名过滤会让文件可见但不可选；
    // 这里多选任意文件，导入前再校验实际扩展名和同名分卷。
    final files = await FilePicker.pickFiles(
      dialogTitle: '选择 MDX，可长按多选同名 MDD 与 CSS',
    );
    if (files.isEmpty) return;
    final paths = [
      for (final file in files)
        if (file.path != null) file.path!,
    ];
    if (paths.length != files.length) {
      throw const LocalDictionaryException('所选文件无法读取，请重新选择本机文件');
    }
    await widget.store.locals.importFiles(paths);
  });

  Future<void> _editRule([DictionaryRule? rule]) async {
    final next = await showReaderDrawer<DictionaryRule>(
      context: context,
      builder: (_) => _RuleForm(rule: rule),
    );
    if (next != null && mounted) {
      await _operate(() => widget.store.saveRule(next));
    }
  }

  Future<void> _importRules() => _operate(() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) throw const FormatException('剪贴板没有规则 JSON');
    final rules = decodeDictionaryRules(text);
    await widget.store.saveRules(rules);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已导入 ${rules.length} 条规则')));
    }
  });

  Future<void> _exportRules() async {
    final rules = _state?.rules ?? const <DictionaryRule>[];
    if (rules.isEmpty) {
      setState(() => _error = '还没有可导出的在线词典规则');
      return;
    }
    await Clipboard.setData(
      ClipboardData(
        text: const JsonEncoder.withIndent('  ').convert({
          'version': 1,
          'rules': rules.map((rule) => rule.toJson()).toList(),
        }),
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已复制 ${rules.length} 条规则')));
    }
  }

  Future<void> _copyRule(DictionaryRule rule) => _editRule(
    rule.copyWith(
      id: 'rule-${DateTime.now().microsecondsSinceEpoch}',
      name: '${rule.name} 副本',
      builtIn: false,
      enabled: true,
    ),
  );

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
                  description: _error,
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
          const SizedBox(height: 12),
        ],
        if (_error != null) ...[
          ReaderInlineNotice(message: _error!, isError: true),
          const SizedBox(height: 16),
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
                    DropdownMenuItem(
                      value: api.id,
                      enabled: api.enabled,
                      child: Text('${api.label}${api.enabled ? '' : '（已停用）'}'),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (id) => _operate(
                        () => widget.store.changeSettings(
                          (s) => s.copyWith(
                            apiId: id,
                            sourceId: s.sourceId.startsWith('ai:')
                                ? (id == null || id.isEmpty ? '' : 'ai:$id')
                                : s.sourceId,
                          ),
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
        const SizedBox(height: 20),
        ReaderSectionGroup(
          title: '本地词典',
          trailing: TextButton.icon(
            key: const ValueKey('dictionary-local-import'),
            onPressed: _busy || !widget.store.locals.canImport
                ? null
                : _importLocal,
            icon: const AppIcon(AppGlyph.add, size: 18),
            label: const Text('导入 MDX/MDD'),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                widget.store.locals.canImport
                    ? '每次选择一个 MDX，可同时选择同名 MDD 分卷和 CSS。优先离线查词，未命中不会自动请求 AI。\n支持 1.x / 2.x 的未压缩或 zlib 词库，不支持 LZO、3.0、记录块加密和词库脚本。'
                    : '当前为临时模式，无法持久保存本地词典。',
              ),
            ),
            if (_locals.isEmpty) const ListTile(title: Text('尚未导入本地词典')),
            for (final entry in _locals)
              ListTile(
                title: Text(entry.name),
                subtitle: Text(
                  '${entry.wordCount} 个词条 · ${entry.mddFiles.length} 个资源包',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ReaderSwitch(
                      value: entry.enabled,
                      onChanged: _busy
                          ? null
                          : (value) => _operate(
                              () => widget.store.locals.setEnabled(
                                entry.id,
                                value,
                              ),
                            ),
                    ),
                    IconButton(
                      tooltip: '移除本地词典',
                      icon: const AppIcon(AppGlyph.delete),
                      onPressed: _busy
                          ? null
                          : () async {
                              final confirmed = await showReaderConfirmDialog(
                                context: context,
                                title: '移除“${entry.name}”？',
                                message: '仅删除应用内的词库副本和索引，不影响原始文件、书籍或笔记。',
                                confirmLabel: '移除',
                                destructive: true,
                              );
                              if (confirmed && mounted) {
                                await _operate(
                                  () => widget.store.locals.remove(entry.id),
                                );
                              }
                            },
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        ReaderSectionGroup(
          title: '在线词典规则',
          trailing: TextButton.icon(
            key: const ValueKey('dictionary-rule-add'),
            onPressed: _busy ? null : () => _editRule(),
            icon: const AppIcon(AppGlyph.add, size: 18),
            label: const Text('添加在线词典'),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                '用 URL 模板和提取规则查询网页或接口，{{word}} 代入查询词。内置规则可停用或复制修改，不能删除；站点改版或要求验证时可能失效。',
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    key: const ValueKey('dictionary-rule-import'),
                    onPressed: _busy ? null : _importRules,
                    child: const Text('从剪贴板导入'),
                  ),
                  OutlinedButton(
                    key: const ValueKey('dictionary-rule-export'),
                    onPressed: _busy ? null : _exportRules,
                    child: const Text('复制全部规则'),
                  ),
                ],
              ),
            ),
            if (state.rules.isEmpty) const ListTile(title: Text('尚未添加在线词典规则')),
            for (final rule in state.rules)
              ListTile(
                key: ValueKey('dictionary-rule-${rule.id}'),
                title: Text('${rule.name}${rule.builtIn ? ' · 内置' : ''}'),
                subtitle: Text(
                  [
                    '${rule.method} · ${Uri.tryParse(rule.buildUrl('词'))?.host ?? ''} · ${rule.extract.label}',
                    if (rule.note.isNotEmpty) rule.note,
                  ].join('\n'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                isThreeLine: rule.note.isNotEmpty,
                onTap: _busy
                    ? null
                    : rule.builtIn
                    ? () => _copyRule(rule)
                    : () => _editRule(rule),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ReaderSwitch(
                      value: rule.enabled,
                      onChanged: _busy
                          ? null
                          : (value) => _operate(
                              () => widget.store.setRuleEnabled(rule.id, value),
                            ),
                    ),
                    if (rule.builtIn)
                      IconButton(
                        tooltip: '复制内置规则',
                        icon: const AppIcon(AppGlyph.copy),
                        onPressed: _busy ? null : () => _copyRule(rule),
                      )
                    else
                      IconButton(
                        tooltip: '删除在线词典',
                        icon: const AppIcon(AppGlyph.delete),
                        onPressed: _busy
                            ? null
                            : () async {
                                final confirmed = await showReaderConfirmDialog(
                                  context: context,
                                  title: '删除“${rule.name}”？',
                                  message: '只删除这条在线词典规则，不影响 AI 服务、本地词典和阅读数据。',
                                  confirmLabel: '删除',
                                  destructive: true,
                                );
                                if (confirmed && mounted) {
                                  await _operate(
                                    () => widget.store.removeRule(rule.id),
                                  );
                                }
                              },
                      ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        ReaderSectionGroup(
          title: '释义预设',
          trailing: TextButton.icon(
            key: const ValueKey('dictionary-preset-add'),
            onPressed: _busy ? null : () => _editPreset(null),
            icon: const AppIcon(AppGlyph.add, size: 18),
            label: const Text('添加自定义预设'),
          ),
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
  final DictionaryApi? api;
  final DictionaryStore store;
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
  final _modelFocus = FocusNode();
  List<String> _models = [];
  (String, String)? _modelsFor;
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
    _modelFocus.dispose();
    super.dispose();
  }

  Future<void> _selectModel() async {
    if (!_validateCredentials()) return;
    final draft = _draft;
    final identity = (draft.baseUrl, draft.apiKey);
    final model = await showReaderDrawer<String>(
      context: context,
      builder: (_) => DictionaryModelPicker(
        currentModel: _model.text,
        initialModels: _modelsFor == identity ? _models : [],
        loadModels: () async {
          final fetched = await widget.store.library.pageCache.load(
            identity: ['词典模型', draft.baseUrl, draft.apiKey],
            fetch: () => _client.models(draft),
            encode: (models) => models,
            decode: (raw) => (raw! as List).cast<String>(),
            unavailable: (error) =>
                error is DictionaryException && error.unavailable,
          );
          if (mounted && (_draft.baseUrl, _draft.apiKey) == identity) {
            _models = fetched;
            _modelsFor = identity;
          }
          return fetched;
        },
      ),
    );
    if (!mounted || model == null) return;
    if (model.isEmpty) {
      _modelFocus.requestFocus();
    } else {
      setState(() => _model.text = model);
    }
  }

  bool _validateCredentials() {
    if (_busy || _url.text.trim().isEmpty || _key.text.trim().isEmpty) {
      setState(() => _message = '请先填写服务地址与 API Key');
      return false;
    }
    try {
      DictionaryClient.endpoint(_url.text);
      return true;
    } on DictionaryException catch (error) {
      setState(() => _message = error.message);
      return false;
    }
  }

  void _credentialsChanged(String _) => setState(() {
    _models = [];
    _modelsFor = null;
    _message = null;
  });

  Future<void> _probe() async {
    if (!_validateCredentials()) return;
    final draft = _draft;
    if (draft.model.isEmpty) {
      setState(() => _message = '请先填写模型');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await _client.lookup(
        api: draft,
        preset: dictionaryBuiltInPresets.first,
        text: '词典',
      );
      if (mounted &&
          (_draft.baseUrl, _draft.apiKey, _draft.model) ==
              (draft.baseUrl, draft.apiKey, draft.model)) {
        setState(() => _message = '连接测试通过');
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
          TextFormField(
            key: const ValueKey('dictionary-api-url'),
            controller: _url,
            enabled: !_busy,
            onChanged: _credentialsChanged,
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
          TextFormField(
            key: const ValueKey('dictionary-api-key'),
            controller: _key,
            enabled: !_busy,
            onChanged: _credentialsChanged,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(labelText: 'API Key'),
            validator: (v) => v?.trim().isEmpty ?? true ? '请输入 API Key' : null,
          ),
          TextFormField(
            key: const ValueKey('dictionary-api-model'),
            controller: _model,
            enabled: !_busy,
            focusNode: _modelFocus,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: '模型',
              helperText: '从服务获取并搜索，也可直接填写模型 ID',
            ),
            validator: (v) => v?.trim().isEmpty ?? true ? '请输入模型' : null,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            children: [
              OutlinedButton(
                key: const ValueKey('dictionary-model-select'),
                onPressed: _busy ? null : _selectModel,
                child: const Text('选择模型'),
              ),
              OutlinedButton(
                onPressed: _busy ? null : _probe,
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
            Padding(padding: const EdgeInsets.all(12), child: Text(_message!)),
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

class _RuleForm extends StatefulWidget {
  const _RuleForm({this.rule});
  final DictionaryRule? rule;
  @override
  State<_RuleForm> createState() => _RuleFormState();
}

class _RuleFormState extends State<_RuleForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.rule?.name ?? '');
  late final _url = TextEditingController(text: widget.rule?.url ?? '');
  late final _headers = TextEditingController(text: widget.rule?.headers ?? '');
  late final _body = TextEditingController(text: widget.rule?.body ?? '');
  late final _selector = TextEditingController(
    text: widget.rule?.selector ?? '',
  );
  late final _remove = TextEditingController(text: widget.rule?.remove ?? '');
  late final _testWord = TextEditingController(text: '词典');
  late String _method = widget.rule?.method ?? 'GET';
  late DictionaryExtractMode _extract =
      widget.rule?.extract ?? DictionaryExtractMode.auto;
  late DictionaryResultFormat _format =
      widget.rule?.format ?? DictionaryResultFormat.auto;
  late String _encoding = widget.rule?.encoding ?? 'auto';
  final _client = DictionaryRuleClient();
  DictionaryRuleResult? _testResult;
  String? _message;
  bool _testing = false;

  DictionaryRule get _draft => DictionaryRule(
    id: widget.rule?.id ?? 'rule-${DateTime.now().microsecondsSinceEpoch}',
    name: _name.text.trim(),
    url: _url.text.trim(),
    method: _method,
    headers: _headers.text.trim(),
    body: _body.text,
    extract: _extract,
    selector: _selector.text.trim(),
    remove: _remove.text.trim(),
    format: _format,
    encoding: _encoding,
    enabled: widget.rule?.enabled ?? true,
  );

  @override
  void dispose() {
    _client.close();
    _name.dispose();
    _url.dispose();
    _headers.dispose();
    _body.dispose();
    _selector.dispose();
    _remove.dispose();
    _testWord.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    if (_testing) return;
    final draft = _draft;
    try {
      validateDictionaryRule(draft);
      if (_testWord.text.trim().isEmpty) {
        throw const FormatException('请输入测试词语');
      }
    } on FormatException catch (error) {
      setState(() => _message = error.message);
      return;
    }
    setState(() {
      _testing = true;
      _message = null;
      _testResult = null;
    });
    try {
      final result = await _client.lookup(rule: draft, word: _testWord.text);
      if (mounted) setState(() => _testResult = result);
    } on DictionaryRuleException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (_) {
      if (mounted) setState(() => _message = '测试失败，请检查规则');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  String _preview(DictionaryRuleResult result) {
    var value = result.value;
    if (result.html) {
      value = html.parseFragment(value).text?.trim() ?? '';
    }
    value = value.trim();
    if (value.isEmpty) return '（提取到 HTML 内容）';
    return value.length > 1200 ? '${value.substring(0, 1200)}…' : value;
  }

  @override
  Widget build(BuildContext context) => ReaderSheetForm(
    title: Text(widget.rule == null ? '添加在线词典' : '编辑在线词典'),
    content: Form(
      key: _form,
      child: Column(
        children: [
          TextFormField(
            key: const ValueKey('dictionary-rule-name'),
            controller: _name,
            decoration: const InputDecoration(labelText: '名称'),
          ),
          TextFormField(
            key: const ValueKey('dictionary-rule-url'),
            controller: _url,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: '查询地址',
              hintText: 'https://example.com/search?q={{word}}',
              helperText: '{{word}} 会自动做 URL 编码',
              helperMaxLines: 2,
            ),
          ),
          ReaderDropdownButtonFormField<String>(
            key: const ValueKey('dictionary-rule-method'),
            initialValue: _method,
            decoration: const InputDecoration(labelText: '请求方式'),
            items: const [
              DropdownMenuItem(value: 'GET', child: Text('GET')),
              DropdownMenuItem(value: 'POST', child: Text('POST')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _method = value);
            },
          ),
          TextFormField(
            key: const ValueKey('dictionary-rule-headers'),
            controller: _headers,
            minLines: 2,
            maxLines: 5,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: '请求头（可选）',
              hintText: '{"User-Agent":"Mozilla/5.0"}',
              helperText: 'JSON 对象；不要在这里填写无法公开的 Cookie',
              helperMaxLines: 2,
            ),
          ),
          TextFormField(
            key: const ValueKey('dictionary-rule-body'),
            controller: _body,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: '请求体（仅 POST）',
              helperText: '{{word}} 直接代入查询词，不额外编码',
              helperMaxLines: 2,
            ),
          ),
          ReaderDropdownButtonFormField<DictionaryExtractMode>(
            key: const ValueKey('dictionary-rule-extract'),
            initialValue: _extract,
            decoration: const InputDecoration(labelText: '提取方式'),
            items: [
              for (final mode in DictionaryExtractMode.values)
                DropdownMenuItem(value: mode, child: Text(mode.label)),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _extract = value);
            },
          ),
          if (_extract != DictionaryExtractMode.auto &&
              _extract != DictionaryExtractMode.text)
            TextFormField(
              key: const ValueKey('dictionary-rule-selector'),
              controller: _selector,
              minLines: 1,
              maxLines: 4,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: '提取规则',
                hintText: switch (_extract) {
                  DictionaryExtractMode.css => 'div.entry 或 div.entry@text',
                  DictionaryExtractMode.json => 'data.items[0].definition',
                  DictionaryExtractMode.regex => '释义：(.+)',
                  _ => '',
                },
                helperText: switch (_extract) {
                  DictionaryExtractMode.css => 'CSS 选择器；加 @text 只取文字',
                  DictionaryExtractMode.json => '用点号或 [数字] 访问 JSON 字段',
                  DictionaryExtractMode.regex => '取第一个捕获组，没有分组时取整个匹配',
                  _ => null,
                },
                helperMaxLines: 2,
              ),
            ),
          if (_extract == DictionaryExtractMode.css)
            TextFormField(
              key: const ValueKey('dictionary-rule-remove'),
              controller: _remove,
              minLines: 1,
              maxLines: 4,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: '先移除的元素（可选）',
                hintText: 'script,style,header,footer',
                helperText: '用逗号分隔 CSS 选择器，在提取前移除',
                helperMaxLines: 2,
              ),
            ),
          ReaderDropdownButtonFormField<DictionaryResultFormat>(
            key: const ValueKey('dictionary-rule-format'),
            initialValue: _format,
            decoration: const InputDecoration(
              labelText: '结果格式',
              helperText: '自动：按提取结果是否包含 HTML 标签选择',
              helperMaxLines: 2,
            ),
            items: [
              for (final format in DictionaryResultFormat.values)
                DropdownMenuItem(value: format, child: Text(format.label)),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _format = value);
            },
          ),
          ReaderDropdownButtonFormField<String>(
            key: const ValueKey('dictionary-rule-encoding'),
            initialValue: _encoding,
            decoration: const InputDecoration(labelText: '编码'),
            items: const [
              DropdownMenuItem(value: 'auto', child: Text('自动')),
              DropdownMenuItem(value: 'utf-8', child: Text('UTF-8')),
              DropdownMenuItem(value: 'gbk', child: Text('GBK')),
              DropdownMenuItem(value: 'gb18030', child: Text('GB18030')),
              DropdownMenuItem(value: 'big5', child: Text('Big5')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _encoding = value);
            },
          ),
          const Divider(height: 28),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: const ValueKey('dictionary-rule-test-word'),
                  controller: _testWord,
                  decoration: const InputDecoration(labelText: '测试词语'),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                key: const ValueKey('dictionary-rule-test'),
                onPressed: _testing ? null : _test,
                child: Text(_testing ? '测试中…' : '测试'),
              ),
            ],
          ),
          if (_testing)
            const Padding(
              padding: EdgeInsets.all(12),
              child: LinearProgressIndicator(),
            ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _message!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_testResult != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest
                    .withValues(alpha: .35),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _testResult!.html ? '测试结果（HTML）' : '测试结果',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 6),
                  SelectableText(_preview(_testResult!)),
                ],
              ),
            ),
        ],
      ),
    ),
    actions: [
      FilledButton(
        key: const ValueKey('dictionary-rule-save'),
        onPressed: _testing
            ? null
            : () {
                final draft = _draft;
                try {
                  validateDictionaryRule(draft);
                } on FormatException catch (error) {
                  setState(() => _message = error.message);
                  return;
                }
                Navigator.pop(context, draft);
              },
        child: const Text('保存在线词典'),
      ),
    ],
  );
}
