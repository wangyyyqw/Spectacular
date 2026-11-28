import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../css/computed_style.dart';
import '../position/cfi.dart';
import '../position/text_length.dart';
import '../src/api/models.dart';
import '../src/api/interfaces.dart';
import 'archive_reader.dart';
import 'container.dart';
import 'epub_exception.dart';
import 'encryption_metadata.dart';
import 'extension.dart';
import 'footnote.dart';
import '../parser/cfi_binder.dart';
import '../parser/cfi_resolver.dart';
import '../parser/block_builder.dart';
import '../parser/document_parser.dart';
import '../parser/text_aggregator.dart';
import 'opf.dart';
import 'toc.dart';
import 'font_obfuscation.dart';
import 'importer.dart';
import 'resource_index.dart';

/// 打开结果：成功时带文档，失败时只带报告。
class EpubOpenResult {
  const EpubOpenResult({this.document, required this.report});

  /// 成功时的文档。
  final EpubDocumentImpl? document;

  /// 导入报告（成功时 ok=true）。
  final ImportReport report;

  /// 是否打开成功。
  bool get ok => document != null;
}

/// 打开 EPUB；任何失败都转成 [ImportReport]，不抛未捕获异常。
Future<EpubOpenResult> openEpub(Uint8List bytes, {bool verifyCrc = true}) {
  return _openWith(() async => EpubArchive.fromBytes(bytes, verify: verifyCrc));
}

/// 从文件打开 EPUB：只解析中央目录，章节与资源按需读取。
///
/// 阅读路径用这个入口——100MB+ 的书不再把整本字节读进 Dart 堆。
/// [verifyCrc] 默认关闭：导入时已完整校验过一次，阅读时逐条重算 CRC
/// 只会增加 CPU 与发热。
Future<EpubOpenResult> openEpubFile(
  File file, {
  bool verifyCrc = false,
  Map<String, Uint8List?> resourceOverrides = const {},
}) {
  return _openWith(() async {
    final archive = await EpubArchive.fromFile(file, verify: verifyCrc);
    return resourceOverrides.isEmpty
        ? archive
        : EpubArchive.withOverrides(archive, resourceOverrides);
  }, parseContainerInIsolate: true);
}

Future<EpubOpenResult> _openWith(
  Future<EpubArchive> Function() create, {
  bool parseContainerInIsolate = false,
}) async {
  final warnings = <String>[];
  EpubArchive? archive;
  var archiveOwnedByResult = false;
  try {
    archive = await create();
    final encryption = EpubEncryptionMetadata.read(archive);
    encryption.requireReadable();
    if (encryption.fonts.parseFailed) {
      warnings.add('E_FONT_OBFUSCATION_FAILED: 加密声明损坏，无法完整判断加密状态');
    }
    final ocf = archive.validateOcf();
    if (!ocf.ok) {
      return EpubOpenResult(
        report: ImportReport(
          ok: false,
          errorCode: 'E_OCF',
          readabilityLevel: EpubReadability.l4,
          message: ocf.errors.join('；'),
          warnings: ocf.warnings,
        ),
      );
    }
    warnings.addAll(ocf.warnings);
    // ZIP 恢复档诊断（P7-15）并入报告。
    warnings.addAll(archive.diagnostics);

    // P7-12：container.xml 缺失/损坏时按候选路径扫描 OPF 兜底（诊断
    // 进 warnings，不静默）；全部候选失败走 L3 拼装（P3-26）。
    ContainerInfo container;
    String? containerDiagnostic;
    try {
      final containerParsed = parseContainerInIsolate
          ? await _parseContainerInIsolate(archive)
          : EpubContainer.parseWithFallback(archive);
      container = containerParsed.$1;
      containerDiagnostic = containerParsed.$2;
    } on EpubException catch (error) {
      final fallbackPackage = buildFallbackPackage(archive);
      if (fallbackPackage == null) {
        return EpubOpenResult(
          report: ImportReport(
            ok: false,
            errorCode: error.code,
            message: error.message,
            warnings: warnings,
          ),
        );
      }
      warnings.add(
        'E_CONTAINER_FALLBACK: 无 OPF，按文件名排序拼出 '
        ' 个章节（结构异常，进度与目录不可靠）',
      );
      final result = await _finishOpen(
        archive: archive,
        package: fallbackPackage,
        opfPath: 'fallback.opf',
        warnings: warnings,
        fontEncryption: encryption.fonts,
      );
      archiveOwnedByResult = result.document != null;
      return result;
    }
    if (containerDiagnostic != null) {
      warnings.add(containerDiagnostic);
    }
    var opfString = archive.readString(container.rootfilePath);
    if (opfString == null) {
      // L3 兜底（P3-26，§55.1）：无 OPF 时按文件名排序拼 XHTML 章节，
      // 比直接拒绝有价值；结构异常记 L3。
      final fallbackPackage = buildFallbackPackage(archive);
      if (fallbackPackage == null) {
        return EpubOpenResult(
          report: ImportReport(
            ok: false,
            errorCode: 'E_OPF_MISSING',
            readabilityLevel: EpubReadability.l4,
            message: 'OPF 不存在：${container.rootfilePath}',
            warnings: warnings,
          ),
        );
      }
      warnings.add(
        'E_CONTAINER_FALLBACK: 无 OPF，按文件名排序拼出 '
        '${fallbackPackage.spine.length} 个章节（结构异常，进度与目录不可靠）',
      );
      final result = await _finishOpen(
        archive: archive,
        package: fallbackPackage,
        opfPath: container.rootfilePath,
        warnings: warnings,
        fontEncryption: encryption.fonts,
      );
      archiveOwnedByResult = result.document != null;
      return result;
    }
    final package = OpfParser.parse(opfString);
    warnings.addAll(package.warnings);
    final result = await _finishOpen(
      archive: archive,
      package: package,
      opfPath: container.rootfilePath,
      warnings: warnings,
      fontEncryption: encryption.fonts,
    );
    archiveOwnedByResult = result.document != null;
    return result;
  } on EpubException catch (error) {
    return EpubOpenResult(
      report: ImportReport(
        ok: false,
        errorCode: error.code,
        message: error.message,
        warnings: warnings,
        readabilityLevel: EpubReadability.l4,
      ),
    );
  } catch (error) {
    return EpubOpenResult(
      report: ImportReport(
        ok: false,
        errorCode: 'E_INTERNAL',
        readabilityLevel: EpubReadability.l4,
        message: '打开失败：$error',
        warnings: warnings,
      ),
    );
  } finally {
    if (!archiveOwnedByResult) {
      archive?.close();
    }
  }
}

Future<(ContainerInfo, String?)> _parseContainerInIsolate(
  EpubArchive archive,
) async {
  final bytes = await archive.readBytesAsync(EpubContainer.containerPath);
  if (bytes == null) return EpubContainer.parseWithFallback(archive);
  try {
    return (await Isolate.run(() => EpubContainer.parseBytes(bytes)), null);
  } on EpubException {
    return EpubContainer.parseWithFallback(archive);
  }
}

/// 打开的收尾段（P3-26）：spine 校验 → 资源探测 → 分级。
Future<EpubOpenResult> _finishOpen({
  required EpubArchive archive,
  required OpfPackage package,
  required String opfPath,
  required List<String> warnings,
  required FontEncryptionMap fontEncryption,
}) async {
  {
    var effectivePackage = package;
    if (effectivePackage.spine.isEmpty) {
      // L3 恢复（对照 Ferrous `epub_fallback_parser.dart`）：spine 声明缺失或
      // 全部失效时按 manifest/文件扫描重建阅读顺序，比直接拒绝有价值。
      final recovered = recoverSpine(
        archive: archive,
        package: effectivePackage,
        opfPath: opfPath,
      );
      if (recovered == null) {
        return EpubOpenResult(
          report: ImportReport(
            ok: false,
            errorCode: 'E_SPINE_EMPTY',
            readabilityLevel: EpubReadability.l4,
            message: 'spine 为空，无法分页',
            warnings: warnings,
          ),
        );
      }
      warnings.add(
        'E_SPINE_FALLBACK: spine 为空，按 manifest 恢复 '
        '${recovered.spine.length} 个章节（阅读顺序不可靠）',
      );
      effectivePackage = recovered;
    }
    final resources = ResourceIndex.build(
      archive: archive,
      manifest: effectivePackage.manifest,
      opfPath: opfPath,
    );
    final tocResult = TocFallback.build(
      archive: archive,
      package: effectivePackage,
      opfPath: opfPath,
    );
    warnings.addAll(tocResult.warnings);
    final resolvedEncryption = fontEncryption.resolvePaths(
      (uri) => resources.resolve(uri, baseDir: ''),
    );
    final extensionConfig = DuokanExtensionParser.parse(
      archive.readString(DuokanExtensionParser.path),
    );
    warnings.addAll(extensionConfig.warnings);
    // 导入期探测与分级（P3-26）：spine 缺失 + 图片/字体资源可解性。
    final probe = probeImport(
      archive: archive,
      package: effectivePackage,
      resources: resources,
      opfDir: opfPath.contains('/')
          ? opfPath.substring(0, opfPath.lastIndexOf('/'))
          : '',
    );
    if (probe.missingSpineItems > 0) {
      warnings.add('E_SPINE_MISSING: ${probe.missingSpineItems} 个章节文件不存在');
    }
    if (probe.missingResources > 0) {
      warnings.add('E_RESOURCE_MISSING: ${probe.missingResources} 个图片/字体资源缺失');
    }
    if (probe.repairedRefs > 0) {
      warnings.add('E_RESOURCE_REPAIRED: 已自动修复 ${probe.repairedRefs} 处引用');
    }
    final level = EpubReadability.grade(
      ok: true,
      warnings: warnings,
      spineCount: effectivePackage.spine.length,
      missingSpineItems: probe.missingSpineItems,
      missingResources: probe.missingResources,
      repairedRefs: probe.repairedRefs,
      // 目录退化（P3-28）：声明了目录源（tocId→ncx，nav 属性→nav）但
      // 实际未达成；书本身无目录声明不算退化。
      tocFallbackUsed: _tocDegraded(effectivePackage, tocResult.source),
    );
    final document = EpubDocumentImpl(
      archive: archive,
      package: effectivePackage,
      resources: resources,
      opfPath: opfPath,
      toc: tocResult.entries,
      tocSource: tocResult.source,
      fontEncryption: resolvedEncryption,
      extensionConfig: extensionConfig,
      report: ImportReport(
        ok: true,
        warnings: List<String>.unmodifiable(warnings),
        readabilityLevel: level,
      ),
    );
    return EpubOpenResult(document: document, report: document.report);
  }
}

/// [openEpub] 的类入口，便于后续替换为 `EpubDocument.open`。
abstract final class EpubDocumentFactory {
  /// 打开 EPUB。
  static Future<EpubOpenResult> open(Uint8List bytes) => openEpub(bytes);

  /// 从文件打开 EPUB（惰性读取，不常驻整本字节）。
  static Future<EpubOpenResult> openFile(File file) => openEpubFile(file);
}

/// [EpubDocument] 的默认实现。
class EpubDocumentImpl implements EpubDocument {
  /// 创建文档。
  EpubDocumentImpl({
    required this.archive,
    required this.package,
    required this.resources,
    required this.opfPath,
    required List<TocEntry> toc,
    required this.tocSource,
    required this.report,
    this.fontEncryption = const FontEncryptionMap.empty(),
    this.extensionConfig = EpubExtensionConfig.none,
  }) : toc = List<TocEntry>.unmodifiable(toc);

  /// 字体混淆声明（P3-05）：ZIP 内路径 → 算法；无加密声明时为空表。
  final FontEncryptionMap fontEncryption;

  @override
  final EpubExtensionConfig extensionConfig;

  /// 读取字体资源字节；混淆资源按 encryption.xml 声明的算法解混淆
  /// （P3-05）。[cache] 提供时解混淆产物按（路径+长度）键落盘，缓存
  /// 命中不重复解密；原书字节始终不动。资源不存在返回 null。
  Future<Uint8List?> readFontBytes(
    String href, {
    DirectoryFontCache? cache,
  }) async {
    final path = resources.resolve(href, baseDir: p.posix.dirname(opfPath));
    if (path == null) {
      return null;
    }
    final raw = archive.readBytes(path);
    if (raw == null) {
      return null;
    }
    final algorithm = fontEncryption.entries[path];
    if (algorithm == null) {
      return raw;
    }
    Future<Uint8List> decrypt() async => FontObfuscator.deobfuscate(
      raw,
      identifier: package.meta.identifier,
      algorithm: algorithm,
    );
    if (cache != null) {
      return cache.getOrCompute(
        'epub-font-v1:$algorithm:$path:${raw.length}',
        decrypt,
      );
    }
    return decrypt();
  }

  /// ZIP 容器。
  final EpubArchive archive;

  /// 解析后的 OPF。
  final OpfPackage package;

  /// 资源索引。
  final ResourceIndex resources;

  /// OPF 路径。
  final String opfPath;

  @override
  final ImportReport report;

  @override
  BookMeta get meta => package.meta;

  @override
  List<SpineItem> get spine => List<SpineItem>.unmodifiable(package.spine);

  @override
  final List<TocEntry> toc;

  /// 目录来源：nav / ncx / spine。
  final String tocSource;

  /// 封面资源在 ZIP 内的路径（§37.3 降级链第 1～3 级）。
  ///
  /// 1. manifest 项 `properties` 含 `cover-image`（EPUB3）；
  /// 2. OPF `<meta name="cover">` 指向的 manifest 项（content 也可能是 href）；
  /// 3. spine 首个 linear 文档里的第一张图。
  ///
  /// 三条都失败返回 null，第 4 级「书名首字 + 派生色」占位由 UI 负责。
  String? get coverResourcePath {
    final opfDir = p.posix.dirname(opfPath);
    for (final item in package.manifest) {
      if (!item.properties.contains('cover-image')) {
        continue;
      }
      final path = resources.resolve(item.href, baseDir: opfDir);
      if (path != null) {
        return path;
      }
    }
    final coverId = package.coverItemId;
    if (coverId != null) {
      final item = package.itemById(coverId);
      if (item != null) {
        final path = resources.resolve(item.href, baseDir: opfDir);
        if (path != null) {
          return path;
        }
      }
      final direct = resources.resolve(coverId, baseDir: opfDir);
      if (direct != null) {
        return direct;
      }
    }
    for (final item in package.spine) {
      if (!item.linear) {
        continue;
      }
      final documentPath = resources.resolve(item.href, baseDir: opfDir);
      if (documentPath == null) {
        continue;
      }
      final xhtml = archive.readString(documentPath);
      if (xhtml == null) {
        continue;
      }
      final href = _firstImageHref(xhtml);
      if (href == null) {
        continue;
      }
      final path = resources.resolve(
        href,
        baseDir: p.posix.dirname(documentPath),
      );
      if (path != null) {
        return path;
      }
    }
    return null;
  }

  /// 不参与进度计算的 spine 索引（§76.2）：`linear="no"` 与 nav 目录文档。
  Set<int> get progressExcludedSpineIndexes {
    final excluded = <int>{};
    final navHrefs = <String>{
      for (final item in package.manifest)
        if (item.properties.contains('nav')) item.href,
    };
    for (var index = 0; index < package.spine.length; index++) {
      final item = package.spine[index];
      if (!item.linear || navHrefs.contains(item.href)) {
        excluded.add(index);
      }
    }
    return excluded;
  }

  /// 统计某章正文字符数（§22.3 轻量扫描，不做完整解析）。
  int characterCountOf(int spineIndex) {
    final item = spine[spineIndex];
    final baseDir = p.posix.dirname(opfPath);
    final resolved = resources.resolve(item.href, baseDir: baseDir);
    final xhtml = resolved == null ? null : archive.readString(resolved);
    return xhtml == null ? 0 : TextLengthScanner.count(xhtml);
  }

  /// 顺序统计各章正文字符数（导入期做）。
  ///
  /// 单章读取失败按 0 计（该章不参与进度）；每 [yieldEvery] 章让出一次
  /// 事件循环，避免长时间占用 UI isolate。
  Future<List<int>> countChapterCharacters({
    void Function(int done, int total)? onProgress,
    int yieldEvery = 50,
  }) async {
    final counts = List<int>.filled(spine.length, 0);
    for (var index = 0; index < spine.length; index++) {
      counts[index] = characterCountOf(index);
      if (index % yieldEvery == yieldEvery - 1) {
        onProgress?.call(index + 1, spine.length);
        await Future<void>.delayed(Duration.zero);
      }
    }
    onProgress?.call(spine.length, spine.length);
    return counts;
  }

  /// 读取封面字节；无封面或资源缺失返回 null。
  Uint8List? readCoverBytes() {
    final path = coverResourcePath;
    return path == null ? null : archive.readBytes(path);
  }

  /// 首个 `<img src>` / `<image href|xlink:href>` 的引用。
  static String? _firstImageHref(String xhtml) {
    final match = _imageHrefPattern.firstMatch(xhtml);
    final href = match?.group(1)?.trim();
    return href == null || href.isEmpty ? null : href;
  }

  static final RegExp _imageHrefPattern = RegExp(
    r'''<(?:img|image)\b[^>]*?\b(?:xlink:)?(?:src|href)\s*=\s*["']([^"']+)["']''',
    caseSensitive: false,
  );

  /// 把指定 spine 聚合为可测量文本块树。
  ///
  /// [whiteSpace] 决定空白与换行如何保留（默认 `normal`）。
  BlockDocument aggregateText(
    int spineIndex, {
    CssWhiteSpace whiteSpace = CssWhiteSpace.normal,
  }) =>
      TextAggregator.aggregate(parseBlocks(spineIndex), whiteSpace: whiteSpace);

  /// 把指定 spine 按 display 构建为块树。
  BlockDocument parseBlocks(int spineIndex) =>
      BlockBuilder.build(parseDocument(spineIndex));

  /// 取指定 spine 的原始 XHTML 字符串（轻量文本提取用，不解析）。
  String? chapterXhtml(int spineIndex) {
    final item = spine[spineIndex];
    final baseDir = p.posix.dirname(opfPath);
    final resolved =
        resources.resolve(item.href, baseDir: baseDir) ??
        p.posix.normalize(p.posix.join(baseDir, item.href));
    return archive.readString(resolved);
  }

  /// 章节文件是否已确认缺失。
  ///
  /// 只检查归档条目是否存在，不解析 XHTML；解析/排版/IO 异常仍按错误
  /// 处理，不能把未知错误当成可跳过的缺章。
  bool isChapterMissing(int spineIndex) {
    if (spineIndex < 0 || spineIndex >= spine.length) return true;
    final item = spine[spineIndex];
    final baseDir = p.posix.dirname(opfPath);
    final resolved =
        resources.resolve(item.href, baseDir: baseDir) ??
        p.posix.normalize(p.posix.join(baseDir, item.href));
    return !archive.contains(resolved);
  }

  /// 把指定 spine 解析为节点树。
  ParsedDocument parseDocument(int spineIndex) {
    final item = spine[spineIndex];
    final baseDir = p.posix.dirname(opfPath);
    final resolved =
        resources.resolve(item.href, baseDir: baseDir) ??
        p.posix.normalize(p.posix.join(baseDir, item.href));
    final xhtml = archive.readString(resolved);
    if (xhtml == null) {
      throw EpubException('E_SPINE_MISSING', '章节文件不存在：');
    }
    return DocumentParser.parse(xhtml: xhtml, spineIndex: spineIndex);
  }

  /// 解析指定 spine 的文本节点并绑定 CFI。
  BoundDocument bindCfi(int spineIndex) {
    final item = spine[spineIndex];
    final baseDir = p.posix.dirname(opfPath);
    final resolved =
        resources.resolve(item.href, baseDir: baseDir) ??
        p.posix.normalize(p.posix.join(baseDir, item.href));
    final xhtml = archive.readString(resolved);
    if (xhtml == null) {
      throw EpubException('E_SPINE_MISSING', '章节文件不存在：');
    }
    return CfiBinder.bind(xhtml: xhtml, spineIndex: spineIndex);
  }

  /// 在当前章节中容错解析 CFI；失败返回 warning 而不抛异常。
  CfiResolution resolveCfi(int spineIndex, EpubCfi target) {
    final item = spine[spineIndex];
    final baseDir = p.posix.dirname(opfPath);
    final resolved =
        resources.resolve(item.href, baseDir: baseDir) ??
        p.posix.normalize(p.posix.join(baseDir, item.href));
    final xhtml = archive.readString(resolved);
    if (xhtml == null) {
      return const CfiResolution(warnings: <String>['章节文件不存在']);
    }
    return CfiResolver.resolve(
      xhtml: xhtml,
      target: target,
      expectedSpineIndex: spineIndex,
    );
  }

  /// 解析指定 spine 的注释锚点（单章，不解析跨文档目标）。
  FootnoteDocument parseFootnotes(int spineIndex) {
    final item = spine[spineIndex];
    final baseDir = p.posix.dirname(opfPath);
    final resolved =
        resources.resolve(item.href, baseDir: baseDir) ??
        p.posix.normalize(p.posix.join(baseDir, item.href));
    final xhtml = archive.readString(resolved);
    if (xhtml == null) {
      throw EpubException('E_SPINE_MISSING', '章节文件不存在：');
    }
    return FootnoteParser.parse(
      spineIndex: spineIndex,
      path: resolved,
      xhtml: xhtml,
    );
  }

  /// 解析当前章的全部注释，并按需加载 href 指向的跨章定义。
  List<FootnoteAnchor> resolveFootnotes(int spineIndex) {
    final item = spine[spineIndex];
    final baseDir = p.posix.dirname(opfPath);
    final sourcePath =
        resources.resolve(item.href, baseDir: baseDir) ??
        p.posix.normalize(p.posix.join(baseDir, item.href));
    final xhtml = archive.readString(sourcePath);
    if (xhtml == null) {
      throw EpubException('E_SPINE_MISSING', '章节文件不存在：');
    }
    if (!FootnoteParser.mayContainReferences(xhtml)) {
      return const <FootnoteAnchor>[];
    }
    final source = FootnoteParser.parse(
      spineIndex: spineIndex,
      path: sourcePath,
      xhtml: xhtml,
    );
    final documents = <String, FootnoteDocument>{source.path: source};
    final following = spineIndex + 1 < spine.length
        ? spine[spineIndex + 1]
        : null;
    for (final targetPath in FootnoteParser.targetPaths(
      source,
      archive.names,
      followingPath: following == null
          ? null
          : resources.resolve(following.href, baseDir: baseDir) ??
                p.posix.normalize(p.posix.join(baseDir, following.href)),
    )) {
      if (targetPath == source.path || documents.containsKey(targetPath)) {
        continue;
      }
      final target = _parseFootnotesAtPath(targetPath);
      if (target != null) {
        documents[target.path] = target;
      }
    }
    return FootnoteParser.resolve(source: source, documents: documents);
  }

  FootnoteDocument? _parseFootnotesAtPath(String path) {
    final xhtml = archive.readString(path);
    if (xhtml == null) {
      return null;
    }
    var spineIndex = -1;
    final baseDir = p.posix.dirname(opfPath);
    for (final item in spine) {
      final resolved =
          resources.resolve(item.href, baseDir: baseDir) ??
          p.posix.normalize(p.posix.join(baseDir, item.href));
      if (resolved == path) {
        spineIndex = item.index;
        break;
      }
    }
    return FootnoteParser.parse(
      spineIndex: spineIndex,
      path: path,
      xhtml: xhtml,
    );
  }

  @override
  Future<SpineDocument> readSpine(int spineIndex) {
    throw UnimplementedError('P1-14 起实现文档树解析');
  }
}

/// 目录退化判定（P3-28）：声明了目录源（tocId→期望 ncx，EPUB3 nav→
/// 期望 nav）但实际回落到更低层级（spine 顺序）。
bool _tocDegraded(OpfPackage package, String actualSource) {
  if (package.tocId != null) {
    return actualSource != 'ncx';
  }
  final hasNav = package.manifest.any(
    (item) => item.properties.contains('nav'),
  );
  return hasNav && actualSource != 'nav';
}
