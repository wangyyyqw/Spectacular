part of 'book_editor_local_tools.dart';

class _NavigationDialog extends StatefulWidget {
  const _NavigationDialog({required this.document, required this.editor});
  final EpubNavigationDocument document;
  final BookEditorController editor;

  @override
  State<_NavigationDialog> createState() => _NavigationDialogState();
}

class _NavigationDialogState extends State<_NavigationDialog> {
  late final _sections = {
    for (final section in NavigationSection.values)
      section: List<NavigationEntry>.of(widget.document.entries(section)),
  };
  NavigationSection _section = NavigationSection.toc;
  String? _error;
  bool _busy = false;
  List<NavigationEntry> get _entries => _sections[_section]!;

  @override
  Widget build(BuildContext context) => ReaderSheetForm(
    title: const Text('目录与导航'),
    onClose: () {
      if (!_busy) Navigator.pop(context);
    },
    content: SizedBox(
      width: 790,
      height: 480,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('EPUB ${widget.document.epubVersion} · 链接使用 EPUB 内完整路径，允许 #锚点'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final section in NavigationSection.values)
                ChoiceChip(
                  label: Text(section.label),
                  selected: _section == section,
                  onSelected: _busy
                      ? null
                      : (_) => setState(() => _section = section),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _entries.isEmpty
                ? const Center(child: Text('此导航区块没有条目，可添加或从正文标题重建。'))
                : ListView.builder(
                    itemCount: _entries.length,
                    itemBuilder: (_, index) => _entryRow(index),
                  ),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Text(
              _error!,
              maxLines: 3,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : _regenerate,
        child: const Text('从 H1–H6 重建目录'),
      ),
      TextButton(
        onPressed: _busy ? null : () => _edit(null),
        child: const Text('添加条目'),
      ),
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _busy ? null : _save, child: const Text('校验并应用')),
    ],
  );

  Widget _entryRow(int index) {
    final entry = _entries[index];
    return ListTile(
      contentPadding: EdgeInsetsDirectional.only(
        start: 8 + (entry.level - 1) * 12,
      ),
      title: Text(entry.title.isEmpty ? '未命名条目' : entry.title),
      subtitle: Text(entry.href, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: _busy ? null : () => _edit(index),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '上移 ${entry.title}',
            icon: const AppIcon(AppGlyph.chevronUp, size: 18),
            onPressed: _busy || index == 0 ? null : () => _move(index, -1),
          ),
          IconButton(
            tooltip: '下移 ${entry.title}',
            icon: const AppIcon(AppGlyph.chevronDown, size: 18),
            onPressed: _busy || index == _entries.length - 1
                ? null
                : () => _move(index, 1),
          ),
          IconButton(
            tooltip: '删除 ${entry.title}',
            icon: const AppIcon(AppGlyph.close, size: 18),
            onPressed: _busy
                ? null
                : () => setState(() => _entries.removeAt(index)),
          ),
        ],
      ),
    );
  }

  void _move(int index, int delta) => setState(() {
    final entry = _entries.removeAt(index);
    _entries.insert(index + delta, entry);
  });

  Future<void> _edit(int? index) async {
    final entry = index == null
        ? const NavigationEntry(title: '', href: '', level: 1)
        : _entries[index];
    final changed = await _localDrawer<NavigationEntry>(
      context,
      (_) => _NavigationEntryDialog(entry: entry, section: _section),
    );
    if (changed == null || !mounted) return;
    setState(() {
      if (index == null) {
        _entries.add(changed);
      } else {
        _entries[index] = changed;
      }
      _error = null;
    });
  }

  Future<void> _regenerate() async {
    setState(() => _busy = true);
    final output = await BookEditorToolkit(widget.editor)
        .run(LocalEpubTool.navigation, options: {'regenerate': true});
    if (output != null) {
      try {
        if (!mounted) return;
        final document = output.result.data! as EpubNavigationDocument;
        setState(() {
          _sections[NavigationSection.toc] = List.of(
            document.entries(NavigationSection.toc),
          );
          _section = NavigationSection.toc;
          _error = null;
        });
      } finally {
        await output.dispose();
      }
    } else if (mounted) {
      setState(() => _error = widget.editor.error ?? '重建目录失败');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final document = widget.document.copyWith(sections: _sections);
    final output = await BookEditorToolkit(
      widget.editor,
    ).run(LocalEpubTool.validateNavigation, options: {'navigation': document});
    if (output == null) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = widget.editor.error ?? '目录校验失败';
        });
      }
      return;
    }
    try {
      final issues = output.result.data! as List<NavigationValidationIssue>;
      final errors = issues.where(
        (issue) => issue.severity == NavigationValidationSeverity.error,
      );
      if (!mounted) return;
      if (errors.isNotEmpty) {
        setState(() {
          _busy = false;
          _error = errors.take(3).map((issue) => issue.message).join('\n');
        });
      } else {
        Navigator.pop(context, document);
      }
    } finally {
      await output.dispose();
    }
  }
}

class _NavigationEntryDialog extends StatefulWidget {
  const _NavigationEntryDialog({required this.entry, required this.section});
  final NavigationEntry entry;
  final NavigationSection section;

  @override
  State<_NavigationEntryDialog> createState() => _NavigationEntryDialogState();
}

class _NavigationEntryDialogState extends State<_NavigationEntryDialog> {
  late final _title = TextEditingController(text: widget.entry.title);
  late final _href = TextEditingController(text: widget.entry.href);
  late final _semantic = TextEditingController(text: widget.entry.semanticType);
  late int _level = widget.entry.level.clamp(1, 6);
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _href.dispose();
    _semantic.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ReaderSheetForm(
    title: Text('编辑${widget.section.label}条目'),
    content: SizedBox(
      width: 540,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: '标题'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _href,
              decoration: const InputDecoration(labelText: '目标路径与锚点'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _level,
              decoration: const InputDecoration(labelText: '层级'),
              items: [
                for (final level in List.generate(6, (index) => index + 1))
                  DropdownMenuItem(value: level, child: Text('第 $level 级')),
              ],
              onChanged: (value) => _level = value ?? 1,
            ),
            if (widget.section == NavigationSection.landmarks) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _semantic,
                decoration: const InputDecoration(
                  labelText: '语义类型',
                  helperText: '例如 cover、bodymatter、toc',
                ),
              ),
            ],
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (_title.text.trim().isEmpty || _href.text.trim().isEmpty) {
            setState(() => _error = '标题与目标路径不能为空');
            return;
          }
          Navigator.pop(
            context,
            widget.entry.copyWith(
              title: _title.text.trim(),
              href: _href.text.trim(),
              level: _level,
              semanticType: _semantic.text.trim(),
              clearSourceHeadingIndex: _href.text.trim() != widget.entry.href,
            ),
          );
        },
        child: const Text('确定'),
      ),
    ],
  );
}
