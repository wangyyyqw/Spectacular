part of 'book_editor_local_tools.dart';

const _formTools = {
  LocalEpubTool.compress,
  LocalEpubTool.watermark,
  LocalEpubTool.cleanText,
  LocalEpubTool.comment,
  LocalEpubTool.footnoteToComment,
  LocalEpubTool.commentToFootnote,
  LocalEpubTool.phonetic,
};

class _ToolOptionsDialog extends StatefulWidget {
  const _ToolOptionsDialog({
    required this.tool,
    required this.title,
    required this.editor,
  });
  final LocalEpubTool tool;
  final String title;
  final BookEditorController editor;

  @override
  State<_ToolOptionsDialog> createState() => _ToolOptionsDialogState();
}

class _ToolOptionsDialogState extends State<_ToolOptionsDialog> {
  final _pattern = TextEditingController();
  final _replacement = TextEditingController();
  final _watermark = TextEditingController();
  final _footnoteColor = TextEditingController(text: '#666666');
  final _noterefColor = TextEditingController(text: '#444444');
  double _quality = 82;
  bool _pngToJpg = false;
  String _toneMode = 'mark';
  bool _annotateAll = false;
  String? _error;
  String? _matches;

  @override
  void initState() {
    super.initState();
    _pattern.text = switch (widget.tool) {
      LocalEpubTool.comment => r'【(.*?)】',
      LocalEpubTool.footnoteToComment => r'^#',
      _ => '',
    };
  }

  @override
  void dispose() {
    for (final controller in [
      _pattern,
      _replacement,
      _watermark,
      _footnoteColor,
      _noterefColor,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.tool.label),
    content: SizedBox(
      width: 620,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.tool.description),
            const SizedBox(height: 12),
            ..._fields(),
            if (_matches != null) ...[
              const SizedBox(height: 12),
              SelectableText(_matches!),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            const Text('应用到当前工作副本，可一步撤销。保存前不会覆盖原书。'),
          ],
        ),
      ),
    ),
    actions: [
      if (widget.tool == LocalEpubTool.cleanText ||
          widget.tool == LocalEpubTool.comment)
        TextButton(onPressed: _previewMatches, child: const Text('预览命中')),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _submit, child: const Text('应用到工作副本')),
    ],
  );

  List<Widget> _fields() => switch (widget.tool) {
    LocalEpubTool.compress => [
      Text('JPEG 质量：${_quality.round()}'),
      Slider(
        value: _quality,
        min: 1,
        max: 100,
        divisions: 99,
        label: '${_quality.round()}',
        onChanged: (value) => setState(() => _quality = value),
      ),
      CheckboxListTile(
        title: const Text('允许不透明 PNG 转为 JPEG'),
        subtitle: const Text('透明图保持透明；GIF 和 WebP 不参与此压缩'),
        value: _pngToJpg,
        controlAffinity: ListTileControlAffinity.leading,
        onChanged: (value) => setState(() => _pngToJpg = value ?? false),
      ),
    ],
    LocalEpubTool.watermark => [
      _field(_watermark, '水印文本', helper: '容量不足或动图将跳过；输出采用 PNG'),
    ],
    LocalEpubTool.cleanText => [
      _field(
        _pattern,
        '清理正则',
        multiline: true,
        helper: '每行一条规则，作用于正文 XHTML 源码；请先预览',
      ),
      const SizedBox(height: 12),
      _field(_replacement, '替换文本', helper: '留空表示删除；按原工具行为进行字面替换'),
    ],
    LocalEpubTool.comment => [
      _field(_pattern, '批注正则', helper: '第一个捕获组作为注释，未提供捕获组则使用完整匹配'),
    ],
    LocalEpubTool.footnoteToComment => [
      _field(_pattern, '脚注链接正则', helper: '匹配同文件 href，例如 ^#；不转换跨文件脚注'),
    ],
    LocalEpubTool.commentToFootnote => [
      _field(_footnoteColor, '脚注文字颜色'),
      const SizedBox(height: 12),
      _field(_noterefColor, '脚注标记颜色'),
    ],
    LocalEpubTool.phonetic => [
      DropdownButtonFormField<String>(
        initialValue: _toneMode,
        decoration: const InputDecoration(labelText: '声调格式'),
        items: const [
          DropdownMenuItem(value: 'mark', child: Text('声调符号')),
          DropdownMenuItem(value: 'number', child: Text('数字声调')),
          DropdownMenuItem(value: 'none', child: Text('无声调')),
        ],
        onChanged: (value) => _toneMode = value ?? 'mark',
      ),
      CheckboxListTile(
        title: const Text('全文注音'),
        subtitle: const Text('不勾选时仅处理原工具常用字表以外的汉字'),
        value: _annotateAll,
        onChanged: (value) => setState(() => _annotateAll = value ?? false),
      ),
    ],
    _ => [],
  };

  Widget _field(
    TextEditingController controller,
    String label, {
    bool multiline = false,
    String? helper,
  }) => TextField(
    controller: controller,
    minLines: multiline ? 3 : 1,
    maxLines: multiline ? 6 : 1,
    decoration: InputDecoration(
      labelText: label,
      helperText: helper,
      helperMaxLines: 3,
    ),
    onChanged: (_) => setState(() {
      _error = null;
      _matches = null;
    }),
  );

  List<RegExp> _patterns() {
    final inputs = widget.tool == LocalEpubTool.cleanText
        ? _pattern.text.split('\n').where((line) => line.trim().isNotEmpty)
        : [_pattern.text];
    if (inputs.isEmpty || inputs.any((pattern) => pattern.trim().isEmpty)) {
      throw const FormatException('请输入正则表达式');
    }
    return [
      for (final pattern in inputs)
        RegExp(pattern, dotAll: widget.tool == LocalEpubTool.comment),
    ];
  }

  void _previewMatches() {
    try {
      final patterns = _patterns();
      var count = 0;
      final examples = <String>[];
      for (final resource in widget.editor.session.resources) {
        if (!RegExp(
          r'\.(xhtml|html|htm)$',
          caseSensitive: false,
        ).hasMatch(resource.path)) {
          continue;
        }
        final source = widget.editor.session.readText(resource.path);
        for (final pattern in patterns) {
          for (final match in pattern.allMatches(source)) {
            count++;
            if (examples.length < 3) {
              final text = match.group(0)!;
              examples.add(
                '${resource.path}：${text.length > 180 ? '${text.substring(0, 180)}…' : text}',
              );
            }
          }
        }
      }
      setState(() {
        _error = null;
        _matches =
            '源码命中 $count 处${examples.isEmpty ? '' : '\n${examples.join('\n')}'}';
      });
    } on FormatException catch (failure) {
      setState(() => _error = '正则无效：${failure.message}');
    }
  }

  void _submit() {
    try {
      final options = _validatedOptions();
      Navigator.pop(context, options);
    } on FormatException catch (failure) {
      setState(() => _error = failure.message);
    }
  }

  Map<String, Object?> _validatedOptions() {
    switch (widget.tool) {
      case LocalEpubTool.compress:
        return {'quality': _quality.round(), 'pngToJpg': _pngToJpg};
      case LocalEpubTool.watermark:
        if (_watermark.text.trim().isEmpty) {
          throw const FormatException('水印文本不能为空');
        }
        return {'watermarkText': _watermark.text};
      case LocalEpubTool.cleanText:
        final patterns = _patterns();
        if (_replacement.text.contains('|||') ||
            patterns.any((pattern) => pattern.pattern.contains('|||'))) {
          throw const FormatException('规则不能包含工具保留分隔符 |||');
        }
        return {
          'patterns': [
            for (final pattern in patterns) ...[
              pattern.pattern,
              _replacement.text,
            ],
          ].join('|||'),
        };
      case LocalEpubTool.comment:
      case LocalEpubTool.footnoteToComment:
        _patterns();
        return {'pattern': _pattern.text};
      case LocalEpubTool.commentToFootnote:
        final color = RegExp(r'^#[0-9a-fA-F]{6}$');
        if (!color.hasMatch(_footnoteColor.text) ||
            !color.hasMatch(_noterefColor.text)) {
          throw const FormatException('颜色需为六位十六进制，例如 #666666');
        }
        return {
          'footnoteColor': _footnoteColor.text,
          'noterefColor': _noterefColor.text,
        };
      case LocalEpubTool.phonetic:
        return {'toneMode': _toneMode, 'annotateAll': _annotateAll};
      default:
        return {};
    }
  }
}

class _SplitDialog extends StatefulWidget {
  const _SplitDialog({required this.targets});
  final List<SplitTarget> targets;

  @override
  State<_SplitDialog> createState() => _SplitDialogState();
}

class _SplitDialogState extends State<_SplitDialog> {
  final _selected = <int>{};
  late final _boundaries = _uniqueBoundaries();

  List<int> _uniqueBoundaries() {
    final seen = <String>{};
    return [
      for (final (index, target) in widget.targets.indexed)
        if (seen.add(target.href) && index > 0) index,
    ];
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('选择分册起始章节'),
    content: SizedBox(
      width: 650,
      height: 420,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('勾选章节将成为下一册的起点。只能在正文文件边界拆分，当前书籍不修改。'),
          const SizedBox(height: 12),
          Expanded(
            child: _boundaries.isEmpty
                ? const Center(child: Text('没有可用的分册边界；可先在章节工具中拆分正文文件。'))
                : ListView.builder(
                    itemCount: _boundaries.length,
                    itemBuilder: (_, index) {
                      final boundary = _boundaries[index];
                      final target = widget.targets[boundary];
                      return CheckboxListTile(
                        title: Text(target.title),
                        subtitle: Text(target.href),
                        value: _selected.contains(boundary),
                        onChanged: (selected) => setState(() {
                          if (selected == true) {
                            _selected.add(boundary);
                          } else {
                            _selected.remove(boundary);
                          }
                        }),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: _selected.isEmpty
            ? null
            : () => Navigator.pop(context, _selected.toList()..sort()),
        child: const Text('生成分册'),
      ),
    ],
  );
}

class _FontTargetDialog extends StatefulWidget {
  const _FontTargetDialog({required this.targets});
  final FontEncryptTargets targets;

  @override
  State<_FontTargetDialog> createState() => _FontTargetDialogState();
}

class _FontTargetDialogState extends State<_FontTargetDialog> {
  late final _families = widget.targets.fontFamilies.toSet();
  late final _chapters = widget.targets.xhtmlFiles.toSet();
  bool _understood = false;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('字体加密目标'),
    content: SizedBox(
      width: 650,
      height: 450,
      child: ListView(
        children: [
          const Text('这不是密码保护：原工具通过 TTF 字形重映射和正文码点替换保持外观。复制、搜索、朗读与无障碍文本会改变。'),
          CheckboxListTile(
            title: const Text('我理解正文码点会改变'),
            value: _understood,
            onChanged: (value) => setState(() => _understood = value ?? false),
          ),
          const Divider(),
          const Text('支持的 TTF 字体族'),
          if (widget.targets.fontFamilies.isEmpty)
            const Text('未找到可加密的 TTF 字体族。'),
          for (final family in widget.targets.fontFamilies)
            _choice(family, _families),
          const Divider(),
          const Text('正文章节'),
          for (final chapter in widget.targets.xhtmlFiles)
            _choice(chapter, _chapters),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: !_understood || _families.isEmpty || _chapters.isEmpty
            ? null
            : () => Navigator.pop(context, <String, Object?>{
                'fontFamilies': _families.toList(),
                'xhtmlFiles': _chapters.toList(),
              }),
        child: const Text('应用到工作副本'),
      ),
    ],
  );

  Widget _choice(String value, Set<String> selected) => CheckboxListTile(
    title: Text(value),
    value: selected.contains(value),
    onChanged: (enabled) => setState(() {
      if (enabled == true) {
        selected.add(value);
      } else {
        selected.remove(value);
      }
    }),
  );
}
