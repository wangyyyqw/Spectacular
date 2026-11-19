import 'dart:convert';

import 'package:flutter_js/flutter_js.dart';

/// 书源 JS 规则执行失败。
class BookSourceScriptException implements Exception {
  const BookSourceScriptException(this.message);

  final String message;

  @override
  String toString() => message;
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
  // ignore: prefer_initializing_formals
  QuickJsBookSourceScriptSession({required String jsLib}) : _jsLib = jsLib;

  final String _jsLib;
  final Map<String, String> _responses = <String, String>{};
  final List<BookSourcePendingRequest> _pending = <BookSourcePendingRequest>[];
  JavascriptRuntime? _runtime;

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
    for (final path in _stringPaths(code)) {
      strings[path] = resolveString(path);
    }
    for (final path in _listPaths(code)) {
      lists[path] = resolveList(path);
    }
    final state = runtime.evaluate(
      '__legadoStrings = ${jsonEncode(strings)};'
      '__legadoLists = ${jsonEncode(lists)};'
      '__legadoResponses = ${jsonEncode(_responses)};'
      '__legadoRequests = [];',
    );
    if (state.isError) {
      throw BookSourceScriptException('书源脚本初始化失败：${state.stringResult}');
    }
    final source = '$_jsLib\n$code';
    final baseUrl = variables['baseUrl'] ?? '';
    final key = variables['key'] ?? variables['keyword'] ?? '';
    final searchKey = variables['searchKey'] ?? key;
    final page = int.tryParse(variables['page'] ?? '') ?? 1;
    final wrapped =
        '(function(result, baseUrl, key, page, searchKey) {'
        'return eval(${jsonEncode(source)});'
        '})(${jsonEncode(result)}, ${jsonEncode(baseUrl)}, '
        '${jsonEncode(key)}, $page, ${jsonEncode(searchKey)});';
    final evaluated = runtime.evaluate(wrapped);
    final pending = runtime.evaluate('JSON.stringify(__legadoRequests)');
    if (!pending.isError && pending.stringResult.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(pending.stringResult);
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
      } on FormatException {
        // 请求列表解析失败时不阻断脚本结果，交由上层正文校验兜底。
      }
    }
    if (evaluated.isError) {
      // 首轮脚本需要远程数据时会先失败（例如 JSON.parse 空响应）；
      // 已记录请求时交给上层拉取并重跑。
      if (_pending.isNotEmpty) return '';
      throw BookSourceScriptException('书源脚本执行失败：${evaluated.stringResult}');
    }
    final output = evaluated.stringResult;
    if (output == 'undefined' || output == 'null') return '';
    return output;
  }

  JavascriptRuntime _ensureRuntime() {
    final existing = _runtime;
    if (existing != null) return existing;
    final runtime = getJavascriptRuntime();
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
  }
}

/// 生产环境默认会话工厂。
class QuickJsBookSourceScriptFactory {
  const QuickJsBookSourceScriptFactory();

  BookSourceScriptSession create(String jsLib) =>
      QuickJsBookSourceScriptSession(jsLib: jsLib);
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
  if (!/^[0-9a-fA-F]+$/.test(text)) return String(value);
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
var java = {
  ajax: function(url) {
    return __legadoRecord('GET', url, '', {});
  },
  post: function(url, body, headers) {
    return __legadoRecord('POST', url, body, headers || {});
  },
  get: function(key, headers) {
    if (typeof key === 'string' && /^https?:\/\//i.test(key)) {
      return __legadoRecord('GET', key, '', headers || {});
    }
    return '';
  },
  getString: function(path) {
    return __legadoStrings[path] || '';
  },
  getStringList: function(path) {
    return __legadoLists[path] || [];
  },
  getCookie: function() {
    return '';
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
  log: function() {}
};
var Packages = {
  java: {
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
