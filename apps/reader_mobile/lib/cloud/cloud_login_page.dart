import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:reader_ui/icons/app_icon.dart';

import 'cloud_login_config.dart';
import 'cloud_models.dart';

/// 登录只发生在官方网盘页面，验证成功后由调用方保存到安全存储。
class CloudLoginPage extends StatefulWidget {
  const CloudLoginPage({super.key, required this.provider});
  final CloudProviderApi provider;
  @override
  State<CloudLoginPage> createState() => _CloudLoginPageState();
}

class _CloudLoginPageState extends State<CloudLoginPage> {
  InAppWebViewController? _web;
  Timer? _timer;
  bool _ready = false, _reading = false, _closing = false;
  String? _error;
  String _candidate = '';
  final _storageSession = DateTime.now().microsecondsSinceEpoch.toString();
  double _progress = 0;
  CloudDrive get _drive => widget.provider.drive;

  @override
  void initState() {
    super.initState();
    unawaited(_prepare());
  }

  Future<void> _clearCookies() async {
    final manager = CookieManager.instance();
    for (final origin in _drive.cookieOrigins) {
      final url = WebUri(origin);
      final cookies = await manager.getCookies(url: url);
      for (final cookie in cookies) {
        await manager.deleteCookie(
          url: url,
          name: cookie.name,
          domain: cookie.domain,
          path: cookie.path ?? '/',
        );
      }
    }
  }

  Future<void> _prepare() async {
    try {
      await _clearCookies();
      if (!mounted) return;
      setState(() => _ready = true);
      _timer = Timer.periodic(const Duration(seconds: 2), (_) => _read());
    } catch (_) {
      if (mounted) setState(() => _error = '无法准备网页登录，请返回后重试');
    }
  }

  Future<void> _read({bool manual = false}) async {
    final web = _web;
    if (!_ready || _reading || _closing || web == null) return;
    _reading = true;
    try {
      final account = await _readAccount(web);
      if (!mounted || _closing) return;
      if (account == null) {
        if (manual) setState(() => _error = '请先在官方页面完成登录并进入文件列表');
        return;
      }
      final candidate = account.fields.toString();
      if (!manual && candidate == _candidate) return;
      _candidate = candidate;
      account.name = await widget.provider.validate(account);
      if (!mounted || _closing) return;
      if (_drive.storageHosts.isNotEmpty) {
        await web.evaluateJavascript(
          source: _drive.prepareStorageScript('closed-$_storageSession'),
        );
      }
      await _clearCookies();
      if (!mounted || _closing) return;
      _closing = true;
      _timer?.cancel();
      if (mounted) Navigator.of(context).pop(account);
    } catch (error) {
      if (mounted && !_closing) {
        setState(
          () => _error = error is CloudException
              ? error.message
              : '无法验证登录，请稍后点击“完成登录”重试',
        );
      }
    } finally {
      _reading = false;
    }
  }

  Future<CloudAccount?> _readAccount(InAppWebViewController web) async {
    final page = await web.getUrl();
    Object? storage;
    if (page != null && _drive.canReadStorage(Uri.parse(page.toString()))) {
      final state = await web.evaluateJavascript(
        source: _drive.prepareStorageScript(_storageSession),
      );
      if (state == 'cleared') {
        await web.reload();
        return null;
      }
      if (state != 'ready') return null;
      storage = await web.evaluateJavascript(source: _drive.storageScript);
      final after = await web.getUrl();
      if (after == null ||
          !_drive.canReadStorage(Uri.parse(after.toString()))) {
        return null;
      }
    }
    final cookies = <String, String>{};
    for (final origin in _drive.cookieOrigins) {
      for (final cookie in await CookieManager.instance().getCookies(
        url: WebUri(origin),
      )) {
        cookies.putIfAbsent(cookie.name, () => '${cookie.value}');
      }
    }
    return cloudLoginCandidate(
      _drive,
      cookies.entries.map((entry) => '${entry.key}=${entry.value}').join('; '),
      storage,
    );
  }

  @override
  void dispose() {
    _closing = true;
    _timer?.cancel();
    unawaited(_clearCookies().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('${_drive.label}登录'),
      actions: [
        IconButton(
          tooltip: '刷新登录页',
          onPressed: () => _web?.reload(),
          icon: const AppIcon(AppGlyph.refresh),
        ),
        TextButton(
          onPressed: () => _read(manual: true),
          child: const Text('完成登录'),
        ),
      ],
    ),
    body: Column(
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (_progress < 1)
          LinearProgressIndicator(value: _progress > 0 ? _progress : null),
        Expanded(
          child: _ready
              ? _browser()
              : const Center(child: CircularProgressIndicator()),
        ),
      ],
    ),
  );

  Widget _browser() => InAppWebView(
    initialUrlRequest: URLRequest(url: WebUri(_drive.loginUrl)),
    initialSettings: InAppWebViewSettings(
      userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
      javaScriptEnabled: true,
      thirdPartyCookiesEnabled: true,
      sharedCookiesEnabled: true,
      useShouldOverrideUrlLoading: true,
      javaScriptCanOpenWindowsAutomatically: false,
    ),
    initialUserScripts: UnmodifiableListView([
      if (_drive.storageHosts.isNotEmpty)
        UserScript(
          source: _drive.prepareStorageScript(_storageSession),
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          forMainFrameOnly: true,
        ),
      if (_drive.bootstrapScript.isNotEmpty)
        UserScript(
          source: _drive.bootstrapScript,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          forMainFrameOnly: true,
        ),
    ]),
    onWebViewCreated: (web) => _web = web,
    onProgressChanged: (_, progress) {
      if (mounted) setState(() => _progress = progress / 100);
    },
    onLoadStop: (_, _) => _read(),
    shouldOverrideUrlLoading: (_, navigation) async {
      final uri = navigation.request.url;
      return uri != null && {'https', 'about'}.contains(uri.scheme)
          ? NavigationActionPolicy.ALLOW
          : NavigationActionPolicy.CANCEL;
    },
    onReceivedError: (_, request, _) {
      if (mounted && request.isForMainFrame == true) {
        setState(() => _error = '登录页面加载失败，请检查网络后刷新');
      }
    },
  );
}
