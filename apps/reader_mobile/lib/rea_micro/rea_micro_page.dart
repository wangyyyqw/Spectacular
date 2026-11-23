import 'dart:async';

import 'package:flutter/material.dart';

import 'rea_micro_book_link_page.dart';
import 'rea_micro_controller.dart';
import 'rea_micro_lan_page.dart';
import 'rea_micro_models.dart';
import 'rea_micro_rating_page.dart';
import 'rea_micro_records_page.dart';
import 'rea_micro_s3_page.dart';

/// 阅微账号、阅读数据与同步设置页。
class ReaMicroPage extends StatefulWidget {
  /// 创建页面。
  const ReaMicroPage({super.key, required this.controller});

  /// 阅微状态控制器。
  final ReaMicroController controller;

  @override
  State<ReaMicroPage> createState() => _ReaMicroPageState();
}

class _ReaMicroPageState extends State<ReaMicroPage> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  bool _switchingCloudSource = false;

  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.initialize());
    unawaited(widget.controller.refreshIfStale());
  }

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final sent = await widget.controller.sendEmailCode(_email.text);
    if (sent && mounted) {
      FocusScope.of(context).unfocus();
    }
  }

  Future<void> _login() async {
    final ok = await widget.controller.login(
      email: _email.text,
      code: _code.text,
    );
    if (ok && mounted) {
      _code.clear();
      FocusScope.of(context).unfocus();
    }
  }

  Future<void> _syncNow() async {
    final result = await widget.controller.syncEverything(refreshStats: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(result.message)));
  }

  Future<void> _setCloudPrimary(bool value) async {
    if (_switchingCloudSource) return;
    setState(() => _switchingCloudSource = true);
    await widget.controller.setCloudAsPrimary(value);
    if (!mounted) return;
    setState(() => _switchingCloudSource = false);
    final message = widget.controller.error ?? widget.controller.notice;
    if (message != null && message.trim().isNotEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _openLanPage() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => ReaMicroLanPage(controller: widget.controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, child) {
        final controller = widget.controller;
        return Scaffold(
          appBar: AppBar(
            title: const Text('阅微同步'),
            actions: [
              if (controller.signedIn)
                IconButton(
                  tooltip: '刷新阅微数据',
                  onPressed: controller.busy
                      ? null
                      : () => unawaited(controller.refresh()),
                  icon: const Icon(Icons.refresh),
                ),
            ],
          ),
          body: SafeArea(
            child: !controller.initialized
                ? const SizedBox.shrink()
                : RefreshIndicator(
                    onRefresh: controller.refresh,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                      children: [
                        if (!controller.signedIn && controller.error != null)
                          _MessageBanner(
                            key: const ValueKey<String>('reamicro-error'),
                            icon: Icons.error_outline,
                            color: Theme.of(context).colorScheme.error,
                            text: controller.error!,
                          ),
                        if (controller.signedIn)
                          ..._accountContent(context, controller)
                        else
                          ..._loginContent(context, controller),
                      ],
                    ),
                  ),
          ),
        );
      },
    );
  }

  List<Widget> _loginContent(
    BuildContext context,
    ReaMicroController controller,
  ) {
    final theme = Theme.of(context);
    return <Widget>[
      const SizedBox(height: 8),
      Row(
        children: [
          Icon(Icons.cloud_sync, size: 40, color: theme.colorScheme.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('连接阅微', style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  '登录后同步阅读时长，并查看阅微账号的阅读统计。',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 24),
      Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey<String>('reamicro-email'),
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const <String>[AutofillHints.email],
                decoration: const InputDecoration(
                  labelText: '邮箱',
                  hintText: 'name@example.com',
                  prefixIcon: Icon(Icons.alternate_email),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                key: const ValueKey<String>('reamicro-code'),
                controller: _code,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: '邮箱验证码',
                  prefixIcon: const Icon(Icons.password),
                  suffixIcon: TextButton(
                    key: const ValueKey<String>('reamicro-send-code'),
                    onPressed: controller.sendingCode ? null : _sendCode,
                    child: Text(controller.sendingCode ? '发送中…' : '发送验证码'),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                key: const ValueKey<String>('reamicro-login'),
                onPressed: controller.busy ? null : _login,
                icon: controller.busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login),
                label: Text(controller.busy ? '正在登录…' : '登录阅微'),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 18),
      OutlinedButton.icon(
        key: const ValueKey<String>('reamicro-lan-login'),
        onPressed: controller.lanLoggingIn ? null : _openLanPage,
        icon: const Icon(Icons.wifi_lock),
        label: Text(controller.lanLoggingIn ? '正在授权…' : '局域网授权登录'),
      ),
      const SizedBox(height: 18),
      Text(
        '账号令牌仅保存在本机应用私有数据库中，不会写入诊断日志。'
        '阅读数据上报只提交关联书籍的云端 ID、日期、时长与阅读位置；'
        '未注册的邮箱会通过验证码自动创建阅微账号。',
        style: theme.textTheme.bodySmall,
      ),
    ];
  }

  List<Widget> _accountContent(
    BuildContext context,
    ReaMicroController controller,
  ) {
    final user = controller.user;
    return <Widget>[
      if (user == null)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        )
      else
        _AccountHeader(user: user),
      if (user != null) ...[const SizedBox(height: 18), _StatsGrid(user: user)],
      const SizedBox(height: 24),
      _ChartCard(points: controller.chart),
      const SizedBox(height: 24),
      _section(context, '数据源', [
        SwitchListTile(
          key: const ValueKey<String>('reamicro-cloud-primary'),
          secondary: Icon(
            controller.cloudAsPrimary
                ? Icons.cloud_done_outlined
                : Icons.cloud_sync_outlined,
          ),
          title: const Text('以阅微为唯一数据源'),
          subtitle: Text(
            controller.cloudAsPrimary
                ? '阅读时长、进度自动上报并按最后修改时间多端合并；统计页显示阅微完整阅读数据'
                : '开启后以阅微为准同步阅读时长和阅读位置；统计页登录后仍显示阅微数据',
          ),
          value: controller.cloudAsPrimary,
          onChanged: _switchingCloudSource
              ? null
              : (value) => unawaited(_setCloudPrimary(value)),
        ),
      ]),
      const SizedBox(height: 24),
      _section(context, '阅读同步', [
        ListTile(
          leading: controller.syncing || controller.syncingProgress
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.sync),
          title: Text(
            controller.syncing || controller.syncingProgress
                ? '正在同步…'
                : '立即同步阅读数据',
          ),
          subtitle: Text(
            controller.lastSyncAt == null
                ? '尚未同步'
                : '上次同步：${_formatDateTime(controller.lastSyncAt!)}',
          ),
          onTap: controller.syncing || controller.syncingProgress
              ? null
              : _syncNow,
        ),
        ListTile(
          key: const ValueKey<String>('reamicro-lan-sync'),
          leading: controller.lanSyncing
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.sync_alt),
          title: const Text('局域网设备互联'),
          subtitle: Text(controller.lanMessage ?? '从同一账号的附近设备合并章节与阅读进度'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _openLanPage,
        ),
        ListTile(
          key: const ValueKey<String>('reamicro-s3-sync'),
          leading: controller.s3Syncing
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.cloud_upload_outlined),
          title: const Text('云端同步'),
          subtitle: Text(
            controller.s3Configured
                ? controller.s3Message ?? '已配置，自动同步本地与阅微图书文件'
                : '配置阅微内置存储、S3、WebDAV 或 GitHub 后多端同步图书文件',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (context) =>
                  ReaMicroS3Page(controller: widget.controller),
            ),
          ),
        ),
        ListTile(
          key: const ValueKey<String>('reamicro-book-links'),
          leading: const Icon(Icons.menu_book_outlined),
          title: const Text('关联阅微公开阅读'),
          subtitle: Text(
            controller.links.isEmpty
                ? '按出版方关联公开阅读版本；阅读数据会独立同步'
                : '已公开关联 ${controller.links.length} 本本地书籍',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (context) =>
                  ReaMicroBookLinkPage(controller: controller),
            ),
          ),
        ),
        ListTile(
          key: const ValueKey<String>('reamicro-records'),
          leading: const Icon(Icons.history_edu_outlined),
          title: const Text('阅读记录与标注'),
          subtitle: const Text('查看周/月/年阅读记录、隐藏记录和标注书籍'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (context) => ReaMicroRecordsPage(controller: controller),
            ),
          ),
        ),
        ListTile(
          key: const ValueKey<String>('reamicro-ratings'),
          leading: const Icon(Icons.workspace_premium_outlined),
          title: const Text('书评与里程碑'),
          subtitle: const Text('查看阅微读完记录，发布评分与书评'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (context) => ReaMicroRatingPage(controller: controller),
            ),
          ),
        ),
      ]),
      const SizedBox(height: 20),
      OutlinedButton.icon(
        onPressed: () => unawaited(controller.logout()),
        icon: const Icon(Icons.logout),
        label: const Text('退出阅微账号'),
      ),
    ];
  }

  Widget _section(BuildContext context, String title, List<Widget> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 10),
        Card(
          child: Column(
            children: [
              for (var index = 0; index < rows.length; index++) ...[
                if (index > 0)
                  const Divider(height: 1, indent: 16, endIndent: 16),
                rows[index],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _MessageBanner extends StatelessWidget {
  const _MessageBanner({
    super.key,
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(color: color, height: 1.4)),
          ),
        ],
      ),
    );
  }
}

class _AccountHeader extends StatelessWidget {
  const _AccountHeader({required this.user});

  final ReaMicroUser user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        ClipOval(
          child: SizedBox(
            width: 60,
            height: 60,
            child: user.avatar.isEmpty
                ? ColoredBox(
                    color: theme.colorScheme.primaryContainer,
                    child: Icon(
                      Icons.person,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  )
                : Image.network(
                    user.avatar,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stack) => ColoredBox(
                      color: theme.colorScheme.primaryContainer,
                      child: Icon(
                        Icons.person,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(user.nickName, style: theme.textTheme.titleLarge),
              if (user.userTitle.isNotEmpty || user.email.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  <String>[
                    if (user.userTitle.isNotEmpty) user.userTitle,
                    if (user.email.isNotEmpty) user.email,
                  ].join(' · '),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.user});

  final ReaMicroUser user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = <(String, String)>[
      ('累计阅读', _formatSeconds(user.totalReadTimeSeconds)),
      ('读完书籍', '${user.readFinishedBookNum} 本'),
      ('当前等级', 'Lv.${user.level}'),
      ('彩筹', '${user.gem}'),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: <Widget>[
            for (final item in items)
              SizedBox(
                width: width,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.55,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.$1, style: theme.textTheme.labelMedium),
                      const SizedBox(height: 6),
                      Text(item.$2, style: theme.textTheme.titleMedium),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.points});

  final List<ReaMicroChartPoint> points;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = points.fold<int>(
      0,
      (sum, point) => sum + point.durationSeconds,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('近期阅读', style: theme.textTheme.titleMedium),
                const Spacer(),
                Text(
                  '共 ${_formatSeconds(total)}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (points.isEmpty)
              SizedBox(
                height: 90,
                child: Center(
                  child: Text('暂无阅读时长数据', style: theme.textTheme.bodyMedium),
                ),
              )
            else
              _BarChart(points: points),
          ],
        ),
      ),
    );
  }
}

class _BarChart extends StatelessWidget {
  const _BarChart({required this.points});

  final List<ReaMicroChartPoint> points;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxDuration = points.fold<int>(
      1,
      (max, point) => point.durationSeconds > max ? point.durationSeconds : max,
    );
    final latestDay = points.isEmpty ? '' : points.last.day;
    return Column(
      children: [
        SizedBox(
          height: 110,
          child: LayoutBuilder(
            builder: (context, constraints) {
              const gap = 2.0;
              final barWidth =
                  ((constraints.maxWidth - gap * (points.length - 1)) /
                          points.length)
                      .clamp(2.0, 14.0);
              final spacing = points.length > 1
                  ? (constraints.maxWidth - barWidth * points.length) /
                        (points.length - 1)
                  : 0.0;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  for (final point in points) ...[
                    Tooltip(
                      message:
                          '${point.day}\n'
                          '${_formatSeconds(point.durationSeconds)}',
                      child: Container(
                        width: barWidth,
                        height: point.durationSeconds <= 0
                            ? 2
                            : 8 +
                                  96 *
                                      (point.durationSeconds / maxDuration)
                                          .clamp(0.0, 1.0),
                        decoration: BoxDecoration(
                          color: point.day == latestDay
                              ? theme.colorScheme.primary
                              : theme.colorScheme.primary.withValues(
                                  alpha: 0.38,
                                ),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    if (point != points.last) SizedBox(width: spacing),
                  ],
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              _shortDay(points.first.day),
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const Spacer(),
            Text(
              _shortDay(points.last.day),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ],
    );
  }
}

String _formatSeconds(int seconds) {
  if (seconds <= 0) return '0 分钟';
  final minutes = seconds ~/ 60;
  if (minutes < 60) {
    return minutes <= 0 ? '<1 分钟' : '$minutes 分钟';
  }
  final hours = minutes ~/ 60;
  final remain = minutes % 60;
  return remain == 0 ? '$hours 小时' : '$hours 小时 $remain 分钟';
}

String _formatDateTime(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$month-$day $hour:$minute';
}

String _shortDay(String day) {
  if (day.length < 10) return day;
  return day.substring(5).replaceAll('-', '/');
}
