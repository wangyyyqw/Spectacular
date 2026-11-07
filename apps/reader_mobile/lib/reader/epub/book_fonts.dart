import 'package:flutter/foundation.dart' show listEquals;
import 'package:reader_core/css/book_font_loader.dart';
import 'package:reader_core/css/computed_style.dart';
import 'package:reader_core/css/font_face.dart';
import 'package:reader_core/css/parser.dart';
import 'package:reader_core/css/reader_overrides.dart';
import 'package:reader_core/text/font_coverage.dart';

import '../bounded_cache.dart';
import 'book_resources.dart';

typedef _CoverageStrategy = ({FontCoverage? coverage, bool defaultCovered});

/// 一本书的字体注册与字形覆盖；资源读取、归档关闭由 [BookResources] 负责。
class BookFonts {
  BookFonts(this._resources, {required this.onFontsChanged});

  final BookResources _resources;
  final void Function(Set<String>) onFontsChanged;
  BookFontLoader? _loader;
  final Set<String> _facesSeen = <String>{};
  Future<void>? _registration;
  final Map<String, String> _engineFamilies = <String, String>{};
  final Set<String> _embeddedEngineFamilies = <String>{};
  final Map<String, FontCoverage> _coverages = <String, FontCoverage>{};
  final Map<String, bool> _userFontAvailability = <String, bool>{};
  int _revision = 0;
  int _availabilityRevision = 0;
  BookFontView? _frozen;
  int _frozenBookRevision = -1;
  int _frozenAvailabilityRevision = -1;
  int _frozenCoverageRevision = -1;
  bool _closed = false;

  /// 只有 CSS 族到引擎族的映射真正变化时递增，不参与稳定字体依赖键。
  int get revision => _revision;

  int get faceCount => _facesSeen.length;

  /// CSS 族名的小写形式到引擎族名；外部不能修改注册状态。
  Map<String, String> get engineFamilies => Map.unmodifiable(_engineFamilies);

  /// 具有包内字节和可检测字形覆盖的引擎族；不包含 local() 别名。
  Set<String> get embeddedEngineFamilies =>
      Set.unmodifiable(_embeddedEngineFamilies);

  bool get _isClosed => _closed || _resources.isClosed;

  /// 同族增量注册串行合并，重复请求等待已在途的注册完成。
  Future<void> ensure(List<CssFontFace> requestedFaces) async {
    while (_registration != null) {
      await _registration!;
    }
    if (_isClosed || requestedFaces.isEmpty) return;
    final loader = _loader ??= BookFontLoader(
      bookId: 'bk-${_resources.document.opfPath.hashCode}',
      contentAddressed: true,
    );
    _syncEngines(loader, requestedFaces);
    final pending = <CssFontFace>[
      for (final face in requestedFaces)
        if (_facesSeen.add(
          '${face.family}|${face.normalizedWeight}|${face.normalizedStyle}',
        ))
          face,
    ];
    if (pending.isEmpty) return;
    final registration = loader
        .load(pending, resolveBytes: _resources.readFont)
        .then((_) {
          if (_isClosed) {
            loader.clear();
          } else {
            _syncEngines(loader, requestedFaces);
          }
        });
    _registration = registration;
    try {
      await registration;
    } finally {
      if (identical(_registration, registration)) _registration = null;
    }
  }

  void _syncEngines(BookFontLoader loader, List<CssFontFace> faces) {
    final changed = <String>{};
    for (final face in faces) {
      final engine = loader.engineFamily(face.family);
      if (engine != null) {
        _putEngine(face.family, engine, changed);
        final coverage = loader.coverage(face.family);
        if (coverage != null) {
          _embeddedEngineFamilies.add(engine);
          _coverages[engine] = coverage;
        }
      } else {
        _syncLocalAlias(face, changed);
      }
    }
    if (changed.isNotEmpty) {
      _revision += 1;
      // 这里只报告依赖变化；宿主决定哪些布局失效，注册作业不自行取消。
      onFontsChanged(Set<String>.unmodifiable(changed));
    }
  }

  void _syncLocalAlias(CssFontFace face, Set<String> changed) {
    for (final source in face.sources) {
      final alias = source.isLocal
          ? FontFamilyAliases.resolve(source.ref)
          : null;
      if (alias == null) continue;
      _putEngine(face.family, alias, changed);
      break;
    }
  }

  void _putEngine(String family, String engine, Set<String> changed) {
    final key = family.toLowerCase();
    final previous = _engineFamilies[key];
    if (previous == engine) return;
    changed.add(key);
    _engineFamilies[key] = engine;
    if (previous != null) {
      _coverages.remove(previous);
      _embeddedEngineFamilies.remove(previous);
    }
  }

  /// 记录宿主实际加载结果；注册表可能仍保留已删除文件的旧字形。
  /// 只改变依赖快照，由宿主更新计页配置，不自行取消或重排章节。
  bool setUserFontAvailability(String family, bool available) {
    if (_isClosed || _userFontAvailability[family] == available) return false;
    _userFontAvailability[family] = available;
    _availabilityRevision += 1;
    return true;
  }

  /// 作业冻结后不再读取本服务的可变映射；已有视图可跨增量注册和关闭使用。
  /// 映射、实际可用性和全局覆盖未变化时复用同一视图，热路径只比较版本。
  BookFontView freeze() {
    final coverageRevision = FontCoverageRegistry.revision;
    if (_frozen != null &&
        _frozenBookRevision == _revision &&
        _frozenAvailabilityRevision == _availabilityRevision &&
        _frozenCoverageRevision == coverageRevision) {
      return _frozen!;
    }
    _frozenBookRevision = _revision;
    _frozenAvailabilityRevision = _availabilityRevision;
    _frozenCoverageRevision = coverageRevision;
    return _frozen = BookFontView._(
      _engineFamilies,
      _embeddedEngineFamilies,
      _coverages,
      FontCoverageRegistry.snapshot(),
      _userFontAvailability,
    );
  }

  /// 只释放 Dart 侧字体字节与状态；Flutter 已注册字形由引擎持有。
  void close() {
    if (_closed) return;
    _closed = true;
    _loader?.clear();
    _loader = null;
    _facesSeen.clear();
    _engineFamilies.clear();
    _embeddedEngineFamilies.clear();
    _coverages.clear();
    _userFontAvailability.clear();
    _revision = 0;
    _availabilityRevision = 0;
    _frozen = null;
  }
}

/// 一次排版使用的不可变书内字体视图，不持有 [BookFonts] 或归档资源。
class BookFontView {
  BookFontView._(
    Map<String, String> engines,
    Set<String> embedded,
    Map<String, FontCoverage> coverages,
    Map<String, FontCoverage> userCoverages,
    Map<String, bool> userFontAvailability,
  ) : _engineFamilies = Map.unmodifiable(engines),
      _embeddedEngineFamilies = Set.unmodifiable(embedded),
      _coverages = Map.unmodifiable(coverages),
      _userCoverages = Map.unmodifiable(userCoverages),
      _userFontAvailability = Map.unmodifiable(userFontAvailability);

  final Map<String, String> _engineFamilies;
  final Set<String> _embeddedEngineFamilies;
  final Map<String, FontCoverage> _coverages;
  final Map<String, FontCoverage> _userCoverages;
  final Map<String, bool> _userFontAvailability;
  // 原始族名保留用户覆盖的精确匹配；策略只依赖当前冻结视图。
  final _coverageStrategies = BoundedCache<String, _CoverageStrategy>(64);

  /// 用户字体环境只取已注册覆盖，不随书内字体逐章注册或加载结果通知改变。
  late final String userFontEnvironmentDependency =
      _userEnvironmentDependency();

  String _userEnvironmentDependency() {
    final entries = [
      for (final entry in _userCoverages.entries)
        if (entry.key.startsWith('user_'))
          '${entry.key}=${entry.value.fingerprint}',
    ]..sort();
    return entries.join(',');
  }

  bool hasGlyph(String family, int codePoint) {
    final strategy = _coverageStrategies.putIfAbsent(
      family,
      () => _coverageStrategy(family),
    );
    return strategy.coverage?.covers(codePoint) ?? strategy.defaultCovered;
  }

  _CoverageStrategy _coverageStrategy(String family) {
    final custom = _userCoverages[family];
    if (custom != null) return (coverage: custom, defaultCovered: false);
    final engine = FontFamilyAliases.resolve(family) ?? family;
    return (
      coverage: _coverages[family] ?? _coverages[engine],
      defaultCovered: engine != FontFamilyAliases.kai,
    );
  }

  /// 只替换字族，保留作者字号、盒样式和可用的内嵌字体回退链。
  ComputedStyle applyCustomFont(
    ComputedStyle computed,
    ReaderOverrides overrides,
  ) {
    if (!overrides.isCustomFont) return computed;
    final families = [
      for (final family in computed.fontFamilies)
        _engineFamilies[family.toLowerCase()] ?? family,
    ];
    if (!overrides.overrideEmbeddedFonts &&
        families.any(_embeddedEngineFamilies.contains)) {
      return listEquals(families, computed.fontFamilies)
          ? computed
          : computed.withTypography(fontFamilyList: families);
    }
    return computed.withTypography(fontFamily: overrides.fontFamily);
  }

  /// 未命中时返回原声明列表；简写命中时保留字重、字号、行高及重置属性。
  List<CssDeclaration> rewriteDeclarations(List<CssDeclaration> declarations) {
    if (_engineFamilies.isEmpty) return declarations;
    var changed = false;
    final rewritten = <CssDeclaration>[];
    for (final declaration in declarations) {
      final shorthand = declaration.property == 'font'
          ? ComputedStyle.parseFontShorthand(declaration.value)
          : null;
      final family =
          shorthand?['font-family'] ??
          (declaration.property == 'font-family' ? declaration.value : null);
      final value = family == null ? null : _rewriteFamilyList(family);
      if (family == null || value == family) {
        rewritten.add(declaration);
        continue;
      }
      changed = true;
      for (final entry in (shorthand ?? {'font-family': family}).entries) {
        rewritten.add(
          CssDeclaration(
            property: entry.key,
            value: entry.key == 'font-family' ? value! : entry.value,
            important: declaration.important,
          ),
        );
      }
    }
    return changed ? rewritten : declarations;
  }

  String _rewriteFamilyList(String value) {
    var changed = false;
    final parts = <String>[];
    for (final raw in value.split(',')) {
      final name = _unquoteFamily(raw.trim());
      final engine = _engineFamilies[name.toLowerCase()];
      if (engine == null) {
        parts.add(raw);
      } else {
        parts.add('"$engine"');
        changed = true;
      }
    }
    return changed ? parts.join(',') : value;
  }

  static String _unquoteFamily(String raw) {
    if (raw.length >= 2 &&
        ((raw.startsWith('"') && raw.endsWith('"')) ||
            (raw.startsWith("'") && raw.endsWith("'")))) {
      return raw.substring(1, raw.length - 1);
    }
    return raw;
  }

  /// 实际引用族及用户字体加载结果的稳定依赖，与注册次数无关。
  String dependency(Set<String> families) {
    final entries = [
      for (final family in families)
        _familyDependency(
          family,
          _engineFamilies[family.toLowerCase()] ?? family,
        ),
    ]..sort();
    return entries.join(',');
  }

  /// 书级只取原始请求族的用户覆盖与加载结果，不随书内字体逐章注册改变。
  String userFontDependency(Set<String> families) {
    final entries = [
      for (final family in families) _familyDependency(family, family),
    ]..sort();
    return entries.join(',');
  }

  String _familyDependency(String family, String engine) {
    final coverage = _userCoverages[engine] ?? _userCoverages[family];
    final available =
        _userFontAvailability[family] ?? _userFontAvailability[engine];
    final dependency = '$family=$engine';
    if (available == null &&
        coverage == null &&
        !family.startsWith('user_') &&
        !engine.startsWith('user_')) {
      return dependency;
    }
    final state = switch (available) {
      true => '可用',
      false => '回退',
      null => '未确认',
    };
    return '$dependency:availability=$state'
        ':coverage=${coverage?.fingerprint ?? "未注册"}';
  }
}
