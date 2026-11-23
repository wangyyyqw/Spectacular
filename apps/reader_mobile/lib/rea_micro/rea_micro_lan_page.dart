import 'dart:async';

import '../library/library_store.dart';

import '../home/book_import_conflict_dialog.dart';
import 'rea_micro_lan_book_picker.dart';

import 'package:flutter/material.dart';

import 'rea_micro_controller.dart';
import 'rea_micro_lan.dart';
import 'rea_micro_lan_server.dart';

/// 局域网授权登录与设备阅读进度同步页。
class ReaMicroLanPage extends StatefulWidget {
  /// 创建页面。
  const ReaMicroLanPage({super.key, required this.controller});

  /// 阅微状态控制器。
  final ReaMicroController controller;

  @override
  State<ReaMicroLanPage> createState() => _ReaMicroLanPageState();
}

class _ReaMicroLanPageState extends State<ReaMicroLanPage> {
  bool _choosingBooks = false;
  @override
  void initState() {
    super.initState();
    unawaited(_scan());
  }

  Future<void> _scan() async {
    try {
      if (widget.controller.signedIn) {
        await widget.controller.discoverLanSyncPeers();
      } else {
        await widget.controller.discoverLanLoginDevices();
      }
    } catch (_) {
      // 错误已由控制器展示。
    }
  }

  Future<void> _login(ReaMicroLanLoginDevice device) async {
    final ok = await widget.controller.loginWithLanDevice(device);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      return;
    }
    _showMessage(widget.controller.error ?? '局域网授权登录失败');
  }

  Future<void> _sync(ReaMicroLanSyncPeer peer) async {
    if (_choosingBooks || widget.controller.lanSyncing) return;
    setState(() => _choosingBooks = true);
    try {
      final manifest = await widget.controller.fetchLanSyncManifest(peer);
      if (!mounted) return;
      final selected = await Navigator.of(context).push<Set<String>>(
        MaterialPageRoute(
          builder: (_) => ReaMicroLanBookPicker(books: manifest.books),
        ),
      );
      if (!mounted || selected == null || selected.isEmpty) return;
      final message = await widget.controller.syncWithLanPeer(
        peer,
        selectedManifest: manifest,
        selectedUuids: selected,
        onConflict: (conflict) => mounted
            ? chooseBookImport(context, conflict)
            : Future.value(BookImportChoice.cancel),
      );
      if (mounted) _showMessage(message);
    } catch (error) {
      if (mounted) _showMessage('同步失败：$error');
    } finally {
      if (mounted) setState(() => _choosingBooks = false);
    }
  }

  Future<void> _approve(ReaMicroLanLoginRequest request) async {
    await widget.controller.approveLanLoginRequest(request.id);
    if (!mounted) return;
    final message =
        widget.controller.lanAuthorizationError ?? widget.controller.lanMessage;
    if (message != null && message.isNotEmpty) _showMessage(message);
  }

  Future<void> _reject(ReaMicroLanLoginRequest request) async {
    await widget.controller.rejectLanLoginRequest(request.id);
    if (!mounted) return;
    final message =
        widget.controller.lanAuthorizationError ?? widget.controller.lanMessage;
    if (message != null && message.isNotEmpty) _showMessage(message);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, child) {
        final controller = widget.controller;
        final signedIn = controller.signedIn;
        return Scaffold(
          appBar: AppBar(title: const Text('互联')),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: <Widget>[
                _IntroCard(signedIn: signedIn),
                const SizedBox(height: 16),
                FilledButton.icon(
                  key: const ValueKey<String>('reamicro-lan-scan'),
                  onPressed: controller.lanScanning ? null : _scan,
                  icon: controller.lanScanning
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.radar),
                  label: Text(controller.lanScanning ? '正在扫描…' : '扫描附近设备'),
                ),
                if (controller.error != null) ...<Widget>[
                  const SizedBox(height: 12),
                  _StatusBanner(
                    key: const ValueKey<String>('reamicro-lan-error'),
                    text: controller.error!,
                    error: true,
                  ),
                ],
                if (controller.lanMessage != null) ...<Widget>[
                  const SizedBox(height: 12),
                  _StatusBanner(
                    key: const ValueKey<String>('reamicro-lan-message'),
                    text: controller.lanMessage!,
                    error: false,
                  ),
                ],
                const SizedBox(height: 20),
                if (signedIn) ...<Widget>[
                  ..._authorizationSection(controller),
                  const SizedBox(height: 20),
                  ..._peerList(controller),
                ] else
                  ..._loginList(controller),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _authorizationSection(ReaMicroController controller) {
    final requests = controller.lanLoginRequests;
    return <Widget>[
      Text('本机授权登录', style: Theme.of(context).textTheme.labelMedium),
      const SizedBox(height: 10),
      Card(
        child: ListTile(
          leading: Icon(
            controller.lanAuthorizationRunning
                ? Icons.verified_user_outlined
                : Icons.gpp_maybe_outlined,
            color: controller.lanAuthorizationRunning
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.error,
          ),
          title: Text(
            controller.lanAuthorizationRunning ? '其他设备可搜索本机并申请登录' : '本机授权服务未启动',
          ),
          subtitle: Text(
            controller.lanAuthorizationRunning
                ? requests.isEmpty
                      ? '暂无待授权申请；批准后令牌只加密回传给申请设备'
                      : '有 ${requests.length} 台设备等待授权'
                : controller.lanAuthorizationError ?? '请检查本地网络后重试',
          ),
          trailing: controller.lanAuthorizationRunning
              ? const Icon(Icons.radar, size: 20)
              : TextButton(
                  onPressed: () =>
                      unawaited(controller.retryLanAuthorization()),
                  child: const Text('重试'),
                ),
        ),
      ),
      if (requests.isNotEmpty) ...<Widget>[
        const SizedBox(height: 8),
        for (final request in requests)
          Card(
            key: ValueKey<String>('reamicro-login-request-${request.id}'),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    request.deviceModel,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '申请时间：${_formatTime(request.receivedAt)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      TextButton(
                        key: ValueKey<String>(
                          'reamicro-login-reject-${request.id}',
                        ),
                        onPressed: () => unawaited(_reject(request)),
                        child: const Text('拒绝'),
                      ),
                      const SizedBox(width: 4),
                      FilledButton(
                        key: ValueKey<String>(
                          'reamicro-login-approve-${request.id}',
                        ),
                        onPressed: () => unawaited(_approve(request)),
                        child: const Text('批准登录'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    ];
  }

  List<Widget> _loginList(ReaMicroController controller) {
    if (controller.lanLoginDevices.isEmpty) {
      return const <Widget>[
        _EmptyHint(text: '请确认阅微设备已打开“局域网登录”，并与本机连接同一个 Wi-Fi。'),
      ];
    }
    return <Widget>[
      Text('可授权设备', style: Theme.of(context).textTheme.labelMedium),
      const SizedBox(height: 10),
      for (final device in controller.lanLoginDevices)
        Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundImage: device.avatar.isEmpty
                  ? null
                  : NetworkImage(device.avatar),
              child: device.avatar.isEmpty
                  ? const Icon(Icons.devices_other)
                  : null,
            ),
            title: Text(
              device.nickname.isEmpty
                  ? '阅微用户 ${device.userId}'
                  : device.nickname,
            ),
            subtitle: Text(
              '用户 ${device.userId} · ${device.host}:${device.port}',
            ),
            trailing: controller.lanLoggingIn
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.login),
            onTap: controller.lanLoggingIn ? null : () => _login(device),
          ),
        ),
    ];
  }

  List<Widget> _peerList(ReaMicroController controller) {
    if (controller.lanSyncPeers.isEmpty) {
      return const <Widget>[_EmptyHint(text: '请确认另一台设备已登录同一阅微账号，并开启局域网同步。')];
    }
    return <Widget>[
      Text('同账号设备', style: Theme.of(context).textTheme.labelMedium),
      const SizedBox(height: 10),
      for (final peer in controller.lanSyncPeers)
        Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.devices)),
            title: Text(
              peer.deviceName.isEmpty
                  ? peer.nickname.isEmpty
                        ? '阅微设备'
                        : peer.nickname
                  : peer.deviceName,
            ),
            subtitle: Text(
              <String>[
                if (peer.nickname.isNotEmpty) peer.nickname,
                '用户 ${peer.userId}',
                '${peer.host}:${peer.port}',
              ].join(' · '),
            ),
            trailing: controller.lanSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            onTap: controller.lanSyncing || _choosingBooks
                ? null
                : () => _sync(peer),
          ),
        ),
    ];
  }
}

String _formatTime(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.signedIn});

  final bool signedIn;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              signedIn ? Icons.sync_alt : Icons.wifi_lock,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                signedIn
                    ? '扫描同一局域网内的同账号设备，下载本地缺失的图书并校验文件，'
                          '同时合并较新的章节、CFI 与阅读百分比；本地尚未上报的位置会保留。'
                    : '通过同一局域网内已登录的阅微设备完成授权，访问令牌只保存在本机。'
                          '首次使用需要在系统设置中允许访问本地网络或附近设备。',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({super.key, required this.text, required this.error});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final color = error
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: TextStyle(color: color, height: 1.4)),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium,
        textAlign: TextAlign.center,
      ),
    );
  }
}
