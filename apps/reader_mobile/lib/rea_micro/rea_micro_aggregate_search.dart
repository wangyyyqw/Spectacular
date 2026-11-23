import 'dart:async';
import 'dart:convert';

import 'package:enough_convert/enough_convert.dart';
import 'package:flutter/services.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:http/http.dart' as http;

import '../library/library_store.dart';
import 'rea_micro_api_client.dart';
import 'rea_micro_models.dart';

/// 一次平台搜索的结果；失败仅影响该平台。
class ReaMicroPlatformSearchResult {
  const ReaMicroPlatformSearchResult(this.source, this.books, {this.error});
  final String source;
  final List<ReaMicroThirdPartyBook> books;
  final String? error;
}

/// 保留阅微原生 search/fetch/gbkEncode 协议的跨端搜索器。
///
/// 同步 JS 请求先登记，再异步获取并重放；响应缓存保证重放不会重复联网。
class ReaMicroAggregateSearch {
  ReaMicroAggregateSearch({
    this.library,
    this.ruleApi,
    this.rulesLoader,
    http.Client Function()? clientFactory,
    this.requestTimeout = const Duration(seconds: 12),
    this.sourceTimeout = const Duration(seconds: 45),
  }) : _clientFactory = clientFactory ?? http.Client.new;

  final LibraryStore? library;
  final ReaMicroThirdPartyApi? ruleApi;
  final Future<Map<String, String>> Function()? rulesLoader;
  final http.Client Function() _clientFactory;
  final Duration requestTimeout, sourceTimeout;
  Map<String, String>? _rules;
  bool _refreshing = false;
  static const _cacheKey = 'reamicro.search.thirdPartyRules';

  static const sourceNames = {
    'ciweimao': '刺猬猫阅读',
    'ciyuanji': '次元姬',
    'douban': '豆瓣',
    'faloo': '飞卢小说网',
    'fanqie': '番茄小说',
    'gongzicp': '长佩文学',
    'jjwxc': '晋江文学城',
    'qidian': '起点中文网',
    'sfacg': '菠萝包轻小说',
    'zongheng': '纵横中文网',
  };

  Future<Map<String, String>> _loadRules() async {
    if (_rules != null) return _rules!;
    if (rulesLoader != null) return _rules = await rulesLoader!();
    const path = 'assets/rea_micro/search/';
    final names = (jsonDecode(
      await rootBundle.loadString('${path}manifest.json'),
    ) as List).cast<String>();
    final entries = await Future.wait(
      names.map(
        (name) async =>
            MapEntry(name, await rootBundle.loadString('$path$name.js')),
      ),
    );
    final rules = Map.fromEntries(entries);
    try {
      final raw = await library?.getSetting(_cacheKey);
      if (raw != null && raw.isNotEmpty) {
        final cached = (jsonDecode(raw) as Map).cast<String, String>();
        for (final entry in cached.entries) {
          if (_validName(entry.key) &&
              entry.value.contains('function search')) {
            if (rules.keys.any(
              (name) =>
                  _type(name) == _type(entry.key) &&
                  _version(name) >= _version(entry.key),
            )) {
              continue;
            }
            rules.removeWhere((name, _) => _type(name) == _type(entry.key));
            rules[entry.key] = entry.value;
          }
        }
      }
    } catch (_) {
      // 缓存不可用时立即使用内置规则。
    }
    return _rules = rules;
  }

  /// 当前搜索先用内置或缓存规则；后台更新供下一次搜索使用。
  Future<void> _refresh(String token) async {
    if (_refreshing || ruleApi == null) return;
    _refreshing = true;
    try {
      final names = await ruleApi!
          .fetchThirdPartyRuleNames(token)
          .timeout(const Duration(seconds: 8));
      final latest = <String, String>{};
      for (final name in names.where(_validName)) {
        final type = _type(name);
        final previous = latest[type];
        if (previous == null || _version(name) > _version(previous)) {
          latest[type] = name;
        }
      }
      final next = Map<String, String>.of(_rules!);
      await Future.wait(
        latest.values.map((name) async {
          if (next.keys.any(
            (key) =>
                _type(key) == _type(name) && _version(key) >= _version(name),
          )) {
            return;
          }
          try {
            final content = await ruleApi!
                .downloadThirdPartyRule(token, name)
                .timeout(const Duration(seconds: 8));
            if (!content.contains('function search')) return;
            next.removeWhere((key, _) => _type(key) == _type(name));
            next[name] = content;
          } catch (_) {
            // 新版本下载失败时保留该源可用的旧版本。
          }
        }),
      );
      _rules = next;
      await library?.setSetting(_cacheKey, jsonEncode(next));
    } catch (_) {
      // 更新接口不可用不阻断平台搜索。
    } finally {
      _refreshing = false;
    }
  }

  Future<void> search({
    required String token,
    required String title,
    required void Function(ReaMicroPlatformSearchResult) onResult,
    bool Function()? isCancelled,
  }) async {
    final rules = await _loadRules();
    if (isCancelled?.call() == true) return;
    unawaited(_refresh(token));
    await Future.wait(
      rules.entries.map((entry) async {
        final result = await searchRule(
          name: entry.key,
          script: entry.value,
          title: title,
          isCancelled: isCancelled,
        );
        if (isCancelled?.call() != true) onResult(result);
      }),
    );
  }

  Future<ReaMicroPlatformSearchResult> searchRule({
    required String name,
    required String script,
    required String title,
    bool Function()? isCancelled,
  }) async {
    final source = sourceNames[_type(name)] ?? _type(name);
    final client = _clientFactory();
    JavascriptRuntime? runtime;
    final deadline = DateTime.now().add(sourceTimeout);
    final responses = <String, Object?>{};
    var query = title.trim();
    var shortened = false;
    try {
      runtime = getJavascriptRuntime(xhr: false);
      runtime.onMessage('ReaMicroGbkEncode', (dynamic args) {
        final text = '${(args as List).first}';
        return const GbkCodec().encode(text).map((byte) {
          if (byte >= 48 && byte <= 57 ||
              byte >= 65 && byte <= 90 ||
              byte >= 97 && byte <= 122 ||
              byte == 45 ||
              byte == 46 ||
              byte == 95 ||
              byte == 126) {
            return String.fromCharCode(byte);
          }
          return '%${byte.toRadixString(16).padLeft(2, '0').toUpperCase()}';
        }).join();
      });
      final setup = runtime.evaluate('$_bridge\n$script', sourceUrl: name);
      if (setup.isError) throw ReaMicroException(setup.stringResult);
      for (var round = 0; round < 80; round++) {
        if (isCancelled?.call() == true) {
          return ReaMicroPlatformSearchResult(source, const []);
        }
        if (DateTime.now().isAfter(deadline)) {
          throw const ReaMicroException('搜索超时');
        }
        final evaluated = runtime.evaluate(
          '__responses=${jsonEncode(responses)};__pending=[];'
          '(function(){var value=null,error=null;'
          'try{value=search(${jsonEncode(query)});}catch(e){error=String(e);}'
          'return JSON.stringify({value:value,error:error,pending:__pending});})()',
        );
        if (evaluated.isError) throw ReaMicroException(evaluated.stringResult);
        final state = jsonDecode(evaluated.stringResult) as Map;
        final pending = state['pending'] as List;
        if (pending.isEmpty) {
          if (state['error'] != null) {
            throw ReaMicroException('${state['error']}');
          }
          final value = state['value'];
          final data = value is String ? jsonDecode(value) : value;
          if (data is! Map || data['data'] is! List) {
            throw const ReaMicroException('平台返回了无效搜索结果');
          }
          if (data['code'] != 200 && data['code'] != 0) {
            throw ReaMicroException('${data['error'] ?? '平台搜索失败'}');
          }
          final seen = <String>{};
          final books = <ReaMicroThirdPartyBook>[];
          for (final raw in data['data'] as List) {
            if (raw is! Map) continue;
            final book = ReaMicroThirdPartyBook.fromJson(
              name,
              raw.cast<String, Object?>(),
            );
            if (book.title.isNotEmpty &&
                _matchesTitle(title, book.title) &&
                seen.add(book.key)) {
              books.add(book);
            }
          }
          if (books.isEmpty && !shortened && title.runes.length >= 10) {
            // 部分平台不接受完整长书名，缩短检索仍按原书名筛选候选。
            query = String.fromCharCodes(title.trim().runes.take(4));
            shortened = true;
            continue;
          }
          return ReaMicroPlatformSearchResult(source, books);
        }
        // 原生规则通常先查列表再查每本详情；同轮请求有限并发。
        for (var start = 0; start < pending.length; start += 6) {
          if (isCancelled?.call() == true) {
            return ReaMicroPlatformSearchResult(source, const []);
          }
          final remaining = deadline.difference(DateTime.now());
          if (remaining <= Duration.zero) throw const ReaMicroException('搜索超时');
          await Future.wait(
            pending.skip(start).take(6).map((raw) async {
              final request = (raw as Map).cast<String, Object?>();
              responses['${request['key']}'] = await _request(
                client,
                request,
                remaining < requestTimeout ? remaining : requestTimeout,
              );
            }),
          );
        }
      }
      throw const ReaMicroException('平台搜索请求过多，请缩小关键词范围');
    } catch (error) {
      return ReaMicroPlatformSearchResult(source, const [], error: '$error');
    } finally {
      runtime?.dispose();
      client.close();
    }
  }

  Future<Map<String, Object?>> _request(
    http.Client client,
    Map<String, Object?> raw,
    Duration timeout,
  ) async {
    try {
      final uri = Uri.parse('${raw['url']}');
      if (!['https', 'http'].contains(uri.scheme)) {
        throw const FormatException('无效平台地址');
      }
      final request = http.Request('${raw['method']}', uri);
      final headers = (raw['headers'] as Map).cast<String, Object?>();
      request.headers.addAll({
        for (final entry in headers.entries)
          // IOClient 自动处理压缩；不能声明它不支持的压缩格式。
          if (entry.key.toLowerCase() != 'accept-encoding')
            entry.key: '${entry.value}',
      });
      if (raw['body'] != null) request.body = '${raw['body']}';
      final response = await (() async => http.Response.fromStream(
        await client.send(request),
      ))().timeout(timeout);
      final bytes = response.bodyBytes;
      final header = response.headers['content-type'] ?? '';
      final prefix = latin1.decode(bytes.take(2048).toList());
      final gbk = RegExp(
        r'charset\s*=?\s*["'
        "'"
        r']?(gbk|gb2312|gb18030)',
        caseSensitive: false,
      ).hasMatch('$header $prefix');
      String text;
      if (gbk) {
        text = const GbkCodec().decode(bytes);
      } else {
        try {
          text = utf8.decode(bytes);
        } on FormatException {
          text = const GbkCodec().decode(bytes);
        }
      }
      return {
        'ok': response.statusCode >= 200 && response.statusCode < 300,
        'status': response.statusCode,
        'statusText': response.reasonPhrase ?? '',
        'headers': response.headers,
        'body': text,
      };
    } catch (error) {
      return {
        'ok': false,
        'status': 0,
        'statusText': '$error',
        'body': '',
        'headers': <String, String>{},
      };
    }
  }

  static String _type(String name) => name.split('_').first;
  static int _version(String name) => int.tryParse(name.split('_').last) ?? 0;
  static bool _validName(String name) =>
      RegExp(r'^[a-z0-9]+_\d+$').hasMatch(name);
  static bool _matchesTitle(String query, String title) {
    final chars = RegExp(
      r'[\p{L}\p{N}]',
      unicode: true,
    ).allMatches(query.toLowerCase()).map((m) => m.group(0)!).toSet();
    if (chars.isEmpty) return true;
    return chars.where(title.toLowerCase().contains).length / chars.length >=
        0.3;
  }
}

const _bridge = r'''
var __responses={}, __pending=[];
globalThis.print=function(){};
globalThis.log=function(){};
globalThis.console={log:log,debug:log,info:log,warn:log,error:log};
globalThis.gbkEncode=function(text){return sendMessage('ReaMicroGbkEncode',JSON.stringify([String(text)]));};
globalThis.gbkencode=globalThis.gbkEncode;
globalThis.fetch=function(url,options){
  var opts=options||{}, headers=opts.headers||{};
  var method=String(opts.method||'GET').toUpperCase();
  var body=opts.body==null?null:String(opts.body);
  if(opts.contentType&&!headers['Content-Type']) headers['Content-Type']=opts.contentType;
  var key=JSON.stringify([String(url),method,body,headers]);
  var raw=__responses[key];
  if(!raw){
    if(!__pending.some(function(p){return p.key===key;}))
      __pending.push({key:key,url:String(url),method:method,body:body,headers:headers});
    throw new Error('等待平台响应');
  }
  return {ok:!!raw.ok,status:raw.status,statusText:raw.statusText||'',
    headers:raw.headers||{},text:function(){return raw.body||'';},
    json:function(){return JSON.parse(raw.body||'');}};
};
''';
