import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import '../cloud_models.dart';

/// 读取网页声明的字符串和请求参数，不运行页面脚本。
class LanzouPageData {
  LanzouPageData(String content) : document = html.parse(content) {
    final scripts = document
        .querySelectorAll('script')
        .map((node) => node.text)
        .join('\n');
    script = scripts.replaceAllMapped(
      RegExp(
        r'''"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|/\*[\s\S]*?\*/|//[^\n]*''',
      ),
      (match) => match[0]!.startsWith('/') ? ' ' : match[0]!,
    );
    for (final match in RegExp(
      r'''\b([A-Za-z_$][\w$]*)\s*=\s*("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|[\w$]+)\s*[;,]''',
    ).allMatches(script)) {
      _variables[match[1]!] = match[2]!;
    }
  }

  final Document document;
  late final String script;
  final _variables = <String, String>{};

  String _value(String text) {
    for (var step = 0; step < 8; step++) {
      if (text.startsWith('"')) {
        try {
          return jsonDecode(text) as String;
        } on FormatException {
          return '';
        }
      }
      if (text.startsWith("'")) {
        return text.substring(1, text.length - 1).replaceAllMapped(
          RegExp(r'\\(?:x[0-9a-fA-F]{2}|u[0-9a-fA-F]{4}|.)'),
          (match) {
            final escaped = match[0]!.substring(1);
            return escaped.startsWith('x') || escaped.startsWith('u')
                ? String.fromCharCode(
                    int.parse(escaped.substring(1), radix: 16),
                  )
                : escaped;
          },
        );
      }
      if (RegExp(r'^\d+$').hasMatch(text)) return text;
      final next = _variables[text];
      if (next == null) return '';
      text = next;
    }
    return '';
  }

  Map<String, String> _fields(String text) => {
    for (final match in RegExp(
      r'''["']?([A-Za-z_$][\w$]*)["']?\s*:\s*("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|[\w$]+)''',
    ).allMatches(text))
      match[1]!: _value(match[2]!),
  };

  Map<String, String> get accountParameters {
    final uid =
        RegExp(r'''uid=(\d+)''').firstMatch(script)?[1] ?? _value('uid');
    final vei = _fields(script)['vei'] ?? _value('vei');
    return {if (uid.isNotEmpty) 'uid': uid, if (vei.isNotEmpty) 'vei': vei};
  }

  String get frame =>
      document.querySelector('iframe[src]')?.attributes['src'] ?? '';

  List<Map<String, String>> get _requests => [
    for (final match in RegExp(r'\bdata\s*:\s*\{([^{}]*)\}').allMatches(script))
      _fields(match[1]!),
  ];

  ({String endpoint, Map<String, String> fields}) download(String password) {
    var endpoint = '';
    for (final match in RegExp(
      r'''["']?url["']?\s*:\s*("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|[\w$]+)''',
    ).allMatches(script)) {
      final candidate = _value(match[1]!);
      if (RegExp(r'(?:^|/)ajax(?:m|file)\.php(?:\?|$)').hasMatch(candidate)) {
        endpoint = candidate;
      }
    }
    final fields = _requests
        .where((row) => row['action'] == 'downprocess')
        .lastOrNull;
    if (endpoint.isEmpty || fields == null) {
      throw const CloudException('蓝奏下载页面已变化，请稍后重试');
    }
    final result = {...fields, 'kd': '1'};
    result['sign'] = result['sign']?.isNotEmpty == true
        ? result['sign']!
        : _value('wp_sign');
    if (document.querySelector('input[type="password"]') != null ||
        script.contains('function down_p')) {
      if (password.isEmpty) throw const CloudException('蓝奏文件缺少访问密码，请在官网检查');
      result['p'] = password;
    } else {
      result['websignkey'] = result['websignkey']?.isNotEmpty == true
          ? result['websignkey']!
          : _value('ajaxdata');
      result.putIfAbsent('ves', () => '1');
    }
    if (result['sign']!.isEmpty) throw const CloudException('蓝奏未返回文件下载签名');
    return (endpoint: endpoint, fields: result);
  }

  Map<String, String>? get confirmation {
    if (!RegExp(r'function\s+down_r\s*\(\s*el\s*\)').hasMatch(script)) {
      return null;
    }
    final fields = _requests
        .where(
          (row) =>
              row['file']?.isNotEmpty == true &&
              row['sign']?.isNotEmpty == true,
        )
        .firstOrNull;
    return fields == null
        ? null
        : {'file': fields['file']!, 'sign': fields['sign']!, 'el': '2'};
  }
}

/// 官网公开挑战仅做固定排列和异或；交互验证码仍交由网页登录。
String? lanzouPageCookie(String body) {
  final hex = RegExp(r'''\barg1\s*=\s*["']([\da-fA-F]{40})["']''')
      .firstMatch(body)?[1];
  if (hex == null) return null;
  const order = [
    15,
    35,
    29,
    24,
    33,
    16,
    1,
    38,
    10,
    9,
    19,
    31,
    40,
    27,
    22,
    23,
    25,
    13,
    6,
    11,
    39,
    18,
    20,
    8,
    14,
    21,
    32,
    26,
    2,
    30,
    7,
    4,
    17,
    5,
    3,
    28,
    34,
    37,
    12,
    36,
  ];
  const mask = '3000176000856006061501533003690027800375';
  final output = StringBuffer();
  for (var offset = 0; offset < 40; offset += 2) {
    final byte = int.parse(
      '${hex[order[offset] - 1]}${hex[order[offset + 1] - 1]}',
      radix: 16,
    );
    output.write(
      (byte ^ int.parse(mask.substring(offset, offset + 2), radix: 16))
          .toRadixString(16)
          .padLeft(2, '0'),
    );
  }
  return output.toString();
}
