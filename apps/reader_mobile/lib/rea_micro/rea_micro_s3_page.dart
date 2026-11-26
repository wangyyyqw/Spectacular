import 'dart:async';

import 'package:reader_ui/theme/reader_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';

import 'rea_micro_controller.dart';
import 'rea_micro_models.dart';
import 'rea_micro_s3.dart';

/// 阅微对象存储同步设置页。
class ReaMicroS3Page extends StatefulWidget {
  /// 创建页面。
  const ReaMicroS3Page({super.key, required this.controller});

  /// 阅微状态控制器。
  final ReaMicroController controller;

  @override
  State<ReaMicroS3Page> createState() => _ReaMicroS3PageState();
}

class _ReaMicroS3PageState extends State<ReaMicroS3Page> {
  late final TextEditingController _endpoint;
  late final TextEditingController _bucket;
  late final TextEditingController _region;
  late final TextEditingController _accessKey;
  late final TextEditingController _secretKey;
  late final TextEditingController _prefix;
  late final TextEditingController _branch;
  String _provider = 'S3';
  bool _saving = false;
  bool _expanding = false;
  bool _showSecret = false;
  bool _cloudLoading = false;
  ReaMicroS3CloudConfig? _cloudConfig;
  ReaMicroStorageQuota? _quota;
  ReaMicroCreditLedgerPage? _ledger;
  String? _cloudError;

  @override
  void initState() {
    super.initState();
    widget.controller.pageRefresh.addListener(_loadCloudOverview);
    final config = widget.controller.s3Config ?? ReaMicroS3Config.empty;
    _provider = config.normalizedProvider;
    if (!const <String>{'MOTE', 'S3', 'WEBDAV', 'GITHUB'}.contains(_provider)) {
      _provider = 'S3';
    }
    _endpoint = TextEditingController(text: config.endpoint);
    _bucket = TextEditingController(text: config.bucket);
    _region = TextEditingController(text: config.region);
    _accessKey = TextEditingController(text: config.accessKey);
    _secretKey = TextEditingController(text: config.secretKey);
    _prefix = TextEditingController(text: config.prefix);
    _branch = TextEditingController(text: config.branch);
    unawaited(_loadCloudOverview());
  }

  @override
  void dispose() {
    widget.controller.pageRefresh.removeListener(_loadCloudOverview);
    _endpoint.dispose();
    _bucket.dispose();
    _region.dispose();
    _accessKey.dispose();
    _secretKey.dispose();
    _prefix.dispose();
    _branch.dispose();
    super.dispose();
  }

  ReaMicroS3Config get _config => ReaMicroS3Config(
    provider: _provider,
    endpoint: _endpoint.text,
    bucket: _bucket.text,
    region: _region.text,
    accessKey: _accessKey.text,
    secretKey: _secretKey.text,
    prefix: _prefix.text,
    branch: _branch.text,
  );

  bool get _isMote => _provider.trim().toUpperCase() == 'MOTE';
  bool get _isWebDav => _provider.trim().toUpperCase() == 'WEBDAV';
  bool get _isGitHub => _provider.trim().toUpperCase() == 'GITHUB';

  String get _invalidHint => switch (_provider.trim().toUpperCase()) {
    'MOTE' => '请填写同步目录',
    'WEBDAV' => '请填写 WebDAV 地址；服务必须支持强 ETag 与条件写入',
    'GITHUB' => '请填写私有仓库（所有者/仓库）和具备写入权限的 Token',
    _ => '请填写端点、存储桶、区域、Access Key 和 Secret Key',
  };

  Future<void> _loadCloudOverview({bool fillForm = false}) async {
    if (_cloudLoading) return;
    setState(() {
      _cloudLoading = true;
      _cloudError = null;
    });
    try {
      final cloud = await widget.controller.fetchCloudS3Config();
      final quota = await widget.controller.fetchStorageQuota();
      final ledger = await widget.controller.fetchCreditLedger(pageSize: 5);
      if (!mounted) return;
      setState(() {
        _cloudConfig = cloud;
        _quota = quota;
        _ledger = ledger;
      });
      if (fillForm) _fillFromCloud(cloud);
    } catch (error) {
      if (!mounted) return;
      setState(() => _cloudError = '$error');
    } finally {
      if (mounted) setState(() => _cloudLoading = false);
    }
  }

  void _fillFromCloud(ReaMicroS3CloudConfig cloud) {
    final config = cloud.config;
    if (config == null || !cloud.enabled) {
      _show('阅微账号没有可载入的存储配置');
      return;
    }
    setState(() {
      _provider = config.normalizedProvider;
      if (!const <String>{
        'MOTE',
        'S3',
        'WEBDAV',
        'GITHUB',
      }.contains(_provider)) {
        _provider = 'S3';
      }
      _endpoint.text = config.endpoint;
      _bucket.text = config.bucket;
      _region.text = config.region;
      _accessKey.text = config.accessKey;
      _secretKey.text = config.secretKey;
      _prefix.text = config.prefix;
      _branch.text = config.branch;
    });
    _show('已载入阅微账号中的存储配置');
  }

  Future<void> _saveToCloud() async {
    if (_saving) return;
    final config = _config;
    if (!config.usable) {
      _show(_invalidHint);
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.controller.saveS3Config(config);
      await widget.controller.saveCloudS3Config(config, enabled: true);
      if (!mounted) return;
      _show('已保存并加密同步到阅微账号');
      await _loadCloudOverview();
    } catch (error) {
      if (mounted) _show('$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removeCloudConfig() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.controller.saveCloudS3Config(
        ReaMicroS3Config.empty,
        enabled: false,
      );
      if (!mounted) return;
      _show('已移除阅微账号中的同步配置');
      await _loadCloudOverview();
    } catch (error) {
      if (mounted) _show('$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _expandQuota() async {
    final quota = _quota;
    if (_expanding || quota == null) return;
    final credit = quota.credit;
    if (credit < 60) {
      _show('至少需要 60 积分才能扩容；扩容积分必须为 60 的整数倍');
      return;
    }
    final units = credit ~/ 60;
    final selected = await showReaderDialog<int>(
      context: context,
      builder: (context) {
        var value = 60;
        return StatefulBuilder(
          builder: (context, setDialogState) => ReaderFrostedAlertDialog(
            title: const Text('扩容对象存储'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('可用积分 ${quota.credit}，每 60 积分扩容 1 GiB。'),
                const SizedBox(height: 16),
                Text('本次使用 $value 积分，扩容 ${value ~/ 60} GiB'),
                Slider(
                  value: value.toDouble(),
                  min: 60,
                  max: (units * 60).toDouble(),
                  divisions: units,
                  label: '$value 积分',
                  onChanged: (next) =>
                      setDialogState(() => value = (next / 60).round() * 60),
                ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(value),
                child: const Text('确认扩容'),
              ),
            ],
          ),
        );
      },
    );
    if (selected == null || !mounted) return;
    setState(() => _expanding = true);
    try {
      final next = await widget.controller.expandStorageQuota(credit: selected);
      if (!mounted) return;
      setState(() => _quota = next);
      _show('扩容成功，当前容量 ${next.capacityGib} GiB');
      await _loadCloudOverview();
    } catch (error) {
      if (mounted) _show('$error');
    } finally {
      if (mounted) setState(() => _expanding = false);
    }
  }

  Future<void> _save({bool syncAfter = false}) async {
    if (_saving) return;
    final config = _config;
    if (!config.usable) {
      _show(_invalidHint);
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.controller.saveS3Config(config);
      if (!mounted) return;
      if (syncAfter) {
        final result = await widget.controller.syncS3();
        if (!mounted) return;
        _show(result?.message ?? widget.controller.s3Message ?? '已保存存储配置');
      } else {
        _show('已保存存储配置');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clear() async {
    await widget.controller.clearS3Config();
    if (!mounted) return;
    _show('已清除云端同步配置');
    Navigator.of(context).pop();
  }

  void _show(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, child) {
        final controller = widget.controller;
        return Scaffold(
          appBar: AppBar(title: const Text('同步')),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: <Widget>[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      '使用阅微内置存储、S3、WebDAV 或 GitHub 私有仓库保存同步目录，'
                      '自动上传本地新增或变更的图书，并下载本机缺失的阅微图书。',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ReaderDropdownButtonFormField<String>(
                  key: const ValueKey('sync-provider-setting'),
                  initialValue: _provider,
                  decoration: const InputDecoration(
                    labelText: '同步方式',
                    border: OutlineInputBorder(),
                  ),
                  items: const <DropdownMenuItem<String>>[
                    DropdownMenuItem<String>(
                      value: 'MOTE',
                      child: Text('阅微对象存储'),
                    ),
                    DropdownMenuItem<String>(value: 'S3', child: Text('自建 S3')),
                    DropdownMenuItem<String>(
                      value: 'WEBDAV',
                      child: Text('WebDAV'),
                    ),
                    DropdownMenuItem<String>(
                      value: 'GITHUB',
                      child: Text('GitHub 私有仓库'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _provider = value);
                  },
                ),
                if (_isMote && _cloudLoading)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: LinearProgressIndicator(),
                  )
                else if (_isMote && _cloudError != null)
                  Card(
                    margin: const EdgeInsets.only(top: 16),
                    child: ListTile(
                      leading: const Icon(Icons.cloud_off_outlined),
                      title: const Text('阅微账号同步信息不可用'),
                      subtitle: Text(_cloudError!),
                      trailing: TextButton(
                        onPressed: () => unawaited(_loadCloudOverview()),
                        child: const Text('重试'),
                      ),
                    ),
                  )
                else ...<Widget>[
                  if (_isMote && _quota != null) ...<Widget>[
                    const SizedBox(height: 16),
                    Card(
                      key: const ValueKey('sync-storage-quota'),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                const Icon(Icons.cloud_queue),
                                const SizedBox(width: 8),
                                Text(
                                  '阅微对象存储',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                const Spacer(),
                                Text('${_quota!.credit} 积分'),
                              ],
                            ),
                            const SizedBox(height: 12),
                            LinearProgressIndicator(value: _quota!.usedRatio),
                            const SizedBox(height: 8),
                            Text(
                              '已使用 ${_formatBytes(_quota!.usedBytes)} / '
                              '${_formatBytes(_quota!.capacityBytes)}',
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: Text(
                                    '每 60 积分可扩容 1 GiB',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: _expanding || _quota!.credit < 60
                                      ? null
                                      : () => unawaited(_expandQuota()),
                                  icon: _expanding
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.add_circle_outline),
                                  label: const Text('扩容'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (_isMote &&
                      _ledger != null &&
                      _ledger!.items.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 10),
                    Card(
                      key: const ValueKey('sync-credit-ledger'),
                      child: ExpansionTile(
                        leading: const Icon(Icons.receipt_long_outlined),
                        title: const Text('最近积分流水'),
                        children: <Widget>[
                          for (final item in _ledger!.items)
                            ListTile(
                              dense: true,
                              title: Text(
                                item.operation.trim().isEmpty
                                    ? item.action
                                    : item.operation,
                              ),
                              subtitle: Text(
                                item.objectKey.isEmpty
                                    ? _formatDateTimeValue(item.createTime)
                                    : item.objectKey,
                              ),
                              trailing: Text(
                                item.amount >= 0
                                    ? '+${item.amount}'
                                    : '${item.amount}',
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  if (_cloudConfig?.enabled == true) ...<Widget>[
                    const SizedBox(height: 10),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.lock_outline),
                        title: const Text('阅微账号已保存存储配置'),
                        subtitle: Text(
                          _cloudConfig?.config == null
                              ? '配置无法用当前账号解密'
                              : '提供方：${_cloudConfig!.config!.provider}',
                        ),
                        trailing: TextButton(
                          onPressed: () => _fillFromCloud(_cloudConfig!),
                          child: const Text('载入'),
                        ),
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 10),
                Text(
                  _isMote
                      ? '使用阅微账号的内置对象存储，无需填写密钥；'
                            '配置会加密保存到阅微账号，并在其他设备登录后自动恢复。'
                      : _isWebDav
                      ? '使用支持强 ETag 与条件写入的 WebDAV 目录，'
                            '书籍与进度按与阅微相同的对象路径保存。'
                      : _isGitHub
                      ? '使用 GitHub 私有仓库保存同步对象；每次写入生成一次提交，'
                            '单文件上限 40 MiB。'
                      : '使用自建 S3 兼容对象存储，密钥只保存在本机应用私有设置中。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (_provider.trim().toUpperCase() == 'S3') ...<Widget>[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _endpoint,
                    decoration: const InputDecoration(
                      labelText: '服务端点',
                      hintText: 'https://s3.example.com',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _bucket,
                    decoration: const InputDecoration(
                      labelText: '存储桶',
                      hintText: 'reamicro',
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _region,
                    decoration: const InputDecoration(
                      labelText: '区域',
                      hintText: 'us-east-1 或 auto',
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _accessKey,
                    decoration: const InputDecoration(
                      labelText: 'Access Key',
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _secretKey,
                    obscureText: !_showSecret,
                    decoration: InputDecoration(
                      labelText: 'Secret Key',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: _showSecret ? '隐藏密钥' : '显示密钥',
                        onPressed: () =>
                            setState(() => _showSecret = !_showSecret),
                        icon: Icon(
                          _showSecret
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                      ),
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                ],
                if (_isWebDav) ...<Widget>[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _endpoint,
                    decoration: const InputDecoration(
                      labelText: 'WebDAV 地址',
                      hintText:
                          'https://dav.example.com/remote.php/dav/files/me',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _accessKey,
                    decoration: const InputDecoration(
                      labelText: '用户名',
                      hintText: '可留空使用匿名访问',
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _secretKey,
                    obscureText: !_showSecret,
                    decoration: InputDecoration(
                      labelText: '密码',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: _showSecret ? '隐藏密码' : '显示密码',
                        onPressed: () =>
                            setState(() => _showSecret = !_showSecret),
                        icon: Icon(
                          _showSecret
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                      ),
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                ],
                if (_isGitHub) ...<Widget>[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _bucket,
                    decoration: const InputDecoration(
                      labelText: '仓库',
                      hintText: '用户名/reamicro-backup',
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _branch,
                    decoration: const InputDecoration(
                      labelText: '分支',
                      hintText: '留空使用仓库默认分支',
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _accessKey,
                    obscureText: !_showSecret,
                    decoration: InputDecoration(
                      labelText: 'GitHub Token',
                      helperText: '需要私有仓库的 Contents 读写权限，建议使用细粒度 Token',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: _showSecret ? '隐藏令牌' : '显示令牌',
                        onPressed: () =>
                            setState(() => _showSecret = !_showSecret),
                        icon: Icon(
                          _showSecret
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                      ),
                    ),
                    textInputAction: TextInputAction.next,
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _prefix,
                  decoration: const InputDecoration(
                    labelText: '同步目录',
                    hintText: 'reamicro',
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.done,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _saving ? null : () => unawaited(_save()),
                  icon: const Icon(Icons.save_outlined),
                  label: Text(_saving ? '正在保存…' : '保存配置'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _saving || controller.s3Syncing
                      ? null
                      : () => unawaited(_save(syncAfter: true)),
                  icon: controller.s3Syncing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  label: Text(controller.s3Syncing ? '正在同步…' : '保存并立即同步'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _saving ? null : () => unawaited(_saveToCloud()),
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('保存并加密同步到阅微账号'),
                ),
                if (_cloudConfig?.enabled == true) ...<Widget>[
                  const SizedBox(height: 6),
                  TextButton.icon(
                    onPressed: _saving
                        ? null
                        : () => unawaited(_removeCloudConfig()),
                    icon: const Icon(Icons.cloud_off_outlined),
                    label: const Text('移除阅微账号中的存储配置'),
                  ),
                ],
                if (controller.s3Configured) ...<Widget>[
                  const SizedBox(height: 18),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.schedule),
                      title: Text(controller.s3Message ?? '等待同步'),
                      subtitle: Text(
                        controller.s3LastSyncAt == null
                            ? '尚未同步'
                            : '上次同步：${_formatDateTime(controller.s3LastSyncAt!)}',
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: _saving ? null : () => unawaited(_clear()),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('清除云端同步配置'),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  static String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  static String _formatDateTimeValue(int milliseconds) {
    if (milliseconds <= 0) return '时间未知';
    return _formatDateTime(DateTime.fromMillisecondsSinceEpoch(milliseconds));
  }

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = <String>['B', 'KiB', 'MiB', 'GiB', 'TiB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit += 1;
    }
    final digits = value >= 100 || unit == 0 ? 0 : 1;
    return '${value.toStringAsFixed(digits)} ${units[unit]}';
  }
}
