import 'dart:async';
import 'dart:ui' show AppExitType;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reader_ui/theme/reader_frosted_popup.dart';
import 'package:url_launcher/url_launcher.dart';

import '../library/library_store.dart';
import '../rea_micro/rea_micro_controller.dart';
import '../rea_micro/rea_micro_page.dart';
import '../rea_micro/rea_micro_store.dart';

/// 本次协议独立于应用版本号；已有账号也需确认一次。
const welcomeAgreementKey = 'app.welcomeAgreement';
const welcomeAgreementRevision = 'reamicro-extend-20261124';

Future<void> exitReaderApplication() async {
  if (defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS) {
    await SystemNavigator.pop();
  } else {
    await ServicesBinding.instance.exitApplication(AppExitType.required);
  }
}

/// 正式启动先确认公告，再初始化账号；未登录时停留在登录页。
Future<void> runWelcomeFlow({
  required BuildContext context,
  required LibraryStore library,
  required ReaMicroController controller,
  Future<void> Function()? onExit,
}) async {
  final accepted = await library.getSetting(welcomeAgreementKey);
  if (!context.mounted) return;
  if (accepted != welcomeAgreementRevision) {
    final agreed = await showReaderDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => WelcomeAnnouncementDialog(
        onAgree: () =>
            library.setSetting(welcomeAgreementKey, welcomeAgreementRevision),
        onExit: onExit ?? exitReaderApplication,
      ),
    );
    if (agreed != true || !context.mounted) return;
  }
  final token = await ReaMicroStore(library).loadToken();
  if (!context.mounted) return;
  unawaited(controller.initialize());
  if (token != null || controller.signedIn) return;
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => _RequiredReaMicroLogin(controller: controller),
    ),
  );
}

/// 欢迎公告使用全应用共用磨砂弹窗，长文本独立滚动。
class WelcomeAnnouncementDialog extends StatefulWidget {
  const WelcomeAnnouncementDialog({
    super.key,
    required this.onAgree,
    required this.onExit,
    this.onOpenLink,
  });

  final Future<void> Function() onAgree;
  final Future<void> Function() onExit;
  final Future<void> Function(Uri)? onOpenLink;

  @override
  State<WelcomeAnnouncementDialog> createState() =>
      _WelcomeAnnouncementDialogState();
}

class _WelcomeAnnouncementDialogState extends State<WelcomeAnnouncementDialog> {
  final _recognizers = <TapGestureRecognizer>[];
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.parse(url);
    try {
      if (widget.onOpenLink != null) {
        await widget.onOpenLink!(uri);
      } else if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('链接未打开');
      }
    } catch (_) {
      if (mounted) setState(() => _error = '链接打开失败，请稍后重试');
    }
  }

  TextSpan _link(String label, String url, TextStyle style) {
    final recognizer = TapGestureRecognizer()
      ..onTap = () => unawaited(_openLink(url));
    _recognizers.add(recognizer);
    return TextSpan(text: label, style: style, recognizer: recognizer);
  }

  Future<void> _agree() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onAgree();
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '保存确认失败，请重试';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
    final theme = Theme.of(context);
    final linkStyle = TextStyle(
      color: theme.colorScheme.primary,
      decoration: TextDecoration.underline,
    );
    return PopScope(
      canPop: false,
      child: ReaderFrostedDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        constraints: const BoxConstraints(maxWidth: 520),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .85,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Flexible(
                  child: SingleChildScrollView(
                    key: const ValueKey('welcome-announcement-content'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Center(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.asset(
                              'assets/branding/app_icon.png',
                              width: 64,
                              height: 64,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '欢迎使用阅微 Extend',
                          key: const ValueKey('welcome-announcement-title'),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text.rich(
                          TextSpan(
                            children: [
                              const TextSpan(text: '欢迎下载并使用阅微 Extend ！\n\n'),
                              const TextSpan(text: '阅微 Extend 是基于 '),
                              _link(
                                'Spectacular',
                                'https://github.com/wangyyyqw/Spectacular',
                                linkStyle,
                              ),
                              const TextSpan(text: ' 作为阅读解析核心，内置'),
                              _link(
                                '阅微',
                                'https://www.zhendong.ltd',
                                linkStyle,
                              ),
                              const TextSpan(text: '的接口作为数据源和'),
                              _link(
                                '阅微补全计划',
                                'https://github.com/YGHFv/ReaMicro-Extend',
                                linkStyle,
                              ),
                              const TextSpan(
                                text:
                                    '的功能作为功能补充构建的第三方阅微应用。\n\n'
                                    '为了确保业务功能的正常运行，我们需要您登录阅微账号继续使用，但是我们不会收集您的任何数据或信息，本项目亦没有设立任何服务器用于数据提供分发或者收集；您的数据将全部保持在设备本地或者您登录的阅微账号上面。\n\n'
                                    '本项目非阅微官方作品，一切行为与官方无关，并存在被阅微封禁风险，请确认您已知悉相关风险后再同意本协议再使用。\n\n'
                                    '本项目为个人开发学习测试应用，仅供学习与测试，请在 24 小时内自行删除，不保证稳定性与可用性。',
                              ),
                            ],
                          ),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton(
                  key: const ValueKey('welcome-agree-login'),
                  onPressed: _saving ? null : _agree,
                  child: Text(_saving ? '正在保存…' : '同意并登录'),
                ),
                const SizedBox(height: 6),
                TextButton(
                  key: const ValueKey('welcome-disagree-exit'),
                  onPressed: _saving ? null : widget.onExit,
                  child: const Text('不同意，退出应用'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RequiredReaMicroLogin extends StatefulWidget {
  const _RequiredReaMicroLogin({required this.controller});
  final ReaMicroController controller;

  @override
  State<_RequiredReaMicroLogin> createState() => _RequiredReaMicroLoginState();
}

class _RequiredReaMicroLoginState extends State<_RequiredReaMicroLogin> {
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_checkLogin);
  }

  void _checkLogin() {
    if (_leaving || !widget.controller.signedIn) return;
    _leaving = true;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_checkLogin);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _leaving,
    child: ReaMicroPage(controller: widget.controller),
  );
}
