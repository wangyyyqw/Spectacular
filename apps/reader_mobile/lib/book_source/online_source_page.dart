import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:reader_ui/theme/reader_switch.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';
import 'package:reader_ui/theme/reader_ui_components.dart';

import 'book_source_models.dart';
import 'book_source_login_dialog.dart';
import 'online_book_controller.dart';
import 'online_book_detail_page.dart';
import 'online_search_page.dart';

/// 在线书源管理。
class OnlineSourcePage extends StatefulWidget {
  const OnlineSourcePage({super.key, required this.controller, this.onRead});

  final OnlineBookController controller;
  final OnlineBookReadCallback? onRead;

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
    final action = await showReaderActionSheet<String>(
      context: context,
      title: '导入书源',
      actions: const [
        ReaderSheetAction(
          key: ValueKey<String>('online-source-import-clipboard'),
          value: 'clipboard',
          icon: AppIcon(AppGlyph.copy),
          title: '从剪贴板导入',
          subtitle: '复制 JSON 书源或下载链接后点这里',
        ),
        ReaderSheetAction(
          key: ValueKey<String>('online-source-import-file'),
          value: 'file',
          icon: AppIcon(AppGlyph.folder),
          title: '从文件导入',
          subtitle: '支持 JSON、TXT 或含 JSON 的书源压缩包',
        ),
        ReaderSheetAction(
          key: ValueKey<String>('online-source-import-url'),
          value: 'url',
          icon: AppIcon(AppGlyph.link),
          title: '从链接导入',
          subtitle: '下载远程 JSON 书源',
        ),
      ],
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
          'zip',
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
    final url = await showReaderDialog<String>(
      context: context,
      builder: (context) => ReaderFrostedAlertDialog(
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
          content: Text(
            widget.controller.lastImportedCount > 1
                ? '已导入 ${widget.controller.lastImportedCount} 个书源'
                : source == null
                ? '书源已导入'
                : '已导入 ${source.name}',
          ),
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
    final confirmed = await showReaderConfirmDialog(
      context: context,
      title: '删除 ${source.name}',
      message: '只删除本机保存的书源，不会删除已经导入书架的书籍。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await widget.controller.removeSource(source.id);
    } on Object catch (error) {
      _showError('删除失败：$error');
    }
  }

  Future<void> _handleLogin(BookSource source) async {
    if (!source.hasLoginConfig || _loggingInSourceId != null) return;
    if (widget.controller.isLoggedIn(source)) {
      final action = await showReaderActionSheet<String>(
        context: context,
        title: '${source.name} 已登录',
        subtitle: '登录信息已保存在本机，可用于书源请求。',
        actions: const [
          ReaderSheetAction(
            value: 'login',
            icon: AppIcon(AppGlyph.lock),
            title: '重新登录',
          ),
          ReaderSheetAction(
            value: 'logout',
            icon: AppIcon(AppGlyph.delete),
            title: '清除登录',
            destructive: true,
          ),
        ],
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
    setState(() => _loggingInSourceId = source.id);
    try {
      final rows = await widget.controller.auth.rowsFor(
        source,
        widget.controller.cookieStore,
      );
      if (!mounted) return;
      Map<String, String>? credentials;
      if (rows.isNotEmpty) {
        setState(() => _loggingInSourceId = null);
        credentials = await showReaderDialog<Map<String, String>>(
          context: context,
          barrierDismissible: false,
          builder: (context) => BookSourceLoginDialog(
            source: source,
            controller: widget.controller,
            rows: rows,
          ),
        );
        if (!mounted || credentials == null) return;
        setState(() => _loggingInSourceId = source.id);
      }
      final result = await widget.controller.login(
        source,
        credentials: credentials,
      );
      _showError(result.message);
    } on Object {
      _showError('登录失败，请检查网络和书源配置');
    } finally {
      if (mounted) setState(() => _loggingInSourceId = null);
    }
  }

  Future<void> _openSearch() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => OnlineSearchPage(
          controller: widget.controller,
          onRead: widget.onRead,
        ),
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
                onPressed: controller.searchableCount == 0 ? null : _openSearch,
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
          body: SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: ReaderUiTokens.pageMaxWidth,
                ),
                child: _buildBody(sources, controller),
              ),
            ),
          ),
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
      return ReaderEmptyState(
        icon: const AppIcon(AppGlyph.warning),
        title: '书源加载失败',
        description: error,
        action: FilledButton.tonal(
          onPressed: () => controller.initialize(refresh: true),
          child: const Text('重试'),
        ),
      );
    }
    if (sources.isEmpty) {
      return ReaderEmptyState(
        icon: const AppIcon(AppGlyph.link),
        title: '还没有在线书源',
        description: '导入阅读/Legado JSON 书源',
        action: FilledButton.icon(
          onPressed: _showAddMenu,
          icon: const AppIcon(AppGlyph.add),
          label: const Text('添加书源'),
        ),
      );
    }
    return ListView(
      padding: ReaderUiTokens.pagePadding,
      children: <Widget>[
        ReaderSectionGroup(
          title: '书源列表（已启用 ${controller.enabledCount} / ${sources.length}）',
          footer: '搜索与下载会直接访问书源站点。',
          children: [
            for (final source in sources)
              ListTile(
                key: ValueKey<String>('online-source-${source.id}'),
                title: Text(source.name, maxLines: 1),
                subtitle: Text(
                  <String>[
                    if (source.group.isNotEmpty) source.group,
                    '${source.searchUrl.isEmpty || source.search.bookList.isEmpty ? '无搜索' : '可搜索'}'
                        '${source.hasLoginConfig ? (controller.isLoggedIn(source) ? ' · 已登录' : ' · 需登录') : ''}',
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
                        key: ValueKey<String>(
                          'online-source-login-${source.id}',
                        ),
                        tooltip: controller.isLoggedIn(source)
                            ? '登录状态'
                            : '登录书源',
                        onPressed: _loggingInSourceId == source.id
                            ? null
                            : () => _handleLogin(source),
                        icon: _loggingInSourceId == source.id
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : AppIcon(
                                controller.isLoggedIn(source)
                                    ? AppGlyph.checkCircle
                                    : AppGlyph.profile,
                              ),
                      ),
                    ReaderSwitch(
                      key: ValueKey<String>(
                        'online-source-enabled-${source.id}',
                      ),
                      value: source.enabled,
                      onChanged: (value) async {
                        try {
                          await controller.setSourceEnabled(source.id, value);
                        } on Object catch (error) {
                          _showError('保存失败：$error');
                        }
                      },
                    ),
                    PopupMenuButton<String>(
                      tooltip: '书源选项',
                      position: PopupMenuPosition.under,
                      onSelected: (value) async {
                        if (value == 'remove') {
                          await _confirmRemove(source);
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'remove',
                          child: Row(
                            children: [
                              AppIcon(
                                AppGlyph.delete,
                                color: Theme.of(context).colorScheme.error,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                '删除书源',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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
