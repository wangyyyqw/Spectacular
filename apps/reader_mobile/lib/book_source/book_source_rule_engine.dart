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
/// 支持 CSS、默认选择链、JSONPath、regex、`@text/@html/@href/@src/@属性`、
/// `##正则##替换` 以及 `||`、`&&`、`%%` 组合。`@js:`、`<js>` 与前导规则结果由 QuickJS 会话执行，
/// 脚本输出可继续接 JSONPath 或模板；XPath 和网页登录流程不在本实现范围。
class BookSourceRuleEngine {
  const BookSourceRuleEngine();

  /// 求值为节点列表。
  List<Object> evaluateList(
    Object? root,
    String rawRule,
    BookSourceRuleContext context, {
    BookSourceScriptSession? script,
  }) => _evaluateList(root, rawRule, context, script: script);

  List<Object> _evaluateList(
    Object? root,
    String rawRule,
    BookSourceRuleContext context, {
    BookSourceScriptSession? script,
    bool htmlContext = false,
  }) {
    final rule = rawRule.trim();
    if (rule.isEmpty) return const <Object>[];
    // 后置脚本处理整个前导规则的结果，不能被前导的 || 提前截断。
    if (_splitScriptRule(rule) != null) {
      return _evaluateSingle(
        root,
        rule,
        context,
        script,
        htmlContext: htmlContext,
      );
    }
    final alternatives = _splitTopLevel(rule, '||');
    if (alternatives.length > 1) {
      for (final alternative in alternatives) {
        final values = _evaluateList(
          root,
          alternative,
          context,
          script: script,
          htmlContext: htmlContext,
        );
        if (values.isNotEmpty) return values;
      }
      return const <Object>[];
    }
    final combined = _splitTopLevel(rule, '&&');
    if (combined.length > 1) {
      return <Object>[
        for (final part in combined)
          ..._evaluateList(
            root,
            part,
            context,
            script: script,
            htmlContext: htmlContext,
          ),
      ];
    }
    final interleaved = _splitTopLevel(rule, '%%');
    if (interleaved.length > 1) {
      final groups = <List<Object>>[
        for (final part in interleaved)
          _evaluateList(
            root,
            part,
            context,
            script: script,
            htmlContext: htmlContext,
          ),
      ].where((values) => values.isNotEmpty).toList();
      if (groups.isEmpty) return const <Object>[];
      return <Object>[
        for (var index = 0; index < groups.first.length; index++)
          for (final values in groups)
            if (index < values.length) values[index],
      ];
    }
    return _evaluateSingle(
      root,
      rule,
      context,
      script,
      htmlContext: htmlContext,
    );
  }

  /// 求值为首个字符串；列表结果用换行拼接。
  String evaluateString(
    Object? root,
    String rawRule,
    BookSourceRuleContext context, {
    BookSourceScriptSession? script,
    bool preserveNewlines = false,
  }) {
    final values = evaluateList(root, rawRule, context, script: script);
    if (values.isEmpty) return '';
    String asString(Object value) =>
        _valueAsString(value, normalize: !preserveNewlines);
    if (values.length == 1) return asString(values.single);
    return values.map(asString).where((value) => value.isNotEmpty).join('\n');
  }

  /// 求值为 HTML 片段或正文文本。
  String evaluateHtml(
    Object? root,
    String rawRule,
    BookSourceRuleContext context, {
    BookSourceScriptSession? script,
  }) {
    final values = _evaluateList(
      root,
      rawRule,
      context,
      script: script,
      htmlContext: true,
    );
    return values
        .map(_htmlValueAsString)
        .where((value) => value.isNotEmpty)
        .join();
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
    BookSourceScriptSession? script, {
    bool htmlContext = false,
  }) {
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
          : _evaluateList(
              root,
              leading,
              context,
              script: script,
              htmlContext: htmlContext,
            );
      final output = <Object>[];
      for (final input in inputs) {
        final evaluated = script
            .evaluate(
              parts.script,
              result: _scriptValueAsString(input),
              variables: {
                ...context.variables,
                'baseUrl': context.pageUrl.isEmpty
                    ? context.baseUrl
                    : context.pageUrl,
                if (input is Map || input is List)
                  '_resultJson': jsonEncode(input),
              },
              resolveString: (path) =>
                  _evaluatePlainString(root, path, context),
              resolveList: (path) => _evaluatePlainList(root, path, context),
            )
            .trim();
        if (evaluated.isEmpty) continue;
        if (parts.trailing.isNotEmpty) {
          output.addAll(
            _evaluateList(
              _parseScriptOutput(evaluated),
              parts.trailing,
              context,
              script: script,
              htmlContext: htmlContext,
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
    return _evaluatePlain(root, text, context, htmlContext: htmlContext);
  }

  List<Object> _evaluatePlain(
    Object? root,
    String rule,
    BookSourceRuleContext context, {
    bool htmlContext = false,
  }) {
    final text = rule.trim();
    if (text.startsWith('http://') ||
        text.startsWith('https://') ||
        text.startsWith('data:')) {
      return <Object>[text];
    }
    final parsed = _parseRule(rule);
    final mode =
        parsed.mode ??
        (_isJsonRoot(root) && _looksLikeJsonPath(parsed.rule)
            ? _RuleMode.json
            : _RuleMode.defaultHtml);
    var extractor = parsed.extractor;
    var selector = parsed.rule;
    if ((mode == _RuleMode.defaultHtml || mode == _RuleMode.css) &&
        extractor.isEmpty &&
        _isBareHtmlExtractor(root, selector)) {
      extractor = selector;
      selector = '';
    }
    if (parsed.rule.isEmpty) {
      if (root == null) return const <Object>[];
      if (extractor.isEmpty && parsed.replacements.isEmpty) {
        return const <Object>[];
      }
      final extracted = extractor.isEmpty
          ? _scriptValueAsString(root)
          : _extract(root, extractor);
      return extracted == null
          ? const <Object>[]
          : _applyReplacements(<Object>[extracted], parsed.replacements);
    }

    final List<Object> selected;
    if (selector.isEmpty) {
      selected = root == null ? const <Object>[] : <Object>[root];
    } else {
      switch (mode) {
        case _RuleMode.json:
          selected = _jsonValues(root, selector);
        case _RuleMode.defaultHtml:
          selected = _cssValues(root, selector, defaultSyntax: true);
        case _RuleMode.css:
          selected = _cssValues(root, selector);
        case _RuleMode.regex:
          selected = _regexValues(root, selector);
        case _RuleMode.xpath:
          throw const BookSourceException(
            '该书源使用 XPath 规则，当前版本暂不支持',
            code: 'ONLINE_RULE_XPATH',
          );
      }
    }

    final extracted = <Object>[];
    for (final value in selected) {
      final item = _extract(value, extractor);
      if (item == null) continue;
      final text = _valueAsString(item);
      if (text.isEmpty && item is! Element) continue;
      extracted.add(item);
    }
    return _applyReplacements(
      extracted,
      parsed.replacements,
      htmlContext: htmlContext && extractor.isEmpty,
    );
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
      variables: {
        ...context.variables,
        'baseUrl': context.pageUrl.isEmpty ? context.baseUrl : context.pageUrl,
      },
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
    final lower = text.toLowerCase();
    var mode = _RuleMode.css;
    var hasMode = false;
    if (lower.startsWith('@css:')) {
      mode = _RuleMode.css;
      hasMode = true;
      text = text.substring(5).trim();
    } else if (lower.startsWith('@@')) {
      mode = _RuleMode.defaultHtml;
      hasMode = true;
      text = text.substring(2).trim();
    } else if (lower.startsWith('@json:')) {
      mode = _RuleMode.json;
      hasMode = true;
      text = text.substring(6).trim();
    } else if (lower.startsWith('@xpath:')) {
      mode = _RuleMode.xpath;
      hasMode = true;
      text = text.substring(7).trim();
    } else if (lower.startsWith('@regex:')) {
      mode = _RuleMode.regex;
      hasMode = true;
      text = text.substring(7).trim();
    }

    final replacementParts = text.split('##');
    var selector = replacementParts.isEmpty
        ? ''
        : replacementParts.first.trim();
    final replacements = <_Replacement>[];
    if (replacementParts.length > 1 && replacementParts[1].isNotEmpty) {
      replacements.add(
        _Replacement(
          replacementParts[1],
          replacementParts.length > 2 ? replacementParts[2] : '',
          firstMatchOnly: replacementParts.length > 3,
        ),
      );
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
      if (_isDefaultSelectorStep(candidate)) continue;
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

  List<Object> _cssValues(
    Object? root,
    String selector, {
    bool defaultSyntax = false,
  }) {
    final nodes = _cssRootNodes(root);
    if (nodes.isEmpty || selector.trim().isEmpty) return const <Object>[];
    var text = selector.trim();
    final reverse = defaultSyntax && text.startsWith('-');
    if (reverse) text = text.substring(1).trim();
    final steps = defaultSyntax ? _splitTopLevel(text, '@') : <String>[text];
    var selected = nodes;
    for (final step in steps) {
      final indexed = defaultSyntax
          ? _parseDefaultIndex(step)
          : _DefaultIndex(step);
      final parsed = _parseJQuerySelector(indexed.base);
      final next = <Object>[];
      for (final node in selected) {
        final matches = _selectHtmlElements(
          node,
          parsed.base,
          defaultSyntax: defaultSyntax,
        );
        next.addAll(
          _applyDefaultIndex(_applyJQueryFilter(matches, parsed), indexed),
        );
      }
      selected = next;
      if (selected.isEmpty) break;
    }
    return reverse ? selected.reversed.toList() : selected;
  }

  bool _isDefaultSelectorStep(String rule) =>
      rule == 'children' ||
      rule.startsWith('children[') ||
      rule.startsWith('children.') ||
      rule.startsWith('children!') ||
      RegExp(r'^(class|tag|id|text)\.').hasMatch(rule);

  bool _isBareHtmlExtractor(Object? root, String rule) =>
      const <String>{
        'text',
        'textNodes',
        'ownText',
        'html',
        'innerHtml',
        'outerHtml',
        'all',
        'href',
        'src',
      }.contains(rule) ||
      (root is Element && root.attributes.containsKey(rule));

  List<Element> _selectHtmlElements(
    Object root,
    String selector, {
    required bool defaultSyntax,
  }) {
    if (root is! Document && root is! Element) return const <Element>[];
    final node = root as Node;
    if (defaultSyntax && (selector.isEmpty || selector == 'children')) {
      return node.children.toList();
    }
    if (selector.isEmpty) {
      return root is Element ? <Element>[root] : const <Element>[];
    }
    if (defaultSyntax && _isDefaultSelectorStep(selector)) {
      final separator = selector.indexOf('.');
      final kind = selector.substring(0, separator);
      final name = selector.substring(separator + 1);
      final elements = <Element>[
        if (root is Element) root,
        if (root is Document) ...root.querySelectorAll('*'),
        if (root is Element) ...root.querySelectorAll('*'),
      ];
      return elements.where((element) {
        return switch (kind) {
          'class' => element.classes.contains(name),
          'tag' => element.localName == name.toLowerCase(),
          'id' => element.id == name,
          'text' => _normalize(
            element.nodes.whereType<Text>().map((child) => child.text).join(),
          ).toLowerCase().contains(name.toLowerCase()),
          _ => false,
        };
      }).toList();
    }
    try {
      final selected = _queryHtmlElements(node, selector);
      if (root is Element) {
        final parent = root.parentNode;
        // JSOUP 的选择范围包含当前元素；Dart DOM 的查询只包含后代。
        if (parent != null &&
            _queryHtmlElements(parent, selector).contains(root)) {
          return <Element>[root, ...selected];
        }
      }
      return selected;
    } on Object {
      throw BookSourceException(
        '书源选择器无法解析：$selector',
        code: 'ONLINE_RULE_SELECTOR',
      );
    }
  }

  List<Element> _queryHtmlElements(Node root, String selector) =>
      switch (root) {
        Document() => root.querySelectorAll(selector),
        Element() => root.querySelectorAll(selector),
        DocumentFragment() => root.querySelectorAll(selector),
        _ => const <Element>[],
      };

  _DefaultIndex _parseDefaultIndex(String selector) {
    final bracket = RegExp(r'\[([^\[\]]+)\]\s*$').firstMatch(selector);
    if (bracket != null) {
      var inner = bracket.group(1)!.trim();
      final exclude = inner.startsWith('!');
      if (exclude) inner = inner.substring(1).trim();
      final indexes = inner
          .split(',')
          .map((part) => part.replaceAll(RegExp(r'\s+'), ''))
          .toList();
      if (indexes.every(
        (part) => RegExp(r'^(?:-?\d+|-?\d*:-?\d*(?::-?\d+)?)$').hasMatch(part),
      )) {
        return _DefaultIndex(
          selector.substring(0, bracket.start).trim(),
          indexes: indexes,
          exclude: exclude,
        );
      }
    }
    final legacy = RegExp(r'([.!])\s*(-?\d+(?:\s*:\s*-?\d+)*)$')
        .firstMatch(selector);
    if (legacy == null) return _DefaultIndex(selector);
    return _DefaultIndex(
      selector.substring(0, legacy.start).trim(),
      indexes: legacy.group(2)!.split(':').map((part) => part.trim()).toList(),
      exclude: legacy.group(1) == '!',
    );
  }

  List<Element> _applyDefaultIndex(List<Element> values, _DefaultIndex rule) {
    if (rule.indexes.isEmpty || values.isEmpty) return values;
    final length = values.length;
    final indexes = <int>{};
    int normalize(int index) => index < 0 ? index + length : index;
    for (final item in rule.indexes) {
      final parts = item.split(':');
      if (parts.length == 1) {
        final index = normalize(int.parse(parts.first));
        if (index >= 0 && index < length) indexes.add(index);
        continue;
      }
      var start = normalize(int.tryParse(parts[0]) ?? 0);
      var end = normalize(int.tryParse(parts[1]) ?? length - 1);
      if ((start < 0 && end < 0) || (start >= length && end >= length)) {
        continue;
      }
      start = start.clamp(0, length - 1);
      end = end.clamp(0, length - 1);
      final rawStep = parts.length > 2 ? int.parse(parts[2]) : 1;
      final step = rawStep > 0
          ? rawStep
          : -rawStep < length
          ? rawStep + length
          : 1;
      if (end >= start) {
        for (var index = start; index <= end; index += step) {
          indexes.add(index);
        }
      } else {
        for (var index = start; index >= end; index -= step) {
          indexes.add(index);
        }
      }
    }
    return rule.exclude
        ? <Element>[
            for (var index = 0; index < length; index++)
              if (!indexes.contains(index)) values[index],
          ]
        : <Element>[for (final index in indexes) values[index]];
  }

  String _scriptValueAsString(Object? value) {
    if (value is Element) return value.outerHtml;
    if (value is Document) return value.outerHtml;
    return _valueAsString(value, normalize: false);
  }

  RegExp _compileRegex(String pattern) {
    var text = pattern;
    var caseSensitive = true;
    var multiLine = true;
    var dotAll = false;
    while (true) {
      final flags = RegExp(r'^\(\?([ims]+)\)').firstMatch(text);
      if (flags == null) break;
      final value = flags.group(1)!;
      if (value.contains('i')) caseSensitive = false;
      if (value.contains('m')) multiLine = true;
      if (value.contains('s')) dotAll = true;
      text = text.substring(flags.end);
    }
    return RegExp(
      text,
      caseSensitive: caseSensitive,
      multiLine: multiLine,
      dotAll: dotAll,
    );
  }

  String _regexReplacement(Match match, String replacement) {
    final result = StringBuffer();
    for (var index = 0; index < replacement.length; index++) {
      final char = replacement[index];
      if (char == r'\') {
        if (++index >= replacement.length) {
          throw const FormatException('正则替换转义不完整');
        }
        result.write(replacement[index]);
      } else if (char == r'$') {
        if (++index >= replacement.length) {
          throw const FormatException('正则替换捕获组不完整');
        }
        final firstGroup = int.tryParse(replacement[index]);
        if (firstGroup == null || firstGroup > match.groupCount) {
          throw const FormatException('正则替换捕获组不存在');
        }
        var group = firstGroup;
        while (index + 1 < replacement.length) {
          final digit = int.tryParse(replacement[index + 1]);
          if (digit == null || group * 10 + digit > match.groupCount) break;
          group = group * 10 + digit;
          index++;
        }
        result.write(match.group(group) ?? '');
      } else {
        result.write(char);
      }
    }
    return result.toString();
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
      r':(eq|gt|lt|first|last)\(\s*(-?\d+)?\s*\)\s*$',
      caseSensitive: false,
    ).firstMatch(selector);
    if (filter != null) {
      return _JQuerySelector(
        selector.substring(0, filter.start).trim(),
        filter.group(1)!.toLowerCase(),
        int.tryParse(filter.group(2) ?? '') ?? 0,
      );
    }
    final simple = RegExp(
      r':(first|last)\s*$',
      caseSensitive: false,
    ).firstMatch(selector);
    if (simple != null) {
      return _JQuerySelector(
        selector.substring(0, simple.start).trim(),
        simple.group(1)!.toLowerCase(),
        0,
      );
    }
    return _JQuerySelector(selector, '', 0);
  }

  List<Element> _applyJQueryFilter(
    List<Element> values,
    _JQuerySelector selector,
  ) {
    final index = selector.index < 0
        ? selector.index + values.length
        : selector.index;
    return switch (selector.filter) {
      'eq' =>
        values
            .asMap()
            .entries
            .where((entry) => entry.key == index)
            .map((entry) => entry.value)
            .toList(),
      'gt' => values.skip((index + 1).clamp(0, values.length)).toList(),
      'lt' => values.take(index.clamp(0, values.length)).toList(),
      'first' => values.isEmpty ? const <Element>[] : <Element>[values.first],
      'last' => values.isEmpty ? const <Element>[] : <Element>[values.last],
      _ => values,
    };
  }

  List<Object> _regexValues(Object? root, String expression) {
    final source = _valueAsString(root);
    if (source.isEmpty) return const <Object>[];
    try {
      final match = _compileRegex(expression).firstMatch(source);
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
      if (value is Element || value is Document) return value;
      if (value is Map || value is List) return value;
      return '$value'.trim();
    }
    if (extractor == 'all') return _scriptValueAsString(value);
    if (extractor == 'text') {
      if (value is Element) return _normalize(value.text);
      if (value is Document) {
        return _normalize(value.documentElement?.text ?? '');
      }
      return _normalize(_valueAsString(value));
    }
    if (extractor == 'textNodes') {
      if (value is Element) {
        return value.nodes
            .whereType<Text>()
            .map((node) => node.text.trim())
            .where((text) => text.isNotEmpty)
            .join('\n');
      }
      return _valueAsString(value, normalize: false);
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
      if (value is Document) return value.body?.innerHtml.trim() ?? '';
      return _valueAsString(value);
    }
    if (extractor == 'outerHtml') {
      if (value is Element) return value.outerHtml.trim();
      if (value is Document) return value.outerHtml.trim();
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
    List<_Replacement> replacements, {
    bool htmlContext = false,
  }) {
    if (replacements.isEmpty) return values;
    final result = <Object>[];
    for (final value in values) {
      if (value is String || value is Element || value is Document) {
        final replaced = _replaceAll(
          // 正文省略提取器时先保留 HTML；文本求值与显式 @text 仍取文本。
          htmlContext
              ? _htmlValueAsString(value)
              : _valueAsString(value, normalize: false),
          replacements,
        );
        if (replaced.isNotEmpty) result.add(replaced);
      } else {
        result.add(value);
      }
    }
    return result;
  }

  String _htmlValueAsString(Object value) {
    if (value is Element) return value.innerHtml.trim();
    if (value is Document) return value.body?.innerHtml.trim() ?? '';
    return _valueAsString(value, normalize: false);
  }

  String _replaceAll(String value, List<_Replacement> replacements) {
    var text = value;
    for (final replacement in replacements) {
      try {
        final regex = _compileRegex(replacement.pattern);
        if (replacement.firstMatchOnly) {
          final match = regex.firstMatch(text);
          text = match == null
              ? ''
              : _regexReplacement(match, replacement.replacement);
        } else {
          text = text.replaceAllMapped(
            regex,
            (match) => _regexReplacement(match, replacement.replacement),
          );
        }
      } on FormatException {
        text = replacement.firstMatchOnly
            ? replacement.replacement
            : text.replaceAll(replacement.pattern, replacement.replacement);
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

enum _RuleMode { defaultHtml, css, json, regex, xpath }

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
  const _Replacement(
    this.pattern,
    this.replacement, {
    this.firstMatchOnly = false,
  });

  final String pattern;
  final String replacement;
  final bool firstMatchOnly;
}

class _DefaultIndex {
  const _DefaultIndex(
    this.base, {
    this.indexes = const [],
    this.exclude = false,
  });

  final String base;
  final List<String> indexes;
  final bool exclude;
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
