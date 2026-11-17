import 'dart:async';

import 'package:flutter/material.dart';

import 'rea_micro_controller.dart';
import 'rea_micro_lan.dart';

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
    try {
      final message = await widget.controller.syncWithLanPeer(peer);
      if (mounted) _showMessage(message);
    } catch (error) {
      if (mounted) _showMessage('同步失败：$error');
    }
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
          appBar: AppBar(title: Text(signedIn ? '局域网设备同步' : '局域网授权登录')),
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
                if (signedIn)
                  ..._peerList(controller)
                else
                  ..._loginList(controller),
              ],
            ),
          ),
        );
      },
    );
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
            onTap: controller.lanSyncing ? null : () => _sync(peer),
          ),
        ),
    ];
  }
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
                    ? '扫描同一局域网内的同账号设备，只合并较新的章节、CFI 与阅读百分比；'
                          '本地尚未上报的位置会保留。'
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
