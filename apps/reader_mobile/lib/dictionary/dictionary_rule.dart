import 'dart:convert';

/// 从网页或接口结果中取正文的方式。
enum DictionaryExtractMode {
  auto('auto', '自动/原文'),
  css('css', 'HTML CSS'),
  json('json', 'JSON 路径'),
  regex('regex', '正则'),
  text('text', '纯文本');

  const DictionaryExtractMode(this.id, this.label);
  final String id, label;

  static DictionaryExtractMode fromId(String? id) =>
      values.where((mode) => mode.id == id).firstOrNull ?? auto;
}

/// 提取结果的展示方式。
enum DictionaryResultFormat {
  auto('auto', '自动'),
  html('html', 'HTML'),
  text('text', '纯文本');

  const DictionaryResultFormat(this.id, this.label);
  final String id, label;

  static DictionaryResultFormat fromId(String? id) =>
      values.where((mode) => mode.id == id).firstOrNull ?? auto;
}

/// 可配置的在线词典：URL 模板加提取规则，不执行规则中的脚本。
class DictionaryRule {
  const DictionaryRule({
    required this.id,
    required this.name,
    required this.url,
    this.method = 'GET',
    this.headers = '',
    this.body = '',
    this.extract = DictionaryExtractMode.auto,
    this.selector = '',
    this.remove = '',
    this.format = DictionaryResultFormat.auto,
    this.encoding = 'auto',
    this.enabled = true,
    this.note = '',
    this.builtIn = false,
  });

  final String id, name, url, method, headers, body, selector, encoding;
  final String remove, note;
  final DictionaryExtractMode extract;
  final DictionaryResultFormat format;
  final bool enabled, builtIn;

  String get sourceId => 'rule:$id';

  DictionaryRule copyWith({
    String? id,
    String? name,
    String? url,
    String? method,
    String? headers,
    String? body,
    DictionaryExtractMode? extract,
    String? selector,
    String? remove,
    DictionaryResultFormat? format,
    String? encoding,
    bool? enabled,
    String? note,
    bool? builtIn,
  }) => DictionaryRule(
    id: id ?? this.id,
    name: name ?? this.name,
    url: url ?? this.url,
    method: method ?? this.method,
    headers: headers ?? this.headers,
    body: body ?? this.body,
    extract: extract ?? this.extract,
    selector: selector ?? this.selector,
    remove: remove ?? this.remove,
    format: format ?? this.format,
    encoding: encoding ?? this.encoding,
    enabled: enabled ?? this.enabled,
    note: note ?? this.note,
    builtIn: builtIn ?? this.builtIn,
  );

  String buildUrl(String word) =>
      url.trim().replaceAll('{{word}}', Uri.encodeComponent(word.trim()));

  String buildBody(String word) => body.replaceAll('{{word}}', word.trim());

  Map<String, String> parseHeaders() {
    if (headers.trim().isEmpty) return const {};
    final value = jsonDecode(headers);
    if (value is! Map) throw const FormatException('请求头必须是 JSON 对象');
    final result = <String, String>{};
    for (final entry in value.entries) {
      if (entry.key is! String || entry.value is! String) {
        throw const FormatException('请求头的名称和值都必须是字符串');
      }
      result[entry.key as String] = entry.value as String;
    }
    return result;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'method': method,
    'headers': headers,
    'body': body,
    'extract': extract.id,
    'selector': selector,
    'remove': remove,
    'format': format.id,
    'encoding': encoding,
    'enabled': enabled,
    'note': note,
  };

  factory DictionaryRule.fromJson(Map<String, dynamic> json) => DictionaryRule(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    url: json['url'] as String? ?? '',
    method: (json['method'] as String? ?? 'GET').toUpperCase(),
    headers: json['headers'] as String? ?? '',
    body: json['body'] as String? ?? '',
    extract: DictionaryExtractMode.fromId(json['extract'] as String?),
    selector: json['selector'] as String? ?? '',
    remove: json['remove'] as String? ?? '',
    format: DictionaryResultFormat.fromId(json['format'] as String?),
    encoding: json['encoding'] as String? ?? 'auto',
    enabled: json['enabled'] != false,
    note: json['note'] as String? ?? '',
    builtIn: dictionaryBuiltInRules.any(
      (rule) => rule.id == (json['id'] as String? ?? ''),
    ),
  );
}

/// 随应用提供、不可删除的内置规则。站点改版后可在不发布新规则的情况下调整停用状态。
const dictionaryBuiltInRules = [
  DictionaryRule(
    id: 'builtin-haici-zh',
    name: '海词中文',
    note: '内置规则；页面结构变化时可能失效',
    url: 'https://hanyu.dict.cn/{{word}}',
    extract: DictionaryExtractMode.css,
    selector: '#ly||#cy',
    remove: 'script,style',
    format: DictionaryResultFormat.auto,
    builtIn: true,
  ),
  DictionaryRule(
    id: 'builtin-zdic',
    name: '汉典',
    note: '内置规则；词语解释、近反义词和翻译',
    url: 'https://zdic.net/hans/{{word}}',
    extract: DictionaryExtractMode.css,
    selector: '#xxjs .dict-section__body, #syn .dict-section__body, #trans .dict-section__body',
    remove: 'script,style,button,svg',
    format: DictionaryResultFormat.auto,
    builtIn: true,
  ),
  DictionaryRule(
    id: 'builtin-zdic-trad',
    name: '漢典',
    note: '与汉典同源，默认停用避免重复',
    url: 'https://zdic.net/hans/{{word}}',
    extract: DictionaryExtractMode.css,
    selector: '#xxjs .dict-section__body',
    remove: 'script,style,button,svg',
    format: DictionaryResultFormat.auto,
    enabled: false,
    builtIn: true,
  ),
  DictionaryRule(
    id: 'builtin-bing',
    name: '必应中英',
    note: '内置规则；中英释义与例句',
    url: 'https://cn.bing.com/dict/search?q={{word}}&qs=ds&form=CM',
    extract: DictionaryExtractMode.css,
    selector:
        '.hd_area, .qdef, #crossid, #webtabid, .def_fl, #senDef, #sentenceSeg',
    remove: 'script,style',
    format: DictionaryResultFormat.auto,
    builtIn: true,
  ),
];

/// 解析导出的规则 JSON：支持单条对象、数组和 `{"rules":[...]}`。
List<DictionaryRule> decodeDictionaryRules(String text) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    throw const FormatException('规则内容不是有效 JSON');
  }
  final items = switch (decoded) {
    final List<Object?> list => list,
    final Map<String, Object?> map when map['rules'] is List =>
      map['rules'] as List,
    final Map<String, Object?> map => [map],
    _ => throw const FormatException('规则 JSON 应为对象或数组'),
  };
  final rules = <DictionaryRule>[];
  for (var index = 0; index < items.length; index++) {
    final item = items[index];
    if (item is! Map) throw const FormatException('规则条目格式无效');
    var rule = DictionaryRule.fromJson(Map<String, dynamic>.from(item));
    if (rule.id.isEmpty) {
      rule = rule.copyWith(
        id: 'rule-${DateTime.now().microsecondsSinceEpoch}-$index',
      );
    }
    rules.add(rule);
  }
  if (rules.isEmpty) throw const FormatException('没有可导入的规则');
  return rules;
}

void validateDictionaryRule(DictionaryRule rule) {
  if (rule.name.trim().isEmpty) throw const FormatException('请输入词典名称');
  final url = rule.buildUrl('test');
  final uri = Uri.tryParse(url);
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty) {
    throw const FormatException('请填写有效的 http/https 地址');
  }
  if (!['GET', 'POST'].contains(rule.method)) {
    throw const FormatException('请求方式只支持 GET 或 POST');
  }
  if (!rule.url.contains('{{word}}') &&
      !(rule.method == 'POST' && rule.body.contains('{{word}}'))) {
    throw const FormatException('地址或 POST 请求体中需要用 {{word}} 代入查询词');
  }
  try {
    rule.parseHeaders();
  } on FormatException catch (error) {
    throw FormatException(error.message);
  } on Object {
    throw const FormatException('请求头必须是 JSON 对象');
  }
  if (rule.extract != DictionaryExtractMode.auto &&
      rule.extract != DictionaryExtractMode.text &&
      rule.selector.trim().isEmpty) {
    throw const FormatException('请填写提取规则');
  }
  if (rule.extract == DictionaryExtractMode.regex) {
    try {
      RegExp(rule.selector, multiLine: true, dotAll: true);
    } on FormatException {
      throw const FormatException('正则表达式格式无效');
    }
  }
}
