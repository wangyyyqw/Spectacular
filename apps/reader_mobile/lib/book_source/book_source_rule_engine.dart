import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import 'book_source_models.dart';
import 'book_source_script.dart';

/// 规则求值上下文。
class BookSourceRuleContext {
  const BookSourceRuleContext({
    required this.baseUrl,
    this.pageUrl = '',
    this.variables = const <String, String>{},
  });

  /// 站点根地址。
  final String baseUrl;

  /// 当前页面地址。
  final String pageUrl;

  /// URL 或 JS 规则可读取的变量。
  final Map<String, String> variables;

  BookSourceRuleContext child({String? pageUrl}) => BookSourceRuleContext(
    baseUrl: baseUrl,
    pageUrl: pageUrl ?? this.pageUrl,
    variables: variables,
  );
}

/// Legado/阅读书源规则的纯 Dart 子集。
///
/// 支持 CSS、JSONPath、regex、`@text/@html/@href/@src/@属性`、`##正则##替换`
/// 以及 `||`、`&&` 组合。`@js:`、`<js>` 与前导规则结果由 QuickJS 会话执行，
/// 脚本输出可继续接 JSONPath 或模板；XPath 和网页登录流程不在本实现范围。
class BookSourceRuleEngine {
  const BookSourceRuleEngine();

  /// 求值为节点列表。
  List<Object> evaluateList(
    Object? root,
    String rawRule,
    BookSourceRuleContext context, {
    BookSourceScriptSession? script,
  }) {
    final rule = rawRule.trim();
    if (rule.isEmpty) return const <Object>[];
    final alternatives = _splitTopLevel(rule, '||');
    if (alternatives.length > 1) {
      for (final alternative in alternatives) {
        final values = evaluateList(root, alternative, context, script: script);
        if (values.isNotEmpty) return values;
      }
      return const <Object>[];
    }
    final combined = _splitTopLevel(rule, '&&');
    if (combined.length > 1) {
      return <Object>[
        for (final part in combined)
          ...evaluateList(root, part, context, script: script),
      ];
    }
    return _evaluateSingle(root, rule, context, script);
  }

  /// 求值为首个字符串；列表结果用换行拼接。
  String evaluateString(
    Object? root,
    String rawRule,
    BookSourceRuleContext context, {
    BookSourceScriptSession? script,
  }) {
    final values = evaluateList(root, rawRule, context, script: script);
    if (values.isEmpty) return '';
    if (values.length == 1) return _valueAsString(values.single);
    return values
        .map(_valueAsString)
        .where((value) => value.isNotEmpty)
        .join('\n');
  }

  /// 求值为 HTML 片段或正文文本。
  String evaluateHtml(
    Object? root,
    String rawRule,
    BookSourceRuleContext context, {
    BookSourceScriptSession? script,
  }) {
    final parsed =
        _splitScriptRule(rawRule.trim()) == null && !_containsTemplate(rawRule)
        ? _parseRule(rawRule)
        : const _ParsedRule(
            rule: '',
            mode: null,
            extractor: '',
            replacements: <_Replacement>[],
          );
    final values = evaluateList(root, rawRule, context, script: script);
    if (values.isEmpty) return '';
    if (parsed.extractor == 'html' || parsed.extractor == 'outerHtml') {
      return values.map(_valueAsString).join();
    }
    final direct = values.whereType<Element>().map(
      (node) => node.innerHtml.trim(),
    );
    final html = direct.where((value) => value.isNotEmpty).join();
    if (html.isNotEmpty) return html;
    return values.map(_valueAsString).where((value) => value.isNotEmpty).join();
  }

  /// 解析相对链接。
  String resolveUrl(String baseUrl, String value) {
    final raw = value.trim();
    if (raw.isEmpty ||
        raw.startsWith('data:') ||
        raw.startsWith('javascript:')) {
      return raw;
    }
    if (raw.startsWith('//')) {
      final scheme = Uri.tryParse(baseUrl)?.scheme ?? 'https';
      return '$scheme:$raw';
    }
    final parsed = Uri.tryParse(raw);
    if (parsed != null && parsed.hasScheme) return parsed.toString();
    final base = Uri.tryParse(baseUrl);
    if (base == null) return raw;
    try {
      return base.resolveUri(Uri.parse(raw)).toString();
    } on FormatException {
      return raw;
    }
  }

  /// 解析 HTML 响应；编码已在网络层处理。
  Document parseHtml(String body) => html_parser.parse(body);

  /// 解析 JSON 响应。
  Object? parseJson(String body) {
    final text = body.trim();
    if (text.isEmpty) return null;
    return jsonDecode(text);
  }

  List<Object> _evaluateSingle(
    Object? root,
    String rule,
    BookSourceRuleContext context,
    BookSourceScriptSession? script,
  ) {
    final text = rule.trim();
    if (text.isEmpty) return const <Object>[];
    final parts = _splitScriptRule(text);
    if (parts != null) {
      if (script == null) {
        throw const BookSourceException(
          '该书源规则依赖 JavaScript，当前版本暂不支持',
          code: 'ONLINE_RULE_JS',
        );
      }
      final leading = parts.leading.trim();
      final inputs = leading.isEmpty
          ? <Object?>[root]
          : _evaluateSingle(root, leading, context, script);
      final output = <Object>[];
      for (final input in inputs) {
        final evaluated = script
            .evaluate(
              parts.script,
              result: _valueAsString(input, normalize: false),
              variables: context.variables,
              resolveString: (path) =>
                  _evaluatePlainString(root, path, context),
              resolveList: (path) => _evaluatePlainList(root, path, context),
            )
            .trim();
        if (evaluated.isEmpty) continue;
        if (parts.trailing.isNotEmpty) {
          output.addAll(
            _evaluatePlain(
              _parseScriptOutput(evaluated),
              parts.trailing,
              context,
            ),
          );
        } else {
          output.add(evaluated);
        }
      }
      return output;
    }
    if (_containsTemplate(text)) {
      final rendered = _renderTemplate(text, root, context, script);
      return rendered == null || rendered.isEmpty
          ? const <Object>[]
          : <Object>[rendered];
    }
    return _evaluatePlain(root, text, context);
  }

  List<Object> _evaluatePlain(
    Object? root,
    String rule,
    BookSourceRuleContext context,
  ) {
    final text = rule.trim();
    if (text.startsWith('http://') ||
        text.startsWith('https://') ||
        text.startsWith('data:')) {
      return <Object>[text];
    }
    final parsed = _parseRule(rule);
    if (parsed.rule.isEmpty) {
      if (parsed.extractor.isEmpty) return const <Object>[];
      final extracted = _extract(root, parsed.extractor);
      return extracted == null ? const <Object>[] : <Object>[extracted];
    }

    final mode =
        parsed.mode ??
        (_isJsonRoot(root) && _looksLikeJsonPath(parsed.rule)
            ? _RuleMode.json
            : _RuleMode.css);
    final List<Object> selected;
    switch (mode) {
      case _RuleMode.json:
        selected = _jsonValues(root, parsed.rule);
      case _RuleMode.css:
        selected = _cssValues(root, parsed.rule);
      case _RuleMode.regex:
        selected = _regexValues(root, parsed.rule);
      case _RuleMode.xpath:
        throw const BookSourceException(
          '该书源使用 XPath 规则，当前版本暂不支持',
          code: 'ONLINE_RULE_XPATH',
        );
    }

    final extracted = <Object>[];
    for (final value in selected) {
      final item = _extract(value, parsed.extractor);
      if (item == null) continue;
      final text = _valueAsString(item);
      if (text.isEmpty && item is! Element) continue;
      extracted.add(item);
    }
    return _applyReplacements(extracted, parsed.replacements);
  }

  String _evaluatePlainString(
    Object? root,
    String rule,
    BookSourceRuleContext context,
  ) {
    final values = _evaluatePlain(root, rule, context);
    if (values.isEmpty) return '';
    return values
        .map((value) => _valueAsString(value, normalize: false))
        .join('\n');
  }

  List<String> _evaluatePlainList(
    Object? root,
    String rule,
    BookSourceRuleContext context,
  ) {
    return <String>[
      for (final value in _evaluatePlain(root, rule, context))
        _valueAsString(value, normalize: false),
    ];
  }

  bool _containsTemplate(String rule) =>
      rule.contains('{{') && rule.contains('}}');

  String? _renderTemplate(
    String template,
    Object? root,
    BookSourceRuleContext context,
    BookSourceScriptSession? script,
  ) {
    final matches = RegExp(r'\{\{([\s\S]*?)\}\}').allMatches(template).toList();
    if (matches.isEmpty) return null;
    if (script == null) {
      return _renderTemplatePlain(template, root, context);
    }
    final pieces = <String>[];
    var cursor = 0;
    for (final match in matches) {
      if (match.start > cursor) {
        pieces.add(jsonEncode(template.substring(cursor, match.start)));
      }
      final expression = match.group(1)?.trim() ?? '';
      pieces.add('(${_compileTemplateExpression(expression)})');
      cursor = match.end;
    }
    if (cursor < template.length) {
      pieces.add(jsonEncode(template.substring(cursor)));
    }
    final code = "'' + ${pieces.join(' + ')}";
    return script.evaluate(
      code,
      result: '',
      variables: context.variables,
      resolveString: (path) => _evaluatePlainString(root, path, context),
      resolveList: (path) => _evaluatePlainList(root, path, context),
    );
  }

  String _compileTemplateExpression(String expression) {
    final text = expression.trim();
    if (text.isEmpty) return "''";
    if (text.startsWith(r'$') ||
        text.startsWith('data.') ||
        text.startsWith('data[') ||
        text.startsWith('result.') ||
        text.startsWith('result[')) {
      return 'java.getString(${jsonEncode(text)})';
    }
    if (RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$').hasMatch(text)) {
      if (const <String>{
        'key',
        'keyword',
        'searchKey',
        'page',
        'searchPage',
        'baseUrl',
        'bookUrl',
        'tocUrl',
        'chapterUrl',
        'title',
      }.contains(text)) {
        return text;
      }
      return 'java.getString(${jsonEncode(text)})';
    }
    return text;
  }

  String _renderTemplatePlain(
    String template,
    Object? root,
    BookSourceRuleContext context,
  ) {
    final buffer = StringBuffer();
    var cursor = 0;
    for (final match in RegExp(r'\{\{([\s\S]*?)\}\}').allMatches(template)) {
      buffer.write(template.substring(cursor, match.start));
      buffer.write(
        _evaluatePlainTemplateExpression(
          match.group(1)?.trim() ?? '',
          root,
          context,
        ),
      );
      cursor = match.end;
    }
    buffer.write(template.substring(cursor));
    return buffer.toString();
  }

  String _evaluatePlainTemplateExpression(
    String expression,
    Object? root,
    BookSourceRuleContext context,
  ) {
    if (expression.isEmpty) return '';
    final variable = context.variables[expression];
    if (variable != null) return variable;
    if (expression == 'baseUrl') return context.baseUrl;
    if (expression.startsWith(r'$') ||
        expression.startsWith('data.') ||
        expression.startsWith('data[') ||
        expression.startsWith('result.') ||
        expression.startsWith('result[')) {
      return _evaluatePlainString(root, expression, context);
    }
    final getString = RegExp(r'''^java\.getString\(\s*["']([^"']*)["']\s*\)$''')
        .firstMatch(expression);
    if (getString != null) {
      return _evaluatePlainString(root, getString.group(1)!, context);
    }
    if ((expression.startsWith("'") && expression.endsWith("'")) ||
        (expression.startsWith('"') && expression.endsWith('"'))) {
      return expression.substring(1, expression.length - 1);
    }
    final numeric = num.tryParse(expression);
    if (numeric != null) return '$numeric';
    throw const BookSourceException(
      '该书源模板依赖 JavaScript，当前版本暂不支持',
      code: 'ONLINE_RULE_JS',
    );
  }

  ({String leading, String script, String trailing})? _splitScriptRule(
    String rule,
  ) {
    final lower = rule.toLowerCase();
    final angleStart = lower.indexOf('<js>');
    if (angleStart >= 0) {
      final angleEnd = lower.indexOf('</js>', angleStart + 4);
      if (angleEnd < 0) {
        return (
          leading: rule.substring(0, angleStart),
          script: rule.substring(angleStart + 4),
          trailing: '',
        );
      }
      return (
        leading: rule.substring(0, angleStart),
        script: rule.substring(angleStart + 4, angleEnd),
        trailing: rule.substring(angleEnd + 5).trim(),
      );
    }
    final index = _topLevelJsIndex(rule);
    if (index < 0) return null;
    return (
      leading: rule.substring(0, index),
      script: rule.substring(index + 4),
      trailing: '',
    );
  }

  int _topLevelJsIndex(String rule) {
    final lower = rule.toLowerCase();
    var quote = '';
    for (var index = 0; index < rule.length - 3; index++) {
      final char = rule[index];
      if (quote.isNotEmpty) {
        if (char == quote && !_isEscaped(rule, index)) {
          quote = '';
        }
        continue;
      }
      if (char == '"' || char == "'") {
        if (_isEscaped(rule, index)) continue;
        quote = char;
        continue;
      }
      if (lower.startsWith('@js:', index)) return index;
    }
    return -1;
  }

  bool _isEscaped(String text, int index) {
    var backslashes = 0;
    for (
      var cursor = index - 1;
      cursor >= 0 && text[cursor] == r'\';
      cursor--
    ) {
      backslashes++;
    }
    return backslashes.isOdd;
  }

  Object? _parseScriptOutput(String value) {
    final text = value.trim();
    if (text.startsWith('{') || text.startsWith('[')) {
      try {
        return jsonDecode(text);
      } on FormatException {
        // 非 JSON 字符串继续按文本处理。
      }
    }
    if (text.startsWith('<')) return parseHtml(text);
    return text;
  }

  _ParsedRule _parseRule(String rawRule) {
    var text = rawRule.trim();
    var mode = _RuleMode.css;
    var hasMode = false;
    if (text.startsWith('@css:')) {
      mode = _RuleMode.css;
      hasMode = true;
      text = text.substring(5).trim();
    } else if (text.startsWith('@json:')) {
      mode = _RuleMode.json;
      hasMode = true;
      text = text.substring(6).trim();
    } else if (text.startsWith('@xpath:')) {
      mode = _RuleMode.xpath;
      hasMode = true;
      text = text.substring(7).trim();
    } else if (text.startsWith('@regex:')) {
      mode = _RuleMode.regex;
      hasMode = true;
      text = text.substring(7).trim();
    }

    final replacementParts = text.split('##');
    var selector = replacementParts.isEmpty
        ? ''
        : replacementParts.first.trim();
    final replacements = <_Replacement>[];
    for (var index = 1; index < replacementParts.length; index += 2) {
      final pattern = replacementParts[index];
      final replacement = index + 1 < replacementParts.length
          ? replacementParts[index + 1]
          : '';
      if (pattern.isEmpty) continue;
      replacements.add(_Replacement(pattern, replacement));
    }

    var extractor = '';
    final marker = _lastAttributeMarker(selector);
    if (marker != null) {
      extractor = marker.extractor;
      selector = selector.substring(0, marker.index).trim();
    }
    if (!hasMode && selector.startsWith(r'$')) mode = _RuleMode.json;
    return _ParsedRule(
      rule: selector,
      mode: hasMode ? mode : null,
      extractor: extractor,
      replacements: replacements,
    );
  }

  _AttributeMarker? _lastAttributeMarker(String selector) {
    var depth = 0;
    for (var index = selector.length - 1; index >= 0; index--) {
      final char = selector[index];
      if (char == ']') depth++;
      if (char == '[') depth--;
      if (char != '@' || depth != 0) continue;
      final candidate = selector.substring(index + 1).trim();
      if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_:.-]*$').hasMatch(candidate)) {
        continue;
      }
      if (RegExp(
        r'^(css|json|xpath|regex|js)$',
        caseSensitive: false,
      ).hasMatch(candidate)) {
        continue;
      }
      return _AttributeMarker(index, candidate);
    }
    return null;
  }

  List<Object> _jsonValues(Object? root, String path) {
    final normalized = path.trim();
    if (normalized == r'$') {
      return root == null ? const <Object>[] : <Object>[root];
    }
    if (normalized.startsWith(r'$..')) {
      return _recursiveJsonValues(root, normalized.substring(3));
    }
    var text = normalized;
    if (text.startsWith(r'$.')) text = text.substring(2);
    if (text.startsWith(r'$')) text = text.substring(1);
    if (text.startsWith('.')) text = text.substring(1);
    if (text.isEmpty) return root == null ? const <Object>[] : <Object>[root];

    var current = <Object?>[root];
    for (final token in _jsonTokens(text)) {
      final next = <Object?>[];
      for (final value in current) {
        if (token.property != null) {
          final property = token.property!;
          if (value is Map) {
            next.add(value[property]);
          } else if (value is List) {
            for (final child in value) {
              if (child is Map) next.add(child[property]);
            }
          }
        } else if (token.wildcard) {
          if (value is List) {
            next.addAll(value);
          } else if (value is Map) {
            next.addAll(value.values);
          }
        } else if (token.index != null) {
          if (value is List &&
              token.index! >= 0 &&
              token.index! < value.length) {
            next.add(value[token.index!]);
          }
        } else if (token.key != null) {
          if (value is Map) next.add(value[token.key!]);
        }
      }
      current = next;
      if (current.isEmpty) break;
    }
    return <Object>[for (final value in current) ?value];
  }

  List<Object> _recursiveJsonValues(Object? root, String descendantPath) {
    final property = descendantPath.split(RegExp(r'[.\[]')).first;
    if (property.isEmpty) return const <Object>[];
    final found = <Object?>[];

    void visit(Object? value) {
      if (value is Map) {
        if (value.containsKey(property)) found.add(value[property]);
        for (final child in value.values) {
          visit(child);
        }
      } else if (value is List) {
        for (final child in value) {
          visit(child);
        }
      }
    }

    visit(root);
    final remainder = descendantPath.substring(property.length).trim();
    final valid = <Object>[for (final value in found) ?value];
    if (remainder.isEmpty || valid.isEmpty) return valid;
    final nextPath = remainder.startsWith('.')
        ? remainder.substring(1)
        : remainder.startsWith('[')
        ? r'$' + remainder
        : remainder;
    return <Object>[for (final value in valid) ..._jsonValues(value, nextPath)];
  }

  List<_JsonToken> _jsonTokens(String path) {
    final tokens = <_JsonToken>[];
    var buffer = StringBuffer();

    void flush() {
      final property = buffer.toString().trim();
      buffer = StringBuffer();
      if (property.isEmpty) return;
      if (property == '*') {
        tokens.add(const _JsonToken.wildcard());
      } else {
        tokens.add(_JsonToken.property(property));
      }
    }

    for (var index = 0; index < path.length; index++) {
      final char = path[index];
      if (char == '.') {
        flush();
        continue;
      }
      if (char != '[') {
        buffer.write(char);
        continue;
      }
      flush();
      final end = path.indexOf(']', index + 1);
      if (end < 0) break;
      final inner = path.substring(index + 1, end).trim();
      if (inner == '*') {
        tokens.add(const _JsonToken.wildcard());
      } else if (inner.startsWith("'") || inner.startsWith('"')) {
        tokens.add(_JsonToken.key(inner.substring(1, inner.length - 1)));
      } else {
        final indexValue = int.tryParse(inner);
        if (indexValue != null) tokens.add(_JsonToken.index(indexValue));
      }
      index = end;
    }
    flush();
    return tokens;
  }

  List<Object> _cssValues(Object? root, String selector) {
    final nodes = _cssRootNodes(root);
    if (nodes.isEmpty || selector.trim().isEmpty) return const <Object>[];
    final parsed = _parseJQuerySelector(selector.trim());
    final selected = <Element>[];
    for (final node in nodes) {
      if (parsed.base.isEmpty) {
        if (node is Element) selected.add(node);
        continue;
      }
      final Iterable<Element> matches;
      try {
        if (node is Document) {
          matches = node.querySelectorAll(parsed.base);
        } else if (node is Element) {
          matches = node.querySelectorAll(parsed.base);
        } else {
          continue;
        }
      } on Object {
        throw BookSourceException(
          '书源选择器无法解析：${parsed.base}',
          code: 'ONLINE_RULE_SELECTOR',
        );
      }
      selected.addAll(matches);
    }
    return <Object>[
      for (final element in _applyJQueryFilter(selected, parsed)) element,
    ];
  }

  List<Object> _cssRootNodes(Object? root) {
    if (root is Document) return <Object>[root];
    if (root is Element) return <Object>[root];
    if (root is String) {
      final trimmed = root.trim();
      if (trimmed.startsWith('<')) return <Object>[parseHtml(trimmed)];
    }
    return const <Object>[];
  }

  _JQuerySelector _parseJQuerySelector(String selector) {
    final filter = RegExp(
      r':(eq|gt|lt|first|last)\(\s*(\d+)?\s*\)\s*$',
      caseSensitive: false,
    ).firstMatch(selector);
    if (filter != null) {
      return _JQuerySelector(
        selector.substring(0, filter.start).trim(),
        filter.group(1)!.toLowerCase(),
        int.tryParse(filter.group(2) ?? '') ?? 0,
      );
    }
    if (selector.endsWith(':first-child')) {
      return _JQuerySelector(selector, 'first', 0);
    }
    if (selector.endsWith(':last-child')) {
      return _JQuerySelector(selector, 'last', 0);
    }
    return _JQuerySelector(selector, '', 0);
  }

  List<Element> _applyJQueryFilter(
    List<Element> values,
    _JQuerySelector selector,
  ) {
    return switch (selector.filter) {
      'eq' =>
        values
            .asMap()
            .entries
            .where((entry) => entry.key == selector.index)
            .map((entry) => entry.value)
            .toList(),
      'gt' => values.skip(selector.index + 1).toList(),
      'lt' => values.take(selector.index).toList(),
      'first' => values.isEmpty ? const <Element>[] : <Element>[values.first],
      'last' => values.isEmpty ? const <Element>[] : <Element>[values.last],
      _ => values,
    };
  }

  List<Object> _regexValues(Object? root, String expression) {
    final source = _valueAsString(root);
    if (source.isEmpty) return const <Object>[];
    try {
      final match = RegExp(expression, multiLine: true).firstMatch(source);
      if (match == null) return const <Object>[];
      if (match.groupCount > 0 && match.group(1) != null) {
        return <Object>[match.group(1)!];
      }
      return <Object>[match.group(0)!];
    } on FormatException {
      throw BookSourceException(
        '书源正则无法解析：$expression',
        code: 'ONLINE_RULE_REGEX',
      );
    }
  }

  Object? _extract(Object? value, String extractor) {
    if (value == null) return null;
    if (extractor.isEmpty) {
      if (value is Element) return _normalize(value.text);
      if (value is Document) {
        return _normalize(value.documentElement?.text ?? '');
      }
      if (value is Map || value is List) return value;
      return '$value'.trim();
    }
    if (extractor == 'text' || extractor == 'all') {
      if (value is Element) return _normalize(value.text);
      if (value is Document) {
        return _normalize(value.documentElement?.text ?? '');
      }
      return _normalize(_valueAsString(value));
    }
    if (extractor == 'ownText') {
      if (value is Element) {
        return _normalize(
          value.nodes.whereType<Text>().map((node) => node.text).join(),
        );
      }
      return _normalize(_valueAsString(value));
    }
    if (extractor == 'html' || extractor == 'innerHtml') {
      if (value is Element) return value.innerHtml.trim();
      return _valueAsString(value);
    }
    if (extractor == 'outerHtml') {
      if (value is Element) return value.outerHtml.trim();
      return _valueAsString(value);
    }
    if (value is Element) {
      final attribute = value.attributes[extractor];
      if (attribute != null) {
        return extractor == 'href' || extractor == 'src'
            ? _normalize(attribute)
            : _normalize(attribute);
      }
    }
    if (value is Map) {
      final entry = value[extractor];
      if (entry != null) return _valueAsString(entry);
    }
    return null;
  }

  List<Object> _applyReplacements(
    List<Object> values,
    List<_Replacement> replacements,
  ) {
    if (replacements.isEmpty) return values;
    return <Object>[
      for (final value in values)
        if (value is String) _replaceAll(value, replacements) else value,
    ];
  }

  String _replaceAll(String value, List<_Replacement> replacements) {
    var text = value;
    for (final replacement in replacements) {
      try {
        text = text.replaceAll(
          RegExp(replacement.pattern, multiLine: true),
          replacement.replacement,
        );
      } on FormatException {
        continue;
      }
    }
    return text.trim();
  }

  String _valueAsString(Object? value, {bool normalize = true}) {
    if (value == null) return '';
    if (value is String) return normalize ? _normalize(value) : value.trim();
    if (value is Element) return _normalize(value.text);
    if (value is Document) return _normalize(value.documentElement?.text ?? '');
    if (value is num || value is bool) return '$value';
    if (value is Map || value is List) {
      final encoded = jsonEncode(value);
      return normalize ? _normalize(encoded) : encoded;
    }
    return _normalize('$value');
  }

  String _normalize(String value) {
    return value
        .replaceAll('\u00a0', ' ')
        .replaceAll(RegExp(r'[ \t\r\n]+'), ' ')
        .trim();
  }

  bool _looksLikeJsonPath(String rule) {
    final text = rule.trim();
    if (text.startsWith(r'$') ||
        text.startsWith('.') ||
        text.startsWith('[') ||
        text.startsWith('data.') ||
        text.startsWith('data[') ||
        text.startsWith('result.') ||
        text.startsWith('result[')) {
      return true;
    }
    return RegExp(
      r'^[A-Za-z_$][A-Za-z0-9_$]*(?:\.[A-Za-z_$][A-Za-z0-9_$]*|\[[^\]]*\])*$',
    ).hasMatch(text);
  }

  bool _isJsonRoot(Object? root) => root is Map || root is List;

  List<String> _splitTopLevel(String rule, String separator) {
    final values = <String>[];
    final lower = rule.toLowerCase();
    var depth = 0;
    var quote = '';
    var inScript = false;
    var start = 0;
    for (var index = 0; index < rule.length - separator.length + 1; index++) {
      if (lower.startsWith('<js>', index)) {
        inScript = true;
        index += 3;
        continue;
      }
      if (lower.startsWith('</js>', index)) {
        inScript = false;
        index += 4;
        continue;
      }
      final char = rule[index];
      if (quote.isNotEmpty) {
        if (char == quote && (index == 0 || rule[index - 1] != r'\')) {
          quote = '';
        }
        continue;
      }
      if (char == '"' || char == "'") {
        quote = char;
        continue;
      }
      if (inScript) continue;
      if (lower.startsWith('@js:', index)) break;
      if (char == '[' || char == '(' || char == '{') depth++;
      if (char == ']' || char == ')' || char == '}') depth--;
      if (depth != 0 || !rule.startsWith(separator, index)) continue;
      values.add(rule.substring(start, index).trim());
      start = index + separator.length;
      index = start - 1;
    }
    if (values.isEmpty) return <String>[rule];
    values.add(rule.substring(start).trim());
    return values.where((value) => value.isNotEmpty).toList();
  }
}

enum _RuleMode { css, json, regex, xpath }

class _ParsedRule {
  const _ParsedRule({
    required this.rule,
    required this.mode,
    required this.extractor,
    required this.replacements,
  });

  final String rule;
  final _RuleMode? mode;
  final String extractor;
  final List<_Replacement> replacements;
}

class _Replacement {
  const _Replacement(this.pattern, this.replacement);

  final String pattern;
  final String replacement;
}

class _AttributeMarker {
  const _AttributeMarker(this.index, this.extractor);

  final int index;
  final String extractor;
}

class _JQuerySelector {
  const _JQuerySelector(this.base, this.filter, this.index);

  final String base;
  final String filter;
  final int index;
}

class _JsonToken {
  const _JsonToken.property(this.property)
    : wildcard = false,
      index = null,
      key = null;

  const _JsonToken.wildcard()
    : property = null,
      wildcard = true,
      index = null,
      key = null;

  const _JsonToken.index(this.index)
    : property = null,
      wildcard = false,
      key = null;

  const _JsonToken.key(this.key)
    : property = null,
      wildcard = false,
      index = null;

  final String? property;
  final bool wildcard;
  final int? index;
  final String? key;
}
