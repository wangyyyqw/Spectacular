import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reader_ui/theme/reader_dropdown.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';

import 'sync_controller.dart';
import 'sync_crypto.dart';
import 'sync_models.dart';

/// 完整阅读数据的独立同步入口，不需要阅微或温知账号。
class SyncPage extends StatefulWidget {
  const SyncPage({super.key, required this.controller});
  final SyncController controller;
  @override
  State<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends State<SyncPage> {
  final _endpoint = TextEditingController();
  final _bucket = TextEditingController();
  final _region = TextEditingController(text: 'us-east-1');
  final _prefix = TextEditingController(text: 'spectacular-sync');
  final _access = TextEditingController();
  final _secret = TextEditingController();
  final _recovery = TextEditingController();
  SyncProvider _provider = SyncProvider.webdav;
  bool _automatic = true;
  bool _preferences = false;
  bool _resources = false;
  bool _encrypt = false;
  bool _loading = true;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      await widget.controller.initialize();
      final profile = widget.controller.profile;
      final credentials = await widget.controller.credentials();
      if (!mounted) return;
      if (profile != null) {
        _provider = profile.provider;
        _endpoint.text = profile.endpoint;
        _bucket.text = profile.bucket;
        _region.text = profile.region;
        _prefix.text = profile.prefix;
        _automatic = profile.automatic;
        _preferences = profile.preferences;
        _resources = profile.resources;
      }
      _access.text = credentials.access;
      _secret.text = credentials.secret;
      _recovery.text = credentials.recovery;
    } catch (error) {
      if (mounted) _show('读取本机凭证失败：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  SyncProfile get _profile => SyncProfile(
    provider: _provider,
    endpoint: _endpoint.text,
    bucket: _bucket.text,
    region: _region.text,
    prefix: _prefix.text,
    automatic: _automatic,
    preferences: _preferences,
    resources: _resources,
  );
  SyncCredentials get _credentials => SyncCredentials(
    access: _access.text,
    secret: _secret.text,
    recovery: _recovery.text,
  );

  Future<void> _run(Future<void> Function() action) async {
    if (_working || widget.controller.syncing) return;
    setState(() => _working = true);
    try {
      await action();
    } catch (error) {
      if (mounted) _show('$error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _show(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _sync() async {
    final result = await widget.controller.synchronize();
    if (mounted) _show(result?.message ?? widget.controller.message);
  }

  Future<void> _test() async {
    if (!await _confirm(
      '测试连接',
      '会在该同步目录写入、读取并清理一个随机临时探针。'
          '不会修改图书、日志或其他现有数据。',
    )) {
      return;
    }
    await _run(() async {
      await widget.controller.testConnection(_profile, _credentials);
      if (mounted) _show(widget.controller.message);
    });
  }

  Future<void> _join() async {
    if (!await _confirm(
      '加入同步库',
      '连接同一同步目录的设备会合并完整阅读数据。'
          '不使用远端数据库覆盖本机；全端删除按墓碑生效，已有阅读历史保留。',
    )) {
      return;
    }
    await _run(() async {
      await widget.controller.join(_profile, _credentials);
      await _sync();
    });
  }

  Future<void> _create() async {
    _profile.validate();
    if (_encrypt) {
      final recovery = await SyncCrypto.generateKey();
      if (!mounted || !await _backupKey(recovery)) return;
      _recovery.text = recovery;
    } else {
      if (!await _confirm(
        '创建明文同步库',
        '云端文件和阅读记录不会端到端加密，'
            '访问安全依赖存储服务鉴权和 HTTPS。不会覆盖已有同步库。',
      )) {
        return;
      }
      _recovery.clear();
    }
    await widget.controller.createLibrary(
      _profile,
      _credentials,
      encrypted: _encrypt,
    );
    await _sync();
  }

  Future<bool> _backupKey(String recovery) async =>
      await showReaderDialog<bool>(
        context: context,
        builder: (context) {
          var backedUp = false;
          return StatefulBuilder(
            builder: (context, update) => ReaderFrostedAlertDialog(
              title: const Text('备份恢复密钥'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('所有设备需要相同恢复密钥。请另行安全保存；遗失后无法通过存储密码恢复。'),
                  const SizedBox(height: 16),
                  SelectableText(recovery),
                  TextButton.icon(
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: recovery)),
                    icon: const Icon(Icons.copy),
                    label: const Text('复制恢复密钥'),
                  ),
                  CheckboxListTile(
                    value: backedUp,
                    title: const Text('我已在应用之外安全备份'),
                    onChanged: (value) =>
                        update(() => backedUp = value ?? false),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: backedUp
                      ? () => Navigator.pop(context, true)
                      : null,
                  child: const Text('创建加密同步库'),
                ),
              ],
            ),
          );
        },
      ) ??
      false;

  Future<bool> _confirm(String title, String description) async =>
      await showReaderDialog<bool>(
        context: context,
        builder: (context) => ReaderFrostedAlertDialog(
          title: Text(title),
          content: Text(description),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _clearBook() async {
    final books = await widget.controller.library.list();
    if (!mounted) return;
    final selected = await showReaderDialog<String>(
      context: context,
      builder: (context) => ReaderFrostedAlertDialog(
        title: const Text('仅清理本机 EPUB'),
        content: SizedBox(
          width: 360,
          height: 320,
          child: ListView(
            children: [
              const Text(
                '保留书架、笔记、书评和统计；联网打开时重新下载。'
                '未完成上传或存在冲突时不会清理。',
              ),
              for (final book in books)
                ListTile(
                  title: Text(book.title),
                  onTap: () => Navigator.pop(context, book.id),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (selected == null ||
        !mounted ||
        !await _confirm('清理本机 EPUB', '只删除本机当前 EPUB 和对应同步文件缓存，不删除云端或其他设备的数据。')) {
      return;
    }
    await _run(() async {
      await widget.controller.clearLocalBook(selected);
      if (mounted) _show(widget.controller.message);
    });
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    bool secret = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      obscureText: secret,
      enabled: !_working && !widget.controller.syncing,
      autocorrect: false,
      enableSuggestions: !secret,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );

  Widget _options(bool enabled) => Column(
    children: [
      SwitchListTile(
        title: const Text('自动同步'),
        subtitle: const Text('前台每两分钟、退出阅读及数据变化后同步，不阻塞本地阅读'),
        value: _automatic,
        onChanged: enabled
            ? (value) => setState(() => _automatic = value)
            : null,
      ),
      SwitchListTile(
        title: const Text('同步阅读偏好'),
        subtitle: const Text('排版、颜色、阅读主题；不同步设备操作和语音模型'),
        value: _preferences,
        onChanged: enabled
            ? (value) => setState(() => _preferences = value)
            : null,
      ),
      SwitchListTile(
        title: const Text('同步字体与阅读背景'),
        value: _resources,
        onChanged: enabled
            ? (value) => setState(() => _resources = value)
            : null,
      ),
      SwitchListTile(
        title: const Text('新同步库启用端到端加密'),
        subtitle: const Text('仅创建时选择；加入已有加密库时填写恢复密钥'),
        value: _encrypt,
        onChanged: enabled ? (value) => setState(() => _encrypt = value) : null,
      ),
    ],
  );

  List<Widget> _actions(bool enabled) => [
    OutlinedButton.icon(
      onPressed: enabled ? () => unawaited(_test()) : null,
      icon: const Icon(Icons.wifi_find),
      label: const Text('测试连接'),
    ),
    OutlinedButton(
      onPressed: enabled
          ? () => unawaited(
              _run(() async {
                await widget.controller.saveProfile(_profile, _credentials);
                if (mounted) _show(widget.controller.message);
              }),
            )
          : null,
      child: const Text('保存连接与选项'),
    ),
    FilledButton.icon(
      onPressed: enabled ? () => unawaited(_join()) : null,
      icon: const Icon(Icons.sync),
      label: const Text('加入并同步'),
    ),
    OutlinedButton(
      onPressed: enabled ? () => unawaited(_run(_create)) : null,
      child: const Text('创建同步库'),
    ),
    OutlinedButton.icon(
      onPressed: enabled && widget.controller.profile != null
          ? () => unawaited(_run(_sync))
          : null,
      icon: const Icon(Icons.sync),
      label: const Text('立即同步已保存连接'),
    ),
    TextButton(
      onPressed: enabled && widget.controller.profile != null
          ? () => unawaited(_clearBook())
          : null,
      child: const Text('仅清理本机 EPUB 副本'),
    ),
  ];

  List<Widget> _conflicts(bool enabled) => [
    if (widget.controller.state?.conflicts.isNotEmpty == true) ...[
      const SizedBox(height: 20),
      const Text('同步冲突（内容已保留）', style: TextStyle(fontWeight: FontWeight.bold)),
      for (final entry in widget.controller.state!.conflicts.entries)
        Card(
          child: ExpansionTile(
            title: Text(
              entry.value.values.first.data['title'] as String? ?? entry.key,
            ),
            children: [
              for (final version in entry.value.values)
                ListTile(
                  title: Text(
                    '设备 ${version.device.substring(0, version.device.length.clamp(0, 6))}',
                  ),
                  subtitle: Text(
                    '${version.data['note'] ?? version.data['content'] ?? version.data['locator_cfi'] ?? version.data['content_revision'] ?? version.data['title'] ?? ''}',
                  ),
                  trailing: TextButton(
                    onPressed: enabled
                        ? () => unawaited(
                            _run(() async {
                              if (await _confirm(
                                '采用此版本',
                                '会将所选内容作为新的同步修订发送，其他版本不会再作为当前版本。',
                              )) {
                                await widget.controller.resolve(
                                  entry.key,
                                  version,
                                );
                              }
                            }),
                          )
                        : null,
                    child: const Text('采用'),
                  ),
                ),
              TextButton(
                onPressed: enabled
                    ? () => unawaited(
                        _run(() => widget.controller.resolve(entry.key, null)),
                      )
                    : null,
                child: const Text('保留本机当前内容'),
              ),
            ],
          ),
        ),
    ],
  ];

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final enabled =
          !_loading &&
          !_working &&
          !widget.controller.syncing &&
          widget.controller.available;
      return Scaffold(
        appBar: AppBar(title: const Text('多设备同步')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      '同步 EPUB、全部笔记、书签、书评、书单、分组标签与原始阅读会话。'
                      '统计页的时长、日历、排行、次数、字数和翻页统计在每台设备重建。'
                      '书架删除会同步到所有设备，已有阅读历史保留。',
                    ),
                  ),
                ),
                if (_loading || _working || widget.controller.syncing)
                  const LinearProgressIndicator(),
                if (!widget.controller.available)
                  const Text('本地数据库不可用，临时模式已禁用同步。'),
                const SizedBox(height: 16),
                ReaderDropdownButtonFormField<SyncProvider>(
                  key: ValueKey('sync-provider-${_provider.name}'),
                  initialValue: _provider,
                  decoration: const InputDecoration(
                    labelText: '存储后端',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: SyncProvider.webdav,
                      child: Text('WebDAV'),
                    ),
                    DropdownMenuItem(
                      value: SyncProvider.s3,
                      child: Text('S3 兼容对象存储'),
                    ),
                  ],
                  onChanged: enabled
                      ? (value) => setState(() => _provider = value!)
                      : null,
                ),
                const SizedBox(height: 12),
                _field('HTTPS 服务地址', _endpoint),
                if (_provider == SyncProvider.s3) ...[
                  _field('存储桶', _bucket),
                  _field('区域', _region),
                ],
                _field('同步目录（所有设备填写相同目录）', _prefix),
                _field(
                  _provider == SyncProvider.s3 ? 'Access Key' : 'WebDAV 用户名',
                  _access,
                ),
                _field(
                  _provider == SyncProvider.s3 ? 'Secret Key' : 'WebDAV 密码',
                  _secret,
                  secret: true,
                ),
                _field('恢复密钥（加入已有加密同步库时填写）', _recovery, secret: true),
                _options(enabled),
                ..._actions(enabled),
                const SizedBox(height: 16),
                Text(widget.controller.message),
                if (widget.controller.lastSync != null)
                  Text('上次同步：${widget.controller.lastSync!.toLocal()}'),
                ..._conflicts(enabled),
              ],
            ),
          ),
        ),
      );
    },
  );

  @override
  void dispose() {
    for (final controller in [
      _endpoint,
      _bucket,
      _region,
      _prefix,
      _access,
      _secret,
      _recovery,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }
}
