import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart' show ByteData, FontLoader;

import 'font_face.dart';
import '../text/font_coverage.dart';
import '../text/font_metrics.dart';

/// 一个已注册的 face 记录（缓存键：weight+italic）。
class RegisteredFontFace {
  const RegisteredFontFace({
    required this.weight,
    required this.italic,
    required this.bytes,
  });

  /// 归一化字重（400/700…）。
  final int weight;

  /// 归一化斜体。
  final bool italic;

  /// 字形数据。
  final Uint8List bytes;
}

/// 一本书的字面注册结果。
class BookFontLoadResult {
  const BookFontLoadResult({
    required this.engineFamilies,
    required this.warnings,
  });

  /// CSS family → 引擎 family（注册成功者）。
  final Map<String, String> engineFamilies;

  /// 诊断告警（face 失败、local 不可加载、格式不支持…）。
  final List<String> warnings;
}

/// 书内字体的生产注册器（P3-02，方案 A：S5 真机结论）。
///
/// 一个 CSS `@font-face` family 注册为一个引擎 family：
/// regular/bold/italic 各 face 通过 [FontLoader.addFont] 并列加载，
/// 渲染期由引擎按 `fontWeight`/`fontStyle` 选面——S5 已在真机验证
/// bold 按字重正确选中，italic 走合成倾斜（P7-08 补测通过）。
///
/// 注册缓存键 `engineFamily → (weight, italic) → 字形数据`：
/// 同键的后注册覆盖先注册；重复打开同一本书时键集一致则跳过重载。
class BookFontLoader {
  BookFontLoader({required this.bookId, this.contentAddressed = false});

  /// 书 id，用于引擎族名隔离（多书同开不串族）。
  final String bookId;

  /// 实际阅读启用内容寻址，避免同路径、同标识的不同书籍共用全局字体族。
  final bool contentAddressed;

  final Map<String, Map<String, RegisteredFontFace>> _registered =
      <String, Map<String, RegisteredFontFace>>{};
  final Map<String, String> _engineNames = <String, String>{};
  final Map<String, String> _faceDigests = <String, String>{};
  Future<void> _pendingLoad = Future<void>.value();
  int _generation = 0;

  /// 进程级已注册字体族：Flutter 引擎无法同步卸载字体，重复打开同一本书
  /// 时若再次 `FontLoader.load`，原生字形资源会继续叠加。
  static final Set<String> _registeredEngineNames = <String>{};
  static final Map<String, Future<void>> _engineRegistrations =
      <String, Future<void>>{};
  static int _engineLoadCount = 0;

  /// 实际调用 `FontLoader.load` 的次数（测试诊断用）。
  static int get engineLoadCountForTest => _engineLoadCount;

  /// 已播报过的降级键（P3-06）：同一 (族, 原因) 只进一次 result.warnings，
  /// 供 UI「提示只出现一次」口径；完整记录见 [degradationLog]。
  final Set<String> _degradationSeen = <String>{};

  /// 全量降级记录（含重复），供诊断导出。
  final List<String> degradationLog = <String>[];

  /// 引擎族名；内容寻址模式在成功加载后插入稳定的字形摘要。
  String engineFamilyName(String cssFamily) =>
      _engineNames[cssFamily] ?? 'bi_${bookId}_$cssFamily';

  /// CSS family 是否已注册；返回引擎族名，未注册返回 null。
  String? engineFamily(String cssFamily) {
    final key = engineFamilyName(cssFamily);
    return _registered.containsKey(key) ? key : null;
  }

  /// 已注册 face 的诊断视图（键 `w<weight>i<0|1>`）。
  Map<String, RegisteredFontFace> facesOf(String cssFamily) {
    final faces = _registered[engineFamilyName(cssFamily)];
    return faces == null
        ? const <String, RegisteredFontFace>{}
        : Map.unmodifiable(faces);
  }

  final Map<String, FontCoverage?> _coverageCache =
      <String, FontCoverage?>{};

  /// 释放书内字体字节与诊断缓存。
  ///
  /// 引擎已注册的字形数据由 Flutter 管理，无法同步卸载；这里清空 Dart 侧
  /// 持有的字节，避免关闭阅读页后重复书仍保留整份字体资源。
  void clear() {
    _generation++;
    _registered.clear();
    _engineNames.clear();
    _faceDigests.clear();
    _degradationSeen.clear();
    degradationLog.clear();
    _coverageCache.clear();
  }

  /// 书内字体的字形覆盖（P3-04）：按 w400 face（无则首个 face）的
  /// 字节解析 cmap。诊断用途——缺失字符清单导出；运行期缺字仍由
  /// fontFamilyFallback 兜底（技术方案 §28.4）。解析失败返回 null。
  FontCoverage? coverage(String cssFamily) {
    final engineName = engineFamilyName(cssFamily);
    if (!_registered.containsKey(engineName)) {
      return null;
    }
    return _coverageCache.putIfAbsent(engineName, () {
      final faces = _registered[engineName]!;
      final face = faces['w400i0'] ?? faces.values.first;
      return FontCoverage.parse(face.bytes);
    });
  }

  /// 按声明加载书内字体。
  ///
  /// [faces] 为 P3-01 解析出的 `@font-face` 列表（url 地址未解析，
  /// 相对路径归一由 [resolveBytes] 的调用方闭包负责）。返回 null 视为
  /// 资源缺失。单个 face 失败只记告警不阻断；一个 family 全部 face
  /// 失败则该族不可用，[engineFamily] 返回 null 走回退链。
  Future<BookFontLoadResult> load(
    List<CssFontFace> faces, {
    required Future<Uint8List?> Function(String url) resolveBytes,
  }) {
    final generation = _generation;
    // 增量章节可能并发添加同族的不同字重，串行合并才能保留全部 face。
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
    final engineFamilies = <String, String>{};

    final byFamily = <String, List<CssFontFace>>{};
    for (final face in faces) {
      byFamily.putIfAbsent(face.family, () => <CssFontFace>[]).add(face);
    }

    for (final entry in byFamily.entries) {
      final cssFamily = entry.key;
      final previousEngineName = engineFamilyName(cssFamily);
      var engineName = previousEngineName;
      final existing = _registered[engineName];
      final cache = existing == null
          ? <String, RegisteredFontFace>{}
          : Map<String, RegisteredFontFace>.of(existing);

      for (final face in entry.value) {
        final key = _faceKey(face);
        if (cache.containsKey(key)) {
          continue; // 缓存键命中：同 (weight, italic) 不重复加载。
        }
        final bytes = await _faceBytes(face, resolveBytes, warnings);
        if (generation != _generation) return _cancelledLoad;
        if (bytes == null) {
          continue;
        }
        if (contentAddressed) {
          final digest = await sha256.bind(_fontChunks(bytes, generation)).single;
          if (generation != _generation) return _cancelledLoad;
          _faceDigests['$cssFamily|$key'] = digest.toString();
        }
        cache[key] = RegisteredFontFace(
          weight: face.normalizedWeight ?? 400,
          italic: face.normalizedStyle == 'italic',
          bytes: bytes,
        );
      }

      if (cache.isEmpty) {
        if (existing == null) {
          _warn(
            warnings,
            '字体族 $cssFamily 无可加载 face，回退链继续',
            'E_FONT_LOAD_FAILED: 字体族 $cssFamily 无可加载 face，回退链继续',
          );
        }
        continue;
      }
      final allCached = existing != null && cache.length == existing.length;
      if (allCached) {
        // 键集未变化：不重复 FontLoader.load。
        engineFamilies[cssFamily] = engineName;
        continue;
      }
      engineName = _contentEngineName(cssFamily, cache);
      final metricFace = cache['w400i0'] ?? cache.values.first;
      final metrics = FontMetrics.parse(metricFace.bytes);
      try {
        if (contentAddressed) {
          // 内容寻址族名已包含全部 face 摘要，同名即同字形，可跨 loader
          // 复用进程级注册；并发打开同一本书也只注册一次。
          await _ensureEngineRegistered(
            engineName,
            cssFamily: cssFamily,
            cache: cache,
            metrics: metrics,
          );
        } else {
          await _registerEngine(
            engineName,
            cssFamily: cssFamily,
            cache: cache,
            metrics: metrics,
          );
        }
        if (generation != _generation) return _cancelledLoad;
        if (engineName != previousEngineName) {
          _registered.remove(previousEngineName);
          _coverageCache.remove(previousEngineName);
        }
        _registered[engineName] = cache;
        _engineNames[cssFamily] = engineName;
        engineFamilies[cssFamily] = engineName;
      } catch (error) {
        _warn(
          warnings,
          '字体族 $cssFamily 注册失败：$error',
          'E_FONT_LOAD_FAILED: 字体族 $cssFamily 注册失败：$error',
        );
      }
    }
    return BookFontLoadResult(
      engineFamilies: Map.unmodifiable(engineFamilies),
      warnings: List.unmodifiable(warnings),
    );
  }

  static Future<void> _ensureEngineRegistered(
    String engineName, {
    required String cssFamily,
    required Map<String, RegisteredFontFace> cache,
    required FontMetrics? metrics,
  }) {
    if (_registeredEngineNames.contains(engineName)) {
      return Future<void>.value();
    }
    final pending = _engineRegistrations[engineName];
    if (pending != null) {
      return pending;
    }
    final registration =
        _registerEngine(
          engineName,
          cssFamily: cssFamily,
          cache: cache,
          metrics: metrics,
        ).then<void>((_) {
          _registeredEngineNames.add(engineName);
        });
    _engineRegistrations[engineName] = registration;
    return registration.whenComplete(() {
      if (identical(_engineRegistrations[engineName], registration)) {
        _engineRegistrations.remove(engineName);
      }
    });
  }

  static Future<void> _registerEngine(
    String engineName, {
    required String cssFamily,
    required Map<String, RegisteredFontFace> cache,
    required FontMetrics? metrics,
  }) async {
    if (metrics != null) {
      FontMetricsRegistry.register(engineName, metrics);
      FontMetricsRegistry.register(cssFamily, metrics);
    }
    final loader = FontLoader(engineName);
    // 先 regular 后其他，稳定顺序利于引擎选面复现。
    final ordered = cache.values.toList()
      ..sort((a, b) {
        if (a.italic != b.italic) {
          return a.italic ? 1 : -1;
        }
        return a.weight.compareTo(b.weight);
      });
    for (final face in ordered) {
      loader.addFont(Future.value(ByteData.sublistView(face.bytes)));
    }
    await loader.load();
    _engineLoadCount += 1;
  }

  static const _cancelledLoad = BookFontLoadResult(
    engineFamilies: <String, String>{},
    warnings: <String>[],
  );

  Stream<List<int>> _fontChunks(Uint8List bytes, int generation) async* {
    // 大字库的纯 Dart SHA-256 在 debug 下可阻塞数秒；分块只让出调度，不改摘要。
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

  String _contentEngineName(
    String cssFamily,
    Map<String, RegisteredFontFace> faces,
  ) {
    if (!contentAddressed) return engineFamilyName(cssFamily);
    final keys = faces.keys.toList()..sort();
    final signature = keys
        .map((key) => '$key:${_faceDigests['$cssFamily|$key']}')
        .join('|');
    final digest = sha256.convert(utf8.encode(signature));
    return 'bi_${bookId}_${digest}_$cssFamily';
  }

  static String _faceKey(CssFontFace face) => 'w${face.normalizedWeight ?? 400}'
      'i${face.normalizedStyle == 'italic' ? 1 : 0}';

  /// 降级告警去重（P3-06）：同一原因只进一次 result.warnings（UI
  /// 「提示只出现一次」），完整记录进 [degradationLog] 供导出。
  void _warn(List<String> warnings, String key, String message) {
    degradationLog.add(message);
    if (_degradationSeen.add(key)) {
      warnings.add(message);
    }
  }

  /// 按来源顺序取第一个可用的 url 字节；local 来源在 P3-03 接入系统
  /// 字体映射前不可加载，记告警跳过。
  Future<Uint8List?> _faceBytes(
    CssFontFace face,
    Future<Uint8List?> Function(String url) resolveBytes,
    List<String> warnings,
  ) async {
    for (final source in face.sources) {
      if (source.isLocal) {
        warnings.add(
          '字体族 ${face.family} 的 local("${source.ref}") 暂不可加载，跳过',
        );
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
      try {
        final bytes = await resolveBytes(source.ref);
        if (bytes != null && bytes.isNotEmpty) {
          return bytes;
        }
        _warn(
          warnings,
          '${face.family}|missing|${source.ref}',
          'E_FONT_LOAD_FAILED: 字体族 ${face.family} 的 ${source.ref} '
              '资源缺失，跳过',
        );
      } catch (error) {
        _warn(
          warnings,
          '${face.family}|read-error|${source.ref}',
          'E_FONT_LOAD_FAILED: 字体族 ${face.family} 的 ${source.ref} '
              '读取失败：$error',
        );
      }
    }
    return null;
  }
}
