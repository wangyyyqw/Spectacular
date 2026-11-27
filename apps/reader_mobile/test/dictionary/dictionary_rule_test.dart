import 'dart:async';
import 'dart:convert';

import 'package:charset/charset.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reader_mobile/dictionary/dictionary_rule.dart';
import 'package:reader_mobile/dictionary/dictionary_rule_client.dart';
import 'package:reader_mobile/dictionary/dictionary_store.dart';
import 'package:reader_mobile/library/library_store.dart';

const _jsonRule = DictionaryRule(
  id: 'rule-json',
  name: '接口词典',
  url: 'https://e.test/api?q={{word}}',
  headers: '{"x-test":"1"}',
  extract: DictionaryExtractMode.json,
  selector: 'data.0.definition',
  format: DictionaryResultFormat.text,
);

void main() {
  test('保留四个内置词典、唯一且始终合并，不能删除或改写', () async {
    expect(dictionaryBuiltInRules, hasLength(4));
    expect(
      dictionaryBuiltInRules.map((rule) => rule.name),
      orderedEquals(['海词中文', '汉典', '漢典', '必应中英']),
    );
    expect(
      dictionaryBuiltInRules.map((rule) => rule.id).toSet(),
      hasLength(dictionaryBuiltInRules.length),
    );
    for (final rule in dictionaryBuiltInRules) {
      expect(rule.builtIn, isTrue);
      validateDictionaryRule(rule);
    }
    final store = DictionaryStore(LibraryStore.memory());
    expect(
      (await store.load()).rules.where((rule) => rule.builtIn),
      hasLength(4),
    );
    await expectLater(
      store.removeRule('builtin-haici-zh'),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      store.saveRule(
        dictionaryBuiltInRules.first.copyWith(url: 'https://e.test/{{word}}'),
      ),
      throwsA(isA<FormatException>()),
    );
    await store.setRuleEnabled('builtin-haici-zh', false);
    expect(
      (await store.load()).rules
          .firstWhere((rule) => rule.id == 'builtin-haici-zh')
          .enabled,
      isFalse,
    );
  });

  test('升级后移除旧配置中的五个内置词典，保留自定义词典与其他设置', () async {
    const removedIds = [
      'builtin-baike',
      'builtin-zdic-cidian',
      'builtin-xinhua',
      'builtin-hanyuguoxue',
      'builtin-hao86',
    ];
    final library = LibraryStore.memory();
    final store = DictionaryStore(library);
    for (final sourceId in removedIds) {
      await library.setSetting(
        DictionaryStore.settingKey,
        jsonEncode({
          'rules': [
            for (final id in removedIds)
              DictionaryRule(
                id: id,
                name: '已移除词典',
                url: 'https://e.test/?q={{word}}',
              ).toJson(),
            dictionaryBuiltInRules.first.copyWith(enabled: false).toJson(),
            _jsonRule.toJson(),
          ],
          'settings': {
            'sourceId': 'rule:$sourceId',
            'disableThinking': false,
            'presetId': 'dictionary_classical',
          },
        }),
      );
      final state = await store.load();
      expect(state.rules, hasLength(5));
      expect(
        state.rules.where((rule) => removedIds.contains(rule.id)),
        isEmpty,
      );
      expect(state.rules.first.enabled, isFalse);
      expect(state.rules.last.toJson(), _jsonRule.toJson());
      expect(state.settings.sourceId, isEmpty);
      expect(state.settings.disableThinking, isFalse);
      expect(state.settings.presetId, 'dictionary_classical');
    }
    await store.changeSettings(
      (settings) => settings.copyWith(sourceId: _jsonRule.sourceId),
    );
    expect(
      (await DictionaryStore(library).load()).settings.sourceId,
      _jsonRule.sourceId,
    );
    final saved = jsonDecode(
      (await library.getSetting(DictionaryStore.settingKey))!,
    ) as Map;
    expect(saved['rules'], hasLength(5));
  });

  test('规则校验地址占位符、请求头、正则和同名限制', () async {
    expect(
      () => validateDictionaryRule(
        const DictionaryRule(id: 'a', name: 'a', url: 'https://e.test/?q=x'),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => validateDictionaryRule(
        const DictionaryRule(
          id: 'a',
          name: 'a',
          url: 'https://e.test/?q={{word}}',
          headers: 'not-json',
        ),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => validateDictionaryRule(
        const DictionaryRule(
          id: 'a',
          name: 'a',
          url: 'https://e.test/?q={{word}}',
          extract: DictionaryExtractMode.regex,
          selector: '(',
        ),
      ),
      throwsA(isA<FormatException>()),
    );
    final store = DictionaryStore(LibraryStore.memory());
    await store.saveRule(_jsonRule);
    await expectLater(
      store.saveRule(_jsonRule.copyWith(id: 'rule-other')),
      throwsA(isA<FormatException>()),
    );
    final loaded = (await store.load()).rules
        .where((rule) => !rule.builtIn)
        .single;
    expect(loaded.name, '接口词典');
    expect(loaded.extract, DictionaryExtractMode.json);
    expect(loaded.toJson()['headers'], '{"x-test":"1"}');
  });

  test('规则 JSON 支持单条、数组和 rules 包装，非法内容明确报错', () {
    final single = decodeDictionaryRules(jsonEncode(_jsonRule.toJson()));
    expect(single.single.name, _jsonRule.name);
    expect(single.single.id, _jsonRule.id);
    final wrapped = decodeDictionaryRules(
      jsonEncode({
        'version': 1,
        'rules': [
          {'name': '无 ID', 'url': 'https://e.test/?q={{word}}'},
        ],
      }),
    );
    expect(wrapped.single.id, startsWith('rule-'));
    expect(
      () => decodeDictionaryRules('not-json'),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => decodeDictionaryRules('{"rules":[]}'),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => validateDictionaryRule(
        const DictionaryRule(
          id: 'post',
          name: 'POST',
          url: 'https://e.test/query',
          method: 'POST',
          body: 'word={{word}}',
        ),
      ),
      returnsNormally,
    );
  });

  test('GET 地址编码、请求头和 JSON 路径提取', () async {
    final client = DictionaryRuleClient(
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.queryParameters['q'], '词典');
        expect(request.headers['x-test'], '1');
        return http.Response(
          jsonEncode({
            'data': [
              {'definition': '收集词语并解释含义的工具。'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    addTearDown(client.close);
    final result = await client.lookup(rule: _jsonRule, word: ' 词典 ');
    expect(result.value, '收集词语并解释含义的工具。');
    expect(result.html, isFalse);
  });

  testWidgets('二十秒超时覆盖连接和正文下载的总时长，超时后关闭连接', (tester) async {
    final headers = Completer<http.StreamedResponse>();
    final body = StreamController<List<int>>();
    final client = DictionaryRuleClient(
      client: MockClient.streaming((_, _) => headers.future),
    );
    addTearDown(client.close);
    var finished = false;
    final result = expectLater(
      client.lookup(rule: _jsonRule, word: '词典'),
      throwsA(
        isA<DictionaryRuleException>().having(
          (error) => error.message,
          '消息',
          '查询超时，请重试',
        ),
      ),
    ).then((_) => finished = true);
    await tester.pump(const Duration(seconds: 12));
    headers.complete(http.StreamedResponse(body.stream, 200));
    await tester.pump();
    body.add(utf8.encode('{"data":'));
    await tester.pump(const Duration(seconds: 7));
    expect(finished, isFalse);
    await tester.pump(const Duration(seconds: 1));
    await result;
    await expectLater(
      client.lookup(rule: _jsonRule, word: '重试'),
      throwsA(
        isA<DictionaryRuleException>().having(
          (error) => error.message,
          '消息',
          '查询已关闭',
        ),
      ),
    );
    await body.close();
    await tester.pump();
  });

  for (final (status, hint) in [
    (403, '请求头或访问权限'),
    (429, '查询过于频繁'),
    (503, '切换词典'),
  ]) {
    test('HTTP $status 无需等待错误正文即可提示并释放响应流', () async {
      var canceled = false;
      final body = StreamController<List<int>>(onCancel: () => canceled = true);
      final client = DictionaryRuleClient(
        client: MockClient.streaming(
          (_, _) async => http.StreamedResponse(body.stream, status),
        ),
      );
      addTearDown(client.close);
      addTearDown(body.close);
      await expectLater(
        client.lookup(rule: _jsonRule, word: '词典'),
        throwsA(
          isA<DictionaryRuleException>()
              .having((error) => error.message, '状态码', contains('HTTP $status'))
              .having((error) => error.message, '提示', contains(hint)),
        ),
      );
      expect(canceled, isTrue);
    });
  }

  test('正文下载中断显示可重试的网络提示，不暴露底层错误', () async {
    final client = DictionaryRuleClient(
      client: MockClient.streaming(
        (_, _) async => http.StreamedResponse(
          Stream<List<int>>.error(StateError('private-response-detail')),
          200,
        ),
      ),
    );
    addTearDown(client.close);
    await expectLater(
      client.lookup(rule: _jsonRule, word: '词典'),
      throwsA(
        isA<DictionaryRuleException>().having(
          (error) => error.message,
          '消息',
          '连接失败，请检查网络和词典地址',
        ),
      ),
    );
  });

  test('POST 请求体、正则提取和错误状态不泄露请求头', () async {
    final client = DictionaryRuleClient(
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.body, contains('查询'));
        expect(request.headers['authorization'], 'Bearer secret-token');
        return http.Response(
          '结果：查询成功',
          200,
          headers: {'content-type': 'text/plain; charset=utf-8'},
        );
      }),
    );
    addTearDown(client.close);
    final rule = DictionaryRule(
      id: 'rule-post',
      name: 'POST 词典',
      url: 'https://e.test/query',
      method: 'POST',
      headers: '{"Authorization":"Bearer secret-token"}',
      body: 'word={{word}}',
      extract: DictionaryExtractMode.regex,
      selector: '结果：(.+)',
      format: DictionaryResultFormat.text,
    );
    expect((await client.lookup(rule: rule, word: '查询')).value, '查询成功');
    final denied = DictionaryRuleClient(
      client: MockClient((_) async => http.Response('secret-token', 403)),
    );
    addTearDown(denied.close);
    await expectLater(
      denied.lookup(rule: rule, word: '查询'),
      throwsA(
        isA<DictionaryRuleException>()
            .having((e) => e.message, '消息', contains('403'))
            .having((e) => e.message, '提示', contains('请求头'))
            .having((e) => e.message, '不泄露', isNot(contains('secret-token'))),
      ),
    );
  });

  test('CSS 提取保留 HTML，@text 与纯文本格式去标签', () async {
    const source =
        '<html><body><div class="entry"><b>词典</b></div>'
        '<div class="entry">第二项</div></body></html>';
    Future<DictionaryRuleResult> run(DictionaryRule rule) =>
        DictionaryRuleClient(
          client: MockClient(
            (_) async => http.Response(
              source,
              200,
              headers: {'content-type': 'text/html; charset=utf-8'},
            ),
          ),
        ).lookup(rule: rule, word: '词典');
    const base = DictionaryRule(
      id: 'rule-css',
      name: 'CSS 词典',
      url: 'https://e.test/?q={{word}}',
      extract: DictionaryExtractMode.css,
      selector: '.entry',
    );
    final htmlResult = await run(base);
    expect(htmlResult.html, isTrue);
    expect(htmlResult.value, contains('<b>词典</b>'));
    expect(htmlResult.value, contains('<hr>'));
    final textResult = await run(base.copyWith(selector: '.entry@text'));
    expect(textResult.value, '词典\n第二项');
    expect(textResult.html, isFalse);
    final stripped = await run(
      base.copyWith(format: DictionaryResultFormat.text),
    );
    expect(stripped.value, '词典\n第二项');
    expect(stripped.value, isNot(contains('<b>')));
  });

  test('CSS 先移除指定元素，备用选择器按顺序生效', () async {
    const source =
        '<html><body><div class="noise">广告</div>'
        '<div class="entry"><b>别名</b></div><div class="other">备用</div>'
        '</body></html>';
    final client = DictionaryRuleClient(
      client: MockClient(
        (_) async => http.Response(
          source,
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        ),
      ),
    );
    addTearDown(client.close);
    final result = await client.lookup(
      rule: const DictionaryRule(
        id: 'css',
        name: 'CSS',
        url: 'https://e.test/?q={{word}}',
        extract: DictionaryExtractMode.css,
        selector: '#missing||.entry',
        remove: '.noise, .other',
      ),
      word: '词',
    );
    expect(result.value, contains('别名'));
    expect(result.value, isNot(contains('广告')));
    expect(result.value, isNot(contains('备用')));
  });

  test('GBK 响应按 charset 解码，缺失匹配与超大响应明确报错', () async {
    final gbkClient = DictionaryRuleClient(
      client: MockClient(
        (_) async => http.Response.bytes(
          gbk.encode('<div class="entry">汉语词典</div>'),
          200,
          headers: {'content-type': 'text/html; charset=gbk'},
        ),
      ),
    );
    addTearDown(gbkClient.close);
    final gbkRule = const DictionaryRule(
      id: 'rule-gbk',
      name: 'GBK',
      url: 'https://e.test/?q={{word}}',
      extract: DictionaryExtractMode.css,
      selector: '.entry@text',
    );
    expect((await gbkClient.lookup(rule: gbkRule, word: '词典')).value, '汉语词典');
    await expectLater(
      gbkClient.lookup(
        rule: gbkRule.copyWith(selector: '.missing'),
        word: '词典',
      ),
      throwsA(isA<DictionaryRuleException>()),
    );
    final large = DictionaryRuleClient(
      client: MockClient(
        (_) async => http.Response(
          'x' * (DictionaryRuleClient.maxResponseBytes + 1),
          200,
        ),
      ),
    );
    addTearDown(large.close);
    await expectLater(
      large.lookup(rule: gbkRule, word: '词典'),
      throwsA(
        isA<DictionaryRuleException>().having(
          (e) => e.message,
          '消息',
          contains('过大'),
        ),
      ),
    );
  });

  test('规则随字段保存、重启后恢复，删除时清理当前来源', () async {
    final library = LibraryStore.memory();
    final store = DictionaryStore(library);
    await store.saveRule(_jsonRule);
    await store.changeSettings((s) => s.copyWith(sourceId: _jsonRule.sourceId));
    final reopened = DictionaryStore(library);
    final state = await reopened.load();
    expect(state.rules.where((rule) => !rule.builtIn).single.id, _jsonRule.id);
    expect(state.settings.sourceId, _jsonRule.sourceId);
    await reopened.removeRule(_jsonRule.id);
    final after = await store.load();
    expect(after.rules.where((rule) => !rule.builtIn), isEmpty);
    expect(after.rules, isNotEmpty);
    expect(after.settings.sourceId, isEmpty);
  });
}
