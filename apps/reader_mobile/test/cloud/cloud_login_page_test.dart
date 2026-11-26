import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader_mobile/cloud/cloud_login_page.dart';
import 'package:reader_mobile/cloud/cloud_models.dart';
import 'package:reader_mobile/theme/app_theme.dart';

class _Cookies extends PlatformCookieManager {
  _Cookies()
    : super.implementation(const PlatformCookieManagerCreationParams());
  bool failReads = false;
  List<Cookie> values = [];

  @override
  Future<List<Cookie>> getCookies({
    required WebUri url,
    PlatformInAppWebViewController? iosBelow11WebViewController,
    PlatformInAppWebViewController? webViewController,
  }) async {
    if (failReads) throw StateError('测试准备失败');
    return List.of(values);
  }

  @override
  Future<bool> deleteCookie({
    required WebUri url,
    required String name,
    String path = '/',
    String? domain,
    PlatformInAppWebViewController? iosBelow11WebViewController,
    PlatformInAppWebViewController? webViewController,
  }) async {
    values.removeWhere((cookie) => cookie.name == name);
    return true;
  }
}

class _Controller extends PlatformInAppWebViewController {
  _Controller()
    : super.implementation(
        const PlatformInAppWebViewControllerCreationParams(id: '登录组件测试'),
      );
  int reloads = 0;
  final viewportScripts = <String>[];
  final viewportArguments = <Map<String, dynamic>>[];

  @override
  Future<CallAsyncJavaScriptResult?> callAsyncJavaScript({
    required String functionBody,
    Map<String, dynamic> arguments = const {},
    ContentWorld? contentWorld,
  }) async {
    viewportScripts.add(functionBody);
    viewportArguments.add(arguments);
    return CallAsyncJavaScriptResult(value: true);
  }

  @override
  Future<WebUri?> getUrl() async => WebUri(CloudDrive.quark.loginUrl);

  @override
  Future<void> reload() async {
    reloads++;
  }

  @override
  void dispose({bool isKeepAlive = false}) {}
}

class _WebView extends PlatformInAppWebViewWidget {
  _WebView(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.expand();

  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      params.controllerFromPlatform!(controller) as T;

  @override
  void dispose() {}
}

class _Platform extends InAppWebViewPlatform {
  final cookies = _Cookies();
  late _Controller controller;
  PlatformInAppWebViewWidgetCreationParams? params;

  InAppWebViewController get web =>
      InAppWebViewController.fromPlatform(platform: controller);

  @override
  PlatformCookieManager createPlatformCookieManager(
    PlatformCookieManagerCreationParams params,
  ) => cookies;

  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) {
    this.params = params;
    return _WebView(params);
  }
}

class _Drive implements CloudProviderApi {
  _Drive(this.verify);
  final Future<String> Function() verify;
  int validations = 0;
  @override
  CloudDrive get drive => CloudDrive.quark;
  @override
  String get rootId => '0';
  @override
  Future<String> validate(CloudAccount account) {
    validations++;
    return verify();
  }

  @override
  Future<CloudListing> list(
    CloudAccount account,
    String folderId, {
    String? cursor,
  }) async => const CloudListing([]);

  @override
  Future<CloudDownload> resolve(CloudAccount account, CloudEntry file) async =>
      throw UnimplementedError();
}

void main() {
  final platform = _Platform();
  setUp(() {
    InAppWebViewPlatform.instance = platform;
    platform.cookies
      ..failReads = false
      ..values = [];
    platform.controller = _Controller();
    platform.params = null;
  });

  Future<void> open(
    WidgetTester tester,
    _Drive drive, {
    void Function(CloudAccount?)? onResult,
    bool largeText = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(brightness: Brightness.dark),
        builder: largeText
            ? (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(1.5),
                  viewInsets: const EdgeInsets.only(bottom: 220),
                ),
                child: child!,
              )
            : null,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                final account = await Navigator.of(context).push<CloudAccount>(
                  MaterialPageRoute(
                    builder: (_) => CloudLoginPage(provider: drive),
                  ),
                );
                onResult?.call(account);
              },
              child: const Text('打开登录'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开登录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    if (platform.params != null) {
      platform.params!.onWebViewCreated!(platform.web);
      platform.params!.onProgressChanged!(platform.web, 100);
      await tester.pump();
    }
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  testWidgets('临时验证失败后同一登录信息自动重试，验证中禁用重复操作', (tester) async {
    final pending = Completer<String>();
    var attempts = 0;
    CloudAccount? result;
    final drive = _Drive(
      () => attempts++ == 0 ? pending.future : Future.value('读者'),
    );
    await open(tester, drive, onResult: (account) => result = account);
    platform.cookies.values = [Cookie(name: '__pus', value: '测试登录')];
    await tester.tap(find.text('完成登录'));
    await tester.pump();
    expect(find.text('正在验证登录…'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(
      tester
          .widget<PopupMenuButton<bool>>(find.byType(PopupMenuButton<bool>))
          .enabled,
      isFalse,
    );
    await tester.pump(const Duration(seconds: 4));
    expect(drive.validations, 1);
    pending.completeError(const CloudException('连接网盘超时，请重试'));
    await tester.pump();
    await tester.pump();
    expect(find.text('连接网盘超时，请重试'), findsOneWidget);
    await tester.pump(const Duration(seconds: 8));
    expect(drive.validations, 1);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(drive.validations, 2);
    expect(result?.name, '读者');
    expect(platform.cookies.values, isEmpty);
    await close(tester);
  });

  testWidgets('应用后台停止验证，回到前台恢复检查', (tester) async {
    final drive = _Drive(
      () async => throw const CloudException('请重新登录', loginRequired: true),
    );
    await open(tester, drive);
    platform.cookies.values = [Cookie(name: '__pus', value: '测试登录')];
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 12));
    expect(drive.validations, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(drive.validations, 1);
    await tester.pump(const Duration(seconds: 12));
    expect(drive.validations, 1);
    await tester.tap(find.text('完成登录'));
    await tester.pump();
    expect(drive.validations, 2);
    await close(tester);
  });

  testWidgets('准备失败可在页内重试并打开官网', (tester) async {
    platform.cookies.failReads = true;
    await open(tester, _Drive(() async => '读者'));
    expect(find.text('无法准备网页登录，请重试'), findsOneWidget);
    expect(find.byType(InAppWebView), findsNothing);
    expect(
      tester
          .widget<PopupMenuButton<bool>>(find.byType(PopupMenuButton<bool>))
          .enabled,
      isFalse,
    );
    platform.cookies.failReads = false;
    await tester.tap(find.text('重试'));
    await tester.pump();
    expect(find.byType(InAppWebView), findsOneWidget);
    expect(find.text('无法准备网页登录，请重试'), findsNothing);
    await close(tester);
  });

  testWidgets('网页显示菜单传入实际宽度且支持恢复原始大小', (tester) async {
    await open(tester, _Drive(() async => '读者'));
    final webState = tester.state(find.byType(InAppWebView));
    expect(platform.controller.viewportScripts, isEmpty);
    await tester.tap(find.byTooltip('网页显示'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('适应屏幕'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('网页显示'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复原始大小'));
    await tester.pumpAndSettle();
    final width = tester.getSize(find.byType(InAppWebView)).width;
    expect(platform.controller.viewportArguments, [
      {'restore': false, 'viewportWidth': width},
      {'restore': true, 'viewportWidth': width},
    ]);
    expect(platform.controller.viewportScripts, [
      cloudLoginViewportScript,
      cloudLoginViewportScript,
    ]);
    expect(
      identical(tester.state(find.byType(InAppWebView)), webState),
      isTrue,
    );
    await close(tester);
  });

  test('真实视口脚本按内容宽度适配并可完整撤销', () async {
    final directory = await Directory.systemTemp.createTemp(
      'cloud-viewport-script-',
    );
    try {
      final input = File('${directory.path}/input.json');
      final fixture = File('${directory.path}/fixture.cjs');
      await input.writeAsString(
        jsonEncode({'script': cloudLoginViewportScript}),
      );
      await fixture.writeAsString(_viewportFixture);
      final result = await Process.run('node', [fixture.path, input.path]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final actual =
          jsonDecode(result.stdout as String) as Map<String, dynamic>;
      final existing = actual['existing'] as Map<String, dynamic>;
      final missing = actual['missing'] as Map<String, dynamic>;
      expect(
        existing['content'],
        'viewport-fit=cover,width=1260,initial-scale=0.2857142857142857,user-scalable=yes',
      );
      expect(
        missing['content'],
        'width=980,initial-scale=0.3673469387755102,user-scalable=yes',
      );
      expect(existing['created'], 0);
      expect(missing['created'], 1);
      expect(existing['restored'], existing['original']);
      expect(missing['restored'], isNull);
      expect(missing['remaining'], 0);
      for (final state in actual.values.cast<Map<String, dynamic>>()) {
        expect(state['value'], isTrue);
        expect(state['frames'], 2);
        expect(state['resolvedBeforeLayout'], isFalse);
        expect(state['afterSecondRun'], state['content']);
        expect(state['memoryCleared'], isTrue);
      }
    } finally {
      await directory.delete(recursive: true);
    }
  });

  testWidgets('仅主文档错误展示刷新入口，刷新清除旧错误', (tester) async {
    await open(tester, _Drive(() async => '读者'));
    final webState = tester.state(find.byType(InAppWebView));
    final response = WebResourceResponse(statusCode: 503);
    platform.params!.onReceivedHttpError!(
      platform.web,
      WebResourceRequest(
        url: WebUri(CloudDrive.quark.loginUrl),
        isForMainFrame: false,
      ),
      response,
    );
    await tester.pump();
    expect(find.textContaining('暂时无法访问'), findsNothing);
    expect(find.text('暂时无法打开登录页'), findsNothing);
    platform.params!.onReceivedHttpError!(
      platform.web,
      WebResourceRequest(
        url: WebUri(CloudDrive.quark.loginUrl),
        isForMainFrame: true,
      ),
      response,
    );
    await tester.pump();
    expect(find.textContaining('暂时无法访问'), findsOneWidget);
    expect(find.text('暂时无法打开登录页'), findsOneWidget);
    expect(
      identical(tester.state(find.byType(InAppWebView)), webState),
      isTrue,
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.tap(find.text('刷新'));
    await tester.pump();
    expect(find.textContaining('暂时无法访问'), findsNothing);
    expect(find.text('暂时无法打开登录页'), findsNothing);
    expect(
      identical(tester.state(find.byType(InAppWebView)), webState),
      isTrue,
    );
    expect(platform.controller.reloads, 1);
    await close(tester);
  });

  testWidgets('窄屏夜间大字和键盘下登录操作没有溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await open(tester, _Drive(() async => '读者'), largeText: true);
    await tester.tap(find.text('完成登录'));
    await tester.pump();
    expect(find.text('请先在官方页面完成登录并进入文件列表'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(find.text('完成登录').hitTestable(), findsOneWidget);
    platform.params!.onReceivedError!(
      platform.web,
      WebResourceRequest(
        url: WebUri(CloudDrive.quark.loginUrl),
        isForMainFrame: true,
      ),
      WebResourceError(
        type: WebResourceErrorType.HOST_LOOKUP,
        description: 'net::ERR_NAME_NOT_RESOLVED',
      ),
    );
    await tester.pump();
    expect(find.text('暂时无法打开登录页'), findsOneWidget);
    expect(find.text('net::ERR_NAME_NOT_RESOLVED'), findsNothing);
    expect(tester.takeException(), isNull);
    expect(find.text('刷新').hitTestable(), findsOneWidget);
    await close(tester);
  });
}

// Node 执行正式脚本，并按帧推进验证布局完成后才结束异步调用。
const _viewportFixture = r'''
const fs = require('node:fs');
const vm = require('node:vm');
const {script} = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
async function run(original, contentWidth) {
  const viewports = [];
  const meta = content => ({
    name: 'viewport', content,
    getAttribute: () => content,
    setAttribute(name, value) { this.content = value; },
    removeAttribute() { this.content = null; },
    remove() { viewports.splice(viewports.indexOf(this), 1); },
  });
  if (original !== null) viewports.push(meta(original));
  let created = 0;
  const frames = [];
  const document = {
    querySelectorAll: () => viewports,
    createElement: () => meta(''),
    head: {appendChild: element => { viewports.push(element); created++; }},
    documentElement: {scrollWidth: contentWidth, clientWidth: 360},
    body: {scrollWidth: contentWidth, clientWidth: 360},
  };
  const context = vm.createContext({
    document, restore: false, viewportWidth: 360,
    requestAnimationFrame: callback => frames.push(callback),
  });
  const invoke = () => vm.runInContext('(async () => {' + script + '\n})()', context);
  let resolved = false;
  const promise = invoke().then(value => { resolved = true; return value; });
  await Promise.resolve();
  const resolvedBeforeLayout = resolved;
  let frameCount = 0;
  while (frames.length) { frames.shift()(); frameCount++; }
  const value = await promise;
  const content = viewports[0].content;
  const second = invoke();
  while (frames.length) frames.shift()();
  await second;
  const afterSecondRun = viewports[0].content;
  context.restore = true;
  const undo = invoke();
  while (frames.length) frames.shift()();
  await undo;
  return {original, content, created, value, frames: frameCount, resolvedBeforeLayout,
    afterSecondRun, restored: viewports[0]?.content ?? null, remaining: viewports.length,
    memoryCleared: !Object.hasOwn(document, '__spectacularOriginalViewport')};
}
(async () => {
  const existing = await run('width=device-width,height=device-height,initial-scale=1, maximum-scale=1; user-scalable=no,MINIMUM-scale = 1,viewport-fit=cover', 1260);
  const missing = await run(null, 360);
  process.stdout.write(JSON.stringify({existing, missing}));
})().catch(error => { console.error(error); process.exitCode = 1; });
''';
