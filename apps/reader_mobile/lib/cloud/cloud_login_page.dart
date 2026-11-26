import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:reader_ui/icons/app_icon.dart';

import 'cloud_http.dart';
import 'cloud_login_config.dart';
import 'cloud_models.dart';

/// 用户主动适配当前页的桌面布局，原声明只留在当前文档内存，供撤销。
const cloudLoginViewportScript = r'''
const key = '__spectacularOriginalViewport';
if (restore) {
  for (const item of document[key] || []) {
    if (item.created) item.element.remove();
    else if (item.content === null) item.element.removeAttribute('content');
    else item.element.setAttribute('content', item.content);
  }
  delete document[key];
} else {
  if (!document[key]) {
    const elements = [...document.querySelectorAll('meta[name="viewport" i]')];
    document[key] = elements.map(element => ({element, content: element.getAttribute('content')}));
    if (elements.length === 0) {
      const element = document.createElement('meta');
      element.name = 'viewport';
      document.head.appendChild(element);
      document[key].push({element, content: null, created: true});
    }
  }
  const root = document.documentElement, body = document.body;
  const width = Math.ceil(Math.max(980, root.scrollWidth, root.clientWidth,
    body?.scrollWidth || 0, body?.clientWidth || 0));
  const scale = Math.min(1, viewportWidth / width);
  for (const item of document[key]) {
    const directives = (item.content || '').split(/[;,]/).map(value => value.trim())
      .filter(value => value && !/^(width|height|initial-scale|minimum-scale|maximum-scale|user-scalable)\s*=/i.test(value));
    item.element.content = [...directives, 'width=' + width, 'initial-scale=' + scale,
      'user-scalable=yes'].join(',');
  }
}
await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
return true;
''';

/// 登录只发生在官方网盘页面，验证成功后由调用方保存到安全存储。
class CloudLoginPage extends StatefulWidget {
  const CloudLoginPage({super.key, required this.provider});
  final CloudProviderApi provider;
  @override
  State<CloudLoginPage> createState() => _CloudLoginPageState();
}

class _CloudLoginPageState extends State<CloudLoginPage>
    with WidgetsBindingObserver {
  InAppWebViewController? _web;
  Timer? _timer, _retryTimer;
  bool _ready = false, _reading = false, _closing = false;
  bool _preparing = false, _verifying = false, _pageFailed = false;
  bool _foreground = true, _adaptingViewport = false;
  String? _error;
  String _candidate = '';
  final _storageSession = DateTime.now().microsecondsSinceEpoch.toString();
  double _progress = 0, _webWidth = 0;
  CloudDrive get _drive => widget.provider.drive;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    unawaited(_prepare());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _poll();
    if (_foreground) unawaited(_read());
  }

  void _poll() {
    _timer?.cancel();
    if (_ready && _foreground && !_closing) {
      _timer = Timer.periodic(const Duration(seconds: 2), (_) => _read());
    }
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
    if (_preparing) return;
    setState(() {
      _preparing = true;
      _error = null;
    });
    try {
      await _clearCookies();
      if (!mounted) return;
      setState(() => _ready = true);
      _poll();
    } catch (_) {
      if (mounted) setState(() => _error = '无法准备网页登录，请重试');
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  Future<void> _read({bool manual = false}) async {
    final web = _web;
    if (!_ready || !_foreground || _reading || _closing || web == null) return;
    if (!manual && (_retryTimer != null || _pageFailed)) return;
    _reading = true;
    if (manual) setState(() => _verifying = true);
    String candidate = '';
    try {
      final account = await _readAccount(web);
      if (!mounted || _closing || !_foreground) return;
      if (account == null) {
        if (manual) setState(() => _error = '请先在官方页面完成登录并进入文件列表');
        return;
      }
      candidate = account.fields.toString();
      if (!manual && candidate == _candidate) return;
      _retryTimer?.cancel();
      _retryTimer = null;
      setState(() {
        _candidate = '';
        _verifying = true;
        _error = null;
      });
      account.name = await widget.provider.validate(account);
      if (!mounted || _closing || !_foreground) return;
      await _complete(web, account);
    } catch (error) {
      if (mounted && !_closing) {
        _verificationFailed(error, candidate);
      }
    } finally {
      _reading = false;
      if (mounted && !_closing && _verifying) {
        setState(() => _verifying = false);
      }
    }
  }

  void _verificationFailed(Object error, String candidate) {
    setState(() {
      _error = error is CloudException ? error.message : '无法验证登录，请稍后点击“完成登录”重试';
    });
    if (error is CloudException && error.loginRequired) {
      _candidate = candidate;
      return;
    }
    // 暂时断网后允许同一登录信息重试，避免每次轮询都请求验证接口。
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 10), () {
      _retryTimer = null;
      unawaited(_read());
    });
  }

  Future<void> _complete(
    InAppWebViewController web,
    CloudAccount account,
  ) async {
    if (_drive.storageHosts.isNotEmpty) {
      await web.evaluateJavascript(
        source: _drive.prepareStorageScript('closed-$_storageSession'),
      );
    }
    await _clearCookies();
    if (!mounted || _closing) return;
    _closing = true;
    _timer?.cancel();
    Navigator.of(context).pop(account);
  }

  Future<void> _refresh() async {
    if (_reading || _preparing || _closing) return;
    if (!_ready) return _prepare();
    _retryTimer?.cancel();
    _retryTimer = null;
    setState(() {
      _candidate = '';
      _error = null;
      _pageFailed = false;
      _progress = 0;
    });
    try {
      await _web?.reload();
    } catch (_) {
      _loadFailed('登录页面刷新失败，请重试');
    }
  }

  void _loadFailed(String message) {
    if (!mounted || _closing) return;
    setState(() {
      _pageFailed = true;
      _error = message;
    });
  }

  Future<void> _adaptViewport(bool restore) async {
    final web = _web;
    if (web == null ||
        _verifying ||
        _closing ||
        _adaptingViewport ||
        _pageFailed) {
      return;
    }
    setState(() => _adaptingViewport = true);
    try {
      final result = await web.callAsyncJavaScript(
        functionBody: cloudLoginViewportScript,
        arguments: {'restore': restore, 'viewportWidth': _webWidth},
      );
      if (result?.value != true || result?.error != null) {
        throw const CloudException('网页显示调整失败，请重试');
      }
    } catch (_) {
      if (mounted && !_closing) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('网页显示调整失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => _adaptingViewport = false);
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
    _retryTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_clearCookies().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        '${_drive.label}登录',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        PopupMenuButton<bool>(
          tooltip: '网页显示',
          enabled:
              _web != null && !_verifying && !_pageFailed && !_adaptingViewport,
          icon: const AppIcon(AppGlyph.preview),
          onSelected: _adaptViewport,
          itemBuilder: (_) => const [
            PopupMenuItem(value: false, child: Text('适应屏幕')),
            PopupMenuItem(value: true, child: Text('恢复原始大小')),
          ],
        ),
        IconButton(
          tooltip: '刷新登录页',
          onPressed: _verifying || _preparing ? null : _refresh,
          icon: const AppIcon(AppGlyph.refresh),
        ),
      ],
    ),
    body: SafeArea(
      top: false,
      child: Column(
        children: [
          _guidance(),
          if (_error != null) _failure(),
          if (_ready && !_pageFailed && _progress < 1)
            LinearProgressIndicator(value: _progress > 0 ? _progress : null),
          Expanded(
            child: _ready
                ? LayoutBuilder(
                    builder: (context, constraints) {
                      _webWidth = constraints.maxWidth;
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          ExcludeSemantics(
                            excluding: _pageFailed,
                            child: _browser(),
                          ),
                          if (_pageFailed) _pageFailure(),
                        ],
                      );
                    },
                  )
                : Center(
                    child: _preparing
                        ? const CircularProgressIndicator()
                        : const AppIcon(AppGlyph.warning, size: 40),
                  ),
          ),
          _actions(),
        ],
      ),
    ),
  );

  Widget _pageFailure() => Material(
    color: Theme.of(context).colorScheme.surface,
    child: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(
              AppGlyph.warning,
              size: 36,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text('暂时无法打开登录页', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Text(
              '请检查网络连接，然后点击上方“刷新”。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
  );

  Widget _guidance() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
    child: Row(
      children: [
        AppIcon(
          AppGlyph.lock,
          size: 18,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '请在下方官网完成登录',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    ),
  );

  Widget _failure() => Material(
    color: Theme.of(context).colorScheme.errorContainer,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          ),
          if (!_ready || _pageFailed)
            TextButton(
              onPressed: _preparing || _verifying ? null : _refresh,
              child: Text(_ready ? '刷新' : '重试'),
            ),
        ],
      ),
    ),
  );

  Widget _actions() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (MediaQuery.viewInsetsOf(context).bottom == 0) ...[
          Text(
            '登录成功后自动返回，登录信息仅保存在本机。',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
        ],
        FilledButton(
          onPressed: !_ready || _verifying || _web == null || _pageFailed
              ? null
              : () => _read(manual: true),
          child: Text(_verifying ? '正在验证登录…' : '完成登录'),
        ),
      ],
    ),
  );

  Widget _browser() => InAppWebView(
    initialUrlRequest: URLRequest(url: WebUri(_drive.loginUrl)),
    initialSettings: InAppWebViewSettings(
      userAgent: cloudUserAgent,
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
    onWebViewCreated: (web) {
      if (mounted) setState(() => _web = web);
    },
    onLoadStart: (_, _) {
      if (!mounted) return;
      setState(() {
        _progress = 0;
        _pageFailed = false;
        _error = null;
      });
    },
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
      if (request.isForMainFrame == true) {
        _loadFailed('登录页面加载失败，请检查网络后刷新');
      }
    },
    onReceivedHttpError: (_, request, response) {
      if (request.isForMainFrame == true) {
        _loadFailed('登录页面暂时无法访问（${response.statusCode}），请稍后刷新');
      }
    },
  );
}
