import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'dictionary_store.dart';

class DictionaryException implements Exception {
  const DictionaryException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 迁移阅微的兼容接口请求与不支持思考参数时的单次降级。
class DictionaryClient {
  DictionaryClient({http.Client? client})
    : _http =
          client ??
          IOClient(
            HttpClient()..connectionTimeout = const Duration(seconds: 12),
          );
  final http.Client _http;
  static final Set<String> _unsupportedReasoning = {};
  bool _closed = false;

  static Uri endpoint(String baseUrl, {bool models = false}) {
    var value = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty) {
      throw const DictionaryException('服务地址格式无效');
    }
    final operation = RegExp(
      r'/(chat/completions|images/generations|models)$',
      caseSensitive: false,
    );
    if (operation.hasMatch(value)) {
      final root = value.replaceFirst(operation, '');
      return Uri.parse('$root/${models ? 'models' : 'chat/completions'}');
    }
    if (!RegExp(r'/(v1|api/v\d+)$', caseSensitive: false).hasMatch(value)) {
      value += '/v1';
    }
    return Uri.parse('$value/${models ? 'models' : 'chat/completions'}');
  }

  Future<String> lookup({
    required DictionaryApi api,
    required DictionaryPreset preset,
    required String text,
    bool disableThinking = true,
  }) async {
    if (text.trim().isEmpty) throw const DictionaryException('选中文字为空');
    final key = '${api.id}|${api.baseUrl}|${api.model}';
    final body = <String, Object?>{
      'model': api.model,
      'messages': [
        {
          'role': 'system',
          'content': disableThinking
              ? '你是词典助手。不要输出思考过程或推理过程，只输出最终答案。'
              : '你是词典助手。',
        },
        {'role': 'user', 'content': preset.render(text)},
      ],
      'temperature': .2,
      'max_tokens': 300,
      'stream': false,
      if (disableThinking && !_unsupportedReasoning.contains(key))
        'reasoning_effort': 'minimal',
    };
    var response = await _request(api, body: body);
    if (response.statusCode >= 400 && body.containsKey('reasoning_effort')) {
      final message = _error(response, api).toLowerCase();
      if (message.contains('reasoning') &&
          RegExp(
            'reasoning_effort|unsupported|not supported|does not support|unknown|unrecognized|invalid',
          ).hasMatch(message)) {
        _unsupportedReasoning.add(key);
        body.remove('reasoning_effort');
        response = await _request(api, body: body);
      }
    }
    final json = _decodeSuccess(response, api);
    try {
      final choices =
          (json as Map<String, Object?>)['choices'] as List<Object?>;
      final first = choices.first as Map<String, Object?>;
      final message = first['message'] as Map<String, Object?>;
      final content = message['content'];
      final answer = content is String
          ? content.trim()
          : content is List
          ? content
                .whereType<Map<String, Object?>>()
                .map((p) => p['text'])
                .whereType<String>()
                .join('\n')
                .trim()
          : '';
      if (answer.isNotEmpty) return answer;
    } catch (_) {
      // 格式不符统一报告为空结果，不泄露响应内容。
    }
    throw const DictionaryException('未获取到词典结果');
  }

  Future<List<String>> models(DictionaryApi api) async {
    final data = _decodeSuccess(await _request(api, models: true), api);
    final ids = <String>{};
    void read(Object? array) {
      if (array is! List) return;
      for (final item in array) {
        final id = item is String
            ? item
            : item is Map
            ? item['id'] ?? item['name'] ?? item['model']
            : null;
        if (id is String && id.trim().isNotEmpty) ids.add(id.trim());
      }
    }

    if (data is List) read(data);
    if (data is Map) {
      for (final key in ['data', 'models', 'items']) {
        read(data[key]);
      }
      if (data['data'] case final Map<String, Object?> nested) {
        read(nested['models']);
        read(nested['items']);
      }
    }
    if (ids.isEmpty) throw const DictionaryException('服务未返回可用模型，可手动填写模型名称');
    return ids.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  Future<http.Response> _request(
    DictionaryApi api, {
    Map<String, Object?>? body,
    bool models = false,
  }) async {
    if (_closed) throw const DictionaryException('查询已关闭');
    final headers = {
      'Authorization': 'Bearer ${api.apiKey.trim()}',
      'Content-Type': 'application/json',
    };
    try {
      final url = endpoint(api.baseUrl, models: models);
      return await (models
              ? _http.get(url, headers: headers)
              : _http.post(url, headers: headers, body: jsonEncode(body)))
          .timeout(const Duration(seconds: 25));
    } on TimeoutException {
      throw const DictionaryException('查询超时，请重试');
    } on DictionaryException {
      rethrow;
    } catch (_) {
      throw const DictionaryException('连接失败，请检查服务地址与网络');
    }
  }

  Object? _decodeSuccess(http.Response response, DictionaryApi api) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DictionaryException(_error(response, api));
    }
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw const DictionaryException('服务返回格式无效');
    }
  }

  String _error(http.Response response, DictionaryApi api) {
    var message = '服务请求失败（${response.statusCode}）';
    try {
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      final error = json is Map ? json['error'] : null;
      final detail = error is Map ? error['message'] : error;
      if (detail is String && detail.trim().isNotEmpty) {
        message += '：${detail.trim()}';
      }
    } catch (_) {}
    if (api.apiKey.isNotEmpty) message = message.replaceAll(api.apiKey, '***');
    return message.length > 500 ? message.substring(0, 500) : message;
  }

  void close() {
    _closed = true;
    _http.close();
  }
}
