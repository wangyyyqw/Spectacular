import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';

import 'book_source_models.dart';
import 'book_source_login_config.dart';
import 'online_book_controller.dart';
import 'online_search_page.dart';

/// 在线书源管理。
class OnlineSourcePage extends StatefulWidget {
  const OnlineSourcePage({super.key, required this.controller});

  final OnlineBookController controller;

  @override
  State<OnlineSourcePage> createState() => _OnlineSourcePageState();
}

class _OnlineSourcePageState extends State<OnlineSourcePage> {
  bool _importing = false;
  String? _loggingInSourceId;

  @override
  void initState() {
    super.initState();
    widget.controller.initialize();
  }

  Future<void> _showAddMenu() async {
    if (_importing) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              key: const ValueKey<String>('online-source-import-clipboard'),
              leading: const AppIcon(AppGlyph.copy),
              title: const Text('从剪贴板导入'),
              subtitle: const Text('复制 JSON 书源或下载链接后点这里'),
              onTap: () => Navigator.of(context).pop('clipboard'),
            ),
            ListTile(
              key: const ValueKey<String>('online-source-import-file'),
              leading: const AppIcon(AppGlyph.folder),
              title: const Text('从文件导入'),
              subtitle: const Text('支持 JSON 或 TXT，只导入单个书源'),
              onTap: () => Navigator.of(context).pop('file'),
            ),
            ListTile(
              key: const ValueKey<String>('online-source-import-url'),
              leading: const AppIcon(AppGlyph.link),
              title: const Text('从链接导入'),
              subtitle: const Text('下载远程 JSON 书源'),
              onTap: () => Navigator.of(context).pop('url'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'clipboard':
        await _importClipboard();
      case 'file':
        await _importFile();
      case 'url':
        await _importUrl();
    }
  }

  Future<void> _importClipboard() async {
    await _runImport(widget.controller.importFromClipboard);
  }

  Future<void> _importFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const <String>[
          'json',
          'txt',
          'rmonline',
          'rmsource',
        ],
      );
      final path = result.isEmpty ? null : result.single.path;
      if (path == null || !mounted) return;
      await _runImport(() => widget.controller.importFile(path));
    } on Object catch (error) {
      _showError('选择书源文件失败：$error');
    }
  }

  Future<void> _importUrl() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('从链接导入'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'https://example.com/book-source.json',
            labelText: '书源地址',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('导入'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (url == null || url.isEmpty || !mounted) return;
    await _runImport(() => widget.controller.importUrl(url));
  }

  Future<void> _runImport(Future<BookSource?> Function() operation) async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final source = await operation();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(source == null ? '书源已导入' : '已导入 ${source.name}'),
        ),
      );
    } on Object catch (error) {
      _showError('导入失败：$error');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _confirmRemove(BookSource source) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除 ${source.name}'),
        content: const Text('只删除本机保存的书源，不会删除已经导入书架的书籍。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.controller.removeSource(source.id);
    } on Object catch (error) {
      _showError('删除失败：$error');
    }
  }

  Future<void> _handleLogin(BookSource source) async {
    if (!source.hasLoginConfig || _loggingInSourceId != null) return;
    if (widget.controller.isLoggedIn(source)) {
      final action = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const AppIcon(AppGlyph.profile),
                title: Text('${source.name} 已登录'),
                subtitle: const Text('登录信息已保存在本机，可用于书源请求。'),
              ),
              ListTile(
                leading: const AppIcon(AppGlyph.lock),
                title: const Text('重新登录'),
                onTap: () => Navigator.of(context).pop('login'),
              ),
              ListTile(
                leading: const AppIcon(AppGlyph.delete),
                title: const Text('清除登录'),
                onTap: () => Navigator.of(context).pop('logout'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
      if (!mounted || action == null) return;
      if (action == 'logout') {
        await widget.controller.logout(source);
        _showError('已清除 ${source.name} 的登录信息');
        return;
      }
      if (action != 'login') return;
    }
    await _openLogin(source);
  }

  Future<void> _openLogin(BookSource source) async {
    final fields = widget.controller.auth.fieldsFor(source);
    Map<String, String>? credentials;
    if (fields.isNotEmpty) {
      credentials = await _enterCredentials(source, fields);
      if (!mounted || credentials == null) return;
    }
    setState(() => _loggingInSourceId = source.id);
    try {
      final result = await widget.controller.login(
        source,
        credentials: credentials,
      );
      _showError(result.message);
    } on Object catch (error) {
      _showError('登录失败：$error');
    } finally {
      if (mounted) setState(() => _loggingInSourceId = null);
    }
  }

  Future<Map<String, String>?> _enterCredentials(
    BookSource source,
    List<BookSourceLoginField> fields,
  ) async {
    final saved = widget.controller.cookieStore.loginInfo(source);
    final inputs = {
      for (final field in fields)
        field.name: TextEditingController(
          text: saved[field.name] ?? field.defaultValue,
        ),
    };
    try {
      return await showDialog<Map<String, String>>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('登录 ${source.name}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final field in fields)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      key: ValueKey('online-login-field-${field.name}'),
                      controller: inputs[field.name],
                      obscureText: field.secret,
                      autocorrect: false,
                      enableSuggestions: !field.secret,
                      decoration: InputDecoration(labelText: field.name),
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
              key: const ValueKey('online-login-submit'),
              onPressed: () => Navigator.pop(context, {
                for (final entry in inputs.entries) entry.key: entry.value.text,
              }),
              child: const Text('登录'),
            ),
          ],
        ),
      );
    } finally {
      // 等待对话框出场动画结束，避免仍在布局的输入框读取已释放控制器。
      await Future<void>.delayed(const Duration(milliseconds: 250));
      for (final input in inputs.values) {
        input.dispose();
      }
    }
  }

  Future<void> _openSearch() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => OnlineSearchPage(controller: widget.controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, child) {
        final controller = widget.controller;
        final sources = controller.sources;
        return Scaffold(
          appBar: AppBar(
            title: const Text('在线书源'),
            actions: <Widget>[
              IconButton(
                key: const ValueKey<String>('online-source-search'),
                tooltip: '搜索在线书籍',
                onPressed: controller.enabledCount == 0 ? null : _openSearch,
                icon: const AppIcon(AppGlyph.search),
              ),
              IconButton(
                key: const ValueKey<String>('online-source-add'),
                tooltip: '添加书源',
                onPressed: _importing ? null : _showAddMenu,
                icon: _importing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const AppIcon(AppGlyph.add),
              ),
            ],
          ),
          body: _buildBody(sources, controller),
        );
      },
    );
  }

  Widget _buildBody(List<BookSource> sources, OnlineBookController controller) {
    if (controller.loading && !controller.initialized) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = controller.error;
    if (error != null) {
      return _ErrorState(
        message: error,
        onRetry: () => controller.initialize(refresh: true),
      );
    }
    if (sources.isEmpty) {
      return _EmptyState(onAdd: _showAddMenu);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
          child: Text(
            '已启用 ${controller.enabledCount} / ${sources.length} 个书源。'
            '搜索与下载会直接访问书源站点。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        for (final source in sources)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              key: ValueKey<String>('online-source-${source.id}'),
              leading: CircleAvatar(child: Text(_initial(source.name))),
              title: Text(source.name, maxLines: 1),
              subtitle: Text(
                <String>[
                  if (source.group.isNotEmpty) source.group,
                  '${source.search.bookList.isEmpty ? '无搜索' : '可搜索'}'
                      '${source.hasLoginConfig ? (controller.isLoggedIn(source) ? '·已登录' : '·需登录') : ''}',
                ].join('\n'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (source.hasLoginConfig)
                    IconButton(
                      key: ValueKey<String>('online-source-login-${source.id}'),
                      tooltip: controller.isLoggedIn(source) ? '登录状态' : '登录书源',
                      onPressed: _loggingInSourceId == source.id
                          ? null
                          : () => _handleLogin(source),
                      icon: _loggingInSourceId == source.id
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : AppIcon(
                              controller.isLoggedIn(source)
                                  ? AppGlyph.checkCircle
                                  : AppGlyph.profile,
                            ),
                    ),
                  Switch(
                    key: ValueKey<String>('online-source-enabled-${source.id}'),
                    value: source.enabled,
                    onChanged: (value) async {
                      try {
                        await controller.setSourceEnabled(source.id, value);
                      } on Object catch (error) {
                        _showError('保存失败：$error');
                      }
                    },
                  ),
                  IconButton(
                    tooltip: '删除书源',
                    onPressed: () => _confirmRemove(source),
                    icon: const AppIcon(AppGlyph.delete),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  String _initial(String name) {
    final trimmed = name.trim();
    return trimmed.isEmpty ? '源' : trimmed.characters.first;
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const AppIcon(AppGlyph.link, size: 48),
            const SizedBox(height: 18),
            Text('还没有在线书源', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
              '导入阅读/Legado JSON 书源后，可以搜索书名并下载正文生成 EPUB。',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const AppIcon(AppGlyph.add),
              label: const Text('添加书源'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const AppIcon(AppGlyph.warning, size: 42),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
