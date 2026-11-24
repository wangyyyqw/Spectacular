import 'dart:convert';

import 'package:flutter_js/flutter_js.dart';

import 'online_review.dart';

/// 书源 JS 规则执行失败。
class BookSourceScriptException implements Exception {
  const BookSourceScriptException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 求值书源请求头；兼容整段 JS 和 JSON 字段中的模板表达式。
Map<String, String> evaluateBookSourceHeaders(
  String raw,
  QuickJsBookSourceScriptSession script,
  String baseUrl,
) {
  String evaluate(String code) => script.evaluate(
    code,
    result: '',
    variables: {'baseUrl': baseUrl},
    resolveString: (_) => '',
    resolveList: (_) => const [],
  );
  var text = raw.trim();
  if (text.isEmpty) return {};
  if (text.startsWith('@js:')) {
    text = evaluate(text.substring(4));
  } else if (text.startsWith('<js>')) {
    text = evaluate(text.substring(4).replaceFirst(RegExp(r'</js>\s*$'), ''));
  }
  final decoded = jsonDecode(text);
  if (decoded is! Map) return {};
  return {
    for (final entry in decoded.entries)
      '${entry.key}': '${entry.value}'.replaceAllMapped(
        RegExp(r'\{\{([\s\S]*?)\}\}'),
        (match) => evaluate(match.group(1)!),
      ),
  };
}

/// 书源脚本发起的一次 HTTP 请求。
///
/// `key` 由脚本侧生成，用于把响应写回同一个缓存位置。
class BookSourcePendingRequest {
  const BookSourcePendingRequest({
    required this.key,
    required this.method,
    required this.url,
    this.body = '',
    this.headers = const <String, String>{},
  });

  final String key;
  final String method;
  final String url;
  final String body;
  final Map<String, String> headers;
}

/// 登录脚本请求打开的网页；等待型调用在返回后重放脚本。
class BookSourceBrowserRequest {
  const BookSourceBrowserRequest(this.key, this.url, this.title, this.wait);
  final String key;
  final String url;
  final String title;
  final bool wait;
}

/// 供书源规则引擎使用的 JS 会话。
///
/// 规则引擎不直接依赖 QuickJS，测试可以注入轻量实现。
abstract class BookSourceScriptSession {
  /// 当前已缓存的响应，键与 [BookSourcePendingRequest.key] 一致。
  Map<String, String> get responses;

  /// 把一次 HTTP 响应写入脚本缓存。
  void rememberResponse(String key, String body);

  /// 取出并清空本轮脚本尚未满足的请求。
  List<BookSourcePendingRequest> takePendingRequests();

  /// 执行一段 Legado JS。
  ///
  /// [resolveString] / [resolveList] 用于实现 `java.getString` 与
  /// `java.getStringList`；它们由规则引擎基于当前页面根节点求值。
  String evaluate(
    String code, {
    required String result,
    required Map<String, String> variables,
    required String Function(String rule) resolveString,
    required List<String> Function(String rule) resolveList,
  });

  void dispose();
}

/// 基于 QuickJS 的生产实现。
class QuickJsBookSourceScriptSession implements BookSourceScriptSession {
  factory QuickJsBookSourceScriptSession({
    required String jsLib,
    String Function(String domain, String name)? cookieProvider,
    String sourceKey = '',
    Map<String, String> loginInfo = const {},
    String loginHeader = '',
    String sourceVariable = '',
    Map<String, String> sourceValues = const {},
    String Function(String domain)? cookieHeaderProvider,
  }) {
    return QuickJsBookSourceScriptSession._(
      jsLib,
      cookieProvider,
      sourceKey,
      loginInfo,
      loginHeader,
      sourceVariable,
      Map.of(sourceValues),
      cookieHeaderProvider,
    );
  }

  QuickJsBookSourceScriptSession._(
    this._jsLib,
    this.cookieProvider,
    this.sourceKey,
    this.loginInfo,
    this.loginHeader,
    this.sourceVariable,
    this.sourceValues,
    this.cookieHeaderProvider,
  );

  final String _jsLib;
  final String sourceKey;
  Map<String, String> loginInfo;
  String loginHeader;
  String sourceVariable;
  Map<String, String> sourceValues;
  final Map<String, String> sourceValueChanges = {};
  final String Function(String domain)? cookieHeaderProvider;
  final Map<String, String> _browserResponses = {};
  final List<BookSourceBrowserRequest> _browsers = [];
  List<String> messages = [];
  bool rebuildLoginView = false;
  List<OnlineReviewPage> reviewPages = [];

  List<BookSourceBrowserRequest> takeBrowserRequests() {
    final requests = List<BookSourceBrowserRequest>.of(_browsers);
    _browsers.clear();
    return requests;
  }

  void rememberBrowser(String key, String url) => _browserResponses[key] = url;
  final String Function(String domain, String name)? cookieProvider;
  final Map<String, String> _responses = <String, String>{};
  final List<BookSourcePendingRequest> _pending = <BookSourcePendingRequest>[];
  JavascriptRuntime? _runtime;
  bool _libraryLoaded = false;
  final Map<String, ({Set<String> strings, Set<String> lists})> _rulePaths = {};

  /// 阅读和段评使用独立运行时，共享同一书源的临时缓存。
  void restoreMemory(Map<String, Object?> memory) {
    _ensureRuntime().evaluate('__legadoMemory=${jsonEncode(memory)};');
  }

  Map<String, Object?> get memory {
    final runtime = _runtime;
    if (runtime == null) return {};
    final value = runtime.evaluate('JSON.stringify(__legadoMemory)');
    if (value.isError) return {};
    return (jsonDecode(value.stringResult) as Map).cast<String, Object?>();
  }

  @override
  Map<String, String> get responses => _responses;

  @override
  void rememberResponse(String key, String body) {
    _responses[key] = body;
  }

  @override
  List<BookSourcePendingRequest> takePendingRequests() {
    final requests = List<BookSourcePendingRequest>.of(_pending);
    _pending.clear();
    return requests;
  }

  @override
  String evaluate(
    String code, {
    required String result,
    required Map<String, String> variables,
    required String Function(String rule) resolveString,
    required List<String> Function(String rule) resolveList,
  }) {
    final runtime = _ensureRuntime();
    _pending.clear();
    final strings = <String, String>{};
    final lists = <String, List<String>>{};
    final paths = _rulePaths.putIfAbsent(
      code,
      () => (strings: _stringPaths(code), lists: _listPaths(code)),
    );
    if (_rulePaths.length > 64) _rulePaths.remove(_rulePaths.keys.first);
    for (final path in paths.strings) {
      strings[path] = resolveString(path);
    }
    for (final path in paths.lists) {
      lists[path] = resolveList(path);
    }
    _browsers.clear();
    messages = [];
    rebuildLoginView = false;
    reviewPages = [];
    final state =
        '__legadoStrings = ${jsonEncode(strings)};'
        '__legadoLists = ${jsonEncode(lists)};'
        '__legadoResponses = ${jsonEncode(_responses)};'
        '__legadoLoginInfo = ${jsonEncode(loginInfo)};'
        '__legadoLoginHeader = ${jsonEncode(loginHeader)};'
        '__legadoSourceVariable = ${jsonEncode(sourceVariable)};'
        '__legadoSourceValues = ${jsonEncode(sourceValues)};'
        '__legadoValueChanges = {};'
        '__legadoBrowserResponses = ${jsonEncode(_browserResponses)};'
        '__legadoBrowsers = []; __legadoReviewPages = [];'
        '__legadoMessages = []; __legadoRebuild = false;'
        '__legadoBook = ${jsonEncode({'bookUrl': variables['bookUrl'] ?? '', 'name': variables['bookName'] ?? '', 'author': variables['author'] ?? ''})};'
        '__legadoChapter = ${jsonEncode({'url': variables['chapterUrl'] ?? '', 'title': variables['title'] ?? '', 'index': int.tryParse(variables['chapterIndex'] ?? '') ?? 0})};'
        '__legadoSourceKey = ${jsonEncode(sourceKey)};'
        '__legadoRequests = [];';
    final baseUrl = variables['baseUrl'] ?? '';
    final key = variables['key'] ?? variables['keyword'] ?? '';
    final searchKey = variables['searchKey'] ?? key;
    final page = int.tryParse(variables['page'] ?? '') ?? 1;
    final arguments =
        '${variables['_resultJson'] ?? jsonEncode(result)}, ${jsonEncode(baseUrl)}, '
        '${jsonEncode(key)}, $page, ${jsonEncode(searchKey)},'
        '__legadoBook, __legadoChapter, ${variables['isLongClick'] == 'true'},'
        '${jsonEncode(variables['src'] ?? '')}';
    if (!_libraryLoaded) {
      // 脚本库在会话内只解析一次；保留其词法作用域，每条规则更新上下文。
      final library = runtime.evaluate(
        '${state}__legadoEvaluate = (function(result, baseUrl, key, page, searchKey, book, chapter, isLongClick, src) {'
        '$_jsLib\n'
        'return function(nextResult, nextBaseUrl, nextKey, nextPage, nextSearchKey, nextBook, nextChapter, nextLongClick, nextSrc, code) {'
        'result=nextResult; baseUrl=nextBaseUrl; key=nextKey; page=nextPage;'
        'searchKey=nextSearchKey; book=nextBook; chapter=nextChapter;'
        'isLongClick=nextLongClick; src=nextSrc;'
        'if (result && typeof result === "object") {'
        'Object.defineProperty(result,"toString",{value:function(){'
        'return JSON.stringify(this);}, configurable:true});}'
        'var output = eval(code);'
        'return output === undefined ? result : output;'
        '};})($arguments);',
      );
      if (library.isError) {
        throw BookSourceScriptException('书源脚本库初始化失败：${library.stringResult}');
      }
      _libraryLoaded = true;
    }
    final wrapped =
        '(function(){var output="",error="";'
        'try{var value=__legadoEvaluate($arguments, ${jsonEncode(code)});'
        'output=value==null?"":typeof value==="object"?JSON.stringify(value):String(value);}'
        'catch(e){error=String(e);}'
        'return JSON.stringify({output:output,error:error,'
        'browsers:__legadoBrowsers,messages:__legadoMessages,'
        'rebuild:__legadoRebuild,reviews:__legadoReviewPages,'
        'requests:__legadoRequests,info:__legadoLoginInfo,'
        'header:__legadoLoginHeader,variable:__legadoSourceVariable,'
        'values:__legadoSourceValues,changes:__legadoValueChanges});})()';
    // 结果、请求和副作用一次跨运行时读取，避免长目录每字段重复桥接。
    final evaluated = runtime.evaluate(state + wrapped);
    if (evaluated.isError) {
      throw BookSourceScriptException('书源脚本执行失败：${evaluated.stringResult}');
    }
    final effects = jsonDecode(evaluated.stringResult) as Map;
    reviewPages = [
      for (final item
          in (effects['reviews'] as List).whereType<Map<Object?, Object?>>())
        OnlineReviewPage(
          url: '${item['url'] ?? ''}',
          html: '${item['html'] ?? ''}',
          preloadJs: '${item['preloadJs'] ?? ''}',
          config: '${item['config'] ?? ''}',
        ),
    ];
    for (final item
        in (effects['browsers'] as List).whereType<Map<Object?, Object?>>()) {
      _browsers.add(
        BookSourceBrowserRequest(
          '${item['key']}',
          '${item['url']}',
          '${item['title']}',
          item['wait'] == true,
        ),
      );
    }
    messages = (effects['messages'] as List).map((item) => '$item').toList();
    rebuildLoginView = effects['rebuild'] == true;
    {
      final decoded = effects['requests'];
      if (decoded is List) {
        for (final item in decoded) {
          if (item is! Map) continue;
          final url = '${item['url'] ?? ''}'.trim();
          if (url.isEmpty) continue;
          _pending.add(
            BookSourcePendingRequest(
              key: '${item['key'] ?? url}',
              method: '${item['method'] ?? 'GET'}',
              url: url,
              body: '${item['body'] ?? ''}',
              headers: <String, String>{
                for (final entry
                    in (item['headers'] is Map
                        ? (item['headers'] as Map).entries
                        : const <MapEntry<Object?, Object?>>[]))
                  '${entry.key}': '${entry.value}',
              },
            ),
          );
        }
      }
    }
    if ((effects['error'] as String).isNotEmpty) {
      // 首轮脚本需要远程数据时会先失败（例如 JSON.parse 空响应）；
      // 已记录请求时交给上层拉取并重跑。
      if (_pending.isNotEmpty || _browsers.any((item) => item.wait)) return '';
      throw BookSourceScriptException('书源脚本执行失败：${effects['error']}');
    }
    if (_pending.isEmpty && !_browsers.any((item) => item.wait)) {
      final data = effects;
      loginInfo = {
        for (final item in (data['info'] as Map).entries)
          '${item.key}': '${item.value}',
      };
      loginHeader = '${data['header'] ?? ''}';
      sourceVariable = '${data['variable'] ?? ''}';
      sourceValues = {
        for (final item in (data['values'] as Map).entries)
          '${item.key}': '${item.value}',
      };
      sourceValueChanges.addAll({
        for (final item in (data['changes'] as Map).entries)
          '${item.key}': '${item.value}',
      });
    }
    final output = effects['output'] as String;
    if (output == 'undefined' || output == 'null') return '';
    return output;
  }

  JavascriptRuntime _ensureRuntime() {
    final existing = _runtime;
    if (existing != null) return existing;
    // 书源联网由 java.ajax 调度，不加载依赖主线程资源通道的网页 fetch polyfill。
    final runtime = getJavascriptRuntime(xhr: false);
    runtime.onMessage('BookSourceCookie', (dynamic arguments) {
      final args = arguments as List;
      final domain = '${args[0]}';
      final name = '${args[1]}';
      return name.isEmpty
          ? cookieHeaderProvider?.call(domain) ?? ''
          : cookieProvider?.call(domain, name) ?? '';
    });
    final setup = runtime.evaluate(_runtimePreamble);
    if (setup.isError) {
      runtime.dispose();
      throw BookSourceScriptException('无法初始化书源 JS 运行时：${setup.stringResult}');
    }
    _runtime = runtime;
    return runtime;
  }

  @override
  void dispose() {
    _runtime?.dispose();
    _runtime = null;
    _libraryLoaded = false;
  }
}

/// 生产环境默认会话工厂。
class QuickJsBookSourceScriptFactory {
  const QuickJsBookSourceScriptFactory({this.cookieProvider});

  final String Function(String domain, String name)? cookieProvider;

  BookSourceScriptSession create(String jsLib) =>
      QuickJsBookSourceScriptSession(
        jsLib: jsLib,
        cookieProvider: cookieProvider,
      );
}

/// 解析脚本里静态写出的 `java.getCookie(domain, name)`。
///
/// 返回值以 `domain\nname` 为键，供 JS 运行时按调用参数读取。
Map<String, String> resolveScriptCookies(
  String code,
  String Function(String domain, String name)? provider,
) {
  if (provider == null) {
    return const <String, String>{};
  }
  final cookies = <String, String>{};
  for (final match in RegExp(
    r'''(?:getCookie|getKey)\(\s*["']([^"']+)["']\s*,\s*["']([^"']*)["']\s*\)''',
  ).allMatches(code)) {
    final domain = match.group(1)?.trim() ?? '';
    final name = match.group(2)?.trim() ?? '';
    if (domain.isEmpty || name.isEmpty) continue;
    cookies['$domain\n$name'] = provider(domain, name);
  }
  return cookies;
}

Set<String> _stringPaths(String code) {
  final paths = <String>{};
  for (final match in RegExp(
    r'''java\.getString\(\s*"([^"]*)"\s*\)''',
  ).allMatches(code)) {
    paths.add(match.group(1)!);
  }
  for (final match in RegExp(
    r"""java\.getString\(\s*'([^']*)'\s*\)""",
  ).allMatches(code)) {
    paths.add(match.group(1)!);
  }
  return paths;
}

Set<String> _listPaths(String code) {
  final paths = <String>{};
  for (final match in RegExp(
    r'''java\.getStringList\(\s*"([^"]*)"\s*\)''',
  ).allMatches(code)) {
    paths.add(match.group(1)!);
  }
  for (final match in RegExp(
    r"""java\.getStringList\(\s*'([^']*)'\s*\)""",
  ).allMatches(code)) {
    paths.add(match.group(1)!);
  }
  return paths;
}

const String _runtimePreamble = r'''
var __legadoStrings = {};
var __legadoLists = {};
var __legadoResponses = {};
var __legadoRequests = [];
var __legadoB64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
function __legadoUtf8Bytes(value) {
  var text = String(value);
  var bytes = [];
  for (var i = 0; i < text.length; i++) {
    var code = text.charCodeAt(i);
    if (code >= 0xd800 && code <= 0xdbff && i + 1 < text.length) {
      var next = text.charCodeAt(i + 1);
      if (next >= 0xdc00 && next <= 0xdfff) {
        code = 0x10000 + ((code - 0xd800) << 10) + (next - 0xdc00);
        i++;
      }
    }
    if (code < 0x80) {
      bytes.push(code);
    } else if (code < 0x800) {
      bytes.push(0xc0 | (code >> 6), 0x80 | (code & 63));
    } else if (code < 0x10000) {
      bytes.push(0xe0 | (code >> 12), 0x80 | ((code >> 6) & 63), 0x80 | (code & 63));
    } else {
      bytes.push(0xf0 | (code >> 18), 0x80 | ((code >> 12) & 63),
        0x80 | ((code >> 6) & 63), 0x80 | (code & 63));
    }
  }
  return bytes;
}
function __legadoUtf8String(bytes) {
  var out = '';
  for (var i = 0; i < bytes.length;) {
    var b = bytes[i++];
    var code;
    if (b < 0x80) {
      code = b;
    } else if (b >= 0xc0 && b < 0xe0) {
      code = ((b & 31) << 6) | (bytes[i++] & 63);
    } else if (b >= 0xe0 && b < 0xf0) {
      code = ((b & 15) << 12) | ((bytes[i++] & 63) << 6) | (bytes[i++] & 63);
    } else {
      code = ((b & 7) << 18) | ((bytes[i++] & 63) << 12) |
        ((bytes[i++] & 63) << 6) | (bytes[i++] & 63);
    }
    if (code > 0xffff) {
      code -= 0x10000;
      out += String.fromCharCode(0xd800 + (code >> 10), 0xdc00 + (code & 1023));
    } else {
      out += String.fromCharCode(code);
    }
  }
  return out;
}
function __legadoBase64Encode(value) {
  var bytes = __legadoUtf8Bytes(value);
  var out = '';
  for (var i = 0; i < bytes.length; i += 3) {
    var b0 = bytes[i];
    var b1 = i + 1 < bytes.length ? bytes[i + 1] : 0;
    var b2 = i + 2 < bytes.length ? bytes[i + 2] : 0;
    out += __legadoB64[b0 >> 2];
    out += __legadoB64[((b0 & 3) << 4) | (b1 >> 4)];
    out += i + 1 < bytes.length ? __legadoB64[((b1 & 15) << 2) | (b2 >> 6)] : '=';
    out += i + 2 < bytes.length ? __legadoB64[b2 & 63] : '=';
  }
  return out;
}
function __legadoBase64Decode(value) {
  var text = String(value).replace(/[^A-Za-z0-9+/=]/g, '');
  var bytes = [];
  var buffer = 0;
  var bits = 0;
  for (var i = 0; i < text.length; i++) {
    var ch = text[i];
    if (ch === '=') break;
    var code = __legadoB64.indexOf(ch);
    if (code < 0) continue;
    buffer = (buffer << 6) | code;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      bytes.push((buffer >> bits) & 255);
    }
  }
  return __legadoUtf8String(bytes);
}
function __legadoHexDecode(value) {
  var text = String(value).replace(/^0x/i, '');
  if (!/^[0-9a-fA-F]+$/.test(text) || text.length % 2 !== 0) return String(value);
  var bytes = [];
  for (var i = 0; i + 1 < text.length; i += 2) {
    var code = parseInt(text.substring(i, i + 2), 16);
    if (!isNaN(code)) bytes.push(code);
  }
  var decoded = __legadoUtf8String(bytes);
  // 部分书源把纯数字章节 ID 当十六进制解码；无效文本时保留原文。
  if (/^\d+$/.test(text) &&
      /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F\uFFFD]/.test(decoded)) {
    return text;
  }
  return decoded;
}
function __legadoPad2(value) {
  return (value < 10 ? '0' : '') + value;
}
function __legadoTimeFormat(value, format) {
  var number = Number(value);
  var date = new Date(isNaN(number) ? 0 : number);
  if (isNaN(date.getTime())) return '';
  var pattern = format || 'yyyy/MM/dd HH:mm';
  return pattern
    .replace('yyyy', '' + date.getFullYear())
    .replace('MM', __legadoPad2(date.getMonth() + 1))
    .replace('dd', __legadoPad2(date.getDate()))
    .replace('HH', __legadoPad2(date.getHours()))
    .replace('mm', __legadoPad2(date.getMinutes()))
    .replace('ss', __legadoPad2(date.getSeconds()));
}
function __legadoRecord(method, url, body, headers) {
  var target = String(url);
  var payload = String(body || '');
  var key = method === 'GET' ? target : target + '\n' + payload;
  if (typeof __legadoResponses[key] === 'string') {
    return __legadoResponses[key];
  }
  for (var i = 0; i < __legadoRequests.length; i++) {
    if (__legadoRequests[i].key === key) return '';
  }
  __legadoRequests.push({
    key: key,
    method: method,
    url: target,
    body: payload,
    headers: headers || {}
  });
  return '';
}
function __legadoPut(key, value) {
  var text = value == null ? '' : String(value);
  __legadoSourceValues[String(key)] = text;
  __legadoValueChanges[String(key)] = text;
  return text;
}
function __legadoBrowser(url, title, wait) {
  var key = String(url) + '\n' + String(title || '');
  if (Object.prototype.hasOwnProperty.call(__legadoBrowserResponses, key)) {
    return __legadoBrowserResponses[key];
  }
  __legadoBrowsers.push({key:key,url:String(url),title:String(title || ''),wait:wait});
  return '';
}
var java = {
  ajax: function(url) {
    if (typeof url === 'string') {
      var split = url.indexOf(',{');
      if (split >= 0) {
        var options = JSON.parse(url.substring(split + 1));
        return __legadoRecord(options.method || 'GET', url.substring(0, split),
          options.body || '', options.headers || {});
      }
    }
    return __legadoRecord('GET', url, '', {});
  },
  post: function(url, body, headers) {
    return __legadoRecord('POST', url, body, headers || {});
  },
  get: function(key, headers) {
    if (typeof key === 'string' && /^https?:\/\//i.test(key)) {
      return __legadoRecord('GET', key, '', headers || {});
    }
    return __legadoSourceValues[String(key)] || '';
  },
  put: __legadoPut,
  getString: function(path) {
    return __legadoStrings[path] || '';
  },
  getStringList: function(path) {
    return __legadoLists[path] || [];
  },
  getCookie: function(domain, name) {
    return sendMessage('BookSourceCookie',
      JSON.stringify([String(domain), String(name || '')])) || '';
  },
  base64Encode: function(value) {
    return __legadoBase64Encode(value);
  },
  base64Decode: function(value) {
    return __legadoBase64Decode(value);
  },
  hexDecodeToString: function(value) {
    return __legadoHexDecode(value);
  },
  timeFormat: function(value, format) {
    return __legadoTimeFormat(value, format);
  },
  timeFormatUTC: function(value, format, offset) {
    var shift = Number(offset || 0);
    if (Math.abs(shift) <= 24) shift *= 3600000;
    var date = new Date(Number(value) + shift);
    if (isNaN(date.getTime())) return '';
    var parts = {yyyy:date.getUTCFullYear(), MM:__legadoPad2(date.getUTCMonth()+1),
      M:date.getUTCMonth()+1, dd:__legadoPad2(date.getUTCDate()), d:date.getUTCDate(),
      HH:__legadoPad2(date.getUTCHours()), mm:__legadoPad2(date.getUTCMinutes()),
      ss:__legadoPad2(date.getUTCSeconds())};
    return String(format || 'yyyy/MM/dd HH:mm').replace(/yyyy|MM|M|dd|d|HH|mm|ss/g,
      function(token) { return String(parts[token]); });
  },
  toast: function(value) { __legadoMessages.push(String(value)); },
  longToast: function(value) { __legadoMessages.push(String(value)); },
  startBrowser: function(url, title) { return __legadoBrowser(url,title,false); },
  startBrowserAwait: function(url, title) { return __legadoBrowser(url,title,true); },
  showBrowser: function(url, html, preloadJs, config) {
    __legadoReviewPages.push({url:String(url || ''),html:String(html || ''),
      preloadJs:String(preloadJs || ''),config:typeof config === 'object'
        ? JSON.stringify(config) : String(config || '')});
    return true;
  },
  reLoginView: function() { __legadoRebuild = true; },
  upLoginData: function(values) {
    if (values) Object.keys(values).forEach(function(key) {
      __legadoLoginInfo[key] = String(values[key] == null ? '' : values[key]);
    });
  },
  log: function() {}
};
var cookie = {
  getCookie: function(domain) { return java.getCookie(domain); },
  getKey: function(domain, name) { return java.getCookie(domain, name); }
};
var __legadoMemory = {};
var cache = {
  putMemory: function(key, value) { __legadoMemory[String(key)] = value; },
  getFromMemory: function(key) { return __legadoMemory[String(key)] || null; }
};
String.prototype.body = function() { return String(this); };
var source = {
  showBrowser: function(url, html, preloadJs, config) {
    return java.showBrowser(url, html, preloadJs, config);
  },
  get key() { return __legadoSourceKey; },
  get: function(key) { return __legadoSourceValues[String(key)] || ''; },
  put: __legadoPut,
  getKey: function() { return __legadoSourceKey; },
  getLoginInfo: function() { return JSON.stringify(__legadoLoginInfo); },
  getLoginInfoMap: function() {
    var values = JSON.parse(JSON.stringify(__legadoLoginInfo));
    Object.defineProperty(values, 'get', {value: function(key) {
      return Object.prototype.hasOwnProperty.call(values, key) ? values[key] : null;
    }});
    return values;
  },
  putLoginInfo: function(value) {
    __legadoLoginInfo = typeof value === 'string' ? JSON.parse(value) : value;
    return true;
  },
  getLoginHeader: function() { return __legadoLoginHeader; },
  getLoginHeaderMap: function() {
    var values = __legadoLoginHeader ? JSON.parse(__legadoLoginHeader) : {};
    Object.defineProperty(values, 'get', {value: function(key) {
      return Object.prototype.hasOwnProperty.call(values, key) ? values[key] : null;
    }});
    return values;
  },
  putLoginHeader: function(value) {
    __legadoLoginHeader = typeof value === 'string' ? value : JSON.stringify(value);
  },
  getVariable: function() { return __legadoSourceVariable; },
  setVariable: function(value) { __legadoSourceVariable = String(value || ''); }
};
var Packages = {
  java: {
    util: {
      HashMap: function() {
        // 方法不参与 JSON 序列化，java.post 收到的仍是纯请求头键值。
        var values = Object.create(null);
        Object.defineProperties(values, {
          put: {value: function(key, value) {
            var previous = this.get(key);
            this[String(key)] = value;
            return previous;
          }},
          get: {value: function(key) {
            return Object.prototype.hasOwnProperty.call(this, key) ? this[key] : null;
          }},
          remove: {value: function(key) {
            var previous = this.get(key);
            delete this[String(key)];
            return previous;
          }}
        });
        return values;
      }
    },
    lang: {
      String: {
        join: function(separator, values) {
          return (values || []).join(separator);
        }
      }
    }
  }
};
''';
