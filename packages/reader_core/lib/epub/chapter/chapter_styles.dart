import 'package:path/path.dart' as p;
import 'package:reader_core/css/cascade.dart';
import 'package:reader_core/css/font_face.dart';
import 'package:reader_core/css/parser.dart';
import 'package:reader_core/css/reader_contract.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/css/selector.dart';
import 'package:reader_core/css/stylesheet_loader.dart';
import 'package:reader_core/css/ua_stylesheet.dart';
import 'package:reader_core/epub/archive_reader.dart';
import 'package:reader_core/epub/xml_encoding.dart';
import 'package:reader_core/source/chapter_source.dart'
    show ChapterLayoutPriority, ChapterLoadCancelled;

import '../../util/bounded_cache.dart';
import 'book_fonts.dart';
import 'book_resources.dart';
import 'chapter_preparation_job.dart';
import 'chapter_selectors.dart';
import 'css_preparation.dart';

/// 章节作者样式与派生级联缓存；原文读取和归档生命周期由资源服务持有。
class ChapterStyles {
  ChapterStyles(this._resources, this._fonts);

  final BookResources _resources;
  final BookFonts _fonts;
  static const int sheetCacheLimit = 32;
  static const int preparationCacheLimit = 3;
  final BoundedCache<String, CssStylesheet> _sheetCache = BoundedCache(
    sheetCacheLimit,
  );
  final BoundedCache<int, List<CssStylesheet>> _chapterSheets = BoundedCache(
    preparationCacheLimit,
  );
  final BoundedCache<_CssSheetSetKey, ChapterCascadePreparation> _baseCache =
      BoundedCache(preparationCacheLimit);
  final BoundedCache<_CssSheetSetKey, ChapterCascadePreparation> _fontCache =
      BoundedCache(preparationCacheLimit);
  final _preparing = ChapterPreparationScheduler();
  bool _closed = false;

  Future<void> get preparationsStopped => _preparing.idle;

  String get cacheReport =>
      '样式章索引 ${_chapterSheets.length}/$preparationCacheLimit 章；'
      '级联准备 ${_fontCache.length}/$preparationCacheLimit 组；'
      '基础级联 ${_baseCache.length}/$preparationCacheLimit 组';

  /// 完整来源只解析一次；每次按作业快照宽度判断 link/@import 的媒体条件。
  List<CssStylesheet> stylesheets(int spineIndex, {required double width}) {
    if (_closed || _resources.isClosed) return const [];
    final sheets = _chapterSheets.putIfAbsent(
      spineIndex,
      () => _loadChapterSheets(spineIndex),
    );
    return _activeSheets(sheets, width);
  }

  /// 每个等待者独立取消；解析与导入等待向共享 worker 传递优先级。
  ChapterPreparationHandle<List<CssStylesheet>> scheduleStylesheets(
    int spineIndex, {
    required double width,
    ChapterLayoutPriority priority = ChapterLayoutPriority.reading,
  }) {
    if (_closed || _resources.isClosed) return cancelledPreparation();
    final cached = _chapterSheets[spineIndex];
    if (cached != null) {
      return completedPreparation(_activeSheets(cached, width));
    }
    return mapPreparation(
      _preparing.schedule(
        'chapter-styles:$spineIndex',
        (task) => _prepareChapterSheets(spineIndex, task),
        priority: priority,
      ),
      (sheets) => _activeSheets(sheets, width),
    );
  }

  /// 生产路径等待目标章与 CSS 的纯数据解析，不退回同步 HTML 扫描。
  Future<List<CssStylesheet>> prepareStylesheets(
    int spineIndex, {
    required double width,
    ChapterLayoutPriority priority = ChapterLayoutPriority.reading,
    Future<void>? cancelSignal,
  }) => awaitPreparation(
    scheduleStylesheets(spineIndex, width: width, priority: priority),
    cancelSignal: cancelSignal,
  );

  Future<List<CssStylesheet>> _prepareChapterSheets(
    int spineIndex,
    PreparationTask task,
  ) async {
    final sources = await task.wait(
      _resources.scheduleStyleSources(spineIndex, priority: task.priority),
    );
    _checkPreparation(task);
    var inlineIndex = 0;
    final sheets = await _loader().loadAsync(
      sources,
      _chapterBase(spineIndex),
      readSheetAsync: (url) => _prepareSheet(url, task),
      prepareInlineAsync: (css, baseDir) async {
        final sheet = await task.wait(
          _resources.preparationWorker.schedule(
            'css-inline:$spineIndex:${inlineIndex++}',
            () {
              _checkPreparation(task);
              return css;
            },
            parseCssText,
            priority: task.priority,
          ),
        );
        _checkPreparation(task);
        return _absolutizeSheet(sheet, baseDir);
      },
    );
    _checkPreparation(task);
    return _chapterSheets.putIfAbsent(spineIndex, () => sheets);
  }

  Future<CssStylesheet> _prepareSheet(String url, PreparationTask task) async {
    final cached = _sheetCache[url];
    if (cached != null) return cached;
    EpubEntryRead? read;
    final prepared = await task.wait(
      _resources.preparationWorker.schedule(
        'css-parse:$url',
        () {
          _checkPreparation(task);
          read = _resources.document.archive.prepareEntry(url);
          return read?.payload;
        },
        parseCssEntry,
        priority: task.priority,
      ),
    );
    _checkPreparation(task);
    if (read != null &&
        !_resources.document.archive.commitEntry(read!, prepared.error)) {
      throw const ChapterLoadCancelled();
    }
    return _sheetCache.putIfAbsent(
      url,
      () => _absolutizeSheet(prepared.sheet, p.posix.dirname(url)),
    );
  }

  void _checkPreparation(PreparationTask task) {
    task.check();
    if (_closed || _resources.isClosed) throw const ChapterLoadCancelled();
  }

  static List<CssStylesheet> _activeSheets(
    List<CssStylesheet> sheets,
    double width,
  ) => [
    for (final sheet in sheets)
      if (sheet.mediaConditions.every(
        (media) => Cascade.mediaMatches(media, width),
      ))
        sheet,
  ];

  List<CssStylesheet> _loadChapterSheets(int spineIndex) => _loader().load(
    _resources.chapterStyleSources(spineIndex),
    _chapterBase(spineIndex),
  );

  String _chapterBase(int spineIndex) {
    final document = _resources.document;
    final item = document.spine[spineIndex];
    final path =
        document.resources.resolve(
          item.href,
          baseDir: p.posix.dirname(document.opfPath),
        ) ??
        item.href;
    return p.posix.dirname(path);
  }

  CssStylesheetLoader _loader() => CssStylesheetLoader(
    resolveUrl: (url, baseDir) =>
        _resources.document.resources.resolve(url, baseDir: baseDir) ?? url,
    prepareInline: (css, baseDir) =>
        _absolutizeSheet(CssParser.parse(css), baseDir),
    readSheet: (url) => _sheetCache.putIfAbsent(url, () => _readSheet(url)),
  );

  CssStylesheet _readSheet(String url) {
    final bytes = _resources.document.archive.readBytes(url);
    if (bytes == null) {
      return const CssStylesheet(rules: [], imports: [], warnings: []);
    }
    return _absolutizeSheet(
      CssParser.parse(decodeTextBytes(bytes)),
      p.posix.dirname(url),
    );
  }

  /// 字体映射变化只改写声明，作者选择器与声明顺序继续复用。
  ChapterCascadePreparation prepare(List<CssStylesheet> sheets) {
    final base = prepareBase(sheets);
    if (_fonts.engineFamilies.isEmpty) return base;
    final key = _CssSheetSetKey(sheets, _fonts.revision);
    return _fontCache.putIfAbsent(
      key,
      () => _rewriteFonts(base, _fonts.freeze()),
    );
  }

  /// 无字体注册依赖的作者级联；可供原文核验和字体使用分析直接复用。
  ChapterCascadePreparation prepareBase(List<CssStylesheet> sheets) {
    return _baseCache.putIfAbsent(_CssSheetSetKey(sheets, 0), () {
      final pseudoRules = Map<String, List<AuxiliaryCssRule>>.unmodifiable({
        for (final pseudo in ['::before', '::after'])
          pseudo: List<AuxiliaryCssRule>.unmodifiable(
            _prepareAuxiliaryRules(sheets, pseudo: pseudo),
          ),
      });
      return ChapterCascadePreparation(
        auxiliaryRules: List.unmodifiable(_prepareAuxiliaryRules(sheets)),
        firstLetterRules: List.unmodifiable(_prepareFirstLetterRules(sheets)),
        pseudoRules: pseudoRules,
        cascadeRules: CascadeRuleSet([
          // 列表容器负责真实缩进，UA 的近似 li 缩进会重复叠加。
          for (final rule in uaRules())
            if (!_isUaListIndentRule(rule.rule)) rule,
          for (var i = 0; i < sheets.length; i++)
            ...CascadeRule.fromStylesheet(
              sheets[i],
              origin: CascadeOrigin.author,
              startOrder: 1000 + i * 10000,
            ),
        ]),
      );
    });
  }

  ChapterCascadePreparation _rewriteFonts(
    ChapterCascadePreparation base,
    BookFontView fonts,
  ) {
    AuxiliaryCssRule rewrite(AuxiliaryCssRule rule) => (
      selectors: rule.selectors,
      declarations: fonts.rewriteDeclarations(rule.declarations),
      selectorText: rule.selectorText,
      media: rule.media,
      mediaConditions: rule.mediaConditions,
    );
    return ChapterCascadePreparation(
      auxiliaryRules: List.unmodifiable(base.auxiliaryRules.map(rewrite)),
      firstLetterRules: List.unmodifiable(base.firstLetterRules.map(rewrite)),
      pseudoRules: Map.unmodifiable({
        for (final entry in base.pseudoRules.entries)
          entry.key: List<AuxiliaryCssRule>.unmodifiable(
            entry.value.map(rewrite),
          ),
      }),
      cascadeRules: CascadeRuleSet([
        for (final rule in base.cascadeRules)
          rule.origin == CascadeOrigin.author
              ? rule.withDeclarations(
                  fonts.rewriteDeclarations(rule.rule.declarations),
                )
              : rule,
      ]),
    );
  }

  /// 只注册当前真实元素及伪元素命中的字族，避免全局字体清单阻塞首屏。
  List<CssFontFace> usedBookFonts(
    List<CssStylesheet> sheets,
    ChapterSelectors selectors,
    ReaderOverrides overrides,
    double width,
  ) {
    final faces = <CssFontFace>[for (final sheet in sheets) ...sheet.fontFaces];
    if (faces.isEmpty ||
        (overrides.isCustomFont && overrides.overrideEmbeddedFonts)) {
      return const [];
    }
    final families = {for (final face in faces) face.family.toLowerCase()};
    final wanted = <String>{};
    final prepared = prepareBase(sheets);
    for (final chain in selectors.chains) {
      for (final declarations in _fontDeclarationsFor(chain, prepared, width)) {
        _inspectFonts(declarations, families, wanted);
      }
    }
    return [
      for (final face in faces)
        if (wanted.contains(face.family.toLowerCase())) face,
    ];
  }

  static Iterable<List<CssDeclaration>> _fontDeclarationsFor(
    List<SelectorElement> chain,
    ChapterCascadePreparation prepared,
    double width,
  ) sync* {
    yield inlineDeclarationsOf(chain.last.attributes['style']);
    for (final rule in prepared.cascadeRules.candidatesFor(chain.last)) {
      if (ruleMediaMatches(rule.rule.media, rule.rule.mediaConditions, width) &&
          _matches(chain, rule.selectors.selectors)) {
        yield rule.rule.declarations;
      }
    }
    for (final rule in prepared.firstLetterRules) {
      if (_matches(chain, rule.selectors.selectors)) yield rule.declarations;
    }
    for (final rules in prepared.pseudoRules.values) {
      for (final rule in rules) {
        if (_matches(chain, rule.selectors.selectors)) yield rule.declarations;
      }
    }
  }

  static bool _matches(
    List<SelectorElement> chain,
    Iterable<ComplexSelector> selectors,
  ) => selectors.any(
    (selector) =>
        selector.matches(chain.last, chain.sublist(0, chain.length - 1)),
  );

  static void _inspectFonts(
    List<CssDeclaration> declarations,
    Set<String> families,
    Set<String> wanted,
  ) {
    for (final declaration in declarations) {
      if (declaration.property != 'font' &&
          declaration.property != 'font-family' &&
          !declaration.property.startsWith('--')) {
        continue;
      }
      final value = declaration.value.toLowerCase();
      wanted.addAll(families.where(value.contains));
    }
  }

  static List<AuxiliaryCssRule> _prepareFirstLetterRules(
    List<CssStylesheet> sheets,
  ) {
    const pseudo = '::first-letter';
    return [
      for (final sheet in sheets)
        for (final rule in sheet.rules)
          for (final raw in rule.selector.split(','))
            if (raw.trim().endsWith(pseudo))
              ..._parseAuxiliary(rule, raw.trim(), pseudo),
    ];
  }

  static List<AuxiliaryCssRule> _prepareAuxiliaryRules(
    List<CssStylesheet> sheets, {
    String? pseudo,
  }) {
    const properties = {
      'counter-reset',
      'counter-increment',
      'object-fit',
      'object-position',
    };
    final result = <AuxiliaryCssRule>[];
    for (final sheet in sheets) {
      for (final rule in sheet.rules) {
        if (!rule.declarations.any(
          (declaration) => pseudo == null
              ? properties.contains(declaration.property)
              : declaration.property == 'content',
        )) {
          continue;
        }
        if (pseudo == null && rule.selector.contains('::')) continue;
        for (final raw in rule.selector.split(',')) {
          final selector = raw.trim();
          if (pseudo != null && !selector.endsWith(pseudo)) continue;
          result.addAll(_parseAuxiliary(rule, selector, pseudo));
        }
      }
    }
    return result;
  }

  static List<AuxiliaryCssRule> _parseAuxiliary(
    CssRule rule,
    String selector,
    String? pseudo,
  ) {
    final main = pseudo == null
        ? selector
        : selector.substring(0, selector.length - pseudo.length);
    if (main.isEmpty) return const [];
    final parsed = SelectorParser.parse(main);
    if (parsed.selectors.isEmpty) return const [];
    return [
      (
        selectors: parsed,
        declarations: rule.declarations,
        selectorText: main,
        media: rule.media,
        mediaConditions: rule.mediaConditions,
      ),
    ];
  }

  static bool _isUaListIndentRule(CssRule rule) =>
      rule.selector.trim() == 'li' &&
      rule.declarations.any(
        (declaration) => declaration.property == 'margin-left',
      );

  static const _urlProperties = {
    'background-image',
    'background',
    'border-image',
    'border-image-source',
    'content',
    'list-style-image',
    'list-style',
  };
  static final _cssUrlPattern = RegExp(r'url\(\s*([^)]*?)\s*\)');

  CssStylesheet _absolutizeSheet(CssStylesheet sheet, String baseDir) {
    if (sheet.rules.isEmpty && sheet.fontFaces.isEmpty) return sheet;
    final rules = [
      for (final rule in sheet.rules) _absolutizeRule(rule, baseDir),
    ];
    final faces = [
      for (final face in sheet.fontFaces) _absolutizeFace(face, baseDir),
    ];
    final changed =
        rules.indexed.any(
          (entry) => !identical(entry.$2, sheet.rules[entry.$1]),
        ) ||
        faces.indexed.any(
          (entry) => !identical(entry.$2, sheet.fontFaces[entry.$1]),
        );
    if (!changed) return sheet;
    return CssStylesheet(
      rules: List.unmodifiable(rules),
      imports: sheet.imports,
      warnings: sheet.warnings,
      fontFaces: List.unmodifiable(faces),
      mediaConditions: sheet.mediaConditions,
    );
  }

  CssRule _absolutizeRule(CssRule rule, String baseDir) {
    var changed = false;
    final declarations = <CssDeclaration>[];
    for (final declaration in rule.declarations) {
      final value =
          _urlProperties.contains(declaration.property) &&
              declaration.value.contains('url(')
          ? _resolveUrls(declaration.value, baseDir)
          : declaration.value;
      if (value == declaration.value) {
        declarations.add(declaration);
      } else {
        changed = true;
        declarations.add(
          CssDeclaration(
            property: declaration.property,
            value: value,
            important: declaration.important,
          ),
        );
      }
    }
    return changed
        ? CssRule(
            selector: rule.selector,
            declarations: List.unmodifiable(declarations),
            media: rule.media,
            mediaConditions: rule.mediaConditions,
          )
        : rule;
  }

  CssFontFace _absolutizeFace(CssFontFace face, String baseDir) {
    var changed = false;
    final sources = <CssFontSource>[];
    for (final source in face.sources) {
      final resolved = source.isLocal || _externalUrl(source.ref)
          ? null
          : _resources.document.resources.resolve(source.ref, baseDir: baseDir);
      if (resolved == null || resolved == source.ref) {
        sources.add(source);
      } else {
        changed = true;
        sources.add(CssFontSource.url(resolved, format: source.format));
      }
    }
    return changed
        ? CssFontFace(
            family: face.family,
            sources: List.unmodifiable(sources),
            weight: face.weight,
            style: face.style,
            display: face.display,
            unicodeRange: face.unicodeRange,
          )
        : face;
  }

  static bool _externalUrl(String raw) =>
      raw.startsWith('data:') ||
      raw.startsWith('http://') ||
      raw.startsWith('https://');

  String _resolveUrls(String value, String baseDir) {
    return value.replaceAllMapped(_cssUrlPattern, (match) {
      var raw = (match.group(1) ?? '').trim();
      if (raw.length >= 2 &&
          ((raw.startsWith('"') && raw.endsWith('"')) ||
              (raw.startsWith("'") && raw.endsWith("'")))) {
        raw = raw.substring(1, raw.length - 1).trim();
      }
      if (raw.isEmpty || _externalUrl(raw)) return match.group(0) ?? '';
      final resolved = _resources.document.resources.resolve(
        raw,
        baseDir: baseDir,
      );
      return resolved == null ? (match.group(0) ?? '') : 'url("$resolved")';
    });
  }

  /// 宿主关闭书籍时释放本服务缓存，不关闭共享资源或字体服务。
  void close() {
    if (_closed) return;
    _closed = true;
    _preparing.close();
    _sheetCache.clear();
    _chapterSheets.clear();
    _baseCache.clear();
    _fontCache.clear();
  }
}

/// 一组作者样式表的只读派生级联结果，供排版作业直接使用。
class ChapterCascadePreparation {
  const ChapterCascadePreparation({
    required this.auxiliaryRules,
    required this.firstLetterRules,
    required this.pseudoRules,
    required this.cascadeRules,
  });

  final List<AuxiliaryCssRule> auxiliaryRules;
  final List<AuxiliaryCssRule> firstLetterRules;
  final Map<String, List<AuxiliaryCssRule>> pseudoRules;
  final CascadeRuleSet cascadeRules;
}

typedef AuxiliaryCssRule = ({
  SelectorList selectors,
  List<CssDeclaration> declarations,
  String selectorText,
  String? media,
  List<String> mediaConditions,
});

/// 以规则和字体列表的身份跨章节共享准备结果，字体修订只影响声明改写层。
class _CssSheetSetKey {
  _CssSheetSetKey(List<CssStylesheet> sheets, this.fontRevision)
    : rules = List.unmodifiable(sheets.map((sheet) => sheet.rules)),
      fontFaces = List.unmodifiable(sheets.map((sheet) => sheet.fontFaces));

  final List<List<CssRule>> rules;
  final List<List<CssFontFace>> fontFaces;
  final int fontRevision;

  @override
  int get hashCode => Object.hash(
    fontRevision,
    Object.hashAll(rules.map(identityHashCode)),
    Object.hashAll(fontFaces.map(identityHashCode)),
  );

  @override
  bool operator ==(Object other) {
    if (other is! _CssSheetSetKey ||
        fontRevision != other.fontRevision ||
        rules.length != other.rules.length ||
        fontFaces.length != other.fontFaces.length) {
      return false;
    }
    for (var i = 0; i < rules.length; i++) {
      if (!identical(rules[i], other.rules[i]) ||
          !identical(fontFaces[i], other.fontFaces[i])) {
        return false;
      }
    }
    return true;
  }
}

/// 每层媒体条件按作业宽度独立合取，保留每层的逗号与 not 语义。
bool ruleMediaMatches(String? media, List<String> conditions, double width) {
  if (conditions.isNotEmpty) {
    return conditions.every(
      (condition) => Cascade.mediaMatches(condition, width),
    );
  }
  return media == null || Cascade.mediaMatches(media, width);
}

/// 内联声明沿用作者来源过滤，不允许读取器私有属性进入级联。
List<CssDeclaration> inlineDeclarationsOf(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  return List.unmodifiable(
    CssParser.parseInlineDeclarations(raw).where(
      (declaration) => !ReaderContract.propertyIsPrivate(declaration.property),
    ),
  );
}
