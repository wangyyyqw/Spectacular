import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:charset/charset.dart';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;

import 'dictionary_rule.dart';

class DictionaryRuleException implements Exception {
  const DictionaryRuleException(this.message);
  final String message;
  @override
  String toString() => message;
}

class DictionaryRuleResult {
  const DictionaryRuleResult({
    required this.value,
    required this.html,
    required this.baseUrl,
  });
  final String value;
  final bool html;
  final String baseUrl;
}

/// 执行用户配置的在线词典规则，只做请求和内容提取，不执行页面或规则脚本。
class DictionaryRuleClient {
  DictionaryRuleClient({http.Client? client}) : _http = client ?? http.Client();
  final http.Client _http;
  static const maxResponseBytes = 2 * 1024 * 1024;
  static const maxResultChars = 500000;
  bool _closed = false;

  Future<DictionaryRuleResult> lookup({
    required DictionaryRule rule,
    required String word,
  }) async {
    final query = word.trim();
    if (query.isEmpty) throw const DictionaryRuleException('查询词为空');
    final uri = Uri.tryParse(rule.buildUrl(query));
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      throw const DictionaryRuleException('词典地址无效');
    }
    final request = http.Request(rule.method, uri);
    try {
      request.headers.addAll(rule.parseHeaders());
      if (rule.method == 'POST' && rule.body.isNotEmpty) {
        request.body = rule.buildBody(query);
      }
    } on FormatException catch (error) {
      throw DictionaryRuleException(error.message);
    }
    http.StreamedResponse response;
    try {
      response = await _http.send(request).timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const DictionaryRuleException('查询超时，请重试');
    } on http.ClientException {
      throw const DictionaryRuleException('连接失败，请检查网络和词典地址');
    } on Object {
      throw const DictionaryRuleException('连接失败，请检查网络和词典地址');
    }
    if (_closed) throw const DictionaryRuleException('查询已关闭');
    final bytes = await _readLimited(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final hint = switch (response.statusCode) {
        401 || 403 => '，请检查请求头或访问权限',
        404 => '，接口未返回结果',
        _ => '',
      };
      throw DictionaryRuleException('请求失败（HTTP ${response.statusCode}）$hint');
    }
    final source = _decode(bytes, response.headers, rule.encoding);
    var value = _extract(rule, source).trim();
    if (value.isEmpty) throw const DictionaryRuleException('未提取到词典内容');
    if (value.length > maxResultChars) {
      value = '${value.substring(0, maxResultChars)}…';
    }
    final hasTags = RegExp(r'<[a-zA-Z][^>]*>').hasMatch(value);
    if (rule.format == DictionaryResultFormat.text && hasTags) {
      value = _plainText(value);
    }
    final isHtml =
        rule.format == DictionaryResultFormat.html ||
        (rule.format == DictionaryResultFormat.auto && hasTags);
    return DictionaryRuleResult(
      value: value,
      html: isHtml,
      baseUrl: (response.request?.url ?? uri).toString(),
    );
  }

  Future<List<int>> _readLimited(http.StreamedResponse response) async {
    final length = response.contentLength;
    if (length != null && length > maxResponseBytes) {
      throw const DictionaryRuleException('词典响应过大');
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      builder.add(chunk);
      if (builder.length > maxResponseBytes) {
        throw const DictionaryRuleException('词典响应过大');
      }
    }
    return builder.takeBytes();
  }

  String _decode(List<int> bytes, Map<String, String> headers, String mode) {
    var name = mode.toLowerCase() == 'auto' ? '' : mode.toLowerCase();
    if (name.isEmpty) {
      final contentType = headers['content-type'] ?? '';
      name =
          RegExp(
            r'''charset\s*=\s*["']?([^;"'\s]+)''',
            caseSensitive: false,
          ).firstMatch(contentType)?.group(1)?.toLowerCase() ??
          '';
    }
    if (name.isEmpty) {
      final head = utf8.decode(bytes.take(2048).toList(), allowMalformed: true);
      name =
          RegExp(
            r'''charset\s*=\s*["']?([^"'\s/>]+)''',
            caseSensitive: false,
          ).firstMatch(head)?.group(1)?.toLowerCase() ??
          'utf-8';
    }
    final encoding = Charset.getByName(name) ?? utf8;
    try {
      return encoding.decode(bytes).replaceFirst('\ufeff', '');
    } on Object {
      return utf8
          .decode(bytes, allowMalformed: true)
          .replaceFirst('\ufeff', '');
    }
  }

  String _extract(DictionaryRule rule, String source) {
    switch (rule.extract) {
      case DictionaryExtractMode.auto:
      case DictionaryExtractMode.text:
        return source;
      case DictionaryExtractMode.css:
        if (rule.selector.trim().isEmpty) {
          throw const DictionaryRuleException('CSS 选择器为空');
        }
        final document = html.parse(source);
        for (final selector in rule.remove.split(',')) {
          final value = selector.trim();
          if (value.isEmpty) continue;
          for (final element in document.querySelectorAll(value)) {
            element.remove();
          }
        }
        // `||` 依次尝试备用选择器，`&&` 合并同一组结果；兼容常见的规则写法。
        for (final group in rule.selector.split('||')) {
          final values = <String>[];
          var textOnly = false;
          for (final raw in group.split('&&')) {
            var selector = raw.trim();
            if (selector.isEmpty) continue;
            if (selector.endsWith('@text')) {
              textOnly = true;
              selector = selector.substring(0, selector.length - 5).trim();
            } else if (selector.endsWith('@html') ||
                selector.endsWith('@all')) {
              selector = selector
                  .substring(0, selector.lastIndexOf('@'))
                  .trim();
            }
            if (selector.isEmpty) continue;
            for (final element in document.querySelectorAll(selector)) {
              final value = textOnly ? element.text.trim() : element.outerHtml;
              if (value.isNotEmpty) values.add(value);
            }
          }
          if (values.isNotEmpty) {
            return values.join(textOnly ? '\n' : '<hr>');
          }
        }
        throw const DictionaryRuleException('CSS 规则没有匹配到内容');
      case DictionaryExtractMode.json:
        Object? value;
        try {
          value = jsonDecode(source);
        } on FormatException {
          throw const DictionaryRuleException('返回内容不是有效 JSON');
        }
        final path = rule.selector.trim().replaceFirst(RegExp(r'^\$\.?'), '');
        if (path.isEmpty) {
          return const JsonEncoder.withIndent(' ').convert(value);
        }
        for (final segment
            in path
                .replaceAllMapped(RegExp(r'\[(\d+)\]'), (m) => '.${m[1]}')
                .split('.')) {
          if (segment.isEmpty) continue;
          if (value is List) {
            final index = int.tryParse(segment);
            if (index == null || index < 0 || index >= value.length) {
              throw const DictionaryRuleException('JSON 路径没有匹配到内容');
            }
            value = value[index];
          } else if (value is Map) {
            value = value[segment];
          } else {
            throw const DictionaryRuleException('JSON 路径没有匹配到内容');
          }
        }
        if (value == null) {
          throw const DictionaryRuleException('JSON 路径没有匹配到内容');
        }
        return _jsonText(value);
      case DictionaryExtractMode.regex:
        final RegExp expression;
        try {
          expression = RegExp(rule.selector, multiLine: true, dotAll: true);
        } on FormatException {
          throw const DictionaryRuleException('正则表达式格式无效');
        }
        final match = expression.firstMatch(source);
        if (match == null) throw const DictionaryRuleException('正则没有匹配到内容');
        return (match.groupCount > 0 ? match.group(1) : match.group(0)) ?? '';
    }
  }

  String _plainText(String value) {
    final withBreaks = value.replaceAll(
      RegExp(
        r'<br\s*/?>|</(?:div|p|li|tr|h[1-6])>|<hr\s*/?>',
        caseSensitive: false,
      ),
      '\n',
    );
    final text = html.parseFragment(withBreaks).text ?? withBreaks;
    return text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join('\n');
  }

  String _jsonText(Object? value) {
    if (value is String) return value;
    if (value is num || value is bool) return '$value';
    if (value is List) {
      return value.map(_jsonText).where((v) => v.isNotEmpty).join('\n');
    }
    return const JsonEncoder.withIndent(' ').convert(value);
  }

  void close() {
    _closed = true;
    _http.close();
  }
}
