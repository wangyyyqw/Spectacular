import 'dart:async';
import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:reader_mobile/dictionary/dictionary_webview_gestures.dart';
import 'package:reader_mobile/dictionary/dictionary_rule_view.dart';
import 'package:reader_mobile/theme/app_theme.dart';

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) fail('在线词典网页加载超时');
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('在线词典 HTML 视图加载清理后的样式和相对图片', (tester) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var imageServed = false;
    final subscription = server.listen((request) async {
      if (request.uri.path == '/pic.png') {
        imageServed = true;
        request.response.headers.contentType = ContentType('image', 'png');
        request.response.add(const [137, 80, 78, 71, 13, 10, 26, 10]);
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    addTearDown(() async {
      await subscription.cancel();
      await server.close(force: true);
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 360,
              child: DictionaryRuleView(
                html:
                    '<style>.entry{color:#2155aa}</style>'
                    '<div class="entry">在线样式</div>'
                    '<img src="pic.png">',
                baseUrl: 'http://127.0.0.1:${server.port}/',
                height: 300,
              ),
            ),
          ),
        ),
      ),
    );
    await _until(
      tester,
      () =>
          imageServed &&
          find
              .byKey(const ValueKey('dictionary-rule-loading'))
              .evaluate()
              .isEmpty,
    );
    expect(find.text('在线词典内容显示失败'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('词典网页内的纵向手势滚动 WebView 而不是底部弹窗', (tester) async {
    final controller = Completer<InAppWebViewController>();
    final loaded = Completer<void>();
    final outerScrollController = ScrollController();
    addTearDown(outerScrollController.dispose);
    final rows = List.generate(40, (index) => '<p>词条内容 $index</p>').join();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            controller: outerScrollController,
            child: SizedBox(
              height: 300,
              child: InAppWebView(
                gestureRecognizers: dictionaryWebViewGestureRecognizers,
                initialData: InAppWebViewInitialData(
                  data: '<!doctype html><html><body>$rows</body></html>',
                  mimeType: 'text/html',
                  encoding: 'utf-8',
                ),
                onWebViewCreated: (value) => controller.complete(value),
                onLoadStop: (_, _) {
                  if (!loaded.isCompleted) loaded.complete();
                },
              ),
            ),
          ),
        ),
      ),
    );
    await _until(tester, () => controller.isCompleted && loaded.isCompleted);
    final webView = await controller.future;
    final before =
        await webView.evaluateJavascript(source: 'window.scrollY') as num;
    await tester.drag(find.byType(InAppWebView), const Offset(0, -200));
    var after =
        await webView.evaluateJavascript(source: 'window.scrollY') as num;
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (after <= before) {
      if (DateTime.now().isAfter(deadline)) fail('词典 WebView 未随手势滚动');
      await tester.pump(const Duration(milliseconds: 50));
      after = await webView.evaluateJavascript(source: 'window.scrollY') as num;
    }
    expect(after, greaterThan(before));
    expect(outerScrollController.offset, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
