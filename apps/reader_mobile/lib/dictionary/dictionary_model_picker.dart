import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/theme/reader_sheet_form.dart';

import 'dictionary_client.dart';

class DictionaryModelPicker extends StatefulWidget {
  const DictionaryModelPicker({
    super.key,
    required this.currentModel,
    required this.loadModels,
    this.initialModels = const [],
  });
  final String currentModel;
  final Future<List<String>> Function() loadModels;
  final List<String> initialModels;

  @override
  State<DictionaryModelPicker> createState() => _DictionaryModelPickerState();
}

class _DictionaryModelPickerState extends State<DictionaryModelPicker> {
  late List<String> _models = widget.initialModels;
  String _query = '';
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (_models.isEmpty) _refresh();
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final models = await widget.loadModels();
      if (mounted) setState(() => _models = models);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is DictionaryException
              ? error.message
              : '获取模型失败，可重试或返回手动填写',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.currentModel.trim();
    final models = <String>{
      if (current.isNotEmpty) current,
      ..._models,
    }.where((model) => model.toLowerCase().contains(_query)).toList();
    return ReaderSheetForm(
      title: const Text('选择 AI 模型'),
      scrollContent: false,
      // 整块列表可滚动：窄屏、大字号和键盘展开时顶部操作区随内容一起滚动。
      content: SizedBox(
        height: 420,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            TextField(
              key: const ValueKey('dictionary-model-search'),
              decoration: const InputDecoration(
                labelText: '搜索模型',
                prefixIcon: AppIcon(AppGlyph.search),
              ),
              onChanged: (value) =>
                  setState(() => _query = value.trim().toLowerCase()),
            ),
            Row(
              children: [
                Expanded(child: Text('共 ${_models.length} 个可用模型')),
                TextButton.icon(
                  key: const ValueKey('dictionary-model-refresh'),
                  onPressed: _loading ? null : _refresh,
                  icon: const AppIcon(AppGlyph.refresh, size: 18),
                  label: const Text('刷新'),
                ),
              ],
            ),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (models.isEmpty)
              SizedBox(
                height: 120,
                child: Center(
                  child: Text(_loading ? '正在获取模型…' : '没有匹配的模型，可返回手动填写'),
                ),
              )
            else
              for (final model in models)
                ListTile(
                  key: ValueKey('dictionary-model-$model'),
                  title: Text(model),
                  subtitle: model == current
                      ? Text(
                          _models.contains(model) ? '当前模型' : '当前手填模型（不在返回列表中）',
                        )
                      : null,
                  trailing: model == current
                      ? const AppIcon(AppGlyph.check)
                      : null,
                  onTap: () => Navigator.pop(context, model),
                ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, ''),
          child: const Text('手动填写'),
        ),
      ],
    );
  }
}
