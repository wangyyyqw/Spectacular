import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart' show ByteData, FontLoader;

import 'font_face.dart';
import 'font_face_selection.dart';
import '../text/font_coverage.dart';
import '../text/font_metrics.dart';
import '../text/font_punctuation_metrics.dart';

/// 已加载的独立 face；缓存身份包含来源、范围、字重与样式。
class RegisteredFontFace {
  const RegisteredFontFace({
    required this.selection,
    required this.bytes,
    this.metrics,
  });

  final BookFontFace selection;
  final Uint8List? bytes;
  final FontMetrics? metrics;
  int get weight => selection.weight;
  bool get italic => selection.style != 'normal';
}

/// 一本书的字体注册结果。
class BookFontLoadResult {
  const BookFontLoadResult({
    required this.engineFamilies,
    required this.warnings,
  });

  /// CSS family → 不可变组合族，原生测量前按样式、字重与字符选择独立 face。
  final Map<String, String> engineFamilies;
  final List<String> warnings;
}

/// 每个 face 保留独立选择别名；相同字形字节共享 Flutter 原生字体族。
class BookFontLoader {
  BookFontLoader({required this.bookId, this.contentAddressed = false})
    : _session = _nextSession++;

  final String bookId;

  /// 阅读路径使用内容寻址，跨 loader 复用同字形；否则仅在当前实例内复用。
  final bool contentAddressed;
  final int _session;
  static int _nextSession = 0;
  String get _scope => contentAddressed ? bookId : '$bookId-session-$_session';

  final Map<String, Map<String, RegisteredFontFace>> _registered = {};
  final Map<String, String> _engineNames = {};
  final Map<String, FontCoverage?> _coverageCache = {};
  Future<void> _pendingLoad = Future<void>.value();
  int _generation = 0;

  // Flutter 无法同步卸载字库，相同字形字节不再重复占用原生资源。
  static final Set<String> _registeredEngineNames = {};
  static final Map<String, Future<void>> _engineRegistrations = {};
  static int _engineLoadCount = 0;
  static int get engineLoadCountForTest => _engineLoadCount;

  final Set<String> _degradationSeen = {};
  final List<String> degradationLog = [];

  String engineFamilyName(String cssFamily) =>
      engineFamily(cssFamily) ?? 'bi_${bookId}_$cssFamily';

  String? engineFamily(String cssFamily) =>
      _engineNames[cssFamily.toLowerCase()];

  /// 诊断视图的键为完整 face 身份，不能仅靠字重和斜体区分字符分片。
  Map<String, RegisteredFontFace> facesOf(String cssFamily) =>
      Map.unmodifiable(_registered[cssFamily.toLowerCase()] ?? {});

  RegisteredFontFace? registeredFace(CssFontFace face) =>
      _registered[face.family.toLowerCase()]?[face.dedupKey];

  /// 只组合指定章节的声明，不把其他章节同族的来源带入当前布局。
  String? familyFor(String cssFamily, Iterable<CssFontFace> declarations) {
    final faces = <String, BookFontFace>{};
    for (final declaration in declarations) {
      final loaded = registeredFace(declaration);
      if (loaded == null) continue;
      faces.remove(declaration.dedupKey);
      faces[declaration.dedupKey] = loaded.selection;
    }
    return faces.isEmpty
        ? null
        : BookFontFaceRegistry.registerFamily(cssFamily, faces.values.toList());
  }

  /// 诊断覆盖使用所有已加载 face 的有效范围；排版逐个查询所选字重的 face。
  FontCoverage? coverage(String cssFamily) {
    final family = engineFamily(cssFamily);
    if (family == null) return null;
    return _coverageCache.putIfAbsent(family, () {
      final coverages = facesOf(cssFamily).values
          .map((face) => face.selection.coverage)
          .whereType<FontCoverage>()
          .toList();
      return coverages.isEmpty ? null : FontCoverage.union(coverages);
    });
  }

  /// 只释放 Dart 字节与诊断状态；旧组合族与已加载原生字形仍可用于绘制。
  void clear() {
    _generation++;
    _registered.clear();
    _engineNames.clear();
    _coverageCache.clear();
    _degradationSeen.clear();
    degradationLog.clear();
  }

  Future<BookFontLoadResult> load(
    List<CssFontFace> faces, {
    required Future<Uint8List?> Function(String url) resolveBytes,
  }) {
    final generation = _generation;
    final loading = _pendingLoad.then(
      (_) => _load(faces, resolveBytes, generation),
    );
    _pendingLoad = loading.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return loading;
  }

  Future<BookFontLoadResult> _load(
    List<CssFontFace> faces,
    Future<Uint8List?> Function(String url) resolveBytes,
    int generation,
  ) async {
    if (generation != _generation) return _cancelledLoad;
    final warnings = <String>[];
    final families = <String, String>{};
    for (final face in faces) {
      await _loadFace(face, resolveBytes, warnings, generation);
      if (generation != _generation) return _cancelledLoad;
    }
    for (final family in faces.map((face) => face.family).toSet()) {
      final engine = _updateFamily(family);
      if (engine != null) {
        families[family] = engine;
      } else {
        _warn(
          warnings,
          '字体族 $family 无可加载 face，回退链继续',
          'E_FONT_LOAD_FAILED: 字体族 $family 无可加载 face，回退链继续',
        );
      }
    }
    return BookFontLoadResult(
      engineFamilies: Map.unmodifiable(families),
      warnings: List.unmodifiable(warnings),
    );
  }

  String? _updateFamily(String family) {
    final loaded = _registered[family.toLowerCase()];
    if (loaded == null || loaded.isEmpty) return null;
    final alias = BookFontFaceRegistry.registerFamily(
      family,
      loaded.values.map((face) => face.selection).toList(),
    );
    _engineNames[family.toLowerCase()] = alias;
    final selected = BookFontFaceRegistry.match(alias, 400, 'normal').first;
    final metrics = loaded.values
        .where((face) => face.selection.alias == selected)
        .first
        .metrics;
    if (metrics != null) FontMetricsRegistry.register(alias, metrics);
    return alias;
  }

  Future<void> _loadFace(
    CssFontFace face,
    Future<Uint8List?> Function(String url) resolveBytes,
    List<String> warnings,
    int generation,
  ) async {
    final key = face.dedupKey;
    final cached = registeredFace(face);
    if (cached != null) {
      _putFace(face, cached);
      return;
    }
    final source = await _faceSource(face, resolveBytes, warnings);
    if (generation != _generation || source == null) return;
    final digest = source.bytes == null
        ? source.localFamily!
        : (await sha256.bind(_fontChunks(source.bytes!, generation)).single)
              .toString();
    if (generation != _generation) return;
    final registered = _prepareFace(
      face,
      _aliasFor('face', [_scope, key, digest]),
      source.localFamily ?? _aliasFor('data', [_scope, digest]),
      source,
    );
    try {
      if (registered.bytes != null) await _ensureEngineRegistered(registered);
      if (generation != _generation) return;
      BookFontFaceRegistry.registerFace(registered.selection);
      _putFace(face, registered);
    } catch (error) {
      _warn(
        warnings,
        '${face.family}|register|$key',
        'E_FONT_LOAD_FAILED: 字体族 ${face.family} 注册失败：$error',
      );
    }
  }

  static String _aliasFor(String kind, List<String> identity) =>
      'bi_${kind}_${sha256.convert(utf8.encode(jsonEncode(identity)))}';

  void _putFace(CssFontFace face, RegisteredFontFace registered) {
    final cache = _registered.putIfAbsent(face.family.toLowerCase(), () => {});
    cache.remove(face.dedupKey);
    cache[face.dedupKey] = registered;
  }

  RegisteredFontFace _prepareFace(
    CssFontFace face,
    String alias,
    String nativeFamily,
    ({Uint8List? bytes, String? localFamily}) source,
  ) {
    final range = CssUnicodeRange.parse(face.unicodeRange);
    final bytes = source.bytes;
    return RegisteredFontFace(
      bytes: bytes,
      metrics: bytes == null ? null : FontMetrics.parse(bytes),
      selection: BookFontFace(
        alias: alias,
        nativeFamily: nativeFamily,
        weight: face.normalizedWeight ?? 400,
        style: face.normalizedStyle,
        unicodeRange: range,
        coverage: bytes == null
            ? null
            : FontCoverage.parse(bytes)?.restricted(range.ranges),
        defaultCovered: source.localFamily != FontFamilyAliases.kai,
      ),
    );
  }

  static Future<void> _ensureEngineRegistered(RegisteredFontFace face) {
    final alias = face.selection.nativeFamily;
    if (_registeredEngineNames.contains(alias)) return Future<void>.value();
    final pending = _engineRegistrations[alias];
    if (pending != null) return pending;
    final registration = _registerEngine(face).then<void>((_) {
      _registeredEngineNames.add(alias);
    });
    _engineRegistrations[alias] = registration;
    return registration.whenComplete(() {
      if (identical(_engineRegistrations[alias], registration)) {
        _engineRegistrations.remove(alias);
      }
    });
  }

  static Future<void> _registerEngine(RegisteredFontFace face) async {
    final alias = face.selection.nativeFamily;
    final bytes = face.bytes!;
    final loader = FontLoader(alias)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
    if (face.metrics != null) {
      FontMetricsRegistry.register(alias, face.metrics!);
    }
    FontPunctuationRegistry.register(
      alias,
      bytes,
      weight: face.weight,
      italic: face.italic,
    );
    _engineLoadCount++;
  }

  static const _cancelledLoad = BookFontLoadResult(
    engineFamilies: {},
    warnings: [],
  );

  Stream<List<int>> _fontChunks(Uint8List bytes, int generation) async* {
    // 分块让出事件循环，保留完整 SHA-256，并允许关闭中断大字库摘要。
    const chunkSize = 64 * 1024;
    for (var start = 0; start < bytes.length; start += chunkSize) {
      if (generation != _generation) return;
      final end = start + chunkSize;
      yield Uint8List.sublistView(
        bytes,
        start,
        end < bytes.length ? end : bytes.length,
      );
      if (end < bytes.length) await Future<void>.delayed(Duration.zero);
    }
  }

  void _warn(List<String> warnings, String key, String message) {
    degradationLog.add(message);
    if (_degradationSeen.add(key)) warnings.add(message);
  }

  Future<({Uint8List? bytes, String? localFamily})?> _faceSource(
    CssFontFace face,
    Future<Uint8List?> Function(String url) resolveBytes,
    List<String> warnings,
  ) async {
    for (final source in face.sources) {
      if (source.isLocal) {
        final alias = FontFamilyAliases.resolve(source.ref);
        if (alias != null) return (bytes: null, localFamily: alias);
        warnings.add('字体族 ${face.family} 的 local("${source.ref}") 暂不可加载，跳过');
        continue;
      }
      if (source.isUnsupportedFormat) {
        _warn(
          warnings,
          '${face.family}|unsupported|${source.ref}',
          'E_FONT_UNSUPPORTED: 字体族 ${face.family} 的 ${source.ref} '
              '格式不支持（${source.format}），跳过',
        );
        continue;
      }
      final bytes = await _readSource(
        face.family,
        source.ref,
        resolveBytes,
        warnings,
      );
      if (bytes != null) return (bytes: bytes, localFamily: null);
    }
    return null;
  }

  Future<Uint8List?> _readSource(
    String family,
    String url,
    Future<Uint8List?> Function(String) resolveBytes,
    List<String> warnings,
  ) async {
    try {
      final bytes = await resolveBytes(url);
      if (bytes != null && bytes.isNotEmpty) return bytes;
      _warn(
        warnings,
        '$family|missing|$url',
        'E_FONT_LOAD_FAILED: 字体族 $family 的 $url 资源缺失，跳过',
      );
    } catch (error) {
      _warn(
        warnings,
        '$family|read-error|$url',
        'E_FONT_LOAD_FAILED: 字体族 $family 的 $url 读取失败：$error',
      );
    }
    return null;
  }
}
