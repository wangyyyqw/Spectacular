part of 'book_editor_local_tools.dart';

class _HealthDialog extends StatefulWidget {
  const _HealthDialog({required this.report, required this.fileName});
  final EpubHealthReport report;
  final String fileName;

  @override
  State<_HealthDialog> createState() => _HealthDialogState();
}

class _HealthDialogState extends State<_HealthDialog> {
  final _selected = <String>{};
  EpubHealthSeverity? _filter;
  String? _exportMessage;

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final issues = report.issues
        .where((issue) => _filter == null || issue.severity == _filter)
        .toList();
    return AlertDialog(
      title: const Text('编辑快照体检'),
      content: SizedBox(
        width: 780,
        height: 470,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '错误 ${report.errorCount} · 警告 ${report.warningCount} · 建议 ${report.suggestionCount}',
            ),
            const SizedBox(height: 8),
            const Text('仅提供内置快速检查。选择安全修复项后应用到工作副本，不代表 EPUBCheck 完整认证。'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('全部'),
                  selected: _filter == null,
                  onSelected: (_) => setState(() => _filter = null),
                ),
                for (final severity in EpubHealthSeverity.values)
                  ChoiceChip(
                    label: Text(severity.label),
                    selected: _filter == severity,
                    onSelected: (_) => setState(() => _filter = severity),
                  ),
              ],
            ),
            Expanded(
              child: issues.isEmpty
                  ? const Center(child: Text('当前筛选下未发现问题。'))
                  : ListView.builder(
                      itemCount: issues.length,
                      itemBuilder: (_, index) => _issue(issues[index]),
                    ),
            ),
            if (_exportMessage != null) Text(_exportMessage!),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => _export('json'),
          child: const Text('导出 JSON'),
        ),
        TextButton(
          onPressed: () => _export('html'),
          child: const Text('导出 HTML'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
        FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.pop(context, _selected.toList()),
          child: Text('应用所选修复（${_selected.length}）'),
        ),
      ],
    );
  }

  Widget _issue(EpubHealthIssue issue) {
    final subtitle =
        '${issue.severity.label} · ${issue.code}\n${issue.message}'
        '${issue.location == null ? '' : '\n${issue.location}'}'
        '${issue.fix == null ? '' : '\n可修复：${issue.fix!.label}'}';
    if (issue.fix == null) {
      return ListTile(title: Text(issue.title), subtitle: Text(subtitle));
    }
    return CheckboxListTile(
      title: Text(issue.title),
      subtitle: Text(subtitle),
      value: _selected.contains(issue.fix!.id),
      controlAffinity: ListTileControlAffinity.leading,
      onChanged: (selected) => setState(() {
        if (selected == true) {
          _selected.add(issue.fix!.id);
        } else {
          _selected.remove(issue.fix!.id);
        }
      }),
    );
  }

  Future<void> _export(String extension) async {
    try {
      final location = await getSaveLocation(
        suggestedName: '${_safeTitle(widget.fileName)}_体检.$extension',
        acceptedTypeGroups: [
          XTypeGroup(label: extension, extensions: [extension]),
        ],
      );
      if (location == null) return;
      final text = extension == 'json'
          ? widget.report.toPrettyJson()
          : widget.report.toHtml();
      await XFile.fromData(utf8.encode(text)).saveTo(location.path);
      if (mounted) setState(() => _exportMessage = '报告已导出');
    } on FileSystemException catch (error) {
      if (mounted) setState(() => _exportMessage = '报告导出失败：${error.message}');
    }
  }
}
