import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reader_mobile/dictionary/dictionary_client.dart';
import 'package:reader_mobile/dictionary/dictionary_rule.dart';
import 'package:reader_mobile/dictionary/dictionary_rule_client.dart';
import 'package:reader_mobile/dictionary/dictionary_rule_html.dart';
import 'package:reader_mobile/dictionary/dictionary_sheet.dart';
import 'package:reader_mobile/dictionary/dictionary_settings_page.dart';
import 'package:reader_mobile/dictionary/dictionary_store.dart';
import 'package:reader_mobile/dictionary/local_dictionary_store.dart';
import 'package:reader_mobile/library/library_store.dart';
import 'package:reader_mobile/theme/app_theme.dart';
import 'package:reader_ui/panels/reader_settings_sheet.dart';
import 'package:reader_ui/theme/reader_section_slider.dart';
import 'package:reader_ui/theme/reader_ui_style.dart';

const api = DictionaryApi(
  id: 'one',
  name: '测试服务',
  baseUrl: 'https://example.test/api/v2/',
  apiKey: '测试私钥',
  model: 'text-model',
);
http.Response answer(String text) => http.Response(
  jsonEncode({
    'choices': [
      {
        'message': {'content': text},
      },
    ],
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Future<DictionaryStore> configured({bool singleUse = true}) async {
  final store = DictionaryStore(LibraryStore.memory());
  await store.saveApi(api);
  await store.changeSettings((s) => s.copyWith(singleUsePreset: singleUse));
  return store;
}

const _onlineRule = DictionaryRule(
  id: 'online',
  name: '在线测试',
  url: 'https://r.test/?q={{word}}',
  extract: DictionaryExtractMode.text,
  format: DictionaryResultFormat.text,
);

http.Response onlineAnswer(String text, [int status = 200]) => http.Response(
  text,
  status,
  headers: {'content-type': 'text/plain; charset=utf-8'},
);

Future<DictionaryStore> onlineConfigured() async {
  final store = DictionaryStore(LibraryStore.memory());
  await store.saveRule(_onlineRule);
  await store.changeSettings(
    (settings) => settings.copyWith(sourceId: _onlineRule.sourceId),
  );
  return store;
}

Future<void> showOnlineDictionary(
  WidgetTester tester,
  DictionaryStore store,
  DictionaryRuleClient Function() factory,
) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: DictionarySheet(
        store: store,
        text: '测试',
        ruleClientFactory: factory,
      ),
    ),
  ),
);

class _RecoveringDictionaryStore extends DictionaryStore {
  _RecoveringDictionaryStore() : super(LibraryStore.memory());
  int attempts = 0;

  @override
  Future<DictionaryState> load() async {
    if (attempts++ == 0) throw StateError('临时读取失败');
    return super.load();
  }
}

const _localEntry = LocalDictionaryEntry(
  id: 'local-test',
  name: '离线词典',
  digest: 'test',
  wordCount: 1,
);

class _LocalMissStore extends LocalDictionaryStore {
  _LocalMissStore(super.library);
  @override
  Future<List<LocalDictionaryEntry>> load() async => [_localEntry];
  @override
  Future<LocalDictionarySession> open(LocalDictionaryEntry entry) async =>
      _LocalMissSession();
}

class _LocalMissSession extends LocalDictionarySession {
  _LocalMissSession() : super(_localEntry, Directory('unused'));
  @override
  Future<String?> lookup(String text) async => null;
  @override
  List<String> suggest(String text) => [];
  @override
  Future<void> close() async {}
}

void main() {
  test('停用当前服务后只选择已启用服务，全部停用后不发起查询', () async {
    final store = await configured();
    await store.changeSettings((s) => s.copyWith(apiId: api.id));
    await store.saveApi(
      DictionaryApi(
        id: api.id,
        name: api.name,
        baseUrl: api.baseUrl,
        apiKey: api.apiKey,
        model: api.model,
        enabled: false,
      ),
    );
    expect((await store.load()).api, isNull);
    await store.saveApi(
      const DictionaryApi(
        id: 'enabled',
        name: '可用',
        baseUrl: 'https://e.test',
        apiKey: 'test',
        model: 'model',
      ),
    );
    expect((await store.load()).api!.id, 'enabled');
  });

  testWidgets('在线词典规则可与 AI 来源切换，规则失败不阻塞 AI', (tester) async {
    final store = await configured();
    const rule = DictionaryRule(
      id: 'online',
      name: '在线测试',
      url: 'https://r.test/?q={{word}}',
      extract: DictionaryExtractMode.text,
      format: DictionaryResultFormat.text,
    );
    await store.saveRule(rule);
    await store.changeSettings((s) => s.copyWith(sourceId: rule.sourceId));
    final loaded = await store.load();
    expect(loaded.settings.sourceId, rule.sourceId);
    expect(loaded.rules.where((item) => !item.builtIn), hasLength(1));
    var aiCalls = 0;
    final ai = DictionaryClient(
      client: MockClient((_) async {
        aiCalls++;
        return answer('AI 释义');
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DictionarySheet(
            store: store,
            text: '测试',
            client: ai,
            ruleClientFactory: () => DictionaryRuleClient(
              client: MockClient(
                (_) async => http.Response(
                  '服务异常',
                  500,
                  headers: {'content-type': 'text/plain; charset=utf-8'},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('在线测试'), findsOneWidget);
    expect(find.textContaining('HTTP 500'), findsOneWidget);
    expect(aiCalls, 0);
    await tester.tap(find.byKey(const ValueKey('dictionary-ai')));
    await tester.pumpAndSettle();
    expect(find.text('AI 释义'), findsOneWidget);
    expect(aiCalls, 1);
    expect((await store.load()).settings.sourceId, 'ai:one');
    expect(tester.takeException(), isNull);
  });

  testWidgets('在线词典纯文本结果正常显示并记住来源', (tester) async {
    final store = await configured();
    const rule = DictionaryRule(
      id: 'online',
      name: '在线测试',
      url: 'https://r.test/?q={{word}}',
      extract: DictionaryExtractMode.text,
      format: DictionaryResultFormat.text,
    );
    await store.saveRule(rule);
    await store.changeSettings((s) => s.copyWith(sourceId: rule.sourceId));
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DictionarySheet(
            store: store,
            text: '测试',
            ruleClientFactory: () => DictionaryRuleClient(
              client: MockClient((request) async {
                calls++;
                expect(request.url.queryParameters['q'], '测试');
                return http.Response(
                  '在线释义',
                  200,
                  headers: {'content-type': 'text/plain; charset=utf-8'},
                );
              }),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('在线释义'), findsOneWidget);
    expect(calls, 1);
    expect((await store.load()).settings.sourceId, rule.sourceId);
    expect(tester.takeException(), isNull);
  });

  testWidgets('切回已查在线词典复用结果，手动重新查询始终刷新', (tester) async {
    final store = await onlineConfigured();
    final other = _onlineRule.copyWith(
      id: 'other',
      name: '另一词典',
      url: 'https://other.test/?q={{word}}',
    );
    await store.saveRule(other);
    final calls = <String, int>{};
    await showOnlineDictionary(
      tester,
      store,
      () => DictionaryRuleClient(
        client: MockClient((request) async {
          final count = calls.update(
            request.url.host,
            (count) => count + 1,
            ifAbsent: () => 1,
          );
          return onlineAnswer('${request.url.host} 释义 $count');
        }),
      ),
    );
    await tester.pumpAndSettle();
    final otherChip = find.byKey(
      ValueKey('dictionary-source-${other.sourceId}'),
    );
    await tester.ensureVisible(otherChip);
    await tester.tap(otherChip);
    await tester.pumpAndSettle();
    expect(find.text('other.test 释义 1'), findsOneWidget);
    final onlineChip = find.byKey(
      ValueKey('dictionary-source-${_onlineRule.sourceId}'),
    );
    await tester.ensureVisible(onlineChip);
    await tester.tap(onlineChip);
    await tester.pumpAndSettle();
    expect(find.text('r.test 释义 1'), findsOneWidget);
    expect(calls, {'r.test': 1, 'other.test': 1});
    final retry = find.byKey(const ValueKey('dictionary-query-retry'));
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(find.text('r.test 释义 2'), findsOneWidget);
    expect(calls['r.test'], 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('网页、本地、AI 三分栏复用装饰组件并记住各栏来源', (tester) async {
    final configuredStore = await configured();
    final store = DictionaryStore(
      configuredStore.library,
      localDictionaries: _LocalMissStore(configuredStore.library),
    );
    await store.saveRule(_onlineRule);
    await store.changeSettings(
      (settings) => settings.copyWith(sourceId: _onlineRule.sourceId),
    );
    var webCalls = 0;
    var aiCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DictionarySheet(
            store: store,
            text: '测试',
            client: DictionaryClient(
              client: MockClient((_) async {
                aiCalls++;
                return answer('AI 释义');
              }),
            ),
            ruleClientFactory: () => DictionaryRuleClient(
              client: MockClient((_) async {
                webCalls++;
                return onlineAnswer('网页释义');
              }),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ReaderSettingsSheet), findsOneWidget);
    final tabs = find.byType(ReaderSectionSlider);
    expect(
      tester
          .widget<ReaderSectionSlider>(tabs)
          .sections
          .map((item) => item.label),
      ['网页', '本地', 'AI'],
    );
    expect(tester.widget<ReaderSectionSlider>(tabs).index, 0);
    expect(find.text('网页释义'), findsOneWidget);
    expect(find.text('离线词典'), findsNothing);
    expect(
      find.byKey(const ValueKey('dictionary-source-ai:one')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('dictionary-ai')));
    await tester.pumpAndSettle();
    expect(tester.widget<ReaderSectionSlider>(tabs).index, 2);
    expect(find.text('AI 释义'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('dictionary-query-preset')),
      findsOneWidget,
    );
    expect(find.text('在线测试'), findsNothing);
    expect(aiCalls, 1);

    await tester.tap(find.byKey(const ValueKey('dictionary-local')));
    await tester.pumpAndSettle();
    expect(tester.widget<ReaderSectionSlider>(tabs).index, 1);
    expect(find.text('离线词典'), findsOneWidget);
    expect(find.text('本地词典未找到该词条。可修改词语、切换词典，或手动选择 AI 释义。'), findsOneWidget);
    expect(find.byKey(const ValueKey('dictionary-query-preset')), findsNothing);
    expect(aiCalls, 1);
    expect((await store.load()).settings.sourceId, 'local:local-test');

    await tester.tap(find.byKey(const ValueKey('dictionary-web')));
    await tester.pumpAndSettle();
    expect(tester.widget<ReaderSectionSlider>(tabs).index, 0);
    expect(find.text('网页释义'), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(ValueKey('dictionary-source-${_onlineRule.sourceId}')),
          )
          .selected,
      isTrue,
    );
    expect(webCalls, 1);
    expect((await store.load()).settings.sourceId, _onlineRule.sourceId);
    expect(tester.takeException(), isNull);
  });

  testWidgets('空分栏显示配置提示，不回退联网且忽略上个分栏的晚到结果', (tester) async {
    final pending = Completer<http.Response>();
    final store = await onlineConfigured();
    var calls = 0;
    await showOnlineDictionary(
      tester,
      store,
      () => DictionaryRuleClient(
        client: MockClient((_) {
          calls++;
          return pending.future;
        }),
      ),
    );
    await tester.pump();
    expect(calls, 1);
    await tester.tap(find.byKey(const ValueKey('dictionary-local')));
    await tester.pumpAndSettle();
    expect(find.text('尚未导入或启用本地词典，请前往词典设置导入。'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('dictionary-query-retry')),
          )
          .onPressed,
      isNull,
    );
    pending.complete(onlineAnswer('已离开的网页结果'));
    await tester.pumpAndSettle();
    expect(find.text('已离开的网页结果'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('dictionary-ai')));
    await tester.pumpAndSettle();
    expect(find.text('尚未配置或启用 AI 释义服务，请前往词典设置添加。'), findsOneWidget);
    expect(calls, 1);
    expect((await store.load()).settings.sourceId, _onlineRule.sourceId);
    await tester.tap(find.byKey(const ValueKey('dictionary-settings')));
    await tester.pumpAndSettle();
    expect(find.byType(DictionarySettingsPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final scenario in [
    (label: '320dp 大字', size: const Size(320, 600), scale: 1.6, inset: 0.0),
    (label: '键盘弹出', size: const Size(360, 800), scale: 1.0, inset: 500.0),
  ]) {
    testWidgets('${scenario.label}词典弹窗保持查询栏、三分栏和底部操作固定可见', (tester) async {
      tester.view.physicalSize = scenario.size;
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = FakeViewPadding(bottom: scenario.inset);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final store = DictionaryStore(LibraryStore.memory());
      for (var index = 0; index < 12; index++) {
        await store.saveRule(
          _onlineRule.copyWith(id: 'layout-$index', name: '布局测试词典${index + 1}'),
        );
      }
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scenario.scale)),
            child: child!,
          ),
          home: Scaffold(
            resizeToAvoidBottomInset: false,
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDictionary(context, store, '测试'),
                child: const Text('打开词典'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开词典'));
      await tester.pumpAndSettle();
      final sheet = find.byKey(const ValueKey('dictionary-sheet'));
      final input = find.byKey(const ValueKey('dictionary-query-text'));
      final tabs = find.byKey(const ValueKey('dictionary-section-tabs'));
      final settings = find.byKey(const ValueKey('dictionary-settings'));
      final query = find.byKey(const ValueKey('dictionary-query-retry'));
      final inputRect = tester.getRect(input);
      final tabsRect = tester.getRect(tabs);
      final queryRect = tester.getRect(query);
      expect(tester.widget<ReaderSettingsSheet>(sheet).title, isNull);
      if (scenario.inset == 0) {
        expect(
          tester.getSize(sheet).height,
          closeTo(
            scenario.size.height * ReaderUiStyle.settingsSheetHeightFraction,
            0.1,
          ),
        );
      }
      await tester.drag(
        find
            .descendant(of: sheet, matching: find.byType(SingleChildScrollView))
            .first,
        const Offset(0, -180),
      );
      await tester.pumpAndSettle();
      for (final tab in ['local', 'ai']) {
        expect(tester.getRect(input), inputRect);
        expect(tester.getRect(tabs), tabsRect);
        expect(tester.getRect(query), queryRect);
        expect(input.hitTestable(), findsOneWidget);
        expect(settings.hitTestable(), findsOneWidget);
        expect(
          queryRect.bottom,
          lessThanOrEqualTo(scenario.size.height - scenario.inset),
        );
        await tester.tap(find.byKey(ValueKey('dictionary-$tab')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      Navigator.of(tester.element(sheet)).pop();
      await tester.pumpAndSettle();
      expect(find.byType(DictionarySheet), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('加载时重复提交不重发，修改词语可立即查询且晚到旧结果不覆盖', (tester) async {
    final pending = <Completer<http.Response>>[];
    final words = <String>[];
    await showOnlineDictionary(
      tester,
      await onlineConfigured(),
      () => DictionaryRuleClient(
        client: MockClient((request) {
          words.add(request.url.queryParameters['q']!);
          final response = Completer<http.Response>();
          pending.add(response);
          return response.future;
        }),
      ),
    );
    await tester.pump();
    expect(words, ['测试']);
    expect(find.text('正在查询「测试」…'), findsOneWidget);
    final input = find.byKey(const ValueKey('dictionary-query-text'));
    await tester.showKeyboard(input);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(words, ['测试']);
    await tester.enterText(input, '新词');
    await tester.pump();
    final button = find.byKey(const ValueKey('dictionary-query-retry'));
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    expect(words, ['测试', '新词']);
    pending.last.complete(onlineAnswer('新词释义'));
    await tester.pumpAndSettle();
    pending.first.complete(onlineAnswer('旧词释义'));
    await tester.pumpAndSettle();
    expect(find.text('新词释义'), findsOneWidget);
    expect(find.text('旧词释义'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('在线查询失败可直接重试，失败结果不进入缓存', (tester) async {
    var calls = 0;
    await showOnlineDictionary(
      tester,
      await onlineConfigured(),
      () => DictionaryRuleClient(
        client: MockClient((_) async {
          calls++;
          return calls == 1
              ? onlineAnswer('错误正文', 503)
              : onlineAnswer('恢复后的释义');
        }),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('HTTP 503'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    final retry = find.byKey(const ValueKey('dictionary-query-retry'));
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('恢复后的释义'), findsOneWidget);
    expect(find.textContaining('HTTP 503'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('词典设置暂时读取失败后可用重试按钮恢复', (tester) async {
    final store = _RecoveringDictionaryStore();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DictionarySheet(store: store, text: '测试'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('词典设置读取失败，请重试'), findsOneWidget);
    final retry = find.byKey(const ValueKey('dictionary-query-retry'));
    expect(tester.widget<FilledButton>(retry).onPressed, isNotNull);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(store.attempts, 2);
    expect(find.text('词典设置读取失败，请重试'), findsNothing);
    expect(find.text('请选择上方词典来源后查询。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('在线 HTML 清理脚本、事件、文件协议并注入基地址和 CSP', () {
    final source = buildRuleDictionaryHtml(
      '<html><body onload="x()"><script>alert(1)</script>'
      '<img src="pic.png" onerror="x()"><a href="javascript:x()">危险</a>'
      '<iframe src="file:///private"></iframe></body></html>',
      Uri.parse('https://e.test/dict/'),
    );
    final document = html.parse(source);
    expect(document.querySelector('script'), isNull);
    expect(document.querySelector('iframe'), isNull);
    expect(document.querySelector('img')!.attributes['onerror'], isNull);
    expect(
      document.querySelector('base')!.attributes['href'],
      'https://e.test/dict/',
    );
    expect(
      document.querySelector('a')!.attributes.containsKey('href'),
      isFalse,
    );
    expect(
      document
          .querySelector('meta[http-equiv="Content-Security-Policy"]')!
          .attributes['content'],
      contains("default-src 'none'"),
    );
  });

  testWidgets('优先离线查询，未命中不自动发送 AI，手动切换来源才请求并保存选择', (tester) async {
    var requests = 0;
    final configuredStore = await configured();
    final store = DictionaryStore(
      configuredStore.library,
      localDictionaries: _LocalMissStore(configuredStore.library),
    );
    final client = DictionaryClient(
      client: MockClient((_) async {
        requests++;
        return answer('AI 释义');
      }),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DictionarySheet(store: store, text: '未收录词语', client: client),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('本地词典未找到该词条。可修改词语、切换词典，或手动选择 AI 释义。'), findsOneWidget);
    expect(requests, 0);
    await tester.tap(
      find.byKey(const ValueKey('dictionary-source-local:local-test')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('dictionary-ai')));
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(find.text('AI 释义'), findsOneWidget);
    expect((await store.load()).settings.sourceId, 'ai:one');
    expect(tester.takeException(), isNull);
  });

  test('迁移 URL、预设替换与模型列表的兼容行为', () async {
    expect(
      DictionaryClient.endpoint('https://e.test'),
      Uri.parse('https://e.test/v1/chat/completions'),
    );
    expect(
      DictionaryClient.endpoint(api.baseUrl),
      Uri.parse('https://example.test/api/v2/chat/completions'),
    );
    expect(
      DictionaryClient.endpoint(
        'https://e.test/v1/chat/completions',
        models: true,
      ),
      Uri.parse('https://e.test/v1/models'),
    );
    expect(
      DictionaryClient.endpoint('https://e.test/v1/images/generations'),
      Uri.parse('https://e.test/v1/chat/completions'),
    );
    expect(
      DictionaryClient.endpoint('https://e.test/custom/chat/completions'),
      Uri.parse('https://e.test/custom/chat/completions'),
    );
    expect(
      const DictionaryPreset('a', 'a', '解释 {{text}} 和 {{text}}').render(' 词 '),
      '解释 词 和 词',
    );
    expect(const DictionaryPreset('a', 'a', '解释').render('词'), '解释\n\n「词」');
    final client = DictionaryClient(
      client: MockClient((request) async {
        expect(request.url.path, '/api/v2/models');
        expect(request.headers['Authorization'], 'Bearer 测试私钥');
        return http.Response(
          '{"data":{"models":[{"id":"z"},{"name":"a"},"z"]}}',
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    addTearDown(client.close);
    expect(await client.models(api), ['a', 'z']);
  });

  test('关闭思考不支持时只重试一次，同服务后续省略字段并解析分段正文', () async {
    final bodies = <Map<String, dynamic>>[];
    final client = DictionaryClient(
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        bodies.add(body);
        expect(body['model'], api.model);
        expect(body['max_tokens'], 300);
        expect(body['stream'], false);
        if (bodies.length == 1) {
          return http.Response(
            '{"error":{"message":"unsupported reasoning_effort"}}',
            400,
          );
        }
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': [
                    {'type': 'text', 'text': '释义'},
                    {'type': 'text', 'text': '例句'},
                  ],
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    addTearDown(client.close);
    expect(
      await client.lookup(
        api: api,
        preset: dictionaryBuiltInPresets.first,
        text: '词',
      ),
      '释义\n例句',
    );
    await client.lookup(
      api: api,
      preset: dictionaryBuiltInPresets.first,
      text: '词',
    );
    expect(bodies, hasLength(3));
    expect(bodies.first['reasoning_effort'], 'minimal');
    expect(
      bodies.skip(1).every((b) => !b.containsKey('reasoning_effort')),
      isTrue,
    );
    final messages = bodies.first['messages'] as List<dynamic>;
    expect(
      (messages.first as Map<String, Object?>)['content'],
      contains('只输出最终答案'),
    );
  });

  test('鉴权失败不重试，错误不暴露密钥，空结果报告明确失败', () async {
    var calls = 0;
    final client = DictionaryClient(
      client: MockClient((_) async {
        calls++;
        return http.Response(
          jsonEncode({
            'error': {'message': 'invalid key ${api.apiKey}'},
          }),
          401,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    addTearDown(client.close);
    try {
      await client.lookup(
        api: api,
        preset: dictionaryBuiltInPresets.first,
        text: '词',
      );
      fail('应报鉴权失败');
    } on DictionaryException catch (e) {
      expect(e.message, contains('401'));
      expect(e.message, isNot(contains(api.apiKey)));
    }
    expect(calls, 1);
    final empty = DictionaryClient(client: MockClient((_) async => answer('')));
    addTearDown(empty.close);
    await expectLater(
      empty.lookup(api: api, preset: dictionaryBuiltInPresets.first, text: '词'),
      throwsA(isA<DictionaryException>()),
    );
  });
  test('允许思考时省略思考参数，使用普通词典系统提示', () async {
    final client = DictionaryClient(
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, Object?>;
        expect(body.containsKey('reasoning_effort'), isFalse);
        final messages = body['messages'] as List<dynamic>;
        expect((messages.first as Map<String, Object?>)['content'], '你是词典助手。');
        return answer('释义');
      }),
    );
    addTearDown(client.close);
    expect(
      await client.lookup(
        api: api,
        preset: dictionaryBuiltInPresets.first,
        text: '词',
        disableThinking: false,
      ),
      '释义',
    );
  });

  test('设置独立实例串行保存，删除恢复默认且保留其他内容', () async {
    final store = await configured();
    final other = DictionaryStore(store.library);
    await Future.wait([
      store.savePreset(const DictionaryPreset('custom', '自定义', '{{text}}')),
      other.changeSettings(
        (s) => s.copyWith(disableThinking: false, presetId: 'custom'),
      ),
    ]);
    var state = await other.load();
    expect(state.presets, hasLength(4));
    expect(state.preset.id, 'custom');
    expect(state.settings.disableThinking, isFalse);
    expect(state.api!.model, api.model);
    await store.removePreset('custom');
    state = await other.load();
    expect(state.preset.id, 'dictionary_short');
    await store.removeApi(api.id);
    expect((await other.load()).api, isNull);
  });

  testWidgets('320dp 预设切换忽略晚到旧结果，关闭时无过期状态写入', (tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final pending = <Completer<http.Response>>[];
    final client = DictionaryClient(
      client: MockClient((_) {
        final future = Completer<http.Response>();
        pending.add(future);
        return future.future;
      }),
    );
    final store = await configured();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: DictionarySheet(store: store, text: '测试词', client: client),
        ),
      ),
    );
    await tester.pump();
    expect(pending, hasLength(1));
    await tester.tap(find.byKey(const ValueKey('dictionary-query-preset')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('详细百科').last);
    await tester.pump();
    expect(pending, hasLength(2));
    pending[1].complete(answer('新的百科释义'));
    await tester.pumpAndSettle();
    pending[0].complete(answer('旧的简短释义'));
    await tester.pumpAndSettle();
    expect(find.text('新的百科释义'), findsOneWidget);
    expect(find.text('旧的简短释义'), findsNothing);
    expect((await store.load()).preset.id, 'dictionary_short');
    await tester.tap(find.byKey(const ValueKey('dictionary-query-retry')));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    pending.last.complete(answer('关闭后的结果'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('持久切换预设用于下次查询，无服务显示配置入口', (tester) async {
    final store = await configured(singleUse: false);
    final client = DictionaryClient(
      client: MockClient((_) async => answer('释义')),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DictionarySheet(store: store, text: '测试', client: client),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('dictionary-query-preset')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('文言文/古诗词').last);
    await tester.pumpAndSettle();
    expect((await store.load()).preset.id, 'dictionary_classical');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DictionarySheet(
            store: DictionaryStore(LibraryStore.memory()),
            text: '测试',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('请选择上方词典来源后查询。'), findsOneWidget);
    expect(find.text('词典设置'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('在线词典规则可新增并保存 URL 与提取配置', (tester) async {
    final store = DictionaryStore(LibraryStore.memory());
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: DictionarySettingsPage(store: store),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('dictionary-rule-add')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('dictionary-rule-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('dictionary-rule-name')),
      '测试在线词典',
    );
    await tester.enterText(
      find.byKey(const ValueKey('dictionary-rule-url')),
      'https://e.test/search?q={{word}}',
    );
    await tester.tap(find.byKey(const ValueKey('dictionary-rule-save')));
    await tester.pumpAndSettle();
    final rule = (await store.load()).rules
        .where((rule) => !rule.builtIn)
        .single;
    expect(rule.name, '测试在线词典');
    expect(rule.url, contains('{{word}}'));
    expect(rule.enabled, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    '词典设置复用凝光抽屉，API 密钥隐藏且服务与预设可保存',
    (tester) async {
      final store = DictionaryStore(LibraryStore.memory());
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: DictionarySettingsPage(store: store),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('dictionary-api-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('dictionary-api-url')),
        api.baseUrl,
      );
      await tester.enterText(
        find.byKey(const ValueKey('dictionary-api-key')),
        api.apiKey,
      );
      await tester.enterText(
        find.byKey(const ValueKey('dictionary-api-model')),
        api.model,
      );
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.byKey(const ValueKey('dictionary-api-key')),
                matching: find.byType(EditableText),
              ),
            )
            .obscureText,
        isTrue,
      );
      await tester.tap(find.byKey(const ValueKey('dictionary-api-save')));
      await tester.pumpAndSettle();
      expect((await store.load()).apis, hasLength(1));
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('dictionary-preset-add')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const ValueKey('dictionary-preset-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('dictionary-preset-name')),
        '释义测试',
      );
      await tester.enterText(
        find.byKey(const ValueKey('dictionary-preset-prompt')),
        '解释 {{text}}',
      );
      await tester.tap(find.byKey(const ValueKey('dictionary-preset-save')));
      await tester.pumpAndSettle();
      expect((await store.load()).customPresets.single.name, '释义测试');
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.windows,
    }),
  );
}
