import 'dart:async';

import 'package:flutter/material.dart';

import 'rea_micro_controller.dart';
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
  bool _saving = false;
  bool _showSecret = false;

  @override
  void initState() {
    super.initState();
    final config = widget.controller.s3Config ?? ReaMicroS3Config.empty;
    _endpoint = TextEditingController(text: config.endpoint);
    _bucket = TextEditingController(text: config.bucket);
    _region = TextEditingController(text: config.region);
    _accessKey = TextEditingController(text: config.accessKey);
    _secretKey = TextEditingController(text: config.secretKey);
    _prefix = TextEditingController(text: config.prefix);
  }

  @override
  void dispose() {
    _endpoint.dispose();
    _bucket.dispose();
    _region.dispose();
    _accessKey.dispose();
    _secretKey.dispose();
    _prefix.dispose();
    super.dispose();
  }

  ReaMicroS3Config get _config => ReaMicroS3Config(
    endpoint: _endpoint.text,
    bucket: _bucket.text,
    region: _region.text,
    accessKey: _accessKey.text,
    secretKey: _secretKey.text,
    prefix: _prefix.text,
  );

  Future<void> _save({bool syncAfter = false}) async {
    if (_saving) return;
    final config = _config;
    if (!config.usable) {
      _show('请填写端点、存储桶、区域、Access Key 和 Secret Key');
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.controller.saveS3Config(config);
      if (!mounted) return;
      if (syncAfter) {
        final result = await widget.controller.syncS3();
        if (!mounted) return;
        _show(result?.message ?? widget.controller.s3Message ?? '已保存 S3 配置');
      } else {
        _show('已保存 S3 配置');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clear() async {
    await widget.controller.clearS3Config();
    if (!mounted) return;
    _show('已清除 S3 配置');
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
          appBar: AppBar(title: const Text('对象存储同步')),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: <Widget>[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      '使用与阅微相同的 S3 兼容对象存储和同步目录，'
                      '自动上传本地新增或变更的图书，并下载本机缺失的阅微图书。'
                      '密钥只保存在本机应用私有设置中。',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
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
                    label: const Text('清除 S3 配置'),
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
}
