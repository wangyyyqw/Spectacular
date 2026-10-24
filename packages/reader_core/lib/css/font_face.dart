import 'parser.dart';

/// `@font-face` 的一个字体来源：`local(名字)` 或 `url(地址)`。
///
/// `src` 里的多个来源按声明顺序构成回退链，消费方（P3-02 注册器）
/// 依次尝试，第一个可用者生效。
class CssFontSource {
  /// `local(...)`：本机已安装字体名。
  const CssFontSource.local(String name, {this.format})
      : isLocal = true,
        ref = name;

  /// `url(...)`：字体文件地址（未解析相对路径）。
  const CssFontSource.url(String href, {this.format})
      : isLocal = false,
        ref = href;

  /// true 为 `local()`，false 为 `url()`。
  final bool isLocal;

  /// local 的字体名或 url 的原始地址。
  final String ref;

  /// `format(...)` 提示（truetype / opentype / woff …），无则为 null。
  final String? format;

  /// woff/woff2/ttc 不支持（技术方案 §15 风险 4），格式明确不支持时为 true。
  bool get isUnsupportedFormat {
    final f = format?.toLowerCase();
    return f == 'woff' || f == 'woff2' || f == 'ttc' || f == 'collection';
  }

  @override
  String toString() =>
      '${isLocal ? 'local' : 'url'}(${format == null ? ref : '$ref format:$format'})';
}

/// 一条解析完成的 `@font-face` 声明。
class CssFontFace {
  const CssFontFace({
    required this.family,
    required this.sources,
    this.weight,
    this.style,
    this.display,
    this.unicodeRange,
  });

  /// `font-family` 描述符（去引号、trim；保留原始大小写）。
  final String family;

  /// `src` 来源，声明顺序即回退顺序。
  final List<CssFontSource> sources;

  /// `font-weight` 原始值（400 / bold / normal …），未声明为 null。
  final String? weight;

  /// `font-style` 原始值（normal / italic / oblique），未声明为 null。
  final String? style;

  /// `font-display` 原始值，未声明为 null。
  final String? display;

  /// `unicode-range` 原始值。记录但不生效（技术方案 §68.1）。
  final String? unicodeRange;

  /// 字重归一化：normal→400、bold→700、数字原样；无法解析为 null。
  int? get normalizedWeight {
    final w = weight?.trim().toLowerCase();
    if (w == null || w.isEmpty) {
      return null;
    }
    if (w == 'normal') {
      return 400;
    }
    if (w == 'bold') {
      return 700;
    }
    return int.tryParse(w);
  }

  /// 斜体归一化：italic/oblique→italic，其余→normal。
  String get normalizedStyle {
    final s = style?.trim().toLowerCase();
    return (s == 'italic' || s == 'oblique') ? 'italic' : 'normal';
  }

  /// 去重键：族名小写 + 字重 + 斜体。同键的后声明覆盖先声明；
  /// 不同字重/斜体是不同 face，可共存（P3-02 多字重注册依赖此语义）。
  String get dedupKey => '${family.toLowerCase()}|'
      '${normalizedWeight ?? weight?.trim().toLowerCase() ?? '400'}|'
      '$normalizedStyle';
}

/// 生成给字体注册器（P3-02）的任务。
class FontRegistrationTask {
  const FontRegistrationTask({
    required this.family,
    required this.sources,
  });

  /// CSS 里的 family 名（原样，别名映射在 P3-03 做）。
  final String family;

  /// 已按顺序解析完的来源；url 项 [CssFontSource.ref] 已是解析后的地址。
  final List<CssFontSource> sources;
}

/// `@font-face` 注册表：收集声明、按序去重、生成注册任务。
class CssFontFaceRegistry {
  final List<CssFontFace> _faces = <CssFontFace>[];

  /// 当前 face（去重后，声明顺序）。
  List<CssFontFace> get faces => List.unmodifiable(_faces);

  final List<String> warnings = <String>[];

  /// 登记一条声明。同一 [CssFontFace.dedupKey] 的后声明覆盖先声明。
  void register(CssFontFace face) {
    if (face.sources.isEmpty) {
      warnings.add('@font-face ${face.family} 无可用 src，跳过');
      return;
    }
    final index =
        _faces.indexWhere((item) => item.dedupKey == face.dedupKey);
    if (index >= 0) {
      _faces[index] = face;
      return;
    }
    _faces.add(face);
  }

  /// 批量登记（保持声明顺序）。
  void registerAll(Iterable<CssFontFace> faces) {
    for (final face in faces) {
      register(face);
    }
  }

  /// 生成注册任务。
  ///
  /// [resolveUrl] 把 `url()` 的相对地址解析为最终地址（EPUB 内按 CSS
  /// 所在目录归一）；传 null 时保持原样。带 local 兜底的 face 即便
  /// 全部 url 解析失败也保留 local 项，由消费方决定是否可回退。
  List<FontRegistrationTask> registrationTasks({
    String Function(String url)? resolveUrl,
  }) {
    return <FontRegistrationTask>[
      for (final face in _faces)
        FontRegistrationTask(
          family: face.family,
          sources: <CssFontSource>[
            for (final source in face.sources)
              source.isLocal || resolveUrl == null
                  ? source
                  : CssFontSource.url(resolveUrl(source.ref),
                      format: source.format),
          ],
        ),
    ];
  }
}

/// 中文/通用字体族别名映射（P3-03，技术方案 §68.3）。
///
/// 两级模型中的**内置别名级**（Reeden 150 号 §0-#9）：全局生效；
/// 按书覆盖级留给后续版本。映射目标是内置字族的规范名
/// （`builtin_song/kai/hei`），内置字族未注册时由引擎回退系统字体。
abstract final class FontFamilyAliases {
  /// 内置字族规范名（P4 内置字体资产接入后生效；未注册时引擎走
  /// 系统默认字体，不会豆腐块）。
  static const song = 'builtin_song';
  static const kai = 'builtin_kai';
  static const hei = 'builtin_hei';

  static const Map<String, String> _table = <String, String>{
    // 宋体系（含 CSS 泛型 serif）
    '宋体': song, 'simsun': song, 'songti': song, 'st': song,
    'song': song, 'serif': song,
    '思源宋体': song, 'sourcehanserif': song, 'sourcehanserifsc': song,
    'sourcehanserifcn': song, 'sourcehanseriftc': song,
    'notoserifcjksc': song, 'notoserifcjk': song,
    // 楷体系
    '楷体': kai, 'kaiti': kai, 'kt': kai, 'stkaiti': kai, 'kai': kai,
    // 黑体系（含 CSS 泛型 sans-serif）
    '黑体': hei, 'simhei': hei, 'heiti': hei, 'sans-serif': hei,
    '微软雅黑': hei, 'microsoftyahei': hei, 'yahei': hei,
    '苹方': hei, 'pingfang': hei, 'pingfangsc': hei,
    '思源黑体': hei, 'sourcehansans': hei, 'sourcehansanssc': hei,
    'sourcehansanscn': hei, 'sourcehansanstc': hei,
    'notosanscjksc': hei, 'notosanscjk': hei,
  };

  /// 解析单个族名：命中返回内置规范名，未命中返回 null（显式回退，
  /// 保留原名交引擎处理）。
  ///
  /// 匹配规则：先全等、再小写全等、最后去空格小写比较；**不做包含
  /// 匹配**——「宋体黑」这类名字不会被错误命中（技术方案 §68.3）。
  static String? resolve(String family) {
    final raw = family.trim();
    if (_table.containsKey(raw)) {
      return _table[raw];
    }
    final lower = raw.toLowerCase();
    if (_table.containsKey(lower)) {
      return _table[lower];
    }
    final squeezed = lower.replaceAll(RegExp(r'\s+'), '');
    return _table[squeezed];
  }

  /// 映射族列表：命中别名替换，未命中原样保留（显式回退）。
  static List<String> mapFamilies(List<String> families) => <String>[
        for (final family in families) resolve(family) ?? family,
      ];

  /// 默认 CJK 回退链（技术方案 §68.4；userFont 级随用户导入字体
  /// 任务插入头部）。追加在声明族之后，缺字时引擎按序兜底。
  static const List<String> defaultChain = <String>[
    song,
    hei,
    'Noto Sans CJK SC',
  ];
}

/// 从 CSS 文本提取 `@font-face` 块并解析成 [CssFontFace]。
///
/// csslib 的 `FontFaceDirective` 不公开声明组，这里自带一层
/// 注释/字符串感知的扫描：找到 `@font-face {…}` 后把块体交给
/// [CssParser.parseStyleAttribute] 复用现有声明解析。
abstract final class CssFontFaceExtractor {
  static final RegExp _directivePattern =
      RegExp(r'@font-face', caseSensitive: false);

  /// 返回声明列表（含来源顺序）；解析告警追加进 [warnings]。
  static List<CssFontFace> extract(String css, List<String> warnings) {
    final faces = <CssFontFace>[];
    final bodies = _blockBodies(css, warnings);
    for (final body in bodies) {
      final declarations = CssParser.parseStyleAttribute(body);
      final face = fromDeclarations(declarations);
      if (face == null) {
        warnings.add('@font-face 缺少 font-family 描述符，跳过');
        continue;
      }
      faces.add(face);
    }
    return faces;
  }

  /// 从声明列表组装 face；缺 font-family 返回 null。
  static CssFontFace? fromDeclarations(List<CssDeclaration> declarations) {
    String? family;
    final sources = <CssFontSource>[];
    String? weight;
    String? style;
    String? display;
    String? unicodeRange;
    for (final declaration in declarations) {
      switch (declaration.property) {
        case 'font-family':
          family = _unquote(declaration.value);
        case 'src':
          sources.addAll(_parseSources(declaration.value));
        case 'font-weight':
          weight = declaration.value;
        case 'font-style':
          style = declaration.value;
        case 'font-display':
          display = declaration.value;
        case 'unicode-range':
          unicodeRange = declaration.value;
      }
    }
    if (family == null || family.isEmpty) {
      return null;
    }
    return CssFontFace(
      family: family,
      sources: List.unmodifiable(sources),
      weight: weight,
      style: style,
      display: display,
      unicodeRange: unicodeRange,
    );
  }

  /// 扫描顶层 `@font-face {…}` 块体。跳过注释与字符串；
  /// 忽略嵌套花括号内的内容（@font-face 不允许嵌套，防御性处理）。
  static List<String> _blockBodies(String css, List<String> warnings) {
    final bodies = <String>[];
    var depth = 0;
    var inString = false;
    var quote = '';
    var inComment = false;
    var bodyStart = -1;
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
        if (char == r'\') {
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
      if (depth == 0 && bodyStart < 0 && char == '@') {
        final rest = css.substring(i);
        final match = _directivePattern.matchAsPrefix(rest, 0);
        if (match != null &&
            !_isWordChar(_peek(css, i + match.end)) &&
            _nextSignificant(css, i + match.end) == '{') {
          bodyStart = 0; // 占位：下一个顶层 '{' 才是真正的块体起点。
        }
        continue;
      }
      if (bodyStart >= 0) {
        if (char == '{') {
          depth += 1;
          if (depth == 1) {
            bodyStart = i + 1;
          }
        } else if (char == '}') {
          depth -= 1;
          if (depth == 0) {
            bodies.add(css.substring(bodyStart, i));
            bodyStart = -1;
          }
        }
      }
    }
    if (bodyStart >= 0) {
      warnings.add('@font-face 块未闭合，已丢弃');
    }
    return bodies;
  }

  static bool _isWordChar(String char) =>
      char.isNotEmpty && RegExp(r'[a-zA-Z0-9_-]').hasMatch(char);

  static String _peek(String css, int index) =>
      index < css.length ? css[index] : '';

  /// 跳过空白与注释后的第一个字符；字符串感知不做（@font-face 后
  /// 紧跟引号不是合法 CSS）。
  static String _nextSignificant(String css, int start) {
    var i = start;
    while (i < css.length) {
      final char = css[i];
      if (char == '/' && i + 1 < css.length && css[i + 1] == '*') {
        final end = css.indexOf('*/', i + 2);
        i = end < 0 ? css.length : end + 2;
        continue;
      }
      if (char.trim().isEmpty) {
        i += 1;
        continue;
      }
      return char;
    }
    return '';
  }

  /// 拆 `src` 值：按顶层逗号分项，每项认 `url(...)`/`local(...)` 与
  /// 可选 `format(...)`。
  static List<CssFontSource> _parseSources(String value) {
    final sources = <CssFontSource>[];
    for (final item in _splitTopLevel(value, ',')) {
      final parts = _splitTopLevel(item, ' ');
      String? url;
      String? local;
      String? format;
      for (final part in parts) {
        final trimmed = part.trim();
        if (trimmed.isEmpty) {
          continue;
        }
        if (trimmed.toLowerCase().startsWith('url(') && trimmed.endsWith(')')) {
          url = _unquote(trimmed.substring(4, trimmed.length - 1).trim());
        } else if (trimmed.toLowerCase().startsWith('local(') &&
            trimmed.endsWith(')')) {
          local = _unquote(trimmed.substring(6, trimmed.length - 1).trim());
        } else if (trimmed.toLowerCase().startsWith('format(') &&
            trimmed.endsWith(')')) {
          format = _unquote(trimmed.substring(7, trimmed.length - 1).trim());
        }
      }
      if (url != null && url.isNotEmpty) {
        sources.add(CssFontSource.url(url, format: format));
      } else if (local != null && local.isNotEmpty) {
        sources.add(CssFontSource.local(local, format: format));
      }
    }
    return sources;
  }

  /// 按 [separator] 拆分，字符串与括号内不拆。separator 只支持单字符。
  static List<String> _splitTopLevel(String value, String separator) {
    final parts = <String>[];
    final buffer = StringBuffer();
    var depth = 0;
    var inString = false;
    var quote = '';
    for (var i = 0; i < value.length; i++) {
      final char = value[i];
      if (inString) {
        buffer.write(char);
        if (char == r'\') {
          if (i + 1 < value.length) {
            buffer.write(value[i + 1]);
            i += 1;
          }
        } else if (char == quote) {
          inString = false;
        }
        continue;
      }
      if (char == '"' || char == "'") {
        inString = true;
        quote = char;
        buffer.write(char);
        continue;
      }
      if (char == '(') {
        depth += 1;
      } else if (char == ')') {
        depth -= 1;
      }
      if (char == separator && depth == 0) {
        parts.add(buffer.toString());
        buffer.clear();
        continue;
      }
      buffer.write(char);
    }
    parts.add(buffer.toString());
    return parts;
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
