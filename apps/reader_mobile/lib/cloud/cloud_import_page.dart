import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';

import '../library/library_store.dart';
import '../txt/txt_encoding_dialog.dart';
import 'cloud_accounts.dart';
import 'cloud_http.dart';
import 'cloud_import_controller.dart';
import 'cloud_login_page.dart';
import 'cloud_models.dart';
import 'cloud_providers.dart';

class CloudImportPage extends StatefulWidget {
  const CloudImportPage({
    super.key,
    required this.library,
    this.accounts,
    this.providerFactory,
  });
  final LibraryStore library;
  final CloudAccountStore? accounts;
  final CloudProviderApi Function(CloudDrive, CloudHttp)? providerFactory;
  @override
  State<CloudImportPage> createState() => _CloudImportPageState();
}

class _CloudImportPageState extends State<CloudImportPage> {
  late final _accounts = widget.accounts ?? SecureCloudAccounts();
  final _http = CloudHttp();
  final _saved = <CloudDrive, CloudAccount>{};
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      _saved.clear();
      for (final drive in CloudDrive.values) {
        final account = await _accounts.read(drive);
        if (account != null) _saved[drive] = account;
      }
    } catch (_) {
      _error = '无法读取系统安全存储中的账号，请重试';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(CloudDrive drive, {bool login = false}) async {
    final provider = (widget.providerFactory ?? cloudProvider)(drive, _http);
    var account = login ? null : _saved[drive];
    if (account == null) {
      account = await Navigator.of(context).push<CloudAccount>(
        MaterialPageRoute(builder: (_) => CloudLoginPage(provider: provider)),
      );
      if (account == null || !mounted) return;
      try {
        await _accounts.save(account);
      } catch (_) {
        if (mounted) setState(() => _error = '登录信息无法保存到系统安全存储，请重试');
        return;
      }
      _saved[drive] = account;
    }
    if (!mounted) return;
    final owner = account;
    final relogin = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CloudFilesPage(
          provider: provider,
          account: owner,
          accounts: _accounts,
          library: widget.library,
        ),
      ),
    );
    if (mounted) setState(() {});
    if (relogin == true && mounted) await _open(drive, login: true);
  }

  Future<void> _forget(CloudDrive drive) async {
    try {
      await _accounts.remove(drive);
      if (mounted) setState(() => _saved.remove(drive));
    } catch (_) {
      if (mounted) setState(() => _error = '退出登录失败，请重试');
    }
  }

  @override
  void dispose() {
    _http.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('网盘导入')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 20),
                    child: Text('登录网盘，选择 EPUB 或 TXT，下载后加入书架。'),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  for (final drive in CloudDrive.values) _row(drive),
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('登录信息仅保存在本机系统安全存储中，不参与阅读数据同步。'),
                  ),
                ],
              ),
            ),
          ),
  );

  Widget _row(CloudDrive drive) => ListTile(
    key: ValueKey('cloud-${drive.name}'),
    leading: const AppIcon(AppGlyph.folder),
    title: Text(drive.label),
    subtitle: Text(
      _saved[drive] == null
          ? '未登录'
          : _saved[drive]!.name.isEmpty
          ? '已登录'
          : _saved[drive]!.name,
    ),
    onTap: () => _open(drive),
    trailing: _saved[drive] == null
        ? const AppIcon(AppGlyph.chevronRight)
        : PopupMenuButton<String>(
            tooltip: '${drive.label}账号操作',
            icon: const AppIcon(AppGlyph.more),
            onSelected: (value) =>
                value == 'login' ? _open(drive, login: true) : _forget(drive),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'login', child: Text('重新登录')),
              PopupMenuItem(value: 'logout', child: Text('退出登录')),
            ],
          ),
  );
}

class CloudFilesPage extends StatefulWidget {
  const CloudFilesPage({
    super.key,
    required this.provider,
    required this.account,
    required this.accounts,
    required this.library,
  });
  final CloudProviderApi provider;
  final CloudAccount account;
  final CloudAccountStore accounts;
  final LibraryStore library;
  @override
  State<CloudFilesPage> createState() => _CloudFilesPageState();
}

class _CloudFilesPageState extends State<CloudFilesPage> {
  late final _imports = CloudImportController(
    provider: widget.provider,
    account: widget.account,
    accounts: widget.accounts,
    library: widget.library,
  );
  late final _path = <({String id, String name})>[
    (id: widget.provider.rootId, name: '全部文件'),
  ];
  final _entries = <CloudEntry>[];
  final _selected = <String>{};
  String? _cursor, _error;
  bool _loading = false, _loginRequired = false, _leaving = false;
  Future<void>? _savingAccount;
  bool get _busy => _loading || _imports.busy;

  @override
  void initState() {
    super.initState();
    _imports.addListener(_changed);
    unawaited(_load());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _load({bool more = false}) async {
    if (_busy) return;
    setState(() {
      _loading = true;
      _error = null;
      _loginRequired = false;
      if (!more) {
        _entries.clear();
        _selected.clear();
        _cursor = null;
      }
    });
    try {
      final listing = await widget.provider.list(
        widget.account,
        _path.last.id,
        cursor: more ? _cursor : null,
      );
      if (!mounted || _leaving) return;
      _savingAccount = widget.accounts.save(widget.account);
      await _savingAccount;
      if (!mounted || _leaving) return;
      setState(() {
        if (!more) {
          _entries.clear();
          _selected.clear();
        }
        final ids = _entries.map((entry) => entry.id).toSet();
        _entries.addAll(listing.entries.where((entry) => ids.add(entry.id)));
        _entries.sort(
          (a, b) => a.isFolder != b.isFolder
              ? a.isFolder
                    ? -1
                    : 1
              : a.name.compareTo(b.name),
        );
        _cursor = listing.nextPage;
      });
    } catch (error) {
      if (mounted && !_leaving) {
        setState(() {
          _error = error is CloudException ? error.message : '读取网盘失败，请稍后重试';
          _loginRequired = error is CloudException && error.loginRequired;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _folder(CloudEntry entry) async {
    if (_busy) return;
    _path.add((id: entry.id, name: entry.name));
    await _load();
  }

  Future<void> _up() async {
    if (_path.length <= 1 || _busy) return;
    _path.removeLast();
    await _load();
  }

  Future<void> _retry(CloudImportItem item) async {
    String? encoding;
    if (item.job?.encodingCandidates.isNotEmpty == true) {
      encoding = await chooseTxtEncoding(context, item.job!.encodingCandidates);
      if (encoding == null || !mounted) return;
    }
    await _imports.retry(item, encoding: encoding);
  }

  Future<void> _leave({bool relogin = false}) async {
    if (_leaving) return;
    if (_imports.busy) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('停止导入并返回？'),
          content: const Text('已导入的书籍会保留，未完成的下载将取消。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('继续导入'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('停止并返回'),
            ),
          ],
        ),
      );
      if (leave != true || !mounted) return;
    }
    setState(() => _leaving = true);
    try {
      await _savingAccount;
    } catch (_) {
      // 已在目录加载处展示存储错误，退出仍需完成连接和暂存清理。
    }
    await _imports.close();
    if (mounted) Navigator.pop(context, relogin);
  }

  @override
  void dispose() {
    _imports.removeListener(_changed);
    _imports.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _leaving,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_leave());
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.provider.drive.label),
        actions: [
          IconButton(
            tooltip: '刷新目录',
            onPressed: _busy ? null : _load,
            icon: const AppIcon(AppGlyph.refresh),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            children: [
              _location(),
              if (_loading) const LinearProgressIndicator(),
              if (_error != null) _failure(),
              if (_imports.items.isNotEmpty) _tasks(),
              Expanded(
                child: _entries.isEmpty && !_loading && _error == null
                    ? const Center(child: Text('此目录没有文件'))
                    : _files(),
              ),
              _actions(),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _location() => ListTile(
    leading: IconButton(
      tooltip: '上级目录',
      onPressed: _path.length > 1 && !_busy ? _up : null,
      icon: const AppIcon(AppGlyph.arrowBack),
    ),
    title: Text(_path.last.name, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: const Text('仅 EPUB / TXT 可以导入'),
  );

  Widget _failure() => Padding(
    padding: const EdgeInsets.all(16),
    child: Row(
      children: [
        Expanded(
          child: Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
        TextButton(
          onPressed: _busy
              ? null
              : _loginRequired
              ? () => _leave(relogin: true)
              : _load,
          child: Text(_loginRequired ? '返回重新登录' : '重试'),
        ),
      ],
    ),
  );

  Widget _files() => ListView.builder(
    itemCount: _entries.length + (_cursor != null ? 1 : 0),
    itemBuilder: (context, index) {
      if (index == _entries.length) {
        return TextButton(
          onPressed: _busy ? null : () => _load(more: true),
          child: const Text('加载更多'),
        );
      }
      final entry = _entries[index];
      return ListTile(
        key: ValueKey('cloud-file-${entry.id}'),
        enabled: !_busy && (entry.isFolder || entry.isBook),
        leading: AppIcon(entry.isFolder ? AppGlyph.folder : AppGlyph.article),
        title: Text(entry.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: entry.isFolder
            ? null
            : Text(entry.isBook ? _bytes(entry.size) : '不支持导入此格式'),
        trailing: entry.isFolder
            ? const AppIcon(AppGlyph.chevronRight)
            : entry.isBook
            ? Checkbox(
                value: _selected.contains(entry.id),
                onChanged: _busy ? null : (_) => _select(entry.id),
              )
            : null,
        onTap: entry.isFolder
            ? () => _folder(entry)
            : entry.isBook
            ? () => _select(entry.id)
            : null,
      );
    },
  );

  void _select(String id) => setState(() {
    if (!_selected.remove(id)) _selected.add(id);
  });

  Widget _tasks() => ConstrainedBox(
    constraints: const BoxConstraints(maxHeight: 190),
    child: ListView(
      shrinkWrap: true,
      children: [
        for (final item in _imports.items)
          ListTile(
            dense: true,
            title: Text(
              item.file.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(item.label),
            trailing:
                {
                  CloudImportStatus.failed,
                  CloudImportStatus.cancelled,
                }.contains(item.status)
                ? TextButton(
                    onPressed: _imports.busy
                        ? null
                        : item.loginRequired
                        ? () => _leave(relogin: true)
                        : () => _retry(item),
                    child: Text(
                      item.loginRequired
                          ? '重新登录'
                          : item.job?.encodingCandidates.isNotEmpty == true
                          ? '选择编码'
                          : '重试',
                    ),
                  )
                : item.status == CloudImportStatus.completed
                ? const AppIcon(AppGlyph.check)
                : null,
          ),
      ],
    ),
  );

  Widget _actions() => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                    final ids = _entries
                        .where((entry) => entry.isBook)
                        .map((entry) => entry.id)
                        .toSet();
                    if (_selected.containsAll(ids)) {
                      _selected.clear();
                    } else {
                      _selected.addAll(ids);
                    }
                  }),
            child: const Text('全选 / 取消'),
          ),
          if (_imports.busy)
            TextButton(onPressed: _imports.cancel, child: const Text('取消导入')),
          FilledButton(
            onPressed: _busy || _selected.isEmpty
                ? null
                : () async {
                    final files = _entries
                        .where((entry) => _selected.contains(entry.id))
                        .toList();
                    setState(_selected.clear);
                    await _imports.start(files);
                  },
            child: Text(_imports.busy ? '正在导入…' : '导入选中（${_selected.length}）'),
          ),
        ],
      ),
    ),
  );

  String _bytes(int size) => size <= 0
      ? 'EPUB / TXT'
      : size < 1024 * 1024
      ? '${(size / 1024).toStringAsFixed(1)} KB'
      : '${(size / 1024 / 1024).toStringAsFixed(1)} MB';
}
