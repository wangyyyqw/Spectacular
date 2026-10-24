import 'dart:typed_data';

import 'package:flutter/services.dart' show ByteData, FontLoader;

import 'font_face.dart';
import '../text/font_coverage.dart';

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
  BookFontLoader({required this.bookId});

  /// 书 id，用于引擎族名隔离（多书同开不串族）。
  final String bookId;

  final Map<String, Map<String, RegisteredFontFace>> _registered =
      <String, Map<String, RegisteredFontFace>>{};

  /// 引擎族名：`bi_<bookId>_<cssFamily>`（技术方案 §68.1 命名）。
  String engineFamilyName(String cssFamily) => 'bi_${bookId}_$cssFamily';

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
  }) async {
    final warnings = <String>[];
    final engineFamilies = <String, String>{};

    final byFamily = <String, List<CssFontFace>>{};
    for (final face in faces) {
      byFamily.putIfAbsent(face.family, () => <CssFontFace>[]).add(face);
    }

    for (final entry in byFamily.entries) {
      final cssFamily = entry.key;
      final engineName = engineFamilyName(cssFamily);
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
        if (bytes == null) {
          continue;
        }
        cache[key] = RegisteredFontFace(
          weight: face.normalizedWeight ?? 400,
          italic: face.normalizedStyle == 'italic',
          bytes: bytes,
        );
      }

      if (cache.isEmpty) {
        if (existing == null) {
          warnings.add('字体族 $cssFamily 无可加载 face，回退链继续');
        }
        continue;
      }
      final allCached =
          existing != null && cache.length == existing.length;
      if (allCached) {
        // 键集未变化：不重复 FontLoader.load。
        engineFamilies[cssFamily] = engineName;
        continue;
      }
      try {
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
        _registered[engineName] = cache;
        engineFamilies[cssFamily] = engineName;
      } catch (error) {
        warnings.add('字体族 $cssFamily 注册失败：$error');
      }
    }
    return BookFontLoadResult(
      engineFamilies: Map.unmodifiable(engineFamilies),
      warnings: List.unmodifiable(warnings),
    );
  }

  static String _faceKey(CssFontFace face) => 'w${face.normalizedWeight ?? 400}'
      'i${face.normalizedStyle == 'italic' ? 1 : 0}';

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
        warnings.add(
          '字体族 ${face.family} 的 ${source.ref} 格式不支持'
          '（${source.format}），跳过',
        );
        continue;
      }
      try {
        final bytes = await resolveBytes(source.ref);
        if (bytes != null && bytes.isNotEmpty) {
          return bytes;
        }
        warnings.add('字体族 ${face.family} 的 ${source.ref} 资源缺失，跳过');
      } catch (error) {
        warnings.add('字体族 ${face.family} 的 ${source.ref} 读取失败：$error');
      }
    }
    return null;
  }
}
