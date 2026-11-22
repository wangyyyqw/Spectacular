import 'package:flutter/material.dart';

import '../home/discover_choice_dialog.dart';
import '../library/library_store.dart';
import 'rea_micro_controller.dart';
import 'rea_micro_manual_association.dart';

/// 手动填写出版版本，提交前预览并校验，保持本项目的表单和选择弹窗样式。
class ReaMicroManualAssociationPage extends StatefulWidget {
  const ReaMicroManualAssociationPage({
    super.key,
    required this.controller,
    required this.book,
  });
  final ReaMicroController controller;
  final BookEntry book;

  @override
  State<ReaMicroManualAssociationPage> createState() =>
      _ReaMicroManualAssociationPageState();
}

class _ReaMicroManualAssociationPageState
    extends State<ReaMicroManualAssociationPage> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.book.title);
  late final _author = TextEditingController(text: widget.book.author);
  late final _intro = TextEditingController(text: widget.book.description);
  late final _cover = TextEditingController(text: widget.book.remoteCoverUrl);
  final _words = TextEditingController();
  String _platform = ReaMicroManualAssociation.platforms.first;
  String _status = ReaMicroManualAssociation.statuses.first;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final field in [_name, _author, _intro, _cover, _words]) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _choose({required bool platform}) async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => DiscoverChoiceDialog<String>(
        title: platform ? '来源平台' : '连载状态',
        options: platform
            ? ReaMicroManualAssociation.platforms
            : ReaMicroManualAssociation.statuses,
        selected: platform ? _platform : _status,
        labelFor: (value) => value,
      ),
    );
    if (value == null || !mounted) return;
    setState(() {
      if (platform) {
        _platform = value;
      } else {
        _status = value;
      }
    });
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    final draft = ReaMicroManualAssociation(
      name: _name.text,
      author: _author.text,
      intro: _intro.text,
      publisher: _platform,
      wordCount: _words.text,
      status: _status,
      cover: _cover.text,
    );
    if (draft.error != null) {
      setState(() => _error = draft.error);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.registerAndLinkBook(
        widget.book.id,
        manual: draft,
      );
      widget.controller.scheduleReadingSync(delay: Duration.zero);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$error';
        });
      }
    }
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    int lines = 1,
    TextInputType? keyboardType,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: controller,
      enabled: !_saving,
      minLines: lines,
      maxLines: lines == 1 ? 1 : 8,
      maxLength: label == '简介' ? 2000 : null,
      keyboardType: keyboardType,
      decoration: InputDecoration(labelText: label),
      validator: (value) =>
          value?.trim().isEmpty != false ? '$label不能为空' : null,
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Scaffold(
      appBar: AppBar(title: const Text('手动关联')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  '填写要关联的版本信息',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                const Text('关联会承接本书已有阅读数据，联网后继续上传。'),
                const SizedBox(height: 18),
                _field('书名', _name),
                _field('作者', _author),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving
                            ? null
                            : () => _choose(platform: true),
                        child: Text(_platform),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () => _choose(platform: false),
                      child: Text(_status),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _field('字数', _words),
                _field('封面地址', _cover, keyboardType: TextInputType.url),
                _field('简介', _intro, lines: 4),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            key: const ValueKey('manual-association-save'),
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.link),
            label: Text(_saving ? '正在保存关联…' : '保存并关联'),
          ),
        ),
      ),
    ),
  );
}
