import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:reader_ui/icons/app_icon.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';
import 'package:url_launcher/url_launcher.dart';

import 'welcome_announcement.dart';

/// 链接沿用阅微原版关于页；构建时间由 Release 脚本注入。
class AboutPage extends StatefulWidget {
  const AboutPage({super.key, this.onOpenLink});
  final Future<void> Function(Uri)? onOpenLink;
  static const agreementUrl =
      'http://reamicro.zhendong.ltd/privacy/copyright.html';
  static const privacyUrl = 'http://reamicro.zhendong.ltd/privacy/privacy.html';
  static const buildTime = String.fromEnvironment(
    'APP_BUILD_TIME',
    defaultValue: '开发构建',
  );

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  late final _package = PackageInfo.fromPlatform();

  Future<void> _open(String url) async {
    try {
      final uri = Uri.parse(url);
      if (widget.onOpenLink != null) {
        await widget.onOpenLink!(uri);
      } else if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('链接未打开');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('链接打开失败，请重试')));
      }
    }
  }

  Widget _row(String title, {String? value, required VoidCallback onTap}) =>
      ListTile(
        title: Row(
          children: [
            Expanded(child: Text(title)),
            if (value != null)
              Expanded(
                flex: 2,
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
        trailing: const AppIcon(AppGlyph.chevronRight),
        onTap: onTap,
      );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 36, 16, 24),
          children: [
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.asset(
                  'assets/branding/app_icon.png',
                  width: 72,
                  height: 72,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              '阅微 Extend',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontSize: 22),
            ),
            const SizedBox(height: 4),
            FutureBuilder<PackageInfo>(
              future: _package,
              builder: (_, snapshot) => Text(
                snapshot.hasData
                    ? 'Ver ${snapshot.data!.version} (${snapshot.data!.buildNumber})'
                    : '正在读取版本',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '构建时间：${formatAppBuildTime(AboutPage.buildTime)}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 30),
            Card(
              child: Column(
                children: [
                  _row(
                    '阅微 Extend',
                    onTap: () => showReaderDialog<void>(
                      context: context,
                      builder: (_) => WelcomeAnnouncementDialog(
                        onAgree: () async {},
                        onExit: () async {},
                        onOpenLink: widget.onOpenLink,
                        showActions: false,
                      ),
                    ),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  _row('阅微用户协议', onTap: () => _open(AboutPage.agreementUrl)),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  _row('阅微隐私政策', onTap: () => _open(AboutPage.privacyUrl)),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 构建时间保留可读日期，兼容旧脚本附加的时区偏移。
String formatAppBuildTime(String value) =>
    value.replaceFirst(RegExp(r'\s*[+-]\d{2}:?\d{2}$'), '');
