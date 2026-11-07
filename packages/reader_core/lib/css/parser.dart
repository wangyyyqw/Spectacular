import 'property_aliases.dart';

import 'package:csslib/parser.dart' as csslib;
import 'package:csslib/visitor.dart';
import 'package:html/parser.dart' as html_parser;

import '../parser/html5_input.dart';
import 'font_face.dart';

/// 一条 CSS 声明。
class CssDeclaration {
  /// 创建声明。
  const CssDeclaration({
    required this.property,
    required this.value,
    this.important = false,
  });

  /// 属性名（小写）。
  final String property;

  /// 原始值（已 trim）。
  final String value;

  /// 是否 `!important`。
  final bool important;
}

/// 一条规则。
class CssRule {
  /// 创建规则。
  const CssRule({
    required this.selector,
    required this.declarations,
    this.media,
    this.mediaConditions = const <String>[],
  });

  /// 选择器文本。
  final String selector;

  /// 声明列表。
  final List<CssDeclaration> declarations;

  /// `@media` 条件；顶层规则为 null。
  final String? media;

  /// 从外到内的逐层 `@media` 条件。
  ///
  /// 每层保留自己的逗号/not 语义，求值时逐层合取；不能把嵌套列表直接
  /// 拼成字符串，否则 `screen, print` 会绕过内层条件。
  final List<String> mediaConditions;
}

/// `@import` 记录。
class CssImport {
  /// 创建导入。
  const CssImport({required this.url, this.media});

  /// 导入地址（原样，未解析相对路径）。
  final String url;

  /// 媒体条件。
  final String? media;
}

/// 解析结果。
class CssStylesheet {
  /// 创建结果。
  const CssStylesheet({
    required this.rules,
    required this.imports,
    required this.warnings,
    this.fontFaces = const <CssFontFace>[],
    this.mediaConditions = const <String>[],
  });

  /// 规则。
  final List<CssRule> rules;

  /// 导入。
  final List<CssImport> imports;

  /// 解析告警（含 csslib 错误与被跳过的声明）。
  final List<String> warnings;

  /// `@font-face` 声明（P3-01，声明顺序；去重由
  /// [CssFontFaceRegistry] 负责）。
  final List<CssFontFace> fontFaces;

  /// 来源元素及逐层 `@import` 的媒体条件，全部命中时才启用本表。
  ///
  /// 与规则自身的 `@media` 分开保存，避免把带逗号或 not 的条件错误拼接。
  final List<String> mediaConditions;
}

/// 按文档顺序出现的一张内嵌或外链样式表。
class CssStyleSource {
  /// 内嵌 `<style>`。
  const CssStyleSource.embedded(this.css, {this.media}) : href = null;

  /// 外链 `<link rel="stylesheet">`。
  const CssStyleSource.linked(this.href, {this.media}) : css = null;

  /// CSS 文本；外链为 null。
  final String? css;

  /// 原始地址；内嵌为 null。
  final String? href;

  /// 元素上的媒体条件。
  final String? media;
}

/// XHTML 中提取出的样式来源。
class InlineStyles {
  /// 创建结果。
  const InlineStyles({
    required this.css,
    required this.links,
    this.sources = const <CssStyleSource>[],
  });

  /// 所有 `<style>` 的 CSS 文本（按文档顺序拼接）。
  final String css;

  /// `<link rel="stylesheet">` 的 href。
  final List<String> links;

  /// 内嵌与外链交错的文档顺序，含各自媒体条件。
  final List<CssStyleSource> sources;
}

/// CSS 基础解析器。
abstract final class CssParser {
  /// 属性名：标准属性、厂商前缀属性与自定义属性（`--token`，P9-14）。
  static final RegExp _propertyPattern = RegExp(
    r'^(?:--[a-zA-Z0-9-]+|-?[a-zA-Z][a-zA-Z0-9-]*)$',
  );

  static final RegExp _syntaxErrorPattern = RegExp(r'^\d+:\d+:');

  /// 解析元素 `style` 属性中的声明。
  ///
  /// 与样式表共用同一套声明解析和属性别名，自定义属性保留大小写；
  /// 版权/私有命名空间过滤由调用方按来源语义完成。
  static List<CssDeclaration> parseInlineDeclarations(String raw) {
    if (raw.trim().isEmpty) return const <CssDeclaration>[];
    final parsed = _parseSingle('*{$raw}');
    final rule = parsed.rules.firstOrNull;
    if (rule != null) return rule.declarations;
    // 极端语法错误时退回逐段解析，至少保留可识别的声明。
    final declarations = <CssDeclaration>[];
    for (final part in raw.split(';')) {
      final colon = part.indexOf(':');
      if (colon <= 0) continue;
      var value = part.substring(colon + 1).trim();
      var important = false;
      if (value.toLowerCase().endsWith('!important')) {
        important = true;
        value = value.substring(0, value.length - '!important'.length).trim();
      }
      final property = part.substring(0, colon).trim();
      if (property.isNotEmpty && value.isNotEmpty) {
        declarations.add(
          CssDeclaration(
            property: property,
            value: value,
            important: important,
          ),
        );
      }
    }
    return List<CssDeclaration>.unmodifiable(declarations);
  }

  /// 解析一段 CSS。
  ///
  /// 伪元素近似诊断（P7-28）：`::first-letter`（首字下沉的最常见载体）
  /// 不在支持集内——规则不生效并记 `E_FIRST_LETTER_APPROXIMATED`，
  /// 提示上层以内置近似（段首大字 run）渲染。
  static CssStylesheet parse(String css) {
    final base = _parseSingle(css);
    final hasSyntaxErrors = base.warnings.any(_syntaxErrorPattern.hasMatch);
    final firstLetterRules = base.rules
        .where((rule) => rule.selector.contains('::first-letter'))
        .map((rule) => rule.selector)
        .toList(growable: false);
    final diagnostics = <String>[
      for (final selector in firstLetterRules)
        'E_FIRST_LETTER_APPROXIMATED: 伪元素 $selector 不支持，'
            '首字下沉以内置近似（段首大字）渲染',
    ];
    if (!hasSyntaxErrors) {
      return diagnostics.isEmpty && base.fontFaces.isEmpty
          ? base
          : CssStylesheet(
              rules: base.rules,
              imports: base.imports,
              warnings: List<String>.unmodifiable(<String>[
                ...base.warnings,
                ...diagnostics,
              ]),
              fontFaces: base.fontFaces,
            );
    }
    final recovered = _parseRecovered(css);
    if (recovered.rules.length <= base.rules.length &&
        recovered.imports.length <= base.imports.length) {
      return CssStylesheet(
        rules: base.rules,
        imports: base.imports,
        warnings: List<String>.unmodifiable(<String>[
          ...base.warnings,
          ...diagnostics,
        ]),
        fontFaces: base.fontFaces,
      );
    }
    return CssStylesheet(
      rules: recovered.rules,
      imports: recovered.imports,
      warnings: List<String>.unmodifiable(<String>[
        ...base.warnings,
        ...recovered.warnings,
        ...diagnostics,
        '检测到语法错误，已分块恢复：${base.rules.length} 条 → ${recovered.rules.length} 条规则',
      ]),
      // @font-face 提取与规则语法无关（独立扫描器），base 全文已提取完整；
      // 分块恢复会重扫到相同块，不重复并入。
      fontFaces: base.fontFaces,
    );
  }

  static CssStylesheet _parseSingle(String css) {
    final errors = <csslib.Message>[];
    final preprocessed = _preprocessSelectors(css);
    final StyleSheet sheet;
    try {
      sheet = csslib.parse(preprocessed.text, errors: errors);
    } catch (error) {
      return CssStylesheet(
        rules: const <CssRule>[],
        imports: const <CssImport>[],
        warnings: <String>['CSS 解析异常：$error'],
      );
    }

    final rules = <CssRule>[];
    final imports = <CssImport>[];
    final warnings = <String>[for (final message in errors) message.describe];
    // @font-face 不走 csslib（其 FontFaceDirective 不公开声明组），
    // 由提取器自行扫描；collect 里对 FontFaceDirective 静默跳过。
    final fontFaces = CssFontFaceExtractor.extract(css, warnings);

    void collect(
      List<TreeNode> nodes, {
      List<String> media = const <String>[],
    }) {
      for (final node in nodes) {
        if (node is RuleSet) {
          final rawSelector = node.selectorGroup?.span?.text.trim() ?? '';
          final selector = preprocessed.selectors[rawSelector] ?? rawSelector;
          if (selector.isEmpty) {
            warnings.add('跳过无选择器的规则');
            continue;
          }
          final declarations = _declarations(node.declarationGroup, warnings);
          if (declarations.isEmpty) {
            continue;
          }
          rules.add(
            CssRule(
              selector: selector,
              declarations: declarations,
              media: media.isEmpty ? null : media.join(' and '),
              mediaConditions: List<String>.unmodifiable(media),
            ),
          );
        } else if (node is MediaDirective) {
          final query = node.mediaQueries
              .map((item) => item.span.text.trim())
              .where((item) => item.isNotEmpty)
              .join(', ');
          collect(
            node.rules,
            media: <String>[...media, if (query.isNotEmpty) query],
          );
        } else if (node is ImportDirective) {
          final mediaText = node.mediaQueries
              .map((item) => item.span.text.trim())
              .where((item) => item.isNotEmpty)
              .join(', ');
          imports.add(
            CssImport(
              url: _unquote(node.import),
              media: mediaText.isEmpty ? null : mediaText,
            ),
          );
        } else if (node is CssComment || node is CommentDefinition) {
          continue;
        } else if (node is FontFaceDirective) {
          // 已由 CssFontFaceExtractor 处理，静默跳过。
          continue;
        } else if (node is Directive) {
          warnings.add('跳过暂不支持的指令：${node.runtimeType}');
        }
      }
    }

    collect(sheet.topLevels);
    return CssStylesheet(
      rules: List<CssRule>.unmodifiable(rules),
      imports: List<CssImport>.unmodifiable(imports),
      warnings: List<String>.unmodifiable(warnings),
      fontFaces: List<CssFontFace>.unmodifiable(fontFaces),
    );
  }

  /// csslib 不认识 `:is()`/`:where()`/`:has()`、列表 `:not()` 与
  /// `nth-child(... of S)`。先把整条选择器换成合法占位类，解析完成后按
  /// 原文还原；否则一条现代选择器会截断同一张表里的后续规则。
  static _CssPreprocessResult _preprocessSelectors(String css) {
    final selectors = <String, String>{};
    final replacements = <(int, int, String)>[];
    var start = 0;
    var depth = 0;
    var parens = 0;
    var brackets = 0;
    var inComment = false;
    String? quote;

    for (var i = 0; i < css.length; i++) {
      final char = css[i];
      if (inComment) {
        if (char == '*' && i + 1 < css.length && css[i + 1] == '/') {
          inComment = false;
          i += 1;
        }
        continue;
      }
      if (quote != null) {
        if (char == r'\' && i + 1 < css.length) {
          i += 1;
        } else if (char == quote) {
          quote = null;
        }
        continue;
      }
      if (char == '/' && i + 1 < css.length && css[i + 1] == '*') {
        inComment = true;
        i += 1;
        continue;
      }
      if (char == '"' || char == "'") {
        quote = char;
        continue;
      }
      if (char == '(') {
        parens += 1;
        continue;
      }
      if (char == ')') {
        if (parens > 0) parens -= 1;
        continue;
      }
      if (char == '[') {
        brackets += 1;
        continue;
      }
      if (char == ']') {
        if (brackets > 0) brackets -= 1;
        continue;
      }
      if (parens > 0 || brackets > 0) continue;
      if (char == ';') {
        start = i + 1;
        continue;
      }
      if (char == '{') {
        final prelude = css.substring(start, i);
        final trimmed = prelude.trimLeft();
        if (!trimmed.startsWith('@') && _containsModernPseudo(prelude)) {
          final placeholder = '.__reader_rp${selectors.length}';
          selectors[placeholder] = prelude.trim();
          replacements.add((start, i, placeholder));
        }
        depth += 1;
        start = i + 1;
        continue;
      }
      if (char == '}') {
        if (depth > 0) depth -= 1;
        start = i + 1;
      }
    }
    if (replacements.isEmpty) {
      return _CssPreprocessResult(
        text: css,
        selectors: const <String, String>{},
      );
    }
    final buffer = StringBuffer();
    var cursor = 0;
    for (final (from, to, placeholder) in replacements) {
      buffer
        ..write(css.substring(cursor, from))
        ..write(placeholder);
      cursor = to;
    }
    buffer.write(css.substring(cursor));
    return _CssPreprocessResult(text: buffer.toString(), selectors: selectors);
  }

  static bool _containsModernPseudo(String prelude) {
    const names = {'is', 'where', 'not', 'has', 'nth-child', 'nth-last-child'};
    var brackets = 0;
    String? quote;
    for (var i = 0; i < prelude.length; i++) {
      final char = prelude[i];
      if (quote != null) {
        if (char == r'\' && i + 1 < prelude.length) {
          i += 1;
        } else if (char == quote) {
          quote = null;
        }
        continue;
      }
      if (char == '"' || char == "'") {
        quote = char;
        continue;
      }
      if (char == '[') {
        brackets += 1;
        continue;
      }
      if (char == ']') {
        if (brackets > 0) brackets -= 1;
        continue;
      }
      if (brackets > 0 || char != ':') continue;
      if (i > 0 && prelude[i - 1] == ':') continue;
      var end = i + 1;
      while (end < prelude.length && _isNameChar(prelude[end])) {
        end += 1;
      }
      if (end == i + 1 || end >= prelude.length || prelude[end] != '(') {
        continue;
      }
      if (names.contains(prelude.substring(i + 1, end).toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  static bool _isNameChar(String char) {
    final unit = char.codeUnitAt(0);
    return (unit >= 0x30 && unit <= 0x39) ||
        (unit >= 0x41 && unit <= 0x5A) ||
        (unit >= 0x61 && unit <= 0x7A) ||
        char == '-' ||
        char == '_';
  }

  /// 按顶层花括号分块，尽量保住语法错误之后的规则。
  static CssStylesheet _parseRecovered(String css) {
    final rules = <CssRule>[];
    final imports = <CssImport>[];
    final warnings = <String>[];
    final chunks = _topLevelChunks(css);
    for (var i = 0; i < chunks.length; i++) {
      final chunk = chunks[i];
      final result = _parseSingle(chunk);
      rules.addAll(result.rules);
      imports.addAll(result.imports);
      for (final warning in result.warnings) {
        warnings.add('分块 ${i + 1}: $warning');
      }
    }
    return CssStylesheet(
      rules: List<CssRule>.unmodifiable(rules),
      imports: List<CssImport>.unmodifiable(imports),
      warnings: List<String>.unmodifiable(warnings),
    );
  }

  static List<String> _topLevelChunks(String css) {
    final chunks = <String>[];
    var start = 0;
    var depth = 0;
    var inString = false;
    var quote = '';
    var inComment = false;
    for (var i = 0; i < css.length; i++) {
      final char = css[i];
      if (inComment) {
        if (char == '*' && i + 1 < css.length && css[i + 1] == '/') {
          inComment = false;
          i += 1;
        }
        continue;
      }
      if (inString) {
        if (char == '\\') {
          i += 1;
        } else if (char == quote) {
          inString = false;
        }
        continue;
      }
      if (char == '/' && i + 1 < css.length && css[i + 1] == '*') {
        inComment = true;
        i += 1;
        continue;
      }
      if (char == '"' || char == "'") {
        inString = true;
        quote = char;
        continue;
      }
      if (char == '{') {
        depth += 1;
      } else if (char == '}') {
        if (depth == 0) {
          final chunk = css.substring(start, i).trim();
          if (chunk.isNotEmpty) {
            chunks.add(chunk);
          }
          start = i + 1;
        } else {
          depth -= 1;
          if (depth == 0) {
            chunks.add(css.substring(start, i + 1).trim());
            start = i + 1;
          }
        }
      } else if (char == ';' && depth == 0) {
        final chunk = css.substring(start, i + 1).trim();
        if (chunk.isNotEmpty) {
          chunks.add(chunk);
        }
        start = i + 1;
      }
    }
    final tail = css.substring(start).trim();
    if (tail.isNotEmpty) {
      chunks.add(tail);
    }
    return chunks;
  }

  /// 解析 style 属性。
  static List<CssDeclaration> parseStyleAttribute(String style) {
    final sheet = parse('x{$style}');
    if (sheet.rules.isEmpty) {
      return const <CssDeclaration>[];
    }
    return sheet.rules.first.declarations;
  }

  /// 从 XHTML 中提取 `<style>` 与 `<link rel=stylesheet>`。
  static InlineStyles extractFromXhtml(String xhtml) {
    final document = html_parser.parse(prepareHtml5Input(xhtml));
    final css = StringBuffer();
    final links = <String>[];
    final sources = <CssStyleSource>[];
    for (final element in document.querySelectorAll('style, link')) {
      final media = element.attributes['media']?.trim();
      if (element.localName == 'style') {
        css.writeln(element.text);
        sources.add(CssStyleSource.embedded(element.text, media: media));
        continue;
      }
      final rel = element.attributes['rel']?.toLowerCase().trim() ?? '';
      if (!rel.split(RegExp(r'\s+')).contains('stylesheet')) {
        continue;
      }
      final href = element.attributes['href']?.trim() ?? '';
      if (href.isNotEmpty) {
        links.add(href);
        sources.add(CssStyleSource.linked(href, media: media));
      }
    }
    return InlineStyles(
      css: css.toString(),
      links: List.unmodifiable(links),
      sources: List.unmodifiable(sources),
    );
  }

  static List<CssDeclaration> _declarations(
    DeclarationGroup group,
    List<String> warnings,
  ) {
    final result = <CssDeclaration>[];
    for (final node in group.declarations) {
      if (node is! Declaration) {
        warnings.add('跳过嵌套规则：${node.runtimeType}');
        continue;
      }
      final property = node.property.trim();
      if (!_propertyPattern.hasMatch(property)) {
        warnings.add('跳过非法属性名：$property');
        continue;
      }
      final spanText = node.span.text.trim();
      final colon = spanText.indexOf(':');
      var value = colon >= 0
          ? spanText.substring(colon + 1).trim()
          : node.expression?.span?.text.trim() ?? '';
      while (value.endsWith(';')) {
        value = value.substring(0, value.length - 1).trim();
      }
      if (node.important) {
        value = value
            .replaceFirst(
              RegExp(r'\s*!\s*important\s*$', caseSensitive: false),
              '',
            )
            .trim();
      }
      if (value.isEmpty) {
        warnings.add('跳过空值声明：$property');
        continue;
      }
      // 厂商私有属性在解析入口统一改名（P9-13）：多看/掌阅的
      // `-duokan-text-indent` 等与标准属性语义一致，改名后各层无需兼容。
      final (aliasProperty, aliasValue) = CssPropertyAliases.resolve(
        property,
        value,
      );
      result.add(
        CssDeclaration(
          property: aliasProperty,
          value: aliasValue,
          important: node.important,
        ),
      );
    }
    return result;
  }

  static String _unquote(String value) {
    var result = value.trim();
    if (result.length >= 2 &&
        ((result.startsWith('"') && result.endsWith('"')) ||
            (result.startsWith("'") && result.endsWith("'")))) {
      result = result.substring(1, result.length - 1);
    }
    return result;
  }
}

class _CssPreprocessResult {
  const _CssPreprocessResult({required this.text, required this.selectors});

  final String text;
  final Map<String, String> selectors;
}
