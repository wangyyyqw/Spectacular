import 'dart:async';

import 'package:flutter/material.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/theme/reader_common_widgets.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';
import 'package:reader_ui/theme/reader_ui_style.dart';

import '../library/library_store.dart';
import '../txt/txt_encoding_dialog.dart';
import 'cloud_accounts.dart';
import 'cloud_http.dart';
import 'cloud_import_controller.dart';
import 'cloud_login_page.dart';
import 'cloud_models.dart';
import 'cloud_providers.dart';
import 'cloud_transfer_panel.dart';

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
  CloudDrive? _opening;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final saved = <CloudDrive, CloudAccount>{};
      for (final drive in CloudDrive.values) {
        final account = await _accounts.read(drive);
        if (account != null) saved[drive] = account;
      }
      if (!mounted) return;
      _saved
        ..clear()
        ..addAll(saved);
    } catch (_) {
      _error = '无法读取系统安全存储中的账号，请重试';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(CloudDrive drive, {bool login = false}) async {
    if (_opening != null) return;
    setState(() {
      _opening = drive;
      _error = null;
    });
    final provider = (widget.providerFactory ?? cloudProvider)(drive, _http);
    try {
      do {
        final account = await _accountFor(provider, login: login);
        if (account == null || !mounted) return;
        login =
            await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) => CloudFilesPage(
                  provider: provider,
                  account: account,
                  accounts: _accounts,
                  library: widget.library,
                ),
              ),
            ) ==
            true;
      } while (login && mounted);
    } catch (_) {
      if (mounted) setState(() => _error = '登录信息无法保存到系统安全存储，请重试');
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  Future<CloudAccount?> _accountFor(
    CloudProviderApi provider, {
    required bool login,
  }) async {
    if (!login && _saved[provider.drive] != null) return _saved[provider.drive];
    final account = await Navigator.of(context).push<CloudAccount>(
      MaterialPageRoute(builder: (_) => CloudLoginPage(provider: provider)),
    );
    if (account == null || !mounted) return null;
    await _accounts.save(account);
    if (mounted) setState(() => _saved[provider.drive] = account);
    return account;
  }

  Future<void> _forget(CloudDrive drive) async {
    if (_opening != null) return;
    try {
      await _accounts.remove(drive);
      if (mounted) {
        setState(() {
          _saved.remove(drive);
          _error = null;
        });
      }
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
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  Text(
                    '把云端藏书带到书架',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '选择网盘，登录后下载 EPUB 或 TXT。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 24),
                  if (_error != null)
                    _CloudNotice(
                      message: _error!,
                      action: '重试',
                      onAction: _load,
                    ),
                  ReaderSectionCard(
                    dividerIndent: 64,
                    children: [
                      for (final drive in CloudDrive.values) _row(drive),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppIcon(
                        AppGlyph.lock,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '通过网盘官方页面登录。登录信息仅保存在本机系统安全存储中，不参与阅读数据同步。',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
  );

  Widget _row(CloudDrive drive) => ListTile(
    key: ValueKey('cloud-${drive.name}'),
    enabled: _opening == null,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    leading: Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: ReaderUiStyle.controlRadius,
      ),
      child: const AppIcon(AppGlyph.folder),
    ),
    title: Text(drive.label),
    subtitle: Text(
      _saved[drive] == null
          ? '未登录 · 点击连接'
          : _saved[drive]!.name.isEmpty
          ? '已登录 · 浏览文件'
          : '已登录 · ${_saved[drive]!.name}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodySmall,
    ),
    onTap: _opening == null ? () => _open(drive) : null,
    trailing: _opening == drive
        ? const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : _saved[drive] == null
        ? const AppIcon(AppGlyph.chevronRight)
        : PopupMenuButton<String>(
            enabled: _opening == null,
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
  final _search = TextEditingController();
  String? _cursor, _error;
  bool _loading = false, _loginRequired = false, _leaving = false;
  bool _booksOnly = false, _retryMore = false;
  Future<void>? _savingAccount;
  bool get _busy => _loading || _imports.busy || _leaving;
  List<CloudEntry> get _visibleEntries => _entries
      .where(
        (entry) =>
            (!_booksOnly || entry.isFolder || entry.isBook) &&
            entry.name.toLowerCase().contains(
              _search.text.trim().toLowerCase(),
            ),
      )
      .toList();
  bool _completed(String id) => _imports.items.any(
    (item) => item.file.id == id && item.status == CloudImportStatus.completed,
  );

  @override
  void initState() {
    super.initState();
    _imports.addListener(_changed);
    unawaited(_load());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _load({bool more = false, bool preserve = false}) async {
    if (_busy) return;
    setState(() {
      _loading = true;
      _retryMore = more;
      _error = null;
      _loginRequired = false;
      if (!more && !preserve) {
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
          _selected.removeWhere(
            (id) =>
                !listing.entries.any((entry) => entry.id == id && entry.isBook),
          );
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
    _search.clear();
    _path.add((id: entry.id, name: entry.name));
    await _load();
  }

  Future<void> _up() async {
    if (_path.length <= 1 || _busy) return;
    _search.clear();
    _path.removeLast();
    await _load();
  }

  Future<void> _goTo(int index) async {
    if (_busy || index == _path.length - 1) return;
    _search.clear();
    _path.removeRange(index + 1, _path.length);
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
      final leave = await showReaderDialog<bool>(
        context: context,
        builder: (context) => ReaderFrostedAlertDialog(
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
    _search.dispose();
    _imports.removeListener(_changed);
    _imports.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _leaving,
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) return;
      if (_path.length > 1 && !_busy) {
        unawaited(_up());
      } else {
        unawaited(_leave());
      }
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.provider.drive.label),
        leading: BackButton(
          onPressed: () => _path.length > 1 && !_busy ? _up() : _leave(),
        ),
        actions: [
          IconButton(
            tooltip: '刷新目录',
            onPressed: _busy ? null : () => _load(preserve: true),
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
              _filters(),
              if (_loading) const LinearProgressIndicator(),
              if (_error != null) _failure(),
              Expanded(child: _files()),
              if (MediaQuery.viewInsetsOf(context).bottom == 0) ...[
                CloudTransferPanel(
                  controller: _imports,
                  onRetry: _retry,
                  onRelogin: () => _leave(relogin: true),
                ),
                _actions(),
              ],
            ],
          ),
        ),
      ),
    ),
  );

  Widget _location() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
    child: Align(
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < _path.length; index++) ...[
              if (index > 0) const AppIcon(AppGlyph.chevronRight, size: 16),
              TextButton(
                onPressed: _busy || index == _path.length - 1
                    ? null
                    : () => _goTo(index),
                style: TextButton.styleFrom(
                  disabledForegroundColor: Theme.of(context)
                      .colorScheme
                      .onSurface,
                ),
                child: Text(_path[index].name),
              ),
            ],
          ],
        ),
      ),
    ),
  );

  Widget _filters() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    child: Column(
      children: [
        ReaderSearchField(
          controller: _search,
          hintText: '筛选当前目录已加载的文件',
          onChanged: (_) => setState(() {}),
          suffixIcon: _search.text.isEmpty
              ? null
              : IconButton(
                  tooltip: '清除筛选',
                  onPressed: () => setState(_search.clear),
                  icon: AppIcon(
                    AppGlyph.close,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            FilterChip(
              label: const Text('仅看书籍'),
              selected: _booksOnly,
              showCheckmark: true,
              onSelected: (value) => setState(() => _booksOnly = value),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _loading
                    ? '正在读取目录…'
                    : '已加载 ${_entries.length} 项${_cursor != null ? ' · 还有更多' : ''}',
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _failure() => _CloudNotice(
    message: _error!,
    action: _loginRequired ? '重新登录' : '重试',
    onAction: _busy
        ? null
        : _loginRequired
        ? () => _leave(relogin: true)
        : () => _load(more: _retryMore, preserve: true),
  );

  Widget _files() {
    final entries = _visibleEntries;
    if (entries.isEmpty && !_loading && _error == null && _cursor == null) {
      return _empty();
    }
    return RefreshIndicator(
      onRefresh: () => _load(preserve: true),
      child: ListView.builder(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: entries.length + (_cursor != null ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == entries.length) {
            return Padding(
              padding: const EdgeInsets.all(12),
              child: TextButton(
                onPressed: _busy ? null : () => _load(more: true),
                child: Text(_loading ? '正在加载…' : '加载更多'),
              ),
            );
          }
          return _fileRow(entries[index]);
        },
      ),
    );
  }

  Widget _empty() => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppIcon(
                _entries.isEmpty ? AppGlyph.folder : AppGlyph.searchOff,
                size: 36,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(_entries.isEmpty ? '此目录没有文件' : '没有匹配的文件'),
              const SizedBox(height: 8),
              Text(
                _entries.isEmpty ? '试试其他目录，支持 EPUB 和 TXT。' : '试试其他名称，或清除筛选条件。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_entries.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() {
                    _search.clear();
                    _booksOnly = false;
                  }),
                  child: const Text('清除筛选'),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _fileRow(CloudEntry entry) {
    final completed = _completed(entry.id);
    final enabled = !_busy && (entry.isFolder || entry.isBook && !completed);
    final selected = _selected.contains(entry.id);
    final colors = Theme.of(context).colorScheme;
    final type = entry.name.split('.').last.toUpperCase();
    return Material(
      color: selected ? colors.primaryContainer : colors.surface,
      child: ListTile(
        key: ValueKey('cloud-file-${entry.id}'),
        enabled: enabled,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          width: 40,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: ReaderUiStyle.controlRadius,
          ),
          child: entry.isBook
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      type,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                )
              : AppIcon(entry.isFolder ? AppGlyph.folder : AppGlyph.article),
        ),
        title: Text(entry.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          entry.isFolder
              ? '文件夹'
              : completed
              ? '已导入书架'
              : entry.isBook
              ? '${entry.size > 0 ? cloudFileSize(entry.size) : '大小未知'} · $type'
              : '不支持导入此格式',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: entry.isFolder
            ? const AppIcon(AppGlyph.chevronRight)
            : completed
            ? const AppIcon(AppGlyph.checkCircle)
            : entry.isBook
            ? Checkbox(
                semanticLabel: '选择 ${entry.name}',
                value: selected,
                onChanged: enabled ? (_) => _select(entry.id) : null,
              )
            : null,
        onTap: !enabled
            ? null
            : entry.isFolder
            ? () => _folder(entry)
            : () => _select(entry.id),
      ),
    );
  }

  void _select(String id) {
    FocusScope.of(context).unfocus();
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  Widget _actions() {
    final selectable = _visibleEntries
        .where((entry) => entry.isBook && !_completed(entry.id))
        .map((entry) => entry.id)
        .toSet();
    final allSelected =
        selectable.isNotEmpty && _selected.containsAll(selectable);
    final bytes = _entries
        .where((entry) => _selected.contains(entry.id))
        .fold<int>(0, (size, entry) => size + entry.size);
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _imports.busy
                    ? '下载完成后自动加入书架，请保持应用运行。'
                    : _selected.isEmpty
                    ? '选择 EPUB 或 TXT，下载后加入书架。'
                    : '已选 ${_selected.length} 项${bytes > 0 ? ' · ${cloudFileSize(bytes)}' : ''}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_imports.busy)
                    TextButton(
                      onPressed: _imports.cancel,
                      child: const Text('取消导入'),
                    )
                  else
                    TextButton(
                      onPressed: _busy || selectable.isEmpty
                          ? null
                          : () => setState(() {
                              if (allSelected) {
                                _selected.removeAll(selectable);
                              } else {
                                _selected.addAll(selectable);
                              }
                            }),
                      child: Text(allSelected ? '取消全选' : '全选当前结果'),
                    ),
                  FilledButton(
                    onPressed: _busy || _selected.isEmpty ? null : _start,
                    child: Text(
                      _imports.busy ? '正在导入…' : '下载并导入（${_selected.length}）',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _start() async {
    final files = _entries
        .where((entry) => _selected.contains(entry.id))
        .toList();
    FocusScope.of(context).unfocus();
    setState(_selected.clear);
    await _imports.start(files);
  }
}

class _CloudNotice extends StatelessWidget {
  const _CloudNotice({
    required this.message,
    required this.action,
    this.onAction,
  });
  final String message;
  final String action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: ReaderUiStyle.controlRadius,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
          TextButton(onPressed: onAction, child: Text(action)),
        ],
      ),
    ),
  );
}
